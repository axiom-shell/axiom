// Package engine is the window rules engine: it follows the compositor's windows (compositor/windows), matches them against the usable window rules with their process facts (procinfo), and holds each rule's while-effects as their triggers say (windowrules.Hold), for the daemon to publish (docs/dev/features/window-rules.md › The engine).
package engine

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"maps"
	"slices"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/compositor/windows"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/procinfo"
	"github.com/axiom-shell/axiom/backend/internal/windowrules"
)

// Options build an Engine; zero values are the real ones.
type Options struct {
	// Events runs the window watcher (windows.Watcher.Run); nil: no
	// compositor, so nothing matches and State.Running is false
	Events   func(ctx context.Context, out chan<- windows.Event) error
	Lookup   func(pid int) (procinfo.Process, bool) // default procinfo.New(procinfo.Options{}).Lookup
	AppIDs   windowrules.AppIDs                     // an `app` condition's ids; nil: such kinds match nothing
	Grace    time.Duration                          // focused's off delay, default 500 ms
	Now      func() time.Time                       // default time.Now
	OnChange func(State)                            // from Run's goroutine, only when State changed
	Log      *slog.Logger                           // nil discards

	// Place sends one batch of placement steps for a window (compositor/place);
	// nil: nothing is placed
	Place      func(ctx context.Context, id string, steps []windowrules.Step) error
	Settle     time.Duration // between a window's batches, default 100 ms
	PlaceGrace time.Duration // how long after it opened a window may still be placed, default 1.5 s
}

// State is what the engine decides (windowRules.state).
type State struct {
	Running bool              `json:"running"`
	Rules   []RuleWindows     `json:"rules"` // usable rules matching any window, priority order
	Holds   windowrules.Holds `json:"holds"`
	Look    windowrules.Look  `json:"look"`
}

// RuleWindows are the open windows a rule matches, in window order.
type RuleWindows struct {
	Rule    string   `json:"rule"`
	Windows []string `json:"windows"`
}

// WindowInfo is an open window as the rules see it (windowRules.windows).
type WindowInfo struct {
	windows.Window                   // inlined
	Process        *procinfo.Process `json:"process"` // null: not known; a bridge has bridge true
	Game           []procinfo.Signal `json:"game"`    // why it's a game (Detect); [] when it isn't
	Rules          []string          `json:"rules"`   // usable rules matching it, priority order
}

// snapshot is what the loop last decided, never changed after it is stored,
// so State, Windows and Match read it from any goroutine.
type snapshot struct {
	state   State
	windows []WindowInfo
	facts   []windowrules.Facts
}

// Engine matches the open windows against the usable rules.
type Engine struct {
	o     Options
	snap  atomic.Pointer[snapshot]
	kick  chan struct{} // capacity 1: the config or the capabilities changed
	apply chan applyRequest

	mu          sync.Mutex // guards the next five
	windowRules any
	keybinds    any
	supports    map[string]bool
	report      map[string]windowrules.Report // nil: the compositor's config hasn't reported
	changed     bool                          // since the loop last took them
}

// applyRequest is Apply's call into the loop.
type applyRequest struct{ reply chan int }

// entry is one open window in the loop's table.
type entry struct {
	win   windows.Window
	proc  *procinfo.Process // the lookup's result; nil: none (no pid, not ours)
	facts windowrules.Facts
	game  []procinfo.Signal // why it's a game (Detect); [] when it isn't
	lost  time.Time         // when it lost focus; zero: not in grace

	opened time.Time // when it opened after a Reset; zero: it was there before (never placed)
	placed bool      // its placement was sent
	kinds  []windowrules.KindMatch
}

// loop is what Run's goroutine owns.
type loop struct {
	e        *Engine
	ctx      context.Context
	wg       *sync.WaitGroup // the placements in flight, and the watcher
	table    []entry
	rules    []windowrules.Rule
	match    windowrules.Matcher
	supports map[string]bool
	reports  map[string]windowrules.Report
	last     []byte // the marshalled State last passed to OnChange
}

// New is an engine with no windows and no rules.
func New(o Options) *Engine {
	if o.Lookup == nil {
		o.Lookup = procinfo.New(procinfo.Options{}).Lookup
	}
	if o.Grace <= 0 {
		o.Grace = 500 * time.Millisecond
	}
	if o.Now == nil {
		o.Now = time.Now
	}
	if o.Log == nil {
		o.Log = slog.New(slog.NewTextHandler(io.Discard, nil))
	}
	if o.Settle <= 0 {
		o.Settle = 100 * time.Millisecond
	}
	if o.PlaceGrace <= 0 {
		o.PlaceGrace = 1500 * time.Millisecond
	}
	e := &Engine{o: o, kick: make(chan struct{}, 1), apply: make(chan applyRequest)}
	e.snap.Store(&snapshot{state: e.empty(), windows: []WindowInfo{}})
	return e
}

func (e *Engine) empty() State {
	return State{
		Running: e.o.Events != nil, Rules: []RuleWindows{},
		Holds: windowrules.Hold(nil), Look: windowrules.LookOf(nil),
	}
}

// SetConfig takes the saved WindowRules and Keybinds sections (Parse,
// Validate with the bind ids, Usable) and rematches every window.
func (e *Engine) SetConfig(windowRules, keybinds any) {
	e.mu.Lock()
	e.windowRules, e.keybinds, e.changed = windowRules, keybinds, true
	e.mu.Unlock()
	e.wake()
}

// SetSupports takes the shell's capabilities (ruleXwayland): a kind testing
// xwayland matches nothing while the compositor can't tell.
func (e *Engine) SetSupports(supports map[string]bool) {
	e.mu.Lock()
	e.supports, e.changed = maps.Clone(supports), true
	e.mu.Unlock()
	e.wake()
}

// SetReport takes compositor.state's windowRules ({issues, rules}, or nil while
// the compositor's config layer isn't live): what the config already does with
// each rule. Nothing is placed without it, since a written rule may have acted
// already; a window waiting in its grace is placed when it comes.
func (e *Engine) SetReport(report any) {
	var reports map[string]windowrules.Report
	if report != nil {
		var rows struct {
			Rules []windowrules.Report `json:"rules"`
		}
		if err := json.Unmarshal(jsonx.MarshalCompact(report), &rows); err != nil {
			e.o.Log.Warn("windowrules: unreadable report", "err", err)
		} else {
			reports = make(map[string]windowrules.Report, len(rows.Rules))
			for _, r := range rows.Rules {
				reports[r.Rule] = r
			}
		}
	}
	e.mu.Lock()
	e.report, e.changed = reports, true
	e.mu.Unlock()
	e.wake()
}

// Apply gives every open window, those from before the daemon started too,
// what the saved rules would give it (Apply to open windows): written rules
// as well, no follow, a special workspace not shown. It returns how many
// windows got any step. Nothing happens without a report or a dispatcher.
func (e *Engine) Apply(ctx context.Context) (int, error) {
	if e.o.Place == nil {
		return 0, nil
	}
	req := applyRequest{reply: make(chan int, 1)}
	select {
	case e.apply <- req:
	case <-ctx.Done():
		return 0, ctx.Err()
	}
	select {
	case n := <-req.reply:
		return n, nil
	case <-ctx.Done():
		return 0, ctx.Err()
	}
}

func (e *Engine) wake() {
	select {
	case e.kick <- struct{}{}:
	default:
	}
}

// inputs are the config and capabilities as they stand.
func (e *Engine) inputs() (windowRules, keybinds any, supports map[string]bool) {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.windowRules, e.keybinds, e.supports
}

// State is what the rules decide of the open windows now.
func (e *Engine) State() State { return e.snap.Load().state }

// Windows are the open windows as the rules see them.
func (e *Engine) Windows() []WindowInfo { return e.snap.Load().windows }

// Run follows the windows until ctx ends (then nil); it runs Events in a
// goroutine it owns and waits for it.
func (e *Engine) Run(ctx context.Context) error {
	events := make(chan windows.Event, 64)
	var wg sync.WaitGroup
	if e.o.Events != nil {
		wg.Add(1)
		go func() {
			defer wg.Done()
			// The watcher reconnects itself: an error means it gave up
			if err := e.o.Events(ctx, events); err != nil && ctx.Err() == nil {
				e.o.Log.Debug("windowrules: window events ended", "err", err)
			}
		}()
	}
	defer wg.Wait()
	l := &loop{e: e, ctx: ctx, wg: &wg}
	l.last, _ = json.Marshal(e.State())
	timer := time.NewTimer(time.Hour)
	defer timer.Stop()
	l.configure()
	for {
		select {
		case <-ctx.Done():
			return nil
		case ev := <-events:
			l.apply(ev)
			// Everything else that is ready belongs to the same batch
		drain:
			for {
				select {
				case ev := <-events:
					l.apply(ev)
				default:
					break drain
				}
			}
		case <-e.kick:
			l.configure()
		case req := <-e.apply:
			req.reply <- l.applyNow()
		case <-timer.C:
		}
		next := l.recompute()
		// One timer, set to the earliest grace end
		timer.Reset(next)
	}
}

// configure takes the config and capabilities that changed into the matcher.
func (l *loop) configure() {
	l.e.mu.Lock()
	changed := l.e.changed
	l.e.changed = false
	l.e.mu.Unlock()
	if !changed {
		return
	}
	section, keybinds, supports := l.e.inputs()
	xwayland := supports["ruleXwayland"]
	cfg := windowrules.Parse(section)
	issues := windowrules.Validate(cfg, windowrules.Context{BindIDs: windowrules.BindIDs(keybinds)})
	l.rules = windowrules.Usable(cfg, issues)
	l.match = windowrules.NewMatcher(l.rules, l.e.o.AppIDs, xwayland)
	l.supports = supports
	l.e.mu.Lock()
	l.reports = l.e.report
	l.e.mu.Unlock()
}

// apply takes one watcher event into the table.
func (l *loop) apply(ev windows.Event) {
	switch ev.Kind {
	case windows.Reset:
		// Nothing lost focus across a reconnect: no grace
		l.table = l.table[:0]
		for _, w := range ev.Windows {
			l.table = append(l.table, l.entryFor(w, nil))
		}
	case windows.Opened, windows.Changed:
		i := slices.IndexFunc(l.table, func(t entry) bool { return t.win.ID == ev.Window.ID })
		if i < 0 {
			n := l.entryFor(ev.Window, nil)
			if ev.Kind == windows.Opened {
				n.opened = l.e.o.Now()
			}
			l.table = append(l.table, n)
			return
		}
		old := l.table[i]
		n := l.entryFor(ev.Window, &old)
		n.opened, n.placed = old.opened, old.placed
		switch {
		case ev.Window.Focused:
		case old.win.Focused:
			n.lost = l.e.o.Now()
		default:
			n.lost = old.lost
		}
		l.table[i] = n
	case windows.Closed:
		if i := slices.IndexFunc(l.table, func(t entry) bool { return t.win.ID == ev.Window.ID }); i >= 0 {
			l.table = slices.Delete(l.table, i, i+1)
		}
	}
}

// entryFor is w's entry; the process is read once per window and pid, so
// old's is kept while the pid stays.
func (l *loop) entryFor(w windows.Window, old *entry) entry {
	e := entry{win: w}
	switch {
	case old != nil && old.win.PID == w.PID:
		e.proc = old.proc
	case w.PID > 0:
		if p, ok := l.e.o.Lookup(w.PID); ok {
			e.proc = &p
		}
	}
	if e.game = procinfo.Detect(w.AppID, e.proc); e.game == nil {
		e.game = []procinfo.Signal{}
	}
	e.facts = windowrules.Facts{
		AppID: w.AppID, Title: w.Title, XWayland: w.XWayland,
		// A bridge stands for many windows: its process isn't theirs (D3)
		Game: len(e.game) > 0,
	}
	if e.proc != nil && !e.proc.Bridge {
		e.facts.Process = &windowrules.ProcessFacts{Name: e.proc.Name, Ancestors: e.proc.Ancestors}
	}
	return e
}

// recompute matches every window, merges the holds, stores the snapshot and
// reports a changed State. It returns how long until a window's grace ends.
func (l *loop) recompute() time.Duration {
	now := l.e.o.Now()
	grace := l.e.o.Grace
	next := time.Hour
	var active []windowrules.Active
	snap := &snapshot{}
	byRule := make([][]string, len(l.rules))
	for i := range l.table {
		t := &l.table[i]
		inGrace := false
		if !t.lost.IsZero() {
			if left := grace - now.Sub(t.lost); left > 0 {
				inGrace, next = true, min(next, left)
			} else {
				t.lost = time.Time{}
			}
		}
		t.kinds = l.match.MatchKinds(t.facts)
		moment := windowrules.Moment{Focused: t.win.Focused || inGrace, Fullscreen: t.win.Fullscreen}
		info := WindowInfo{Window: t.win, Process: t.proc, Game: t.game, Rules: []string{}}
		for _, km := range t.kinds {
			ri := km.Rule
			active = append(active, windowrules.Active{
				Rule: l.rules[ri], Priority: ri, Window: t.win.ID, Output: t.win.Output, Moment: moment,
			})
			byRule[ri] = append(byRule[ri], t.win.ID)
			info.Rules = append(info.Rules, l.rules[ri].ID)
		}
		snap.windows = append(snap.windows, info)
		snap.facts = append(snap.facts, t.facts)
	}
	if snap.windows == nil {
		snap.windows = []WindowInfo{}
	}
	st := State{
		Running: l.e.o.Events != nil, Rules: []RuleWindows{},
		Holds: windowrules.Hold(active), Look: windowrules.LookOf(active),
	}
	for ri, ids := range byRule {
		if len(ids) > 0 {
			st.Rules = append(st.Rules, RuleWindows{Rule: l.rules[ri].ID, Windows: ids})
		}
	}
	snap.state = st
	l.e.snap.Store(snap)
	l.placePass(now)
	// Only what the rules decide is compared: a title that changes no
	// match pushes nothing
	b, _ := json.Marshal(st)
	if string(b) != string(l.last) {
		l.last = b
		if l.e.o.OnChange != nil {
			l.e.o.OnChange(st)
		}
	}
	return next
}

// Match is, for every rule of a WindowRules section (defaults filled, not
// saved), the open windows it matches: one row per rule in the section's
// order, its kinds with an issue at or under windows.<k> left out. A
// half-typed condition doesn't zero the others, and a disabled rule counts.
func (e *Engine) Match(section any) []RuleWindows {
	_, keybinds, supports := e.inputs()
	xwayland := supports["ruleXwayland"]
	cfg := windowrules.Parse(section)
	issues := windowrules.Validate(cfg, windowrules.Context{BindIDs: windowrules.BindIDs(keybinds)})
	rules := make([]windowrules.Rule, len(cfg.Rules))
	for i, r := range cfg.Rules {
		kinds := []windowrules.Kind{}
		for ki, k := range r.Kinds {
			if !slices.ContainsFunc(issues, func(is windowrules.Issue) bool { return is.Rule == r.ID && underKind(is.Path, ki) }) {
				kinds = append(kinds, k)
			}
		}
		r.Kinds = kinds
		rules[i] = r
	}
	m := windowrules.NewMatcher(rules, e.o.AppIDs, xwayland)
	snap := e.snap.Load()
	out := make([]RuleWindows, len(rules))
	for i, r := range rules {
		out[i] = RuleWindows{Rule: r.ID, Windows: []string{}}
	}
	for wi, f := range snap.facts {
		for _, ri := range m.Match(f) {
			out[ri].Windows = append(out[ri].Windows, snap.windows[wi].ID)
		}
	}
	return out
}

// underKind is whether an issue's path is windows.<k> or below it.
func underKind(path string, k int) bool {
	p := "windows." + strconv.Itoa(k)
	return path == p || strings.HasPrefix(path, p+".")
}

// planFor is what the saved rules give window t now.
func (l *loop) planFor(t *entry, apply bool) [][]windowrules.Step {
	matches := make([]windowrules.RuleMatch, len(t.kinds))
	for i, km := range t.kinds {
		matches[i] = windowrules.RuleMatch{Rule: l.rules[km.Rule], Kinds: km.Kinds}
	}
	return windowrules.PlanFor(matches, l.reports, l.supports, apply).Batches(t.win.Fullscreen)
}

// placePass places each window that opened within the grace, once. A late
// title that makes a rule match is placed when it arrives; the grace is
// checked when the window next changes, there is no timer. Plans are made
// here, sent outside the loop.
func (l *loop) placePass(now time.Time) {
	if l.e.o.Place == nil || l.reports == nil {
		return
	}
	for i := range l.table {
		t := &l.table[i]
		if t.opened.IsZero() || t.placed || now.Sub(t.opened) > l.e.o.PlaceGrace {
			continue
		}
		if batches := l.planFor(t, false); len(batches) > 0 {
			t.placed = true
			l.send(t.win.ID, batches)
		}
	}
}

// applyNow is Apply to open windows: every window, from before too.
func (l *loop) applyNow() int {
	if l.reports == nil {
		return 0
	}
	n := 0
	now := l.e.o.Now()
	for i := range l.table {
		if t := &l.table[i]; !t.opened.IsZero() && now.Sub(t.opened) <= l.e.o.PlaceGrace {
			continue // placePass owns a window in its grace
		}
		if batches := l.planFor(&l.table[i], true); len(batches) > 0 {
			n++
			l.send(l.table[i].win.ID, batches)
		}
	}
	return n
}

// send runs a window's batches in a goroutine the engine owns, Settle apart.
// A batch that fails (the window closed, a refused command) is logged and the
// next still goes.
func (l *loop) send(id string, batches [][]windowrules.Step) {
	o := l.e.o
	l.wg.Add(1)
	go func() {
		defer l.wg.Done()
		for i, b := range batches {
			if i > 0 {
				timer := time.NewTimer(o.Settle)
				select {
				case <-l.ctx.Done():
					timer.Stop()
					return
				case <-timer.C:
				}
			}
			if l.ctx.Err() != nil {
				return
			}
			if err := o.Place(l.ctx, id, b); err != nil && l.ctx.Err() == nil {
				o.Log.Debug("windowrules: placing a window", "window", id, "err", err)
			}
		}
	}()
}
