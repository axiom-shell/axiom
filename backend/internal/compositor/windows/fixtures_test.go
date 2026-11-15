package windows

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"testing"
)

var update = flag.Bool("update", false, "rewrite testdata/<kind>.want.json from what the watcher makes now")

// recording is testdata/<kind>.json: a session in nested Hyprland, sway or
// niri (docs/dev/features/window-rules.md › Watching windows)
type recording struct {
	Recorded string                     `json:"recorded"`
	Start    map[string]json.RawMessage `json:"start"`
	Steps    []struct {
		Note    string                     `json:"note"`
		Events  []json.RawMessage          `json:"events"`
		Replies map[string]json.RawMessage `json:"replies"`
	} `json:"steps"`
}

// stepResult is what one step made, as the .want.json holds it
type stepResult struct {
	Note   string  `json:"note"`
	Events []Event `json:"events"`
}

var kinds = map[string]func() source{
	"hypr": func() source { return &hyprSource{} },
	"sway": func() source { return &swaySource{} },
	"niri": func() source { return &niriSource{} },
}

func load(t testing.TB, kind string) recording {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("testdata", kind+".json"))
	if err != nil {
		t.Fatal(err)
	}
	var r recording
	if err := json.Unmarshal(data, &r); err != nil {
		t.Fatal(err)
	}
	return r
}

// line is an event as the compositor wrote it: a string as it is, a JSON
// value as its text
func line(raw json.RawMessage) []byte {
	var s string
	if json.Unmarshal(raw, &s) == nil {
		return []byte(s)
	}
	return raw
}

// replay runs a recording through its source as the run loop would, with
// fetches answered from the step's replies (else the latest the recording
// gave)
func replay(t testing.TB, kind string) []stepResult {
	t.Helper()
	r := load(t, kind)
	ctx := context.Background()
	replies := map[string]json.RawMessage{}
	fetchFrom := func(extra map[string]json.RawMessage) fetch {
		for k, v := range extra {
			replies[k] = v
		}
		return func(_ context.Context, request string) ([]byte, error) {
			v, ok := replies[request]
			if !ok {
				return nil, fmt.Errorf("no recorded reply to %s", request)
			}
			if kind == "niri" {
				// The recording holds the reply under its request's name
				return json.Marshal(map[string]json.RawMessage{request: v})
			}
			return v, nil
		}
	}
	src, tbl := kinds[kind](), &table{}
	ready, err := start(ctx, fetchFrom(r.Start), src, tbl)
	if err != nil {
		t.Fatal(err)
	}
	var out []stepResult
	wasReady := false
	if ready {
		out = append(out, stepResult{"start", tbl.settle(nil, ready, wasReady)})
		wasReady = true
	}
	for _, s := range r.Steps {
		var lines [][]byte
		for _, e := range s.Events {
			lines = append(lines, line(e))
		}
		before := slices.Clone(tbl.list)
		ready, err := batch(ctx, fetchFrom(s.Replies), src, tbl, lines)
		if err != nil {
			t.Fatalf("%s: %v", s.Note, err)
		}
		out = append(out, stepResult{s.Note, tbl.settle(before, ready, wasReady)})
		wasReady = wasReady || ready
	}
	return out
}

func TestFixtures(t *testing.T) {
	t.Parallel()
	for kind := range kinds {
		t.Run(kind, func(t *testing.T) {
			t.Parallel()
			got, err := json.MarshalIndent(replay(t, kind), "", " ")
			if err != nil {
				t.Fatal(err)
			}
			got = append(got, '\n')
			path := filepath.Join("testdata", kind+".want.json")
			if *update {
				if err := os.WriteFile(path, got, 0o644); err != nil {
					t.Fatal(err)
				}
				return
			}
			want, err := os.ReadFile(path)
			if err != nil {
				t.Fatalf("%v (go test -run TestFixtures -update writes it)", err)
			}
			if string(got) != string(want) {
				t.Errorf("%s differs from what the watcher makes (go test -run TestFixtures -update, then read the diff)", path)
			}
		})
	}
}

var (
	hexID     = regexp.MustCompile(`^0x[0-9a-f]+$`)
	decimalID = regexp.MustCompile(`^[0-9]+$`)
)

// TestFixtureFacts states what the recordings must show, so the goldens
// are not the only test.
func TestFixtureFacts(t *testing.T) {
	t.Parallel()
	for kind := range kinds {
		t.Run(kind, func(t *testing.T) {
			t.Parallel()
			steps := replay(t, kind)
			var all []Event
			for _, s := range steps {
				all = append(all, s.Events...)
			}
			if len(all) == 0 || all[0].Kind != Reset {
				t.Fatalf("the first event is %+v, not a Reset", all[0])
			}
			a := byApp(all[0].Windows, "wr-fixture-a")
			if a.ID == "" {
				t.Fatalf("A is not in the Reset: %+v", all[0].Windows)
			}
			if a.Title != "fixture-a" || !a.Focused {
				t.Errorf("A at the start: %+v", a)
			}
			for _, e := range all {
				for _, w := range append([]Window{e.Window}, e.Windows...) {
					if w.ID == "" {
						continue
					}
					if kind == "hypr" && !hexID.MatchString(w.ID) || kind != "hypr" && !decimalID.MatchString(w.ID) {
						t.Errorf("id %q is not the contract's", w.ID)
					}
				}
			}

			// B: opened once, then its fields change
			var opened []Window
			for _, e := range all[1:] {
				if e.Kind == Opened && e.Window.AppID == "wr-fixture-b" {
					opened = append(opened, e.Window)
				}
			}
			if len(opened) != 1 {
				t.Fatalf("B opened %d times: %+v", len(opened), opened)
			}
			b := opened[0]
			if b.PID <= 0 || b.Title != "before" {
				t.Errorf("B as opened: %+v", b)
			}
			sawB := func(what string, ok func(Window) bool) {
				t.Helper()
				for _, e := range all {
					if e.Kind == Changed && e.Window.ID == b.ID && ok(e.Window) {
						return
					}
				}
				t.Errorf("B never changed to %s", what)
			}
			sawB("title after", func(w Window) bool { return w.Title == "after" })
			sawB("floating", func(w Window) bool { return w.Floating })
			sawB("fullscreen", func(w Window) bool { return w.Fullscreen })
			sawB("workspace 2", func(w Window) bool { return w.Workspace == "2" })
			sawB("fullscreen off again", func(w Window) bool { return !w.Fullscreen && !w.Floating && w.Title == "after" && w.Workspace == "1" })
			if last := all[len(all)-1]; last.Kind != Closed || last.Window.ID != b.ID {
				t.Errorf("B doesn't end Closed: %+v", last)
			}

			// The X11 window. Tk capitalises the class it is given ("Wrfixturex"),
			// and the title is what it set.
			var x Window
			for _, e := range all[1:] {
				if e.Kind == Opened && e.Window.Title == "x11 fixture" {
					x = e.Window
				}
			}
			if x.ID == "" {
				// niri and sway name the window in a Changed: the title comes after the open
				for _, e := range all[1:] {
					if (e.Kind == Changed || e.Kind == Opened) && e.Window.Title == "x11 fixture" {
						x = e.Window
					}
				}
			}
			if x.ID == "" {
				t.Fatal("no X11 window")
			}
			switch kind {
			case "niri":
				// niri has no XWayland flag and gives the satellite's window its
				// class as app id ("Wrfixturex") and the pid it reports
				if x.XWayland || x.AppID != "Wrfixturex" || x.PID <= 0 {
					t.Errorf("niri's X11 window: %+v", x)
				}
			default:
				if !x.XWayland || !strings.EqualFold(x.Class, "wrfixturex") || x.PID <= 0 {
					t.Errorf("X11 window: %+v", x)
				}
			}

			// The 'A focused' step: focus moves from the X11 window to A and nothing else
			for _, s := range steps {
				if s.Note != "A focused" {
					continue
				}
				var focus []string
				for _, e := range s.Events {
					if e.Kind != Changed {
						t.Errorf("A focused made a %v", e.Kind)
					}
					focus = append(focus, e.Window.ID+":"+strconv.FormatBool(e.Window.Focused))
				}
				slices.Sort(focus)
				want := []string{a.ID + ":true", x.ID + ":false"}
				slices.Sort(want)
				if !slices.Equal(focus, want) {
					t.Errorf("A focused changed %v, want %v", focus, want)
				}
			}
			var closed []string
			for _, e := range all {
				if e.Kind == Closed {
					closed = append(closed, e.Window.ID)
				}
			}
			if !slices.Equal(closed, []string{x.ID, b.ID}) {
				t.Errorf("closed %v, want the X11 window then B", closed)
			}
		})
	}
}

func byApp(list []Window, app string) Window {
	for _, w := range list {
		if w.AppID == app {
			return w
		}
	}
	return Window{}
}
