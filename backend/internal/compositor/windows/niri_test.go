package windows

import (
	"context"
	"slices"
	"testing"
)

const (
	niriWS      = `{"WorkspacesChanged":{"workspaces":[{"id":1,"idx":1,"name":null,"output":"DP-1"},{"id":2,"idx":2,"name":"games","output":"DP-1"},{"id":3,"idx":1,"name":null,"output":"HDMI-1"}]}}`
	niriWindows = `{"WindowsChanged":{"windows":[` +
		`{"id":1,"title":"a","app_id":"x","pid":5,"workspace_id":1,"is_focused":true,"is_floating":false,"layout":{"tile_size":[100,100]}},` +
		`{"id":2,"title":"b","app_id":"y","pid":null,"workspace_id":2,"is_focused":false,"is_floating":false,"layout":{"tile_size":[1920.5,1080]}}]}}`
)

func niriStart(t *testing.T) (*niriSource, *table, *fake) {
	t.Helper()
	f := &fake{replies: map[string]string{"Outputs": `{"Outputs":{"DP-1":{"logical":{"width":1920,"height":1080}},"HDMI-1":{"logical":{"width":800,"height":600}}}}`}}
	s, tbl := &niriSource{}, &table{}
	ready, err := start(context.Background(), f.fetch, s, tbl)
	if err != nil || ready {
		t.Fatalf("start: %v %v", ready, err)
	}
	f.calls = nil
	return s, tbl, f
}

func TestNiriEvents(t *testing.T) {
	t.Parallel()
	ctx := context.Background()

	t.Run("nothing before WindowsChanged, then the list", func(t *testing.T) {
		t.Parallel()
		s, tbl, f := niriStart(t)
		ready, err := batch(ctx, f.fetch, s, tbl, [][]byte{[]byte(niriWS)})
		if err != nil || ready || len(tbl.list) != 0 {
			t.Fatalf("%v %v %+v", ready, err, tbl.list)
		}
		ready, _ = batch(ctx, f.fetch, s, tbl, [][]byte{[]byte(niriWindows)})
		if !ready || len(tbl.list) != 2 {
			t.Fatalf("%v %+v", ready, tbl.list)
		}
		if ev := tbl.settle(nil, ready, false); len(ev) != 1 || ev[0].Kind != Reset || len(ev[0].Windows) != 2 {
			t.Errorf("%+v", ev)
		}
		if len(f.calls) != 0 {
			t.Errorf("fetched %v after the start's", f.calls)
		}
	})

	run := func(t *testing.T, lines ...string) (*niriSource, *table, *fake, []Event) {
		t.Helper()
		s, tbl, f := niriStart(t)
		all := [][]byte{[]byte(niriWS), []byte(niriWindows)}
		if _, err := batch(ctx, f.fetch, s, tbl, all); err != nil {
			t.Fatal(err)
		}
		before := slices.Clone(tbl.list)
		f.calls = nil
		var more [][]byte
		for _, l := range lines {
			more = append(more, []byte(l))
		}
		if _, err := batch(ctx, f.fetch, s, tbl, more); err != nil {
			t.Fatal(err)
		}
		return s, tbl, f, tbl.diff(before)
	}

	t.Run("workspace names, else the idx; pid null is 0; fullscreen 0.5 off", func(t *testing.T) {
		t.Parallel()
		_, tbl, _, _ := run(t)
		a, b := tbl.list[0], tbl.list[1]
		if a.Workspace != "1" || a.Output != "DP-1" || a.PID != 5 || a.Fullscreen {
			t.Errorf("%+v", a)
		}
		if b.Workspace != "games" || b.PID != 0 || !b.Fullscreen {
			t.Errorf("%+v", b)
		}
	})
	t.Run("an opened focused window unfocuses the others", func(t *testing.T) {
		t.Parallel()
		_, tbl, _, ev := run(t, `{"WindowOpenedOrChanged":{"window":{"id":3,"title":"c","app_id":"z","pid":1,"workspace_id":1,"is_focused":true,"is_floating":false}}}`)
		if tbl.list[0].Focused || !tbl.list[2].Focused || len(ev) != 2 || ev[0].Kind != Changed || ev[1].Kind != Opened {
			t.Errorf("%+v %+v", tbl.list, ev)
		}
	})
	t.Run("focus null", func(t *testing.T) {
		t.Parallel()
		_, tbl, _, _ := run(t, `{"WindowFocusChanged":{"id":null}}`)
		if tbl.list[0].Focused || tbl.list[1].Focused {
			t.Errorf("%+v", tbl.list)
		}
	})
	t.Run("floating at the output's size isn't fullscreen", func(t *testing.T) {
		t.Parallel()
		_, tbl, _, _ := run(t, `{"WindowOpenedOrChanged":{"window":{"id":2,"title":"b","app_id":"y","workspace_id":2,"is_floating":true,"layout":{"tile_size":[1920,1080]}}}}`)
		if tbl.list[1].Fullscreen || !tbl.list[1].Floating {
			t.Errorf("%+v", tbl.list[1])
		}
	})
	t.Run("a layout change makes a window fullscreen", func(t *testing.T) {
		t.Parallel()
		_, tbl, _, ev := run(t, `{"WindowLayoutsChanged":{"changes":[[1,{"tile_size":[1920,1080]}]]}}`)
		if !tbl.list[0].Fullscreen || len(ev) != 1 {
			t.Errorf("%+v %+v", tbl.list, ev)
		}
	})
	t.Run("a workspace on another output", func(t *testing.T) {
		t.Parallel()
		moved := `{"WorkspacesChanged":{"workspaces":[{"id":1,"idx":1,"name":null,"output":"HDMI-1"},{"id":2,"idx":2,"name":"games","output":"DP-1"}]}}`
		_, tbl, f, ev := run(t, moved)
		if len(ev) != 1 || ev[0].Kind != Changed || ev[0].Window.Output != "HDMI-1" || tbl.list[0].Output != "HDMI-1" {
			t.Errorf("%+v", ev)
		}
		if !slices.Equal(f.calls, []string{"Outputs"}) {
			t.Errorf("fetched %v", f.calls)
		}
	})
}
