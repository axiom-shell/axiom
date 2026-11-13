package windows

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"io"
	"net"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

func TestDiff(t *testing.T) {
	t.Parallel()
	w := func(id, title string) Window { return Window{ID: id, Title: title} }
	before := []Window{w("1", "a"), w("2", "b"), w("3", "c"), w("4", "d")}
	tbl := &table{list: []Window{w("5", "new"), w("4", "d"), w("3", "changed"), w("2", "changed")}}
	var got []string
	for _, e := range tbl.diff(before) {
		got = append(got, e.Window.ID+":"+e.Window.Title+":"+map[Kind]string{Opened: "opened", Changed: "changed", Closed: "closed"}[e.Kind])
	}
	want := "1:a:closed 3:changed:changed 2:changed:changed 5:new:opened"
	if strings.Join(got, " ") != want {
		t.Errorf("%v, want %s", got, want)
	}
	// Opened and closed inside one batch, and nothing changed
	if ev := (&table{list: []Window{w("1", "a")}}).diff([]Window{w("1", "a")}); len(ev) != 0 {
		t.Errorf("%+v", ev)
	}
	b, _ := json.Marshal(Event{Kind: Closed, Window: w("1", "a")})
	if !strings.Contains(string(b), `"kind":"closed"`) {
		t.Errorf("%s", b)
	}
}

func TestNew(t *testing.T) {
	t.Parallel()
	env := func(kv ...string) func(string) string {
		return func(k string) string {
			for i := 0; i+1 < len(kv); i += 2 {
				if kv[i] == k {
					return kv[i+1]
				}
			}
			return ""
		}
	}
	if New(Options{Getenv: env()}) != nil {
		t.Error("a watcher with no compositor")
	}
	tests := []struct {
		name string
		env  func(string) string
		src  any
	}{
		{"hyprland", env("HYPRLAND_INSTANCE_SIGNATURE", "sig", "XDG_RUNTIME_DIR", "/run/user/1"), &hyprSource{}},
		{"sway", env("SWAYSOCK", "/x/sway.sock"), &swaySource{}},
		{"niri", env("NIRI_SOCKET", "/x/niri.sock"), &niriSource{}},
	}
	for _, tc := range tests {
		w := New(Options{Getenv: tc.env})
		if w == nil {
			t.Errorf("%s: nil", tc.name)
			continue
		}
		switch tc.src.(type) {
		case *hyprSource:
			_, ok := w.src.(*hyprSource)
			if !ok {
				t.Errorf("%s: %T", tc.name, w.src)
			}
		case *swaySource:
			if _, ok := w.src.(*swaySource); !ok {
				t.Errorf("%s: %T", tc.name, w.src)
			}
		case *niriSource:
			if _, ok := w.src.(*niriSource); !ok {
				t.Errorf("%s: %T", tc.name, w.src)
			}
		}
	}
}

// --- fake compositor sockets ---

func short(t *testing.T) string {
	t.Helper()
	dir, err := os.MkdirTemp("", "axwin")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	return dir
}

// serve accepts connections on path; handle gets each, with the count so far
func serve(t *testing.T, path string, handle func(c net.Conn, n int)) {
	t.Helper()
	l, err := net.Listen("unix", path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { l.Close() })
	var n atomic.Int32
	go func() {
		for {
			c, err := l.Accept()
			if err != nil {
				return
			}
			go func() {
				defer c.Close()
				handle(c, int(n.Add(1)))
			}()
		}
	}()
}

func swayWriteTo(c net.Conn, kind uint32, body string) {
	head := make([]byte, 14)
	copy(head, "i3-ipc")
	binary.LittleEndian.PutUint32(head[6:], uint32(len(body)))
	binary.LittleEndian.PutUint32(head[10:], kind)
	c.Write(append(head, body...))
}

func swayReadFrom(c net.Conn) (uint32, error) {
	head := make([]byte, 14)
	if _, err := io.ReadFull(c, head); err != nil {
		return 0, err
	}
	body := make([]byte, binary.LittleEndian.Uint32(head[6:]))
	_, err := io.ReadFull(c, body)
	return binary.LittleEndian.Uint32(head[10:]), err
}

// compositors starts a fake of each kind: streams counts event connections;
// closeEvents ends the event socket's connection; failFetch makes requests fail
type fakeSet struct {
	getenv  func(string) string
	streams *atomic.Int32
}

func startFake(t *testing.T, kind string, failFetch bool, hold chan struct{}) fakeSet {
	t.Helper()
	dir := short(t)
	streams := &atomic.Int32{}
	var getenv func(string) string
	switch kind {
	case "hyprland":
		serve(t, filepath.Join(dir, ".socket.sock"), func(c net.Conn, _ int) {
			buf := make([]byte, 64)
			n, _ := c.Read(buf)
			if failFetch {
				return
			}
			switch string(buf[:n]) {
			case "j/clients":
				io.WriteString(c, `[`+client("0xa1", "app", "one", "")+`]`)
			case "j/monitors":
				io.WriteString(c, `[{"id":0,"name":"DP-1"}]`)
			default:
				io.WriteString(c, `{}`)
			}
		})
		serve(t, filepath.Join(dir, ".socket2.sock"), func(c net.Conn, _ int) {
			streams.Add(1)
			select {
			case <-hold:
			case <-time.After(testkit.Bound(200 * time.Millisecond)):
			}
		})
		getenv = func(k string) string {
			return map[string]string{"XDG_RUNTIME_DIR": dir, "HYPRLAND_INSTANCE_SIGNATURE": "s"}[k]
		}
		// Hypr dir is $XDG_RUNTIME_DIR/hypr/<sig>: link it
		os.MkdirAll(filepath.Join(dir, "hypr"), 0o755)
		os.Symlink(dir, filepath.Join(dir, "hypr", "s"))
	case "sway":
		path := filepath.Join(dir, "sway.sock")
		serve(t, path, func(c net.Conn, _ int) {
			kind, err := swayReadFrom(c)
			if err != nil {
				return
			}
			if kind == 4 {
				if !failFetch {
					swayWriteTo(c, 4, swayTree)
				}
				return
			}
			streams.Add(1)
			swayWriteTo(c, 2, `{"success":true}`)
			select {
			case <-hold:
			case <-time.After(testkit.Bound(200 * time.Millisecond)):
			}
		})
		getenv = func(k string) string { return map[string]string{"SWAYSOCK": path}[k] }
	case "niri":
		path := filepath.Join(dir, "niri.sock")
		serve(t, path, func(c net.Conn, _ int) {
			buf := make([]byte, 64)
			n, _ := c.Read(buf)
			if strings.Contains(string(buf[:n]), "Outputs") {
				if !failFetch {
					io.WriteString(c, `{"Ok":{"Outputs":{"DP-1":{"logical":{"width":10,"height":10}}}}}`+"\n")
				}
				return
			}
			streams.Add(1)
			io.WriteString(c, `{"Ok":"Handled"}`+"\n"+niriWS+"\n"+niriWindows+"\n")
			select {
			case <-hold:
			case <-time.After(testkit.Bound(200 * time.Millisecond)):
			}
		})
		getenv = func(k string) string { return map[string]string{"NIRI_SOCKET": path}[k] }
	}
	return fakeSet{getenv, streams}
}

func TestRunReconnects(t *testing.T) {
	t.Parallel()
	for _, kind := range []string{"hyprland", "sway", "niri"} {
		t.Run(kind, func(t *testing.T) {
			t.Parallel()
			f := startFake(t, kind, false, nil)
			w := New(Options{Getenv: f.getenv, Retry: 10 * time.Millisecond})
			if w == nil {
				t.Fatal("no watcher")
			}
			before := runtime.NumGoroutine()
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			out := make(chan Event, 16)
			done := make(chan error, 1)
			go func() { done <- w.Run(ctx, out) }()
			// Each connection ends after a moment: a fresh Reset follows
			for range 2 {
				select {
				case e := <-out:
					if e.Kind != Reset || len(e.Windows) == 0 {
						t.Fatalf("%+v", e)
					}
				case <-time.After(testkit.Bound(5 * time.Second)):
					t.Fatal("no Reset")
				}
			}
			if f.streams.Load() < 2 {
				t.Errorf("%d connections", f.streams.Load())
			}
			cancel()
			select {
			case err := <-done:
				if err != nil {
					t.Error(err)
				}
			case <-time.After(testkit.Bound(5 * time.Second)):
				t.Fatal("Run didn't return")
			}
			if !testkit.Eventually(func() bool { return runtime.NumGoroutine() <= before+2 }) {
				t.Errorf("%d goroutines, %d before", runtime.NumGoroutine(), before)
			}
		})
	}
}

func TestRunSilentStreamEnds(t *testing.T) {
	t.Parallel()
	for _, kind := range []string{"hyprland", "sway", "niri"} {
		t.Run(kind, func(t *testing.T) {
			t.Parallel()
			hold := make(chan struct{})
			defer close(hold)
			f := startFake(t, kind, false, hold)
			w := New(Options{Getenv: f.getenv, Retry: 10 * time.Millisecond})
			ctx, cancel := context.WithCancel(context.Background())
			out := make(chan Event, 16)
			done := make(chan error, 1)
			go func() { done <- w.Run(ctx, out) }()
			select {
			case <-out:
			case <-time.After(testkit.Bound(5 * time.Second)):
				t.Fatal("no Reset")
			}
			cancel()
			select {
			case err := <-done:
				if err != nil {
					t.Error(err)
				}
			case <-time.After(testkit.Bound(5 * time.Second)):
				t.Fatal("Run didn't return while the stream was silent")
			}
		})
	}
}

func TestRunFailedFetch(t *testing.T) {
	t.Parallel()
	for _, kind := range []string{"hyprland", "sway", "niri"} {
		t.Run(kind, func(t *testing.T) {
			t.Parallel()
			hold := make(chan struct{})
			defer close(hold)
			f := startFake(t, kind, true, hold)
			w := New(Options{Getenv: f.getenv, Retry: 10 * time.Millisecond})
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			out := make(chan Event, 16)
			go w.Run(ctx, out)
			// A failing fetch ends the session: the stream is opened again and again
			if !testkit.Eventually(func() bool { return f.streams.Load() >= 3 }) {
				t.Fatalf("%d connections", f.streams.Load())
			}
			select {
			case e := <-out:
				t.Errorf("an event with no fetch: %+v", e)
			default:
			}
		})
	}
}
