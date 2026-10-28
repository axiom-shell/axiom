// Package manager sets the compositor up for axiom: the Compositor section's
// mode, through the running compositor's config writer
// (docs/dev/compositor/config-modes.md). One layer (binds, required
// settings, the window look, input, blur, monitor profiles, strips) reaches
// the compositor in one of three ways:
//
//	detached  evaluated at runtime, again after every config reload, which
//	          drops it
//	included  written to a module the user's config loads (includeLines)
//	managed   written as the compositor's config itself, after a takeover,
//	          loading the user's own files after it
//
// Whenever the file isn't loaded (included but the lines are missing, or a
// takeover refused), the runtime layer stands in, and `problem` says why.
// The window look and the input are evaluated at runtime as they change, in
// every mode, and again after every reload, so they win over the user's own
// lines while they're on; niri, taking nothing at runtime, gets them in its
// files instead.
//
// What the layer is made of is read from the config (binds, profiles,
// strips, the look's and input's settings, the session, the options), with
// what only the shell knows (Facts: compositor.inputs); the mode is the
// config's too. Everything runs on one goroutine, in order.
package manager

import (
	"context"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/compositor/binds"
	"github.com/axiom-shell/axiom/backend/internal/compositor/edit"
	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/compositor/takeover"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// Options configure a manager.
type Options struct {
	Getenv func(string) string
	// StateDir is $XDG_STATE_HOME/axiom (the modules and approvals go there)
	StateDir string
	// RuntimeFile keeps what was applied across re-execs of the daemon
	RuntimeFile string
	Tables      *render.Tables
	// Schema is the config's schema; Mode the config's Compositor.mode,
	// "" while it isn't known (config.json didn't load at the start): the
	// manager then holds, changing no mode it applied (the defaults'
	// runtime layer only while nothing of axiom's is in the compositor's
	// config); Config the config the layer is made of; Binds its
	// Keybinds.binds; CommitBinds saves Keybinds.binds
	Schema      func() any
	Mode        func() string
	Config      func() *jsonx.Object
	Binds       func() any
	CommitBinds func(binds *jsonx.Array) error
	// Push sends the shell a compositor.* push
	Push func(method string, params any)
	// Bin: the binary (the daemon's own, /proc/self/exe) a bind merge
	// reads Hyprland's files in, a child with its memory limited
	// (binds.Options.Isolate); "" reads them in this process
	Bin string
	Log *slog.Logger
}

// Manager drives the layer for the compositor axiom runs under.
type Manager struct {
	o    Options
	kind string
	w    writer
	st   *runtimeState

	// The manager's goroutine's work, in order. Queued without ever
	// blocking: the store's event delivery and RPC handlers enqueue, and
	// the goroutine may itself be waiting on the store (a merge's save)
	mu      sync.Mutex
	queue   []func(context.Context)
	wake    chan struct{}
	stopped chan struct{}
	stop    sync.Once

	in Inputs
	// facts: the shell's (SetFacts), nil until it sends them
	facts *Facts
	// mode: the config's; "" while it isn't known (holding)
	mode    string
	lastKey string
	liveKey string

	problem         string
	runtimeProblem  string // the last runtimeApply's problems().Runtime
	loaded          bool
	takeoverPending bool
	// pickedHere: managed was saved while axiom runs (its card's Save, not
	// an edit of the file), where the card asks for the approval: no
	// notification
	pickedHere bool
	// releaseProblem: why the managed config couldn't be given back (retried
	// after releaseBackoff)
	releaseProblem string
	releaseBackoff time.Duration
	// releaseFirst is the first retry's delay (tests shorten it)
	releaseFirst    time.Duration
	managedCheck    string
	monitorConflict []string
	merging         bool
	lastMerge       any
	mergeable       float64
	pushed          string

	debounce, liveDebounce, fileSync, releaseRetry *time.Timer
}

// New is the manager for the compositor the environment names; Kind is ""
// (and it does nothing) under none of axiom's config modes' compositors.
func New(o Options) *Manager {
	m := &Manager{o: o, wake: make(chan struct{}, 1), stopped: make(chan struct{}), mergeable: -1, releaseFirst: 10 * time.Second}
	instance := ""
	switch {
	case o.Getenv("HYPRLAND_INSTANCE_SIGNATURE") != "":
		m.kind, instance = "hyprland", o.Getenv("HYPRLAND_INSTANCE_SIGNATURE")
	case o.Getenv("NIRI_SOCKET") != "":
		m.kind, instance = "niri", o.Getenv("NIRI_SOCKET")
	case o.Getenv("SWAYSOCK") != "":
		m.kind, instance = "sway", o.Getenv("SWAYSOCK")
	}
	m.st = loadState(o.RuntimeFile, m.kind+":"+instance)
	stateDir := strings.TrimSuffix(o.StateDir, "/") + "/"
	e := env{getenv: o.Getenv, stateDir: stateDir, tables: o.Tables, schema: o.Schema, logf: m.logf, state: m.st}
	switch m.kind {
	case "hyprland":
		m.w = newHypr(e, ipc.HyprFromEnv(o.Getenv))
	case "sway":
		m.w = newSway(e, ipc.SwayFromEnv(o.Getenv))
	case "niri":
		m.w = newNiri(e, ipc.NiriFromEnv(o.Getenv))
	}
	m.debounce = m.timer(func(ctx context.Context) { m.apply(ctx) })
	m.liveDebounce = m.timer(m.liveChanged)
	m.fileSync = m.timer(m.syncFile)
	m.releaseRetry = m.timer(func(ctx context.Context) { m.apply(ctx) })
	return m
}

// Kind is the compositor ("hyprland", "sway", "niri" or "").
func (m *Manager) Kind() string { return m.kind }

// ScreenPower turns every screen off, or back on, through the
// compositor's own socket.
func (m *Manager) ScreenPower(ctx context.Context, on bool) error {
	if m.w == nil {
		return axerr.New(axerr.Unavailable, "no compositor to turn the screens off with")
	}
	return m.w.screenPower(ctx, on)
}

// AddLayerRules adds Hyprland's layer rules for axiom's surfaces
// (compositor.layerRules), which the shell waits for before mapping the
// ones with an order; one Hyprland didn't take is logged.
func (m *Manager) AddLayerRules(ctx context.Context) error {
	h, ok := m.w.(*hyprWriter)
	if !ok {
		return axerr.New(axerr.Unavailable, "layer rules are Hyprland's")
	}
	h.addLayerRules(ctx)
	return nil
}

func (m *Manager) logf(format string, args ...any) {
	m.o.Log.Info("compositor: " + sprintf(format, args...))
}

// timer is a stopped timer running fn on the manager's goroutine
func (m *Manager) timer(fn func(context.Context)) *time.Timer {
	t := time.AfterFunc(time.Hour, func() { m.enqueue(fn) })
	t.Stop()
	return t
}

// enqueue queues fn for the manager's goroutine; dropped with no
// compositor to drive (nothing would ever run it) or once Run has ended
func (m *Manager) enqueue(fn func(context.Context)) bool {
	if m.w == nil {
		return false
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	select {
	case <-m.stopped:
		return false
	default:
	}
	m.queue = append(m.queue, fn)
	select {
	case m.wake <- struct{}{}:
	default:
	}
	return true
}

// next takes the first queued fn, or nil
func (m *Manager) next() func(context.Context) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if len(m.queue) == 0 {
		return nil
	}
	fn := m.queue[0]
	m.queue[0] = nil
	m.queue = m.queue[1:]
	return fn
}

// do runs fn on the manager's goroutine and waits for it (not at all when
// it can't run)
func (m *Manager) do(ctx context.Context, fn func(context.Context)) {
	done := make(chan struct{})
	if !m.enqueue(func(c context.Context) { fn(c); close(done) }) {
		return
	}
	select {
	case <-done:
	case <-ctx.Done():
	case <-m.stopped:
	}
}

// Run runs the manager until ctx ends: its goroutine, and the compositor's
// event stream (reconnected while the compositor runs).
func (m *Manager) Run(ctx context.Context) error {
	defer m.stop.Do(func() {
		m.mu.Lock()
		close(m.stopped)
		m.queue = nil
		m.mu.Unlock()
		for _, t := range []*time.Timer{m.debounce, m.liveDebounce, m.fileSync, m.releaseRetry} {
			t.Stop()
		}
	})
	if m.w == nil {
		<-ctx.Done()
		return nil
	}
	reloads := make(chan ipc.Reload, 8)
	var watching sync.WaitGroup
	watching.Add(1)
	go func() {
		defer watching.Done()
		m.watchReloads(ctx, reloads)
	}()
	// The event stream ends with ctx: waited for, so nothing of the
	// manager's outlives Run
	defer watching.Wait()
	poll := time.NewTicker(2 * time.Second)
	defer poll.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-m.wake:
			for fn := m.next(); fn != nil && ctx.Err() == nil; fn = m.next() {
				fn(ctx)
			}
			m.push()
		case r := <-reloads:
			m.configReloaded(ctx, r)
			m.push()
		case <-poll.C:
			// What the layer is made of beyond the shell's inputs (niri's
			// user files)
			m.checkKey()
		}
	}
}

func (m *Manager) watchReloads(ctx context.Context, out chan<- ipc.Reload) {
	for ctx.Err() == nil {
		inner := make(chan ipc.Reload)
		forwarded := make(chan struct{})
		go func() {
			defer close(forwarded)
			for r := range inner {
				// Counted at once: a reload while the runtime layer reads the
				// binds makes what it read stale
				m.w.seenReload()
				select {
				case out <- r:
				case <-ctx.Done():
				}
			}
		}()
		err := m.w.reloads(ctx, inner)
		close(inner)
		<-forwarded
		if ctx.Err() != nil {
			return
		}
		if err != nil {
			m.o.Log.Debug("compositor: event stream", "err", err)
		}
		select {
		case <-ctx.Done():
		case <-time.After(2 * time.Second):
		}
	}
}

// live: the shell has sent what the layer is made of, for this compositor
func (m *Manager) live() bool {
	return m.w != nil && m.in.Object != nil && m.in.str("kind") == m.kind
}

// --- From the daemon ---

// SetFacts takes what only the shell knows of the layer
// (compositor.inputs).
func (m *Manager) SetFacts(f Facts) {
	m.enqueue(func(ctx context.Context) {
		m.facts = &f
		m.setInputs(buildInputs(m.o.Config(), m.facts))
	})
}

// setInputs takes what the layer is made of, on the manager's goroutine
func (m *Manager) setInputs(in Inputs) {
	wasLive := m.live()
	m.in = in
	if !m.live() {
		return
	}
	if !wasLive {
		m.mode = m.o.Mode()
		m.noteHolding()
		m.debounce.Reset(300 * time.Millisecond)
	}
	m.checkKey()
	if key := m.in.str("liveKey"); key != m.liveKey {
		m.liveKey = key
		m.liveDebounce.Reset(300 * time.Millisecond)
	}
}

// ConfigChanged tells of a config change (what the layer is made of, the
// mode); fromFile when it was read from config.json (an edit made outside),
// not saved by the shell.
func (m *Manager) ConfigChanged(fromFile bool) {
	m.enqueue(func(ctx context.Context) {
		if m.facts != nil {
			m.setInputs(buildInputs(m.o.Config(), m.facts))
		}
		if !m.live() {
			return
		}
		if mode := m.o.Mode(); mode != m.mode {
			m.mode = mode
			m.modeChanged(fromFile)
			m.debounce.Reset(300 * time.Millisecond)
		}
	})
}

// noteHolding logs that the mode isn't known, so no mode is applied
func (m *Manager) noteHolding() {
	if m.mode == "" {
		m.logf("config.json doesn't load: leaving the compositor's config as it is until it's fixed")
	}
}

// axiomsInConfig: a managed config or an include of axiom's is actually
// in the compositor's config, which holding never touches; loaded when
// axiom's file (the module, or the managed config) is in effect.
// AppliedMode managed alone doesn't count: a takeover awaiting approval,
// blocked or failed left the user's config in place, and gets the runtime
// layer as outside the hold
func (m *Manager) axiomsInConfig(ctx context.Context) (in, loaded bool) {
	if m.moduleLoaded(ctx) {
		return true, true
	}
	if !m.configIsOurs() {
		return false, false
	}
	loaded, _ = m.w.checkLoaded(ctx, m.in, "managed")
	return true, loaded
}

// moduleLoaded: the included module is in effect with axiom's layer in it.
// An emptied one (left behind by a switch out of included) doesn't count:
// niri's check only sees that the user's config reaches the file, and its
// include line is often left in place
func (m *Manager) moduleLoaded(ctx context.Context) bool {
	if text := readFile(m.files().IncludePath); text == "" || text == m.w.emptyModuleText() {
		return false
	}
	loaded, _ := m.w.checkLoaded(ctx, m.in, "included")
	return loaded
}

// applyHolding: while the mode isn't known, the defaults' runtime layer,
// as detached mode applies it, only when nothing of axiom's is in the
// compositor's config; no mode is set up or given back, and the applied
// mode stays
func (m *Manager) applyHolding(ctx context.Context) {
	if in, loaded := m.axiomsInConfig(ctx); in {
		// A layer applied before axiom's file loaded comes off, as
		// checkLoaded takes it off (niri's wrapper would load it twice)
		if loaded {
			m.w.runtimeClear(ctx)
		}
		return
	}
	// The reload's configReloaded applies the layer again
	if m.undoLive(ctx) {
		return
	}
	m.runtimeApply(ctx)
}

// checkKey re-applies the layer when what it's made of changed
func (m *Manager) checkKey() {
	if !m.live() {
		return
	}
	key := m.in.str("layerKey") + "|" + m.w.ownKey(m.in)
	if key != m.lastKey {
		m.lastKey = key
		m.debounce.Reset(300 * time.Millisecond)
	}
}

// --- The state the shell shows ---

func (m *Manager) status() string {
	switch {
	case m.mode == "":
		return "pending"
	case m.mode == "detached":
		return "runtime"
	case m.problem != "":
		return "fallback"
	case m.loaded:
		return "loaded"
	}
	return "pending"
}

// State is what the shell shows (compositor.state).
func (m *Manager) State(ctx context.Context) *jsonx.Object {
	var out *jsonx.Object
	m.do(ctx, func(context.Context) { out = m.state() })
	return out
}

func (m *Manager) state() *jsonx.Object {
	check, by, repo := m.managedCheck, "", ""
	if word, rest, ok := strings.Cut(m.managedCheck, ":"); ok {
		check = word
		by, repo, _ = strings.Cut(rest, ":")
		if by != "git" {
			repo = ""
		}
	}
	complete := jsonx.Arr()
	skipped, conflicts := jsonx.Arr(), jsonx.Arr()
	var fs, look any
	runningConfig, userBindsRead := "", false
	if m.w != nil {
		runningConfig, userBindsRead = m.w.runningConfig(m.in), m.w.userBindsRead()
	}
	if m.live() {
		for _, b := range itemsOf(activeBinds(m.in)) {
			if m.w.complete(m.in, b) {
				complete.Append(b)
			}
		}
		for _, k := range m.w.skippedKeys() {
			skipped.Append(k)
		}
		fs = m.w.files(m.in).json()
		// The window look as set now, for a backend setting it a window at
		// a time as windows open (sway: SwayManager.setLiveLook)
		look = getAny(m.in.get("specLive"), "look")
	}
	for _, c := range m.monitorConflict {
		conflicts.Append(c)
	}
	return jsonx.Obj("kind", m.kind, "live", m.live(), "mode", m.mode, "status", m.status(), "problem", m.problem,
		"takeoverPending", m.takeoverPending, "managedCheck", check, "managedBlockedBy", by, "managedBlockedRepo", repo,
		"monitorConflicts", conflicts, "skippedKeys", skipped, "complete", complete, "merging", m.merging,
		"lastMerge", m.lastMerge, "mergeable", m.mergeable, "runningConfig", runningConfig, "userBindsRead", userBindsRead,
		"releaseProblem", m.releaseProblem, "files", fs, "look", look)
}

// push sends the state when it changed
func (m *Manager) push() {
	if m.w == nil || m.o.Push == nil {
		return
	}
	s := m.state()
	if text := string(jsonx.MarshalCompact(s)); text != m.pushed {
		m.pushed = text
		m.o.Push("compositor.state", s)
	}
}

func (m *Manager) warnOnce(message string) {
	if m.problem == message {
		return
	}
	m.problem = message
	m.o.Log.Warn("compositor: " + message)
}

func (m *Manager) files() files { return m.w.files(m.in) }

// --- Files (included, managed) ---

// writeIfChanged writes text to path unless it's already there, then
// reloads the compositor, which doesn't watch files a config loads. A
// writer that can check its text first leaves the file as it was when the
// compositor would refuse it, and says why.
func (m *Manager) writeIfChanged(ctx context.Context, path, text string) {
	if readFile(path) == text {
		m.checkLoaded(ctx)
		// No reload to evaluate the live parts after: what's only set at
		// runtime is sent now
		m.applyLive(ctx)
		return
	}
	if err := m.w.validate(ctx, text); err != "" {
		m.warnOnce(m.w.problems(m.in).Invalid(err))
		return
	}
	if err := writeFile(path, text); err != nil {
		m.o.Log.Warn("compositor: could not write "+path, "err", err)
		return
	}
	m.w.reload(ctx)
}

// checkLoaded: after a (re)load, is the file in effect? If not, the
// runtime layer stands in for it
func (m *Manager) checkLoaded(ctx context.Context) {
	if !m.live() {
		return
	}
	loaded, failed := m.w.checkLoaded(ctx, m.in, m.mode)
	if m.mode == "detached" {
		return
	}
	// The compositor couldn't load its config at all: the runtime layer
	// wouldn't load either
	if failed {
		m.warnOnce(m.w.problems(m.in).Failed)
		return
	}
	if loaded {
		m.problem = ""
		m.loaded = true
		m.w.runtimeClear(ctx)
		return
	}
	if m.mode == "included" {
		m.warnOnce(m.w.problems(m.in).NotIncluded)
		m.notify("included")
	} else if m.problem == "" {
		m.warnOnce(m.w.problems(m.in).NotManaged)
	}
	m.runtimeApply(ctx)
}

func (m *Manager) runtimeApply(ctx context.Context) {
	m.w.runtimeApply(ctx, m.in, func() []string { return m.liveLines(ctx) })
	// The layer isn't as axiom made it: the card says so (a file mode's own
	// problem comes first), until it is
	p := m.w.problems(m.in).Runtime
	switch {
	case p != "" && (m.problem == "" || m.problem == m.runtimeProblem):
		m.warnOnce(p)
	case p == "" && m.runtimeProblem != "" && m.problem == m.runtimeProblem:
		m.problem = ""
	case p != "" && p != m.runtimeProblem:
		// Behind a file mode's problem: logged, once
		m.o.Log.Warn("compositor: " + p)
	}
	m.runtimeProblem = p
	m.applied()
}

// applied tells the shell the compositor was changed at runtime (it reads
// back what it follows: Hyprland's options, sway's windows)
func (m *Manager) applied() {
	if m.o.Push != nil {
		m.o.Push("compositor.applied", jsonx.NewObject())
	}
}

func (m *Manager) notify(what string) {
	if m.o.Push != nil {
		m.o.Push("compositor.notify", jsonx.Obj("what", what))
	}
}

// --- Driving it ---

func (m *Manager) apply(ctx context.Context) {
	if !m.live() {
		return
	}
	// The mode isn't known (config.json didn't load at the start, and
	// running on the defaults would read detached): the mode applied stays,
	// a managed config never given back, until the file is fixed
	if m.mode == "" {
		m.applyHolding(ctx)
		return
	}
	// Detached, the reload's configReloaded applies the layer again. The
	// file modes go on: returning would drop a mode switch or a rewrite
	if m.undoLive(ctx) && m.mode == "detached" {
		return
	}
	previous := m.st.AppliedMode
	// The config still axiom's outside managed mode (a release that failed,
	// or a mode changed while axiom wasn't running): given back now, and
	// again until it is
	if m.mode != "managed" && previous != "managed" && m.configIsOurs() {
		previous = "managed"
	}
	if m.mode == "managed" {
		m.releaseDone()
	}
	released := false
	if previous != "" && previous != m.mode {
		released = m.leave(ctx, previous)
	}
	m.st.AppliedMode = m.mode
	m.st.save()
	switch m.mode {
	case "included":
		m.writeIfChanged(ctx, m.files().IncludePath, m.w.moduleText(m.in, m.in.get("specFile")))
	case "managed":
		m.claimIfApproved(ctx)
	default:
		m.problem = ""
		// A release has applied it, or reloads the given-back config
		// first (the managed layer would be in the way)
		if !released {
			m.runtimeApply(ctx)
		}
	}
}

// modeChanged: a problem belongs to the mode it was found in
func (m *Manager) modeChanged(fromFile bool) {
	m.problem = ""
	m.loaded = false
	m.takeoverPending = false
	m.monitorConflict = nil
	// Saving managed never approves a takeover: the card shows Allow
	// takeover after it, as it does for a config loaded with the mode.
	// Read from the file (one that didn't load at the start, fixed to say
	// managed), no card is open: the notification asks
	m.pickedHere = m.mode == "managed" && !fromFile
}

// --- Approving a takeover ---

func (m *Manager) approvals() approvals {
	return approvals{path: filepath.Join(m.o.StateDir, "ui", "takeover.json")}
}

func (m *Manager) approve() {
	if err := m.approvals().add(m.kind); err != nil {
		m.o.Log.Warn("compositor: saving the takeover's approval", "err", err)
	}
}

func (m *Manager) approvalProblem() string {
	return `Compositor mode is "managed", but taking over ` + m.files().ManagedPath +
		` needs your approval (Settings › Compositor). Applying axiom's layer at runtime meanwhile.`
}

// AllowTakeover is the status card's (and the notification's) Allow: the
// one approval to take over the user's own config, used up when it's given
// back.
func (m *Manager) AllowTakeover() {
	m.enqueue(func(ctx context.Context) {
		if m.w == nil || m.mode != "managed" {
			return
		}
		m.approve()
		m.takeoverPending = false
		m.problem = ""
		if m.mode == "managed" {
			m.apply(ctx)
		}
	})
}

func (m *Manager) takeoverOptions(mode string) takeover.Options {
	kind, _ := takeover.KindNamed(m.w.takeoverKind())
	return takeover.Options{Kind: kind, Dir: m.files().ConfigDir, Header: m.w.header(),
		Fallback: m.w.releasedText(m.in, mode), Getenv: m.o.Getenv}
}

// configIsOurs: the compositor's config is the one axiom wrote (its first
// line starts with the header)
func (m *Manager) configIsOurs() bool {
	first, _, _ := strings.Cut(readFile(m.files().ManagedPath), "\n")
	return strings.HasPrefix(first, m.w.header())
}

// CheckManaged says what switching to managed would do: ours, adopt,
// stock, released, new or blocked.
func (m *Manager) CheckManaged(ctx context.Context) string {
	out := ""
	m.do(ctx, func(ctx context.Context) {
		if m.live() {
			m.check(ctx)
			out, _, _ = strings.Cut(m.managedCheck, ":")
		}
	})
	return out
}

func (m *Manager) check(ctx context.Context) {
	result, err := takeover.Check(ctx, m.takeoverOptions(m.mode))
	if err != nil {
		m.o.Log.Warn("compositor: checking the takeover", "err", err)
		return
	}
	m.managedCheck = result
}

// claimIfApproved takes the config over when there's nothing of the
// user's in it (axiom's already, none, the example, what a release wrote),
// or they allowed it; else it waits for Allow takeover, the runtime layer
// standing in
func (m *Manager) claimIfApproved(ctx context.Context) {
	if !m.approvals().has(m.kind) {
		m.check(ctx)
		word, _, _ := strings.Cut(m.managedCheck, ":")
		switch word {
		// Nothing of the user's to take over, or blocked anyway (claim says)
		case "ours", "new", "stock", "released", "blocked":
		default:
			m.takeoverPending = true
			m.warnOnce(m.approvalProblem())
			if !m.pickedHere {
				m.notify("approval")
			}
			m.runtimeApply(ctx)
			return
		}
	}
	m.takeoverPending = false
	m.claim(ctx)
}

// claim takes the config over and writes the managed config, both under
// the config dir's lock, so a command line's release can't come between
// them
func (m *Manager) claim(ctx context.Context) {
	lock, err := edit.LockDir(ctx, m.files().ConfigDir)
	if err != nil {
		m.o.Log.Warn("compositor: taking over "+m.files().ManagedPath, "err", err)
		return
	}
	o := m.takeoverOptions(m.mode)
	o.Locked = true
	result, err := takeover.Claim(ctx, o)
	m.findMonitorConflicts()
	if err != nil {
		lock.Release()
		m.o.Log.Warn("compositor: taking over "+m.files().ManagedPath, "err", err)
		return
	}
	word, rest, _ := strings.Cut(result, ":")
	switch word {
	case "blocked":
		lock.Release()
		m.warnOnce(m.w.problems(m.in).Blocked)
		m.runtimeApply(ctx)
		return
	case "adopted":
		m.logf("Took over %s; your previous one is %s/%s", m.files().ManagedPath, m.files().UserDir, rest)
	case "replaced":
		m.logf("Replaced %s (the example config is kept as a dated backup beside it)", m.files().ManagedPath)
	}
	m.writeIfChanged(ctx, m.files().ManagedPath, m.w.managedText(m.in, m.in.get("specFile")))
	lock.Release()
	// The adopted config's binds would fight axiom's: they move in. Only
	// that file's: the user's other files are left to the Keybinds page's
	// Merge (which takes the lock itself)
	if word == "adopted" {
		m.merge(ctx, rest, false)
	}
}

// release gives the config back. One that fails (an error, or the dir now
// a link or in git) is tried again, ever later, while the mode isn't
// managed, and the shell shows why (releaseProblem)
func (m *Manager) release(ctx context.Context) {
	result, err := takeover.Release(ctx, m.takeoverOptions(m.mode))
	word, rest, _ := strings.Cut(result, ":")
	switch {
	case err != nil:
		m.releaseFailed("Couldn't give back " + m.files().ManagedPath + ": " + err.Error())
	case word == "blocked":
		m.releaseFailed(m.files().ManagedPath + " is a symlink or in a git repository now, so axiom can't give it back: " +
			"make it a plain file outside git, or replace it with your own config")
	default:
		m.releaseDone()
		if word != "notours" {
			// The approval was for this takeover: the next asks again
			if err := m.approvals().remove(m.kind); err != nil {
				m.o.Log.Warn("compositor: forgetting the takeover's approval", "err", err)
			}
		}
	}
	switch word {
	case "restored":
		from, n, _ := strings.Cut(rest, ":")
		m.logf("Gave back %s: it's %s again", m.files().ManagedPath, from)
		if n != "0" && n != "" {
			m.o.Log.Warn("compositor: " + m.files().ManagedPath + " is your previous config again, which doesn't load " +
				m.files().UserFiles + " (" + n + " files): load them from it if you still want them")
		}
	case "written":
		m.logf("Gave back %s: it now starts axiom and loads %s, and is yours to edit", m.files().ManagedPath, m.files().UserFiles)
	}
	// A reload brings the given-back config in, and with it the runtime
	// layer; without one, the runtime layer goes on now
	if word == "restored" || word == "written" {
		m.w.reload(ctx)
	} else if m.mode == "detached" {
		m.runtimeApply(ctx)
	}
}

// releaseFailed notes why a release failed (logged when it changes) and
// tries again later: 10 s, doubling up to 5 min
func (m *Manager) releaseFailed(why string) {
	if why != m.releaseProblem {
		m.o.Log.Warn("compositor: " + why)
	}
	m.releaseProblem = why
	switch {
	case m.releaseBackoff == 0:
		m.releaseBackoff = m.releaseFirst
	case m.releaseBackoff < 5*time.Minute:
		m.releaseBackoff = min(2*m.releaseBackoff, 5*time.Minute)
	}
	m.releaseRetry.Reset(m.releaseBackoff)
}

func (m *Manager) releaseDone() {
	m.releaseProblem = ""
	m.releaseBackoff = 0
	m.releaseRetry.Stop()
}

// leave gives back what previous took: leaving managed, the config it
// claimed; leaving included (or managed, whose restored config may load
// it), the module, which then does nothing. Else the old layer stays in
// the compositor's config, and the runtime layer, which only adds, can't
// undo it. True when it ran a release, which brings the runtime layer
// in itself.
func (m *Manager) leave(ctx context.Context, previous string) bool {
	if m.mode != "included" {
		m.emptyModule(ctx)
	}
	if previous == "managed" {
		m.release(ctx)
		return true
	}
	return false
}

func (m *Manager) emptyModule(ctx context.Context) {
	path, empty := m.files().IncludePath, m.w.emptyModuleText()
	if current := readFile(path); current == "" || current == empty {
		return
	}
	if err := writeFile(path, empty); err != nil {
		m.o.Log.Warn("compositor: could not write "+path, "err", err)
		return
	}
	m.w.reload(ctx)
}

// findMonitorConflicts: managed mode's files in user/ that set monitors
// themselves (they load after axiom's layer, so theirs win)
func (m *Manager) findMonitorConflicts() {
	m.monitorConflict = nil
	if m.mode != "managed" {
		return
	}
	pattern, glob := m.w.monitorPattern()
	dir := m.files().UserDir
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		if ok, _ := filepath.Match(glob, e.Name()); !ok || e.IsDir() {
			continue
		}
		for _, line := range strings.Split(readFile(filepath.Join(dir, e.Name())), "\n") {
			if pattern.MatchString(line) {
				m.monitorConflict = append(m.monitorConflict, dir+"/"+e.Name())
				break
			}
		}
	}
}

// --- The window look and the input, over the user's config in every mode ---

// applyLive evaluates the live parts now (after a reload in the file
// modes: the module set them before the user's own lines)
func (m *Manager) applyLive(ctx context.Context) {
	if !m.live() || m.w.liveByFile() {
		return
	}
	m.w.runLive(ctx, m.liveLines(ctx))
	m.applied()
}

// liveLines are the live parts as evaluated now, noting which parts that
// applies; the cursor theme is set as it changes (a reload keeps it)
func (m *Manager) liveLines(ctx context.Context) []string {
	now := m.in.get("specLive")
	m.st.LiveApplied = strings.Join(m.appliedParts(now), ",")
	cursor := getAny(getAny(now, "input"), "cursor")
	key := ""
	if cursor != nil {
		key = jsonx.ToString(getAny(cursor, "theme")) + "|" + jsonx.ToString(getAny(cursor, "xcursor")) + "|" + jsonx.ToString(getAny(cursor, "size"))
	}
	if key != "" && key != m.st.LiveCursor {
		m.w.setCursor(ctx, cursor)
	}
	m.st.LiveCursor = key
	m.st.save()
	return m.w.liveLines(m.in, now)
}

// appliedParts are the look's and the input's parts on in spec, of those
// the compositor applies (one it can't was never evaluated, so turning it
// off reloads nothing) and the shell doesn't take back itself (takesBack)
func (m *Manager) appliedParts(spec any) []string {
	supports := m.in.get("supports")
	var out []string
	for _, p := range strList(getAny(getAny(spec, "look"), "parts")) {
		if p != "" && getAny(supports, "window"+strings.ToUpper(p[:1])+p[1:]) == true && !m.w.takesBack(p) {
			out = append(out, p)
		}
	}
	if getAny(supports, "inputConfig") == true {
		for _, p := range strList(getAny(getAny(spec, "input"), "parts")) {
			if p != "cursor" {
				out = append(out, "input:"+p)
			}
		}
	}
	return out
}

// droppedParts are the parts evaluated since the last reload that are off
// now
func (m *Manager) droppedParts() []string {
	now := map[string]bool{}
	for _, p := range m.appliedParts(m.in.get("specLive")) {
		now[p] = true
	}
	var out []string
	for _, p := range strings.Split(m.st.LiveApplied, ",") {
		if p != "" && !now[p] {
			out = append(out, p)
		}
	}
	return out
}

// fileText is the mode's file's text now, and its path
func (m *Manager) fileText() (string, string) {
	spec := m.in.get("specFile")
	switch m.mode {
	case "managed":
		return m.files().ManagedPath, m.w.managedText(m.in, spec)
	case "included":
		return m.files().IncludePath, m.w.moduleText(m.in, spec)
	}
	return "", ""
}

// undoLive: a runtime eval can't take a setting back, so a part turned off
// since it was evaluated reloads the compositor's config. True when it
// reloaded.
func (m *Manager) undoLive(ctx context.Context) bool {
	dropped := m.droppedParts()
	if len(dropped) == 0 {
		return false
	}
	m.st.LiveApplied = ""
	m.st.save()
	// The file modes rewrite their file, which reloads anyway, unless it
	// never held the part (only evaluated at runtime since its last write)
	if m.mode != "detached" && m.st.AppliedMode == m.mode && m.status() == "loaded" {
		if path, text := m.fileText(); readFile(path) != text {
			return false
		}
	}
	m.logf("Window look or input turned off (%s); reloading the compositor's config to take it back", strings.Join(dropped, ", "))
	m.w.reload(ctx)
	return true
}

// liveChanged: the look, the input or the blur changed. Only evaluated at
// runtime, in every mode (a reload on every step of a setting stalls the
// desktop); turning a part off goes through apply()
func (m *Manager) liveChanged(ctx context.Context) {
	if !m.live() {
		return
	}
	if m.mode == "" {
		if in, _ := m.axiomsInConfig(ctx); in {
			return
		}
		if m.w.liveByFile() || len(m.droppedParts()) > 0 {
			m.apply(ctx)
			return
		}
		m.applyLive(ctx)
		return
	}
	if m.w.liveByFile() || m.st.AppliedMode != m.mode || len(m.droppedParts()) > 0 {
		m.apply(ctx)
		return
	}
	m.applyLive(ctx)
	m.fileSync.Reset(2 * time.Second)
}

// syncFile: the file modes' file follows the live parts too, once they've
// settled, written without a reload (the runtime eval applied them), so the
// next session starts from them
func (m *Manager) syncFile(ctx context.Context) {
	if !m.live() || m.w.liveByFile() || m.st.AppliedMode != m.mode || m.status() != "loaded" {
		return
	}
	path, text := m.fileText()
	if path == "" || readFile(path) == text {
		return
	}
	if m.mode == "managed" {
		lock, err := edit.LockDir(ctx, m.files().ConfigDir)
		if err != nil {
			m.o.Log.Warn("compositor: could not write "+path, "err", err)
			return
		}
		defer lock.Release()
		// Given back meanwhile (a command line's release): never written
		// over. The takeover allowed is over, so apply() asks again
		if !m.configIsOurs() {
			m.logf("%s isn't axiom's any more: taking it over needs your approval again", path)
			if err := m.approvals().remove(m.kind); err != nil {
				m.o.Log.Warn("compositor: forgetting the takeover's approval", "err", err)
			}
			m.loaded = false
			m.debounce.Reset(300 * time.Millisecond)
			return
		}
	}
	if err := writeFile(path, text); err != nil {
		m.o.Log.Warn("compositor: could not write "+path, "err", err)
	}
}

// configReloaded: a reload drops runtime binds, rules, the look and the
// input
func (m *Manager) configReloaded(ctx context.Context, r ipc.Reload) {
	// Hyprland drops the layer rules a reload doesn't load, which the
	// detached mode's files don't hold and a broken include loses
	if h, ok := m.w.(*hyprWriter); ok {
		h.addLayerRules(ctx)
	}
	if n, ok := m.w.(*niriWriter); ok {
		n.lastFailed = r.Failed
		if r.Failed {
			return
		}
	}
	if !m.live() {
		return
	}
	m.w.noteReload()
	m.st.LiveApplied = ""
	m.st.save()
	if m.w.configReloaded(ctx, m.in) {
		m.checkKey()
	}
	// Holding, apply() applies the defaults' layer again when nothing of
	// axiom's is in the config
	if m.mode == "detached" || m.mode == "" {
		m.debounce.Reset(300 * time.Millisecond)
	} else {
		m.checkLoaded(ctx)
		m.applyLive(ctx)
	}
	// The compositor reloads when one of the user's files changes
	if m.mode == "managed" {
		m.findMonitorConflicts()
	}
}

// Reload reloads the compositor's config (the include lines just added).
func (m *Manager) Reload() {
	m.enqueue(func(ctx context.Context) {
		if m.live() {
			m.w.reload(ctx)
		}
	})
}

// Entries are the binds in effect (the user's and axiom's) where the shell
// can't read them from the compositor (sway, niri); nil when unknown.
func (m *Manager) Entries(ctx context.Context) any {
	var out any
	m.do(ctx, func(ctx context.Context) {
		if m.live() {
			if e := m.w.entries(ctx, m.in); e != nil {
				out = e
			}
		}
	})
	return out
}

// --- Moving the user's binds into axiom (managed mode) ---

// Merge moves the binds in user/ into axiom (only: one file name there,
// the adopted one, else all of them).
func (m *Manager) Merge(only string) {
	m.enqueue(func(ctx context.Context) { m.merge(ctx, only, false) })
}

// PreviewMerge counts what a Merge would move (mergeable), changing
// nothing.
func (m *Manager) PreviewMerge() {
	m.enqueue(func(ctx context.Context) { m.merge(ctx, "", true) })
}

func (m *Manager) mergeOptions(only string) binds.Options {
	return binds.Options{Kind: m.kind, Dir: m.files().ConfigDir, Only: only, Getenv: m.o.Getenv,
		Isolate: m.o.Bin}
}

// merge: every bind in user/ that can move becomes one of axiom's, saved
// first, then it's taken out of its file (a dated backup kept). A bind
// that couldn't be has its binds taken back out of axiom's, so no key is
// ever bound twice.
func (m *Manager) merge(ctx context.Context, only string, preview bool) {
	if !m.live() || m.mode != "managed" || m.merging {
		return
	}
	m.merging = true
	m.push()
	defer func() { m.merging = false }()
	found, err := binds.Extract(ctx, m.mergeOptions(only))
	if err != nil {
		if preview {
			m.mergeable = 0
			return
		}
		m.o.Log.Warn("compositor: reading your binds failed", "err", err)
		m.lastMerge = jsonx.Obj("moved", 0.0, "removed", 0.0, "kept", jsonx.Arr(), "failed", jsonx.Arr(), "remapped", jsonx.Arr(),
			"tracked", jsonx.Arr(), "errors", jsonx.Arr(err.Error()))
		return
	}
	moving := itemsOf(found.Value("binds"))
	if preview {
		m.mergeable = float64(len(moving))
		return
	}
	merged := jsonx.Obj("moved", float64(len(moving)), "removed", 0.0, "kept", found.Value("kept"), "failed", jsonx.Arr(),
		"remapped", found.Value("remapped"), "tracked", found.Value("tracked"), "errors", found.Value("errors"))
	if len(moving) == 0 {
		m.lastMerge = merged
		m.mergeable = 0
		return
	}
	// Saved before the calls go, so no bind is ever missing
	before := m.o.Binds()
	if err := m.o.CommitBinds(withIDs(render.MergeBinds(before, found.Value("binds")))); err != nil {
		m.o.Log.Warn("compositor: saving the merged binds", "err", err)
		merged.Set("moved", 0.0)
		merged.Set("saveFailed", true)
		m.lastMerge = merged
		return
	}
	sites, _ := found.Value("sites").(*jsonx.Array)
	done, err := binds.Remove(ctx, m.mergeOptions(""), sites)
	if err != nil {
		// Nothing is known to be deleted: every file's binds go back
		failed, seen := jsonx.Arr(), map[string]bool{}
		for _, s := range itemsOf(sites) {
			if f := jsonx.ToString(getAny(s, "file")); !seen[f] {
				seen[f] = true
				failed.Append(jsonx.Obj("file", f, "line", 0.0, "reason", "crashed", "detail", err.Error()))
			}
		}
		done = jsonx.Obj("removed", 0.0, "files", jsonx.Arr(), "failed", failed)
	}
	failed := itemsOf(done.Value("failed"))
	left := func(site any) bool {
		for _, f := range failed {
			if getAny(f, "file") == getAny(site, "file") && (getAny(f, "line") == 0.0 || getAny(f, "line") == getAny(site, "line")) {
				return true
			}
		}
		return false
	}
	moved := jsonx.Arr()
	for _, s := range itemsOf(sites) {
		if !left(s) {
			moved.Append(itemsOf(getAny(s, "binds"))...)
		}
	}
	if len(failed) > 0 {
		if err := m.o.CommitBinds(withIDs(render.MergeBinds(before, moved))); err != nil {
			m.o.Log.Warn("compositor: couldn't take the binds left in your config back out of axiom's", "err", err)
		}
		for _, f := range failed {
			m.o.Log.Warn("compositor: left binds where they were", "file", getAny(f, "file"), "line", getAny(f, "line"),
				"reason", getAny(f, "reason"), "detail", getAny(f, "detail"))
		}
	}
	merged.Set("moved", float64(len(moved.Items)))
	merged.Set("removed", done.Value("removed"))
	merged.Set("failed", done.Value("failed"))
	if len(moved.Items) > 0 && m.o.Push != nil {
		m.o.Push("compositor.bindsMerged", jsonx.Obj("binds", moved))
	}
	m.lastMerge = merged
	m.mergeable = -1
	m.logf("Moved %d binds from %s into axiom; %d stay there", len(moved.Items), m.files().UserDir, len(itemsOf(found.Value("kept"))))
}

var (
	nonSlug = regexp.MustCompile(`[^a-z0-9]+`)
	validID = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]*$`)
)

// withIDs gives every bind an id (the schema's ItemId: required, unique in
// the list), as BindKeys.withIds does on the Keybinds page: a valid one not
// taken by an earlier bind is kept, the rest get one made from the key
// ("SUPER + Y" -> "super-y", then "super-y-2"; "bind" with no key). The
// binds a merge moves in come without one.
func withIDs(list *jsonx.Array) *jsonx.Array {
	taken := map[string]bool{}
	for i, b := range list.Items {
		o, ok := b.(*jsonx.Object)
		if !ok {
			continue
		}
		if id, _ := o.Value("id").(string); validID.MatchString(id) && !taken[id] {
			taken[id] = true
			continue
		}
		base := strings.Trim(nonSlug.ReplaceAllString(strings.ToLower(jsonx.ToString(o.Value("key"))), "-"), "-")
		if len(base) > 40 {
			base = strings.TrimRight(base[:40], "-")
		}
		if base == "" {
			base = "bind"
		}
		id := base
		for n := 2; taken[id]; n++ {
			id = base + "-" + strconv.Itoa(n)
		}
		taken[id] = true
		withID := jsonx.Obj("id", id)
		for _, k := range o.Keys() {
			if k != "id" {
				withID.Set(k, o.Value(k))
			}
		}
		list.Items[i] = withID
	}
	return list
}
