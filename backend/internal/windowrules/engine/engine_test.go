package engine

import (
	"context"
	"reflect"
	"strconv"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/compositor/windows"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/procinfo"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

const grace = 50 * time.Millisecond

// rig is an engine run on scripted events.
type rig struct {
	t       *testing.T
	e       *Engine
	script  chan windows.Event
	mu      sync.Mutex
	changes []State
	lookups map[int]int
	procs   map[int]procinfo.Process
	done    chan error
	ended   atomic.Bool
	now     time.Time // the engine's clock, frozen until advance
	sent    int
}

func newRig(t *testing.T) *rig {
	t.Helper()
	r := &rig{t: t, script: make(chan windows.Event, 16), lookups: map[int]int{}, procs: map[int]procinfo.Process{}, done: make(chan error, 1), now: time.Date(2026, 11, 13, 12, 0, 0, 0, time.UTC)}
	r.e = New(Options{
		Events: func(ctx context.Context, out chan<- windows.Event) error {
			defer r.ended.Store(true)
			for {
				select {
				case ev := <-r.script:
					select {
					case out <- ev:
					case <-ctx.Done():
						return nil
					}
				case <-ctx.Done():
					return nil
				}
			}
		},
		Lookup: func(pid int) (procinfo.Process, bool) {
			r.mu.Lock()
			defer r.mu.Unlock()
			r.lookups[pid]++
			p, ok := r.procs[pid]
			return p, ok
		},
		AppIDs: func(id string) []string { return nil },
		Grace:  grace,
		Now: func() time.Time {
			r.mu.Lock()
			defer r.mu.Unlock()
			return r.now
		},
		OnChange: func(s State) {
			r.mu.Lock()
			r.changes = append(r.changes, s)
			r.mu.Unlock()
		},
	})
	return r
}

func (r *rig) run() {
	ctx, cancel := context.WithCancel(context.Background())
	go func() { r.done <- r.e.Run(ctx) }()
	r.t.Cleanup(func() {
		cancel()
		select {
		case <-r.done:
		case <-time.After(testkit.Bound(5 * time.Second)):
			r.t.Error("Run did not end")
		}
	})
}

func (r *rig) send(kind windows.Kind, w ...windows.Window) {
	ev := windows.Event{Kind: kind}
	if kind == windows.Reset {
		ev.Windows = w
	} else {
		ev.Window = w[0]
	}
	r.script <- ev
}

func (r *rig) count() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return len(r.changes)
}

// waitFor waits until cond holds of the engine's state
func (r *rig) waitFor(what string, cond func(State) bool) {
	r.t.Helper()
	if !testkit.Eventually(func() bool { return cond(r.e.State()) }) {
		r.t.Fatalf("never: %s (state %+v)", what, r.e.State())
	}
}

// advance moves the engine's clock on
func (r *rig) advance(d time.Duration) {
	r.mu.Lock()
	r.now = r.now.Add(d)
	r.mu.Unlock()
}

// quiet checks no push followed what was sent: the engine handles events in
// order, so once an unrelated window it is sent shows in Windows, everything
// before it has been decided and pushed.
func (r *rig) quiet(n int) {
	r.t.Helper()
	r.sent++
	id := "sentinel" + strconv.Itoa(r.sent)
	r.send(windows.Opened, win(id, "unrelated"))
	if !testkit.Eventually(func() bool {
		for _, w := range r.e.Windows() {
			if w.ID == id {
				return true
			}
		}
		return false
	}) {
		r.t.Fatal("the sentinel window never showed")
	}
	if got := r.count(); got != n {
		r.t.Fatalf("%d pushes, want %d", got, n)
	}
}

func section(t *testing.T, json string) any {
	t.Helper()
	v, err := jsonx.Unmarshal([]byte(json))
	if err != nil {
		t.Fatal(err)
	}
	return v
}

func ruleJSON(id, cond, shell string) string {
	return `{"id":"` + id + `","enabled":true,"windows":[{"conditions":[` + cond + `]}],"shell":` + shell + `}`
}

const (
	appFoot = `{"field":"appId","op":"is","value":"foot"}`
	dndOpen = `{"dnd":{"enabled":true,"when":"open"}}`
	dndFoc  = `{"dnd":{"enabled":true,"when":"focused"}}`
	dndFull = `{"dnd":{"enabled":true,"when":"fullscreen"}}`
)

func rulesOf(t *testing.T, rules ...string) any {
	s := `{"rules":[`
	for i, r := range rules {
		if i > 0 {
			s += ","
		}
		s += r
	}
	return section(t, s+`]}`)
}

func win(id, app string) windows.Window {
	return windows.Window{ID: id, AppID: app, Output: "DP-1"}
}

func TestResetHoldsAtOnce(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	r.e.SetConfig(rulesOf(t, ruleJSON("a", appFoot, dndOpen)), nil)
	r.run()
	r.send(windows.Reset, win("1", "foot"), win("2", "other"))
	r.waitFor("dnd held", func(s State) bool { return len(s.Holds.DND) == 1 })
	st := r.e.State()
	if !st.Running || !reflect.DeepEqual(st.Rules, []RuleWindows{{"a", []string{"1"}}}) {
		t.Errorf("state %+v", st)
	}
}

func TestOpenedChangedClosed(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	cond := `{"field":"title","op":"is","value":"late"}`
	r.e.SetConfig(rulesOf(t, ruleJSON("a", cond, dndOpen)), nil)
	r.run()
	r.send(windows.Reset)
	w := win("1", "x")
	r.send(windows.Opened, w)
	// A title change that matches nothing pushes nothing (D10)
	w.Title = "spam"
	r.send(windows.Changed, w)
	r.send(windows.Changed, w)
	r.quiet(0)
	w.Title = "late"
	r.send(windows.Changed, w)
	r.waitFor("held", func(s State) bool { return len(s.Holds.DND) == 1 })
	r.send(windows.Closed, w)
	r.waitFor("released", func(s State) bool { return len(s.Holds.DND) == 0 })
	if got := r.count(); got != 2 {
		t.Errorf("%d pushes, want 2", got)
	}
}

func TestFocusedGrace(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	r.e.SetConfig(rulesOf(t, ruleJSON("a", appFoot, dndFoc)), nil)
	r.run()
	w := win("1", "foot")
	w.Focused = true
	r.send(windows.Reset, w)
	r.waitFor("held", func(s State) bool { return len(s.Holds.DND) == 1 })
	// Focus away: still held, then released after the grace
	w.Focused = false
	r.send(windows.Changed, w)
	r.quiet(r.count())
	if len(r.e.State().Holds.DND) != 1 {
		t.Error("released before the grace")
	}
	r.advance(grace)
	r.waitFor("released", func(s State) bool { return len(s.Holds.DND) == 0 })
	// Focus back inside the grace: no push at all
	w.Focused = true
	r.send(windows.Changed, w)
	r.waitFor("held again", func(s State) bool { return len(s.Holds.DND) == 1 })
	n := r.count()
	w.Focused = false
	r.send(windows.Changed, w)
	r.quiet(n)
	w.Focused = true
	r.send(windows.Changed, w)
	r.quiet(n)
}

func TestFullscreenOffAtOnce(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	r.e.SetConfig(rulesOf(t, ruleJSON("a", appFoot, dndFull)), nil)
	r.run()
	w := win("1", "foot")
	w.Fullscreen = true
	r.send(windows.Reset, w)
	r.waitFor("held", func(s State) bool { return len(s.Holds.DND) == 1 })
	w.Fullscreen = false
	r.send(windows.Changed, w)
	r.waitFor("released", func(s State) bool { return len(s.Holds.DND) == 0 })
}

func TestConfigAndSupports(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	r.run()
	x := win("1", "foot")
	x.XWayland = true
	r.send(windows.Reset, x)
	r.waitFor("running", func(s State) bool { return s.Running })
	r.e.SetConfig(rulesOf(t, ruleJSON("a", appFoot, dndOpen), ruleJSON("x", `{"field":"xwayland","op":"is"}`, dndOpen)), nil)
	r.waitFor("a matches", func(s State) bool { return len(s.Rules) == 1 && s.Rules[0].Rule == "a" })
	r.e.SetSupports(map[string]bool{"ruleXwayland": true})
	r.waitFor("xwayland kind matches", func(s State) bool { return len(s.Rules) == 2 })
}

func TestUnknownProcess(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	r.procs[20] = procinfo.Process{PID: 20, Bridge: true, Ancestors: []string{}, Signals: []procinfo.Signal{}}
	r.procs[30] = procinfo.Process{PID: 30, Name: "steam", Ancestors: []string{"kitty"}, Signals: []procinfo.Signal{}}
	proc := `{"field":"process","op":"isNot","value":"firefox"}`
	game := `{"field":"game","op":"is"}`
	r.e.SetConfig(rulesOf(t, ruleJSON("p", proc, dndOpen), ruleJSON("g", game, dndOpen)), nil)
	r.run()
	nopid := win("1", "x")
	bridge := win("2", "steam_app_1")
	bridge.PID = 20
	known := win("3", "x")
	known.PID = 30
	r.send(windows.Reset, nopid, bridge, known)
	r.waitFor("matched", func(s State) bool { return len(s.Rules) == 2 })
	st := r.e.State()
	want := []RuleWindows{{"p", []string{"3"}}, {"g", []string{"2"}}}
	if !reflect.DeepEqual(st.Rules, want) {
		t.Errorf("rules %+v, want %+v", st.Rules, want)
	}
	infos := r.e.Windows()
	if len(infos) != 3 || infos[0].Process != nil || infos[1].Process == nil || !infos[1].Process.Bridge || infos[2].Process.Name != "steam" {
		t.Errorf("windows %+v", infos)
	}
	if infos[0].Game == nil || len(infos[0].Game) != 0 || !reflect.DeepEqual(infos[1].Game, []procinfo.Signal{procinfo.SignalSteamApp}) {
		t.Errorf("game %+v / %+v", infos[0].Game, infos[1].Game)
	}
	if !reflect.DeepEqual(infos[1].Rules, []string{"g"}) || !reflect.DeepEqual(infos[2].Rules, []string{"p"}) || infos[0].Rules == nil {
		t.Errorf("rules %+v", infos)
	}
	// One lookup per window and pid, however often the title changes
	for i := range 3 {
		known.Title = string(rune('a' + i))
		r.send(windows.Changed, known)
	}
	r.waitFor("settled", func(State) bool { return r.e.Windows()[2].Title == "c" })
	r.mu.Lock()
	n := r.lookups[30]
	r.mu.Unlock()
	if n != 1 {
		t.Errorf("%d lookups of pid 30", n)
	}
	known.PID = 31
	r.send(windows.Changed, known)
	r.waitFor("new pid", func(State) bool { return r.e.Windows()[2].PID == 31 })
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.lookups[31] != 1 || r.lookups[0] != 0 {
		t.Errorf("lookups %v", r.lookups)
	}
}

func TestMatchDraft(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	r.run()
	r.send(windows.Reset, win("1", "foot"), win("2", "kitty"))
	r.waitFor("running", func(State) bool { return len(r.e.Windows()) == 2 })
	draft := section(t, `{"rules":[
		{"id":"a","enabled":true,"windows":[{"conditions":[`+appFoot+`]},{"conditions":[{"field":"title","op":"matches","value":"("}]}]},
		{"id":"b","enabled":false,"windows":[{"conditions":[{"field":"appId","op":"is","value":"kitty"}]}]},
		{"id":"c","enabled":true,"windows":[{"conditions":[{"field":"appId","op":"is","value":""}]}]}
	]}`)
	got := r.e.Match(draft)
	want := []RuleWindows{{"a", []string{"1"}}, {"b", []string{"2"}}, {"c", []string{}}}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("Match = %+v, want %+v", got, want)
	}
}

func TestNoCompositor(t *testing.T) {
	t.Parallel()
	e := New(Options{})
	if e.State().Running {
		t.Error("running without events")
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- e.Run(ctx) }()
	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Error(err)
		}
	case <-time.After(testkit.Bound(5 * time.Second)):
		t.Error("Run did not end")
	}
}

func TestRunWaitsForEvents(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- r.e.Run(ctx) }()
	r.send(windows.Reset, win("1", "foot"))
	r.waitFor("a window", func(State) bool { return len(r.e.Windows()) == 1 })
	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Error(err)
		}
	case <-time.After(testkit.Bound(5 * time.Second)):
		t.Fatal("Run did not end")
	}
	if !r.ended.Load() {
		t.Error("the events goroutine outlived Run")
	}
}
