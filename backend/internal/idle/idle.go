// Package idle is what axiom does when the user steps away (the Idle
// section), in place of hypridle: dimming, locking, turning the screens
// off and suspending after their timeouts (idle notifications on the
// daemon's Wayland connection, wayland/idlenotify), locking when logind
// asks (loginctl lock-session) and before sleep (holding sleep with a
// delay inhibitor until the lock screen is up), and holding off while an
// app asks it to: over org.freedesktop.ScreenSaver (internal/screensaver),
// logind's idle inhibitors (systemd-inhibit), or, when the compositor's
// own inhibitors are ignored, axiom's caffeine. Docs:
// docs/dev/features/idle.md.
package idle

import (
	"context"
	"encoding/json"
	"log/slog"
	"os"
	"reflect"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/logind"
	"github.com/axiom-shell/axiom/backend/internal/screensaver"
)

// Notifier arms idle notifications (wayland/idlenotify.Notifier).
type Notifier interface {
	Available() bool
	Watch(timeout time.Duration, respectInhibitors bool, onIdle, onResume func()) (cancel func())
}

// Actions are how the steps reach the rest of axiom.
type Actions struct {
	// Dim dims every screen to percent ("to") or by percent of its
	// brightness ("by"); Undim brings them back (the shell's brightness)
	Dim   func(ctx context.Context, mode string, percent int) error
	Undim func(ctx context.Context) error
	// Lock locks the session (lock.Locker)
	Lock func(ctx context.Context) error
	// ScreenPower turns the screens off or on (the compositor's socket)
	ScreenPower func(ctx context.Context, on bool) error
	// Command runs a line of the user's own (shellcmd)
	Command func(line string) error
}

// Options configure the service.
type Options struct {
	Notifier Notifier
	Actions  Actions
	// SystemBus and SessionBus connect to the buses (nil: none, in
	// tests); logind is on the first, ScreenSaver on the second
	SystemBus, SessionBus func(ctx context.Context) (*dbus.Conn, error)
	Getenv                func(string) string
	// CompositorPID tells whether the program holding ScreenSaver is the
	// compositor (niri answers it itself)
	CompositorPID func() int
	// OnState is told every new state
	OnState func(State)
	Log     *slog.Logger
	// Retry is how long a lost bus waits to be dialled again (30 s)
	Retry time.Duration
}

// State is what the shell shows (idle.state).
type State struct {
	Enabled bool `json:"enabled"`
	// Notifier: the compositor offers idle notifications
	Notifier bool `json:"notifier"`
	// Armed is how many listeners are armed; 0 while inhibited
	Armed      int         `json:"armed"`
	Inhibited  bool        `json:"inhibited"`
	Inhibitors []Inhibitor `json:"inhibitors"`
	// Fired are the listeners (by plan index) idle has reached
	Fired       []int            `json:"fired"`
	Logind      bool             `json:"logind"`
	ScreenSaver ScreenSaverState `json:"screensaver"`
}

// Inhibitor is one thing holding idle off.
type Inhibitor struct {
	Source string `json:"source"` // "screensaver" | "logind" | "caffeine"
	App    string `json:"app"`
	Reason string `json:"reason"`
}

// ScreenSaverState is the ScreenSaver name, while axiom serves it.
type ScreenSaverState struct {
	Serving bool `json:"serving"`
	Owned   bool `json:"owned"`
	// Owner holds the name when axiom doesn't; Compositor when it's the
	// compositor (which then applies the inhibitors itself)
	Owner      *screensaver.Owner `json:"owner"`
	Compositor bool               `json:"compositor"`
}

// Service runs the idle steps.
type Service struct {
	o       Options
	posts   chan func()
	work    chan func(context.Context)
	stopped chan struct{}

	mu    sync.Mutex
	state State

	// The sleep inhibitor, taken and closed by the worker
	sleepMu   sync.Mutex
	sleepFile *os.File

	// The loop's own state
	settings      Settings
	armKey        string
	gen           int
	armed         []*armed
	plan          []Listener
	caffeine      bool
	lg            *logind.Logind
	delayMax      time.Duration
	idleBlocked   bool
	idleApps      []logind.Inhibitor
	ss            *screensaver.Server
	sleepHeld     *logind.Logind // the logind the sleep inhibitor was taken from
	stopSystem    context.CancelFunc
	stopSession   context.CancelFunc
	busCtx        context.Context
	wg            sync.WaitGroup
	lastPublished State
	published     bool
}

type armed struct {
	cancel func()
	fired  bool
}

// New returns a service; Run runs it.
func New(o Options) *Service {
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	if o.Retry == 0 {
		o.Retry = 30 * time.Second
	}
	if o.Getenv == nil {
		o.Getenv = os.Getenv
	}
	return &Service{o: o, posts: make(chan func(), 256), work: make(chan func(context.Context), 64), stopped: make(chan struct{})}
}

// State is the last state.
func (s *Service) State() State {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.state
}

// Configure applies the Idle settings.
func (s *Service) Configure(settings Settings) {
	s.post(func() {
		s.settings = settings
		s.reconcile()
	})
}

// SetCaffeine is the shell's caffeine switch: it holds idle off itself
// only where notifications ignore the compositor's inhibitors.
func (s *Service) SetCaffeine(on bool) {
	s.post(func() {
		s.caffeine = on
		s.reconcile()
	})
}

// NotifierChanged is told when the compositor's notifier came or went.
func (s *Service) NotifierChanged() { s.post(s.publish) }

// post runs fn on the loop; dropped once the service stopped.
func (s *Service) post(fn func()) {
	select {
	case s.posts <- fn:
	case <-s.stopped:
	}
}

// Run runs the service until ctx ends.
func (s *Service) Run(ctx context.Context) error {
	s.busCtx = ctx
	s.wg.Add(1)
	go func() {
		defer s.wg.Done()
		s.worker(ctx)
	}()
	defer func() {
		close(s.stopped)
		s.stopBuses()
		s.wg.Wait()
	}()
	for {
		select {
		case <-ctx.Done():
			s.disarm(false)
			return nil
		case fn := <-s.posts:
			fn()
		}
	}
}

// reconcile brings everything in line with the settings and what holds
// idle off: the buses, the sleep inhibitor, the armed listeners.
func (s *Service) reconcile() {
	st := s.settings
	if st.Enabled && s.o.SystemBus != nil && s.stopSystem == nil {
		var ctx context.Context
		ctx, s.stopSystem = context.WithCancel(s.busCtx)
		s.goBus(func() { s.runLogind(ctx) })
	} else if !st.Enabled && s.stopSystem != nil {
		s.stopSystem()
		s.stopSystem, s.lg, s.idleBlocked, s.idleApps = nil, nil, false, nil
	}
	wantSession := st.Enabled && st.RespectInhibitors && s.o.SessionBus != nil
	if wantSession && s.stopSession == nil {
		var ctx context.Context
		ctx, s.stopSession = context.WithCancel(s.busCtx)
		s.goBus(func() { s.runScreenSaver(ctx) })
	} else if !wantSession && s.stopSession != nil {
		s.stopSession()
		s.stopSession, s.ss = nil, nil
	}

	// The sleep inhibitor, from the logind connected now
	wantSleep := st.Enabled && st.LockBeforeSleep && s.lg != nil
	switch {
	case wantSleep && s.sleepHeld != s.lg:
		lg := s.lg
		s.sleepHeld = lg
		s.enqueue(func(ctx context.Context) { s.takeSleep(ctx, lg) })
	case !wantSleep && s.sleepHeld != nil:
		s.sleepHeld = nil
		s.enqueue(func(context.Context) { s.releaseSleep() })
	}

	if !st.Enabled || s.inhibited() {
		s.disarm(true)
	} else if key := armKey(Plan(st), st.RespectInhibitors); key != s.armKey {
		s.disarm(true)
		s.arm(Plan(st), key)
	}
	s.publish()
}

func (s *Service) goBus(fn func()) {
	s.wg.Add(1)
	go func() {
		defer s.wg.Done()
		fn()
	}()
}

func (s *Service) stopBuses() {
	if s.stopSystem != nil {
		s.stopSystem()
	}
	if s.stopSession != nil {
		s.stopSession()
	}
}

// inhibited: something holds idle off that the compositor doesn't know
// of. With inhibitors respected, the compositor holds off for Wayland
// inhibitors (caffeine among them), and axiom for ScreenSaver's and
// logind's; ignoring them, only caffeine still counts.
func (s *Service) inhibited() bool {
	if !s.settings.RespectInhibitors {
		return s.caffeine
	}
	return s.idleBlocked || s.ss != nil && len(s.ss.Inhibitors()) > 0
}

// armKey: a plan armed the same way needs no arming again.
func armKey(plan []Listener, respect bool) string {
	b, _ := json.Marshal(struct {
		Plan    []Listener
		Respect bool
	}{plan, respect})
	return string(b)
}

func (s *Service) arm(plan []Listener, key string) {
	s.plan, s.armKey = plan, key
	s.gen++
	gen := s.gen
	respect := s.settings.RespectInhibitors
	s.armed = make([]*armed, len(plan))
	for i, l := range plan {
		a := &armed{}
		s.armed[i] = a
		a.cancel = s.o.Notifier.Watch(l.Timeout, respect,
			func() { s.post(func() { s.idled(gen, i) }) },
			func() { s.post(func() { s.resumed(gen, i) }) })
	}
}

// disarm cancels every listener; resume runs the return of those idle
// had reached (the screens come back when an app starts holding idle
// off, or idle is turned off).
func (s *Service) disarm(resume bool) {
	for i, a := range s.armed {
		a.cancel()
		if a.fired && resume {
			s.act(s.plan[i].OnResume)
		}
	}
	s.armed, s.armKey = nil, ""
	s.gen++
}

func (s *Service) idled(gen, i int) {
	if gen != s.gen || s.armed[i].fired {
		return
	}
	s.armed[i].fired = true
	s.o.Log.Debug("idle", "after", s.plan[i].Timeout, "action", s.plan[i].OnTimeout.Kind)
	s.act(s.plan[i].OnTimeout)
	s.publish()
}

func (s *Service) resumed(gen, i int) {
	if gen != s.gen || !s.armed[i].fired {
		return
	}
	s.armed[i].fired = false
	s.act(s.plan[i].OnResume)
	s.publish()
}

// activity: an app said the user is active (SimulateUserActivity): the
// timeouts start again.
func (s *Service) activity() {
	if len(s.armed) == 0 {
		return
	}
	plan, key := s.plan, s.armKey
	s.disarm(true)
	s.arm(plan, key)
	s.publish()
}

// --- Actions, run in order off the loop ---

func (s *Service) enqueue(job func(context.Context)) {
	select {
	case s.work <- job:
	default:
		s.o.Log.Warn("idle: too many actions waiting: one was dropped")
	}
}

func (s *Service) worker(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			s.releaseSleep()
			return
		case job := <-s.work:
			job(ctx)
		}
	}
}

// act queues an action.
func (s *Service) act(a Action) {
	if a.Kind == None {
		return
	}
	lg := s.lg
	s.enqueue(func(ctx context.Context) {
		ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
		defer cancel()
		if err := s.run(ctx, a, lg); err != nil {
			s.o.Log.Warn("idle: an action failed", "action", a.Kind, "err", err)
		}
	})
}

func (s *Service) run(ctx context.Context, a Action, lg *logind.Logind) error {
	x := s.o.Actions
	switch a.Kind {
	case Dim:
		return call(x.Dim != nil, func() error { return x.Dim(ctx, a.Mode, a.Percent) })
	case Undim:
		return call(x.Undim != nil, func() error { return x.Undim(ctx) })
	case Lock:
		return call(x.Lock != nil, func() error { return x.Lock(ctx) })
	case ScreenOff, ScreenOn:
		return call(x.ScreenPower != nil, func() error { return x.ScreenPower(ctx, a.Kind == ScreenOn) })
	case Suspend:
		if lg == nil {
			return axerr.New(axerr.Unavailable, "logind isn't reachable: can't suspend")
		}
		return lg.Suspend(ctx)
	case Command:
		return call(x.Command != nil, func() error { return x.Command(a.Line) })
	}
	return nil
}

func call(ok bool, fn func() error) error {
	if !ok {
		return axerr.New(axerr.Unavailable, "not available here")
	}
	return fn()
}

func (s *Service) takeSleep(ctx context.Context, lg *logind.Logind) {
	s.releaseSleep()
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	f, err := lg.InhibitSleep(ctx, "axiom", "Lock the screen before sleep")
	if err != nil {
		s.o.Log.Warn("idle: no sleep inhibitor: the screen may lock after sleep, not before", "err", err)
		return
	}
	s.sleepMu.Lock()
	s.sleepFile = f
	s.sleepMu.Unlock()
}

func (s *Service) releaseSleep() {
	s.sleepMu.Lock()
	defer s.sleepMu.Unlock()
	if s.sleepFile != nil {
		s.sleepFile.Close()
		s.sleepFile = nil
	}
}

// --- logind ---

func (s *Service) runLogind(ctx context.Context) {
	for {
		err := s.logindOnce(ctx)
		if ctx.Err() != nil {
			return
		}
		s.o.Log.Warn("idle: logind is out of reach: retrying", "in", s.o.Retry, "err", err)
		select {
		case <-ctx.Done():
			return
		case <-time.After(s.o.Retry):
		}
	}
}

func (s *Service) logindOnce(ctx context.Context) error {
	conn, err := s.o.SystemBus(ctx)
	if err != nil {
		return err
	}
	defer conn.Close()
	lg, err := logind.Open(ctx, conn, s.o.Getenv)
	if err != nil {
		return err
	}
	delay, err := lg.InhibitDelayMax(ctx)
	if err != nil {
		delay = 5 * time.Second
	}
	s.o.Log.Debug("idle: logind", "session", lg.Session(), "delay", delay)
	s.post(func() {
		if ctx.Err() == nil {
			s.lg, s.delayMax = lg, delay
			s.reconcile()
		}
	})
	defer s.post(func() {
		if s.lg == lg {
			s.lg, s.idleBlocked, s.idleApps = nil, false, nil
			s.reconcile()
		}
	})
	return lg.Watch(ctx, func(e logind.Event) {
		switch {
		case e.Lock:
			s.post(func() {
				if s.settings.Enabled {
					s.act(Action{Kind: Lock})
				}
			})
		case e.SleepChanged:
			sleep := e.Sleep
			s.post(func() { s.sleepChanged(sleep) })
		case e.IdleChanged:
			var apps []logind.Inhibitor
			if e.IdleBlocked {
				apps, _ = lg.IdleInhibitors(ctx)
			}
			blocked := e.IdleBlocked
			s.post(func() {
				if s.lg == lg {
					s.idleBlocked, s.idleApps = blocked, apps
					s.reconcile()
				}
			})
		}
	})
}

// sleepChanged: before sleep, lock, then let sleep go on; after it, take
// the inhibitor again and turn the screens on.
func (s *Service) sleepChanged(sleeping bool) {
	st := s.settings
	if !st.Enabled {
		return
	}
	if sleeping {
		if st.LockBeforeSleep {
			delay := s.delayMax - 500*time.Millisecond
			if delay < time.Second {
				delay = time.Second
			}
			lock := s.o.Actions.Lock
			s.sleepHeld = nil // taken again on waking
			s.enqueue(func(ctx context.Context) {
				ctx, cancel := context.WithTimeout(ctx, delay)
				defer cancel()
				if lock != nil {
					if err := lock(ctx); err != nil {
						s.o.Log.Warn("idle: locking before sleep", "err", err)
					}
				}
				s.releaseSleep()
			})
		}
		return
	}
	s.reconcile()
	if st.ScreenOnAfterSleep {
		s.act(Action{Kind: ScreenOn})
	}
}

// --- ScreenSaver ---

func (s *Service) runScreenSaver(ctx context.Context) {
	for {
		err := s.screenSaverOnce(ctx)
		if ctx.Err() != nil {
			return
		}
		s.o.Log.Warn("idle: the session bus is out of reach: retrying", "in", s.o.Retry, "err", err)
		select {
		case <-ctx.Done():
			return
		case <-time.After(s.o.Retry):
		}
	}
}

func (s *Service) screenSaverOnce(ctx context.Context) error {
	conn, err := s.o.SessionBus(ctx)
	if err != nil {
		return err
	}
	defer conn.Close()
	srv := screensaver.New(screensaver.Options{
		Log:        s.o.Log,
		OnChange:   func() { s.post(func() { s.reconcile() }) },
		OnActivity: func() { s.post(s.activity) },
	})
	s.post(func() {
		if ctx.Err() == nil {
			s.ss = srv
			s.reconcile()
		}
	})
	defer s.post(func() {
		if s.ss == srv {
			s.ss = nil
			s.reconcile()
		}
	})
	return srv.Run(ctx, conn)
}

// --- State ---

func (s *Service) publish() {
	st := State{
		Enabled:    s.settings.Enabled,
		Notifier:   s.o.Notifier.Available(),
		Armed:      len(s.armed),
		Inhibited:  s.settings.Enabled && s.inhibited(),
		Logind:     s.lg != nil,
		Inhibitors: []Inhibitor{},
		Fired:      []int{},
	}
	for i, a := range s.armed {
		if a.fired {
			st.Fired = append(st.Fired, i)
		}
	}
	if s.ss != nil {
		owned, owner := s.ss.Owned()
		st.ScreenSaver = ScreenSaverState{Serving: true, Owned: owned, Owner: owner}
		if owner != nil && s.o.CompositorPID != nil && owner.PID != 0 && int(owner.PID) == s.o.CompositorPID() {
			st.ScreenSaver.Compositor = true
		}
		for _, in := range s.ss.Inhibitors() {
			st.Inhibitors = append(st.Inhibitors, Inhibitor{Source: "screensaver", App: in.App, Reason: in.Reason})
		}
	}
	for _, in := range s.idleApps {
		st.Inhibitors = append(st.Inhibitors, Inhibitor{Source: "logind", App: in.Who, Reason: in.Why})
	}
	if s.caffeine && !s.settings.RespectInhibitors {
		st.Inhibitors = append(st.Inhibitors, Inhibitor{Source: "caffeine"})
	}
	if s.published && reflect.DeepEqual(st, s.lastPublished) {
		return
	}
	s.lastPublished, s.published = st, true
	s.mu.Lock()
	s.state = st
	s.mu.Unlock()
	if s.o.OnState != nil {
		s.o.OnState(st)
	}
}
