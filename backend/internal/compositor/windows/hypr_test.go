package windows

import (
	"context"
	"slices"
	"strings"
	"testing"
)

// fake answers fetches from replies and counts them by request
type fake struct {
	replies map[string]string
	calls   []string
}

func (f *fake) fetch(_ context.Context, request string) ([]byte, error) {
	f.calls = append(f.calls, request)
	return []byte(f.replies[request]), nil
}

func client(addr, class, title string, extra string) string {
	return `{"address":"` + addr + `","mapped":true,"floating":false,"monitor":0,"class":"` + class + `","title":"` + title + `","pid":7,"xwayland":false,"fullscreen":0,"workspace":{"id":1,"name":"1"}` + extra + `}`
}

func hyprStart(t *testing.T, clients ...string) (*hyprSource, *table, *fake) {
	t.Helper()
	f := &fake{replies: map[string]string{
		"j/clients":      "[" + strings.Join(clients, ",") + "]",
		"j/monitors":     `[{"id":0,"name":"DP-1"}]`,
		"j/activewindow": `{}`,
	}}
	s, tbl := &hyprSource{}, &table{}
	if _, err := s.start(context.Background(), f.fetch, tbl); err != nil {
		t.Fatal(err)
	}
	f.calls = nil
	return s, tbl, f
}

func TestHyprLines(t *testing.T) {
	t.Parallel()
	a := client("0xa1", "app", "one", "")
	b := client("0xb2", "app", "two", "")
	tests := []struct {
		name    string
		lines   []string
		replies map[string]string
		calls   []string
		check   func(t *testing.T, tbl *table, ev []Event)
	}{
		{"the event's address gets its 0x", []string{"windowtitlev2>>a1,new"}, nil, nil, func(t *testing.T, tbl *table, ev []Event) {
			if tbl.list[0].Title != "new" || len(ev) != 1 || ev[0].Kind != Changed {
				t.Errorf("%+v %+v", tbl.list, ev)
			}
		}},
		{"a title with commas", []string{"windowtitlev2>>a1,x, y,z"}, nil, nil, func(t *testing.T, tbl *table, _ []Event) {
			if tbl.list[0].Title != "x, y,z" {
				t.Errorf("%q", tbl.list[0].Title)
			}
		}},
		{"an empty active window", []string{"activewindowv2>>a1", "activewindowv2>>"}, nil, nil, func(t *testing.T, tbl *table, ev []Event) {
			if tbl.list[0].Focused || tbl.list[1].Focused || len(ev) != 0 {
				t.Errorf("%+v %+v", tbl.list, ev)
			}
		}},
		{"an active window of ','", []string{"activewindowv2>>b2", "activewindowv2>>,"}, nil, nil, func(t *testing.T, tbl *table, ev []Event) {
			if tbl.list[1].Focused || len(ev) != 0 {
				t.Errorf("%+v %+v", tbl.list, ev)
			}
		}},
		{"an unknown event", []string{"workspace>>3", "urgent>>a1"}, nil, nil, func(t *testing.T, _ *table, ev []Event) {
			if len(ev) != 0 {
				t.Errorf("%+v", ev)
			}
		}},
		{"twenty titles", repeat(20, "windowtitlev2>>a1,spam"), nil, nil, func(t *testing.T, _ *table, ev []Event) {
			if len(ev) != 1 || ev[0].Kind != Changed {
				t.Errorf("%+v", ev)
			}
		}},
		{"open and move", []string{"openwindow>>c3,1,app,three", "movewindowv2>>c3,1,1"}, map[string]string{
			"j/clients": "[" + a + "," + b + "," + client("0xc3", "app", "three", "") + "]",
		}, []string{"j/clients"}, func(t *testing.T, _ *table, ev []Event) {
			if len(ev) != 1 || ev[0].Kind != Opened || ev[0].Window.ID != "0xc3" {
				t.Errorf("%+v", ev)
			}
		}},
		{"a client on an unknown monitor", []string{"movewindowv2>>a1,2,2"}, map[string]string{
			"j/clients": "[" + strings.Replace(a, `"monitor":0`, `"monitor":3`, 1) + "," + b + "]",
		}, []string{"j/clients", "j/monitors"}, func(t *testing.T, _ *table, ev []Event) {
			if len(ev) != 1 || ev[0].Window.Output != "" {
				t.Errorf("%+v", ev)
			}
		}},
		{"an unmapped client", []string{"movewindowv2>>a1,2,2"}, map[string]string{
			"j/clients": "[" + a + "," + strings.Replace(client("0xd4", "x", "y", ""), `"mapped":true`, `"mapped":false`, 1) + "]",
		}, []string{"j/clients"}, func(t *testing.T, tbl *table, _ []Event) {
			if len(tbl.list) != 1 {
				t.Errorf("%+v", tbl.list)
			}
		}},
		{"focus is not focusHistoryID", []string{"movewindowv2>>a1,1,1"}, map[string]string{
			"j/clients": "[" + strings.Replace(a, `"mapped"`, `"focusHistoryID":0,"mapped"`, 1) + "," + b + "]",
		}, []string{"j/clients"}, func(t *testing.T, tbl *table, _ []Event) {
			if tbl.list[0].Focused {
				t.Errorf("%+v", tbl.list)
			}
		}},
		{"openwindow the clients lack", []string{"openwindow>>e5,2,Cls,A, title"}, nil, []string{"j/clients"}, func(t *testing.T, tbl *table, ev []Event) {
			if len(ev) != 1 || ev[0].Kind != Opened || ev[0].Window != (Window{ID: "0xe5", AppID: "Cls", Title: "A, title", Workspace: "2"}) {
				t.Errorf("%+v", ev)
			}
		}},
		{"opened and closed in a batch", []string{"openwindow>>e5,2,Cls,t", "closewindow>>e5"}, nil, []string{"j/clients"}, func(t *testing.T, _ *table, ev []Event) {
			if len(ev) != 0 {
				t.Errorf("%+v", ev)
			}
		}},
		{"a close", []string{"closewindow>>b2"}, nil, nil, func(t *testing.T, _ *table, ev []Event) {
			if len(ev) != 1 || ev[0].Kind != Closed || ev[0].Window.ID != "0xb2" {
				t.Errorf("%+v", ev)
			}
		}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			s, tbl, f := hyprStart(t, a, b)
			for k, v := range tc.replies {
				f.replies[k] = v
			}
			before := slices.Clone(tbl.list)
			var lines [][]byte
			for _, l := range tc.lines {
				lines = append(lines, []byte(l))
			}
			if _, err := s.batch(context.Background(), f.fetch, tbl, lines); err != nil {
				t.Fatal(err)
			}
			if !slices.Equal(f.calls, tc.calls) {
				t.Errorf("fetched %v, want %v", f.calls, tc.calls)
			}
			tc.check(t, tbl, tbl.diff(before))
		})
	}
}

func repeat(n int, s string) []string {
	out := make([]string, n)
	for i := range out {
		out[i] = s
	}
	return out
}
