package windows

import (
	"context"
	"slices"
	"testing"
)

const swayTree = `{"id":1,"type":"root","nodes":[
 {"id":2,"type":"output","name":"__i3","nodes":[{"id":3,"type":"workspace","name":"__i3_scratch","nodes":[],"floating_nodes":[
   {"id":30,"type":"floating_con","name":"scratch","pid":30,"app_id":"scr","nodes":[],"floating_nodes":[]}]}]},
 {"id":4,"type":"output","name":"DP-1","nodes":[
  {"id":5,"type":"workspace","name":"1","nodes":[
    {"id":6,"type":"con","nodes":[
      {"id":10,"type":"con","name":"deep","pid":10,"app_id":"term","focused":true,"nodes":[],"floating_nodes":[]},
      {"id":11,"type":"con","name":"x11","pid":11,"app_id":null,"shell":"xwayland","window_properties":{"class":"Cls"},"nodes":[],"floating_nodes":[]}]}],
    "floating_nodes":[{"id":12,"type":"floating_con","name":"fl","pid":12,"app_id":"flt","fullscreen_mode":1,"nodes":[],"floating_nodes":[]}]}]}]}`

func swayEvent(typ, change, container string) []byte {
	body := `{"change":"` + change + `"`
	if container != "" {
		body += `,"container":` + container
	}
	return []byte(`{"type":"` + typ + `","body":` + body + `}}`)
}

func swayStart(t *testing.T) (*swaySource, *table, *fake) {
	t.Helper()
	f := &fake{replies: map[string]string{"get_tree": swayTree}}
	s, tbl := &swaySource{}, &table{}
	if _, err := s.start(context.Background(), f.fetch, tbl); err != nil {
		t.Fatal(err)
	}
	f.calls = nil
	return s, tbl, f
}

func TestSwayTree(t *testing.T) {
	t.Parallel()
	_, tbl, _ := swayStart(t)
	want := map[string]Window{
		"10": {ID: "10", AppID: "term", Title: "deep", PID: 10, Workspace: "1", Output: "DP-1", Focused: true},
		"11": {ID: "11", AppID: "Cls", Class: "Cls", Title: "x11", PID: 11, XWayland: true, Workspace: "1", Output: "DP-1"},
		"12": {ID: "12", AppID: "flt", Title: "fl", PID: 12, Floating: true, Fullscreen: true, Workspace: "1", Output: "DP-1"},
		"30": {ID: "30", AppID: "scr", Title: "scratch", PID: 30, Floating: true},
	}
	if len(tbl.list) != len(want) {
		t.Fatalf("%+v", tbl.list)
	}
	for _, w := range tbl.list {
		if w != want[w.ID] {
			t.Errorf("%s: %+v, want %+v", w.ID, w, want[w.ID])
		}
	}
}

func TestSwayEvents(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name  string
		lines [][]byte
		calls []string
		check func(t *testing.T, tbl *table)
	}{
		{"a title changes only the title", [][]byte{swayEvent("window", "title", `{"id":10,"name":"new","pid":10,"app_id":"term","focused":false}`)}, nil, func(t *testing.T, tbl *table) {
			w := tbl.list[tbl.find("10")]
			if w.Title != "new" || w.Workspace != "1" || w.Output != "DP-1" || !w.Focused {
				t.Errorf("%+v", w)
			}
		}},
		{"focus unfocuses the others", [][]byte{swayEvent("window", "focus", `{"id":12,"name":"fl","pid":12,"app_id":"flt","focused":true,"type":"floating_con"}`)}, nil, func(t *testing.T, tbl *table) {
			for _, w := range tbl.list {
				if w.Focused != (w.ID == "12") {
					t.Errorf("%+v", w)
				}
			}
		}},
		{"new fetches", [][]byte{swayEvent("window", "new", `{"id":10,"pid":10}`)}, []string{"get_tree"}, nil},
		{"move fetches", [][]byte{swayEvent("window", "move", `{"id":10,"pid":10}`)}, []string{"get_tree"}, nil},
		{"close doesn't", [][]byte{swayEvent("window", "close", `{"id":10,"pid":10}`)}, nil, func(t *testing.T, tbl *table) {
			if tbl.find("10") >= 0 {
				t.Error("still there")
			}
		}},
		{"a workspace rename fetches", [][]byte{swayEvent("workspace", "rename", "")}, []string{"get_tree"}, nil},
		{"a workspace focus doesn't", [][]byte{swayEvent("workspace", "focus", "")}, nil, nil},
		{"a new window the tree lacks", [][]byte{swayEvent("window", "new", `{"id":40,"name":"fresh","pid":40,"app_id":"new"}`)}, []string{"get_tree"}, func(t *testing.T, tbl *table) {
			w := tbl.list[tbl.find("40")]
			if w.Title != "fresh" || w.Workspace != "" {
				t.Errorf("%+v", w)
			}
		}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			s, tbl, f := swayStart(t)
			if _, err := s.batch(context.Background(), f.fetch, tbl, tc.lines); err != nil {
				t.Fatal(err)
			}
			if !slices.Equal(f.calls, tc.calls) {
				t.Errorf("fetched %v, want %v", f.calls, tc.calls)
			}
			if tc.check != nil {
				tc.check(t, tbl)
			}
		})
	}
}
