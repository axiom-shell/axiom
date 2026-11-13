package engine

import (
	"context"
	"errors"
	"reflect"
	"slices"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/compositor/windows"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/procinfo"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"github.com/axiom-shell/axiom/backend/internal/windowrules"
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

func newRig(t *testing.T) *rig { return newRigWith(t, nil) }

// newRigWith is newRig with its options adjusted first.
func newRigWith(t *testing.T, adjust func(*Options)) *rig {
	t.Helper()
	r := &rig{t: t, script: make(chan windows.Event, 16), lookups: map[int]int{}, procs: map[int]procinfo.Process{}, done: make(chan error, 1), now: time.Date(2026, 11, 13, 12, 0, 0, 0, time.UTC)}
	o := Options{
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
	}
	if adjust != nil {
		adjust(&o)
	}
	r.e = New(o)
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

// count is the pushes so far, less those of quiet's sentinel windows (each
// changes State.Open once).
func (r *rig) count() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return len(r.changes) - r.sent
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
	// The snapshot is stored just before its push
	if !testkit.Eventually(func() bool {
		r.mu.Lock()
		defer r.mu.Unlock()
		return len(r.changes) > 0 && slices.Contains(r.changes[len(r.changes)-1].Open, id)
	}) {
		r.t.Fatal("the sentinel window was never pushed")
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
	if !st.Running || !reflect.DeepEqual(st.Rules, []RuleWindows{{"a", "a", []string{"1"}}}) {
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
	r.waitFor("open", func(s State) bool { return len(s.Open) == 1 })
	n := r.count()
	// A title change that matches nothing pushes nothing (D10)
	w.Title = "spam"
	r.send(windows.Changed, w)
	r.send(windows.Changed, w)
	r.quiet(n)
	w.Title = "late"
	r.send(windows.Changed, w)
	r.waitFor("held", func(s State) bool { return len(s.Holds.DND) == 1 })
	r.send(windows.Closed, w)
	r.waitFor("released", func(s State) bool { return len(s.Holds.DND) == 0 })
	if got := r.count(); got != 3 {
		t.Errorf("%d pushes, want 3 (open, held, released)", got)
	}
}

func TestWindowFocused(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	r.run()
	idOf := func() string {
		w, _, ok := r.e.Window("")
		if !ok {
			return ""
		}
		return w.ID
	}
	a, b := win("1", "foot"), win("2", "kitty")
	b.PID = 5
	r.procs[5] = procinfo.Process{PID: 5, Name: "kitty", Ancestors: []string{}, Signals: []procinfo.Signal{}}
	a.Focused = true
	r.send(windows.Reset, a, b)
	r.waitFor("both open", func(s State) bool { return len(s.Open) == 2 })
	if idOf() != "1" {
		t.Errorf("focused %q after Reset", idOf())
	}
	a.Focused, b.Focused = false, true
	r.send(windows.Changed, a)
	r.send(windows.Changed, b)
	r.waitFor("moved", func(State) bool { return idOf() == "2" })
	// Focus to nothing (a layer surface took it): still the last one
	b.Focused = false
	r.send(windows.Changed, b)
	r.quiet(r.count())
	if idOf() != "2" {
		t.Errorf("focused %q after focus left", idOf())
	}
	w, facts, ok := r.e.Window("2")
	if !ok || w.ID != "2" || facts.Process == nil || facts.Process.Name != "kitty" || facts.AppID != "kitty" {
		t.Errorf("by id: %+v %+v %v", w, facts, ok)
	}
	if _, _, ok := r.e.Window("9"); ok {
		t.Error("an unknown id was found")
	}
	r.send(windows.Closed, b)
	r.waitFor("closed", func(s State) bool { return !slices.Contains(s.Open, "2") })
	if idOf() != "" {
		t.Errorf("focused %q after it closed", idOf())
	}
}

func TestStateOpen(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	r.run()
	r.send(windows.Reset)
	w := win("1", "x")
	r.send(windows.Opened, w)
	r.waitFor("open", func(s State) bool { return reflect.DeepEqual(s.Open, []string{"1"}) })
	n := r.count()
	// A title nothing matches pushes nothing
	w.Title = "spam"
	r.send(windows.Changed, w)
	r.quiet(n)
	r.send(windows.Closed, w)
	r.waitFor("closed", func(s State) bool { return !slices.Contains(s.Open, "1") })
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
	want := []RuleWindows{{"p", "p", []string{"3"}}, {"g", "g", []string{"2"}}}
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

func TestRuleNames(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	named := `{"id":"n","name":"Games","enabled":true,"windows":[{"conditions":[` + appFoot + `]}],"shell":` + dndOpen + `}`
	r.e.SetConfig(rulesOf(t, named, ruleJSON("u", appFoot, dndOpen)), nil)
	r.run()
	r.send(windows.Reset, win("1", "foot"))
	r.waitFor("matched", func(s State) bool { return len(s.Rules) == 2 })
	want := []RuleWindows{{"n", "Games", []string{"1"}}, {"u", "u", []string{"1"}}}
	if got := r.e.State().Rules; !reflect.DeepEqual(got, want) {
		t.Errorf("rules %+v, want %+v", got, want)
	}
	if got := r.e.Match(rulesOf(t, named, ruleJSON("u", appFoot, dndOpen))); !reflect.DeepEqual(got, want) {
		t.Errorf("Match %+v, want %+v", got, want)
	}
}

func TestOverride(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	r.e.SetConfig(rulesOf(t, ruleJSON("a", appFoot, dndOpen)), nil)
	r.run()
	r.send(windows.Reset, win("1", "foot"))
	r.waitFor("dnd held", func(s State) bool { return len(s.Holds.DND) == 1 })
	if err := r.e.Override("x"); err == nil {
		t.Error("an unknown effect was accepted")
	}
	if err := r.e.Override("dnd"); err != nil {
		t.Fatal(err)
	}
	r.waitFor("overridden", func(s State) bool { return s.Overrides.DND })
	// The hold ends with its window
	r.send(windows.Closed, win("1", "foot"))
	r.waitFor("not overridden", func(s State) bool { return !s.Overrides.DND && len(s.Holds.DND) == 0 })
	// Asked while nothing is held: ignored, nothing pushed
	n := r.count()
	if err := r.e.Override("dnd"); err != nil {
		t.Fatal(err)
	}
	// The loop takes the ask (it's recomputed against nothing held) before
	// the next window opens, or the stale ask would meet its hold
	if !testkit.Eventually(func() bool {
		r.e.mu.Lock()
		defer r.e.mu.Unlock()
		return r.e.overrides == nil
	}) {
		t.Fatal("the loop never took the override")
	}
	r.quiet(n)
	if r.e.State().Overrides.DND {
		t.Error("an override with nothing held stuck")
	}
	// And the next hold isn't overridden
	r.send(windows.Opened, win("2", "foot"))
	r.waitFor("held again", func(s State) bool { return len(s.Holds.DND) == 1 })
	if r.e.State().Overrides.DND {
		t.Error("the next hold was overridden")
	}
}

func TestPowerOverrideEndsWithAnotherHold(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	power := func(profile string) string {
		return `{"powerProfile":{"enabled":true,"profile":"` + profile + `","when":"open"}}`
	}
	appBar := `{"field":"appId","op":"is","value":"bar"}`
	r.e.SetConfig(rulesOf(t, ruleJSON("hi", appBar, power("powerSaver")), ruleJSON("lo", appFoot, power("performance"))), nil)
	r.run()
	r.send(windows.Reset, win("1", "foot"))
	r.waitFor("held", func(s State) bool { return s.Holds.PowerProfile.Rule == "lo" })
	r.e.Override("powerProfile")
	r.waitFor("overridden", func(s State) bool { return s.Overrides.PowerProfile })
	r.send(windows.Opened, win("2", "bar"))
	r.waitFor("another hold", func(s State) bool { return s.Holds.PowerProfile.Rule == "hi" && !s.Overrides.PowerProfile })
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
	want := []RuleWindows{{"a", "a", []string{"1"}}, {"b", "b", []string{"2"}}, {"c", "c", []string{}}}
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

// placed is one batch the fake Place was given.
type placed struct {
	at    time.Time
	id    string
	steps []windowrules.Step
}

// placer is a fake compositor: it records what it is sent.
type placer struct {
	mu    sync.Mutex
	calls []placed
	fail  map[int]bool // batch numbers (0-based, over all calls) that error
}

func (p *placer) place(ctx context.Context, id string, steps []windowrules.Step) error {
	p.mu.Lock()
	n := len(p.calls)
	p.calls = append(p.calls, placed{time.Now(), id, steps})
	fail := p.fail[n]
	p.mu.Unlock()
	if fail {
		return errors.New("refused")
	}
	return nil
}

func (p *placer) got() []placed {
	p.mu.Lock()
	defer p.mu.Unlock()
	return slices.Clone(p.calls)
}

// kinds are the step kinds of each batch, as one string per batch.
func kindsOf(calls []placed) []string {
	var out []string
	for _, c := range calls {
		var ks []string
		for _, s := range c.steps {
			ks = append(ks, string(s.Kind))
		}
		out = append(out, c.id+":"+strings.Join(ks, ","))
	}
	return out
}

const settle = 20 * time.Millisecond

// placeRig is a rig with a fake compositor and clock; foot's process is known.
func placeRig(t *testing.T) (*rig, *placer) {
	t.Helper()
	p := &placer{}
	r := newRigWith(t, func(o *Options) {
		o.Place = p.place
		o.Settle = settle
		o.PlaceGrace = 200 * time.Millisecond
	})
	r.procs[10] = procinfo.Process{PID: 10, Name: "foot"}
	return r, p
}

const procFoot = `{"field":"process","op":"is","value":"foot"}`

func placeRule(id, cond, window string) string {
	return `{"id":"` + id + `","enabled":true,"windows":[{"conditions":[` + cond + `]}],"window":` + window + `,"shell":{}}`
}

// report is compositor.state's windowRules with one live kind (index 0) per rule,
// or the given rows.
func report(t *testing.T, rows ...string) any {
	return section(t, `{"issues":[],"rules":[`+strings.Join(rows, ",")+`]}`)
}

func liveRow(id string) string {
	return `{"rule":"` + id + `","placed":[],"dropped":[],"live":[0],"skipped":[]}`
}

func footWin(id string) windows.Window {
	w := win(id, "foot")
	w.PID = 10
	return w
}

// settled waits until no more batches arrive for a while.
func (p *placer) settled() []placed {
	time.Sleep(testkit.Bound(6 * settle))
	return p.got()
}

func TestPlaceOnOpenedNotReset(t *testing.T) {
	t.Parallel()
	r, p := placeRig(t)
	r.e.SetConfig(rulesOf(t, placeRule("p", procFoot, `{"float":true,"size":{"width":400,"height":300}}`)), nil)
	r.e.SetReport(report(t, liveRow("p")))
	r.run()
	r.send(windows.Reset, footWin("1"))
	r.waitFor("matched", func(s State) bool { return len(s.Rules) == 1 })
	if calls := p.settled(); len(calls) != 0 {
		t.Fatalf("a Reset window was placed: %v", kindsOf(calls))
	}
	r.send(windows.Opened, footWin("2"))
	if !testkit.Eventually(func() bool { return len(p.got()) == 2 }) {
		t.Fatalf("batches: %v", kindsOf(p.got()))
	}
	calls := p.got()
	if got := kindsOf(calls); !reflect.DeepEqual(got, []string{"2:float", "2:size"}) {
		t.Errorf("batches %v", got)
	}
	if gap := calls[1].at.Sub(calls[0].at); gap < settle {
		t.Errorf("batches %v apart, want at least %v", gap, settle)
	}
	if calls[1].steps[0].Width != 400 || calls[1].steps[0].Height != 300 {
		t.Errorf("size step %+v", calls[1].steps[0])
	}
	// A later change places nothing more
	w := footWin("2")
	w.Title = "again"
	r.send(windows.Changed, w)
	if got := p.settled(); len(got) != 2 {
		t.Errorf("placed again: %v", kindsOf(got))
	}
}

func TestPlaceLateTitle(t *testing.T) {
	t.Parallel()
	r, p := placeRig(t)
	titled := `{"field":"title","op":"is","value":"late"}`
	r.e.SetConfig(rulesOf(t, placeRule("p", procFoot+","+titled, `{"float":true}`)), nil)
	r.e.SetReport(report(t, liveRow("p")))
	r.run()
	r.send(windows.Reset)
	r.send(windows.Opened, footWin("1"))
	r.send(windows.Opened, footWin("2"))
	if !testkit.Eventually(func() bool { return len(r.e.Windows()) == 2 }) {
		t.Fatal("windows not in the table")
	}
	// 1's title comes within the grace, 2's after it
	r.advance(100 * time.Millisecond)
	w := footWin("1")
	w.Title = "late"
	r.send(windows.Changed, w)
	r.waitFor("1 matched", func(s State) bool { return len(s.Rules) == 1 })
	r.advance(150 * time.Millisecond)
	w = footWin("2")
	w.Title = "late"
	r.send(windows.Changed, w)
	r.waitFor("2 matched", func(s State) bool { return len(s.Rules[0].Windows) == 2 })
	if got := kindsOf(p.settled()); !reflect.DeepEqual(got, []string{"1:float"}) {
		t.Errorf("batches %v", got)
	}
}

func TestPlaceOnceAndNotForLaterRules(t *testing.T) {
	t.Parallel()
	r, p := placeRig(t)
	r.e.SetConfig(rulesOf(t, placeRule("p", procFoot, `{"float":true}`)), nil)
	r.e.SetReport(report(t, liveRow("p")))
	r.run()
	r.send(windows.Reset)
	r.send(windows.Opened, footWin("1"))
	if !testkit.Eventually(func() bool { return len(p.got()) == 1 }) {
		t.Fatal("not placed")
	}
	// A rule added after placement doesn't place a window already placed
	r.e.SetConfig(rulesOf(t, placeRule("q", procFoot, `{"workspace":"3"}`), placeRule("p", procFoot, `{"float":true}`)), nil)
	r.e.SetReport(report(t, liveRow("p"), liveRow("q")))
	r.waitFor("both match", func(s State) bool { return len(s.Rules) == 2 })
	if got := p.settled(); len(got) != 1 {
		t.Errorf("placed again: %v", kindsOf(got))
	}
}

func TestPlaceWrittenKinds(t *testing.T) {
	t.Parallel()
	for name, tc := range map[string]struct {
		row  string
		want []string
	}{
		"nothing placed":      {`{"rule":"p","placed":[],"dropped":[],"live":[],"skipped":[]}`, nil},
		"workspace is placed": {`{"rule":"p","placed":["workspace"],"dropped":[],"live":[],"skipped":[]}`, []string{"1:move"}},
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			r, p := placeRig(t)
			r.e.SetConfig(rulesOf(t, placeRule("p", appFoot, `{"float":true,"workspace":"3"}`)), nil)
			r.e.SetReport(report(t, tc.row))
			r.run()
			r.send(windows.Reset)
			r.send(windows.Opened, footWin("1"))
			r.waitFor("matched", func(s State) bool { return len(s.Rules) == 1 })
			if got := kindsOf(p.settled()); !reflect.DeepEqual(got, tc.want) {
				t.Errorf("batches %v, want %v", got, tc.want)
			}
		})
	}
}

func TestPlaceWaitsForTheReport(t *testing.T) {
	t.Parallel()
	r, p := placeRig(t)
	r.e.SetConfig(rulesOf(t, placeRule("p", procFoot, `{"float":true}`)), nil)
	r.run()
	r.send(windows.Reset)
	r.send(windows.Opened, footWin("1"))
	r.waitFor("matched", func(s State) bool { return len(s.Rules) == 1 })
	if got := p.settled(); len(got) != 0 {
		t.Fatalf("placed without a report: %v", kindsOf(got))
	}
	// A report within the grace places it
	r.advance(50 * time.Millisecond)
	r.e.SetReport(report(t, liveRow("p")))
	if !testkit.Eventually(func() bool { return len(p.got()) == 1 }) {
		t.Fatal("not placed once the report came")
	}
}

func TestApplyNow(t *testing.T) {
	t.Parallel()
	r, p := placeRig(t)
	r.e.SetConfig(rulesOf(t, placeRule("p", appFoot, `{"workspace":"3","follow":true}`)), nil)
	// The kind is written: only Apply gives the window the rule
	r.e.SetReport(report(t, `{"rule":"p","placed":[],"dropped":[],"live":[],"skipped":[]}`))
	r.run()
	r.send(windows.Reset, footWin("1"), footWin("2"), win("3", "other"))
	r.waitFor("matched", func(s State) bool { return len(s.Rules) == 1 })
	n, err := r.e.Apply(context.Background())
	if err != nil || n != 2 {
		t.Fatalf("Apply: %d %v", n, err)
	}
	if !testkit.Eventually(func() bool { return len(p.got()) == 2 }) {
		t.Fatalf("batches %v", kindsOf(p.got()))
	}
	got := kindsOf(p.got())
	slices.Sort(got)
	if !reflect.DeepEqual(got, []string{"1:move", "2:move"}) {
		t.Errorf("batches %v (no focus: Apply never follows)", got)
	}
}

func TestApplyNowSkipsWindowsInGrace(t *testing.T) {
	t.Parallel()
	r, p := placeRig(t)
	r.e.SetConfig(rulesOf(t, placeRule("p", appFoot, `{"fullscreen":true}`)), nil)
	r.e.SetReport(report(t, `{"rule":"p","placed":[],"dropped":[],"live":[],"skipped":[]}`))
	r.run()
	r.send(windows.Reset)
	r.send(windows.Opened, footWin("1"))
	r.waitFor("matched", func(s State) bool { return len(s.Rules) == 1 })
	// placePass owns a window within its grace
	if n, err := r.e.Apply(context.Background()); err != nil || n != 0 {
		t.Fatalf("Apply in grace: %d %v", n, err)
	}
	r.advance(time.Second)
	if n, err := r.e.Apply(context.Background()); err != nil || n != 1 {
		t.Fatalf("Apply after grace: %d %v", n, err)
	}
	if !testkit.Eventually(func() bool { return len(p.got()) == 1 }) {
		t.Fatalf("batches %v", kindsOf(p.got()))
	}
}

func TestApplyNowWithoutReportOrPlacer(t *testing.T) {
	t.Parallel()
	r, p := placeRig(t)
	r.e.SetConfig(rulesOf(t, placeRule("p", appFoot, `{"float":true}`)), nil)
	r.run()
	r.send(windows.Reset, footWin("1"))
	r.waitFor("matched", func(s State) bool { return len(s.Rules) == 1 })
	if n, err := r.e.Apply(context.Background()); n != 0 || err != nil || len(p.settled()) != 0 {
		t.Errorf("without a report: %d %v", n, err)
	}
	bare := New(Options{})
	if n, err := bare.Apply(context.Background()); n != 0 || err != nil {
		t.Errorf("without a dispatcher: %d %v", n, err)
	}
}

func TestPlaceErrorsDontStopTheRest(t *testing.T) {
	t.Parallel()
	r, p := placeRig(t)
	p.fail = map[int]bool{0: true}
	r.e.SetConfig(rulesOf(t, placeRule("p", procFoot, `{"float":true,"size":{"width":4,"height":5}}`)), nil)
	r.e.SetReport(report(t, liveRow("p")))
	r.run()
	r.send(windows.Reset)
	r.send(windows.Opened, footWin("1"))
	if !testkit.Eventually(func() bool { return len(p.got()) == 2 }) {
		t.Fatalf("the second batch wasn't sent: %v", kindsOf(p.got()))
	}
}

func TestPlaceCancelledBetweenBatches(t *testing.T) {
	t.Parallel()
	p := &placer{}
	e := New(Options{
		Events: func(ctx context.Context, out chan<- windows.Event) error {
			out <- windows.Event{Kind: windows.Opened, Window: footWin("1")}
			<-ctx.Done()
			return nil
		},
		Lookup: func(int) (procinfo.Process, bool) { return procinfo.Process{Name: "foot"}, true },
		Place:  p.place, Settle: time.Hour,
	})
	e.SetConfig(rulesOf(t, placeRule("p", procFoot, `{"float":true,"size":{"width":4,"height":5}}`)), nil)
	e.SetReport(report(t, liveRow("p")))
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- e.Run(ctx) }()
	if !testkit.Eventually(func() bool { return len(p.got()) == 1 }) {
		t.Fatal("no first batch")
	}
	cancel()
	select {
	case <-done:
	case <-time.After(testkit.Bound(5 * time.Second)):
		t.Fatal("Run waited for the pending batch")
	}
	if got := p.got(); len(got) != 1 {
		t.Errorf("a batch after cancel: %v", kindsOf(got))
	}
}
