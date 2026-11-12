package daemon

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sync"
	"syscall"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/compositor/manager"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	sessx "github.com/axiom-shell/axiom/backend/internal/session"
)

// What the session effects of the daemon are, in one place
// (docs/dev/backend/session-teardown.md): the records, the guard process,
// the polkit and wlsunset stops that need undoing, the portal restart, and
// the teardown at the end of Run.

// sessionTest replaces the real effects in tests (nothing here runs a real
// systemctl, kill, spawn or portal restart there).
type sessionTest struct {
	Seams    sessx.Seams
	ProcRoot string
	Bus      sessx.Bus
	// StartGuard replaces starting the guard process; CompositorTeardown
	// the manager's
	StartGuard         func() error
	CompositorTeardown func(context.Context)
}

// guardWait is how long a fresh daemon waits for the old guard to finish
const guardWait = 10 * time.Second

// sessionRec is the runtime record in memory: written on every change, so
// the guard always reads what the daemon knows.
type sessionRec struct {
	mu   sync.Mutex
	path string
	rec  sessx.Runtime
	log  sessx.Logf
}

func (r *sessionRec) saveLocked() {
	// The guard's pid is the guard's to write: keep what is on disk
	if r.rec.GuardPID == 0 {
		if cur := sessx.ReadRuntime(r.path, nil); cur != nil {
			r.rec.GuardPID = cur.GuardPID
		}
	}
	if err := r.rec.Write(r.path); err != nil {
		r.log("session: saving the record: %v", err)
	}
}

// with changes the record under the lock, then saves it.
func (r *sessionRec) with(fn func(*sessx.Runtime)) {
	r.mu.Lock()
	defer r.mu.Unlock()
	fn(&r.rec)
	r.saveLocked()
}

func (r *sessionRec) setSteps(steps []sessx.Step) {
	r.with(func(rt *sessx.Runtime) { rt.Compositor.Steps = steps })
}

func (d *Daemon) sessionLog(format string, args ...any) {
	d.opts.Log.Info("session: "+fmt.Sprintf(format, args...), "part", "session")
}

// seams are the effects of a teardown: real, or a test's
func (d *Daemon) sessionSeams() sessx.Seams {
	if t := d.opts.session; t != nil {
		return t.Seams
	}
	return sessx.Seams{}
}

func (d *Daemon) sessionScope() sessx.Scope {
	s := sessx.ScopeFrom(d.opts.Getenv)
	if t := d.opts.session; t != nil && t.ProcRoot != "" {
		s.ProcRoot = t.ProcRoot
	}
	return s
}

func (d *Daemon) sessionStore() sessx.Store {
	return sessx.StoreFrom(d.opts.Getenv, d.sessionLog)
}

// sessionBusFor is the session bus for one use (nil: none), and its close.
func (d *Daemon) sessionBusFor(ctx context.Context) (sessx.Bus, func()) {
	if t := d.opts.session; t != nil {
		return t.Bus, func() {}
	}
	conn, err := d.sessionBus(ctx)
	if err != nil {
		return nil, func() {}
	}
	return conn, func() { conn.Close() }
}

// sessionActive: the effects are real, or a test replaces them
func (d *Daemon) sessionActive() bool { return d.opts.Guard || d.opts.session != nil }

// teardownOptions are the options a teardown of this session takes, with
// rt the record (under d.sess's lock) and the bus open until done.
func (d *Daemon) teardownOptions(ctx context.Context, rt *sessx.Runtime) (sessx.TeardownOptions, func()) {
	bus, closeBus := d.sessionBusFor(ctx)
	seams := d.sessionSeams()
	o := sessx.TeardownOptions{
		Runtime: rt, RuntimePath: d.sess.path, State: d.sessionStore(), Scope: d.sessionScope(),
		CompositorAlive: !d.compositorGone.Load(), SameInstance: true,
		Bus: bus, Seams: seams, Portal: sessx.PortalEnvFrom(d.opts.Getenv), Log: d.sessionLog,
	}
	o.RestartPortal = sessx.RestartPortalFunc(bus, seams)
	return o, closeBus
}

// startSession makes this daemon's record, and (when it runs the guard)
// heals what a daemon that died left and starts the guard.
func (d *Daemon) startSession(h *handoff) {
	path := d.runtime.File(sessx.RuntimeFile)
	d.sess = &sessionRec{path: path, log: d.sessionLog}
	instance := manager.Instance(d.opts.Getenv)
	kind := ipc.Detect(ipc.LiveEnv(d.opts.Getenv))
	fresh := sessx.Runtime{Instance: instance, DaemonPID: os.Getpid()}
	fresh.Compositor.Kind = kind
	fresh.Compositor.Env = compositorEnv(d.opts.Getenv)
	if h.carried() {
		// A re-exec keeps its guard (the pidfd outlives the exec) and its
		// record
		if cur := sessx.ReadRuntime(path, d.sessionLog); cur != nil && cur.DaemonPID == os.Getpid() {
			d.sess.rec = *cur
			d.sess.rec.Clean = false
		} else {
			d.sess.rec = fresh
		}
		d.sess.with(func(*sessx.Runtime) {})
		if d.opts.Guard && d.guardFree() {
			d.spawnGuard()
		}
		return
	}
	if d.opts.Guard {
		d.waitForGuard(path)
		d.heal(path, instance)
	}
	d.sess.rec = fresh
	d.sess.with(func(*sessx.Runtime) {})
	if d.opts.Guard {
		d.spawnGuard()
	}
}

func compositorEnv(getenv func(string) string) map[string]string {
	env := map[string]string{}
	for _, k := range []string{"HYPRLAND_INSTANCE_SIGNATURE", "SWAYSOCK", "NIRI_SOCKET", "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY"} {
		if v := ipc.LiveEnv(getenv)(k); v != "" {
			env[k] = v
		}
	}
	return env
}

// guardFree: no guard holds guard.lock
func (d *Daemon) guardFree() bool {
	l, err := fsx.TryLock(filepath.Join(d.runtime.Dir, sessx.GuardLock))
	if err != nil {
		return false
	}
	l.Release()
	return true
}

// waitForGuard waits for the old guard (of a daemon that died just now) to
// finish its teardown, so the new daemon doesn't apply its layer under it;
// one that doesn't is killed when it is ours.
func (d *Daemon) waitForGuard(path string) {
	deadline := time.Now().Add(guardWait)
	for !d.guardFree() {
		if time.Now().After(deadline) {
			if rec := sessx.ReadRuntime(path, nil); rec != nil && rec.GuardPID > 0 && d.sessionScope().Owns(rec.GuardPID) {
				d.sessionLog("the old guard %d didn't finish: killing it", rec.GuardPID)
				syscall.Kill(rec.GuardPID, syscall.SIGKILL)
			} else {
				d.sessionLog("the old guard didn't finish in time")
			}
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
}

// heal undoes what a daemon that stopped without its teardown left: for
// the same compositor instance the record's processes and units, for
// another only the state record (units, portal lines). Never the
// compositor's own layer: a fresh daemon re-checks that itself.
func (d *Daemon) heal(path, instance string) {
	rec := sessx.ReadRuntime(path, d.sessionLog)
	if rec == nil || rec.Clean {
		rec = &sessx.Runtime{Clean: true}
	}
	same := rec.Instance == instance
	if !same {
		rec.Stopped = nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), sessx.TeardownBound)
	defer cancel()
	d.sess = &sessionRec{path: path, log: d.sessionLog}
	o, closeBus := d.teardownOptions(ctx, rec)
	defer closeBus()
	o.SameInstance, o.Compositor, o.CompositorAlive = same, false, true
	if rec.Clean && rec.Instance == "" {
		o.RuntimePath = ""
	}
	if err := sessx.Teardown(ctx, o); err != nil {
		d.sessionLog("healing: %v", err)
	}
}

// spawnGuard starts the guard (`axiom guard --stage1`), a process outside
// the daemon's tree that tears down if the daemon dies without doing so.
func (d *Daemon) spawnGuard() {
	if t := d.opts.session; t != nil && t.StartGuard != nil {
		t.StartGuard()
		return
	}
	if err := sessx.StartGuard(d.executable); err != nil {
		d.opts.Log.Warn("session: can't start the guard: a crash won't be cleaned up", "err", err)
	}
}

// sessionTeardown gives the session back what axiom took, as the daemon
// stops cleanly (the shell and the manager are stopped): the compositor's
// layer (unless the compositor is gone), then everything else.
func (d *Daemon) sessionTeardown() {
	if !d.sessionActive() || d.sess == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*sessx.TeardownBound)
	defer cancel()
	gone := d.compositorGone.Load()
	if t := d.opts.session; t != nil && t.CompositorTeardown != nil {
		if !gone {
			t.CompositorTeardown(ctx)
		}
	} else if d.compositor != nil && !gone {
		d.compositor.Teardown(ctx)
	}
	d.sess.mu.Lock()
	defer d.sess.mu.Unlock()
	o, closeBus := d.teardownOptions(ctx, &d.sess.rec)
	defer closeBus()
	o.CompositorAlive = !gone
	d.sess.rec.Compositor.Steps = nil
	if err := sessx.Teardown(ctx, o); err != nil {
		d.sessionLog("teardown: %v", err)
	}
	d.opts.Log.Info("session teardown done")
}

// --- Stopping what the user's session runs ---

// sessionPart: what the shell asks of the session's processes.
func (d *Daemon) sessionPart() part {
	return part{name: "session", methods: d.sessionMethods}
}

// sessionMethods are the daemon's RPCs that stop or restart processes of
// the session, each only in this session's scope: polkit.*, nightlight.
// wlsunset*, screenShare.restartPortal. Only the shell asks.
func (d *Daemon) sessionMethods(reg *rpc.Registry) {
	shellOnly := func(c *rpc.Conn) error {
		if !fromShell(c) {
			return axerr.New(axerr.Refused, "only the shell stops the session's processes")
		}
		return nil
	}
	type patternParams struct {
		Pattern string `json:"pattern"`
	}
	type namesResult struct {
		Names []string `json:"names"`
	}
	rpc.Handle(reg, "polkit.probe", func(ctx context.Context, c *rpc.Conn, p patternParams) (namesResult, error) {
		if err := shellOnly(c); err != nil {
			return namesResult{}, err
		}
		re, err := regexp.Compile(p.Pattern)
		if err != nil {
			return namesResult{}, axerr.Wrap(axerr.BadRequest, err, "the pattern")
		}
		return namesResult{Names: namesOf(d.sessionScope().Find(re))}, nil
	})
	type stopParams struct {
		Pattern string   `json:"pattern"`
		Units   []string `json:"units"`
	}
	rpc.Handle(reg, "polkit.stopOthers", func(ctx context.Context, c *rpc.Conn, p stopParams) (stopOthersResult, error) {
		if err := shellOnly(c); err != nil {
			return stopOthersResult{}, err
		}
		re, err := regexp.Compile(p.Pattern)
		if err != nil {
			return stopOthersResult{}, axerr.Wrap(axerr.BadRequest, err, "the pattern")
		}
		return d.stopOthers(ctx, re, p.Units), nil
	})
	rpc.Handle(reg, "polkit.handBack", func(ctx context.Context, c *rpc.Conn, _ struct{}) (struct{}, error) {
		if err := shellOnly(c); err != nil {
			return struct{}{}, err
		}
		d.handBack(ctx)
		return struct{}{}, nil
	})
	type wlsunsetParams struct {
		On   bool     `json:"on"`
		Argv []string `json:"argv"`
	}
	rpc.Handle(reg, "nightlight.wlsunset", func(ctx context.Context, c *rpc.Conn, p wlsunsetParams) (struct{}, error) {
		if err := shellOnly(c); err != nil {
			return struct{}{}, err
		}
		if p.On && (len(p.Argv) == 0 || filepath.Base(p.Argv[0]) != "wlsunset") {
			return struct{}{}, axerr.New(axerr.BadRequest, "not wlsunset: %v", p.Argv)
		}
		return struct{}{}, d.wlsunset(ctx, p.On, p.Argv)
	})
	rpc.Handle(reg, "nightlight.wlsunsetState", func(ctx context.Context, c *rpc.Conn, _ struct{}) (map[string]bool, error) {
		return map[string]bool{"running": len(d.sessionScope().FindEnv(sessx.Marker(d.sessionScope().WaylandDisplay))) > 0}, nil
	})
	type restartParams struct {
		Backends []sessx.BusUnit `json:"backends"`
	}
	rpc.Handle(reg, "screenShare.restartPortal", func(ctx context.Context, c *rpc.Conn, p restartParams) (struct{}, error) {
		if err := shellOnly(c); err != nil {
			return struct{}{}, err
		}
		return struct{}{}, d.restartPortal(ctx, p.Backends)
	})
}

func namesOf(found []sessx.Found) []string {
	names := []string{}
	for _, f := range found {
		n := f.Basename()
		dup := false
		for _, x := range names {
			dup = dup || x == n
		}
		if !dup {
			names = append(names, n)
		}
	}
	return names
}

// stopOthers stops the polkit agents of this session (their units when the
// user manager is ours, then their processes), each recorded before it is
// stopped; matches outside the session are logged and left alone.
func (d *Daemon) stopOthers(ctx context.Context, re *regexp.Regexp, units []string) stopOthersResult {
	scope := d.sessionScope()
	o, closeBus := d.teardownOptions(ctx, &sessx.Runtime{})
	defer closeBus()
	seams := o.Seams
	res := stopOthersResult{Units: []string{}, Names: []string{}}
	if sessx.UnitsAllowed(ctx, o.Bus) {
		for _, unit := range units {
			if _, err := seams.SystemctlOrDefault()(ctx, "-q", "is-active", unit); err != nil {
				continue
			}
			store := d.sessionStore()
			store.Update(func(st *sessx.State) error {
				for _, u := range st.Units {
					if u.Name == unit && u.Display == scope.WaylandDisplay {
						return nil
					}
				}
				st.Units = append(st.Units, sessx.Unit{Name: unit, Display: scope.WaylandDisplay})
				return nil
			})
			if _, err := seams.SystemctlOrDefault()(ctx, "stop", unit); err != nil {
				d.sessionLog("stopping %s: %v", unit, err)
				continue
			}
			res.Units = append(res.Units, unit)
		}
	} else if len(units) > 0 {
		d.sessionLog("left units alone: this daemon's bus isn't the user manager's")
	}
	for _, f := range scope.Find(re) {
		d.sess.with(func(rt *sessx.Runtime) {
			rt.Stopped = append(rt.Stopped, sessx.Process{Kind: "polkit", Argv: f.Argv, Env: f.Env, Cwd: f.Cwd, PID: f.PID, Start: f.Start})
		})
		if err := seams.SignalOrDefault()(f.PID, syscall.SIGTERM); err != nil {
			d.sessionLog("stopping %s: %v", f.Basename(), err)
			continue
		}
		waitGone(scope, f)
		res.Names = append(res.Names, f.Basename())
	}
	for _, pid := range scope.Elsewhere(re) {
		d.sessionLog("a polkit agent (pid %d) runs in another session: left alone", pid)
	}
	return res
}

type stopOthersResult struct {
	Units []string `json:"units"`
	Names []string `json:"names"`
}

// waitGone waits up to a second for f to exit
func waitGone(scope sessx.Scope, f sessx.Found) {
	for range 20 {
		if !scope.Same(f.PID, f.Start) {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
}

// handBack starts the units axiom stopped and the agents again (polkit
// off).
func (d *Daemon) handBack(ctx context.Context) {
	d.sess.mu.Lock()
	defer d.sess.mu.Unlock()
	o, closeBus := d.teardownOptions(ctx, &d.sess.rec)
	defer closeBus()
	o.CompositorAlive = true
	o.StartUnits(ctx)
	o.Respawn(ctx, "polkit")
	d.sess.saveLocked()
}

// wlsunset turns axiom's own wlsunset on or off. On: a user's wlsunset of
// this session is recorded and stopped first (teardown starts it again);
// axiom's, marked in its environment, is replaced.
func (d *Daemon) wlsunset(ctx context.Context, on bool, argv []string) error {
	scope := d.sessionScope()
	seams := d.sessionSeams()
	marker := sessx.Marker(scope.WaylandDisplay)
	signal := seams.SignalOrDefault()
	if on {
		ours := map[int]bool{}
		for _, f := range scope.FindEnv(marker) {
			ours[f.PID] = true
		}
		for _, f := range scope.Find(sessx.PatternFor("wlsunset")) {
			if ours[f.PID] {
				continue
			}
			d.sess.with(func(rt *sessx.Runtime) {
				rt.Stopped = append(rt.Stopped, sessx.Process{Kind: "wlsunset", Argv: f.Argv, Env: f.Env, Cwd: f.Cwd, PID: f.PID, Start: f.Start})
			})
			signal(f.PID, syscall.SIGTERM)
			waitGone(scope, f)
		}
	}
	for _, f := range scope.FindEnv(marker) {
		signal(f.PID, syscall.SIGTERM)
		waitGone(scope, f)
	}
	if !on {
		return nil
	}
	env := d.commandOptions().Env
	if env == nil {
		env = os.Environ()
	}
	return seams.SpawnOrDefault()(ctx, argv, append(append([]string{}, env...), marker), "")
}

// restartPortal restarts the portal frontend and backends of this session
// only (sessx.RestartPortal), so a changed portal config is read.
func (d *Daemon) restartPortal(ctx context.Context, backends []sessx.BusUnit) error {
	bus, closeBus := d.sessionBusFor(ctx)
	defer closeBus()
	if bus == nil {
		return axerr.New(axerr.Unavailable, "no session bus")
	}
	seams := d.sessionSeams()
	return sessx.RestartPortal(ctx, bus, seams.SystemctlOrDefault(), seams.SignalOrDefault(), backends)
}
