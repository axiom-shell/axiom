// Package lockscreen makes `axiom lock` dependable. With the built-in locker
// (Lockscreen.mode "quickshell") it succeeds only when the shell confirms
// the lock screen is up on every output, else tries harder (a shell
// started locked), then fails loudly: there is no other locker to fall
// back on. With the user's own locker ("none") it runs their lock
// command. A shell that dies while locked is started again at once,
// locking before anything else. Nothing here unlocks: only PAM, in the
// shell, does (docs/dev/features/lockscreen.md).
package lockscreen

import (
	"context"
	"log/slog"
	"strings"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/shellcmd"
)

// Options are how the locker reaches the shell.
type Options struct {
	// AskShell asks the running shell to lock (ipc lockscreen lock)
	AskShell func(ctx context.Context) error
	// StartLocked (re)starts the shell with AXIOM_LOCK_ON_START=1
	StartLocked func(ctx context.Context) error
	// Mode is Lockscreen.mode, and Command Lockscreen.lockCommand (the
	// user's own locker, for mode "none")
	Mode    func() string
	Command func() string
	// Confirm is how long the shell has to report it locked
	Confirm time.Duration
	Log     *slog.Logger
	// Go runs work that outlives a call (a relaunch, waiting for the
	// user's locker) on a goroutine its owner stops (default: a plain
	// goroutine on a background context, for tests)
	Go func(func(context.Context))
}

// State is what the shell last reported.
type State struct {
	// Locked: the session lock is up and the compositor acknowledged it
	Locked bool `json:"locked"`
	// Holding: the shell holds the session lock or is taking it,
	// acknowledged or not. A shell that dies so is restarted locked: the
	// acknowledgement can be missing while the compositor keeps the
	// session locked (a lock taken over by a reloaded generation never
	// sees it again), and nothing else would take the lock back
	Holding  bool `json:"holding"`
	Surfaces int  `json:"surfaces"`
	Outputs  int  `json:"outputs"`
}

// held: the session is locked, or being locked, by the shell.
func (s State) held() bool {
	return s.Locked || s.Holding
}

// Locker tracks the lock screen and locks on request.
type Locker struct {
	opts Options

	mu    sync.Mutex
	state State
	// gone: the shell that made the last report has stopped, so the
	// report confirms nothing until the next shell reports
	gone    bool
	changed chan struct{} // closed and replaced on every report
}

// New returns a locker.
func New(opts Options) *Locker {
	if opts.Confirm == 0 {
		opts.Confirm = 3 * time.Second
	}
	if opts.Log == nil {
		opts.Log = slog.New(slog.DiscardHandler)
	}
	if opts.Go == nil {
		opts.Go = func(fn func(context.Context)) { go fn(context.Background()) }
	}
	return &Locker{opts: opts, changed: make(chan struct{})}
}

// Report records the shell's lock state (lock.state, from the shell's own
// connection only).
func (l *Locker) Report(s State) {
	l.mu.Lock()
	l.state = s
	l.gone = false
	close(l.changed)
	l.changed = make(chan struct{})
	l.mu.Unlock()
}

// State is the last report.
func (l *Locker) State() State {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.state
}

// Held is whether the last report holds the session locked (or locking):
// what a restarted shell must lock again.
func (l *Locker) Held() bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.state.held()
}

// ShellStopped is told when the shell was stopped on purpose (a restart,
// which starts the next one locked itself, or the daemon stopping): its
// surfaces went with it. It reports whether the session was locked
// (held).
func (l *Locker) ShellStopped() bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.state.Surfaces = 0
	l.gone = true
	return l.state.held()
}

// confirmed: the session lock is up, with a lock surface on every output
// the shell knows of. With no output connected the session lock alone
// confirms it: the compositor holds the session locked, and the shell
// builds a lock surface for each output connected later.
func (s State) confirmed() bool {
	return s.Locked && s.Surfaces >= s.Outputs
}

// confirmed: the running shell's last report confirms the lock.
func (l *Locker) confirmed() bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.confirmedLocked()
}

// confirmedLocked is confirmed with l.mu held.
func (l *Locker) confirmedLocked() bool {
	return !l.gone && l.state.confirmed()
}

// Lock locks the session: with the built-in locker, returning nil only
// once the shell confirms it.
func (l *Locker) Lock(ctx context.Context) error {
	if l.opts.Mode != nil && l.opts.Mode() == "none" {
		return l.ownLocker()
	}
	if l.confirmed() {
		return nil
	}
	if l.opts.AskShell != nil {
		if err := l.opts.AskShell(ctx); err != nil {
			l.opts.Log.Warn("the shell didn't take the lock request", "err", err)
		} else if l.wait(ctx, l.opts.Confirm) {
			return nil
		}
	}
	if l.opts.StartLocked != nil {
		l.opts.Log.Warn("the shell didn't confirm the lock: starting it locked")
		if err := l.opts.StartLocked(ctx); err != nil {
			l.opts.Log.Error("starting the shell locked", "err", err)
		} else if l.wait(ctx, 2*l.opts.Confirm) {
			return nil
		}
	}
	l.opts.Log.Error("the session could not be locked: the shell didn't confirm the lock screen")
	return axerr.New(axerr.Unavailable, "the session could not be locked: the shell didn't confirm the lock screen")
}

// ownLocker runs the user's lock command (mode "none"). Their locker
// can't confirm anything to axiom, so running it is all there is.
// `loginctl lock-session` is refused: logind hands that lock request to
// the idle daemon, which calls axiom lock again.
func (l *Locker) ownLocker() error {
	command := ""
	if l.opts.Command != nil {
		command = strings.TrimSpace(l.opts.Command())
	}
	if command == "" || command == "loginctl lock-session" {
		return axerr.New(axerr.Unavailable, "the lock screen is your own (Lockscreen.mode none), and Lockscreen.lockCommand doesn't name a locker")
	}
	return shellcmd.Start(command, l.opts.Go)
}

// wait waits for a confirmed report.
func (l *Locker) wait(ctx context.Context, d time.Duration) bool {
	deadline := time.After(d)
	for {
		l.mu.Lock()
		ok, changed := l.confirmedLocked(), l.changed
		l.mu.Unlock()
		if ok {
			return true
		}
		select {
		case <-changed:
		case <-deadline:
			return false
		case <-ctx.Done():
			return false
		}
	}
}

// ShellExited is told when the shell process ends on its own. Locked, it
// is started again at once and locks before anything else: the compositor
// keeps the session locked meanwhile (ext-session-lock), and the new shell
// takes the lock over.
func (l *Locker) ShellExited() {
	if !l.ShellStopped() || l.opts.StartLocked == nil {
		return
	}
	l.opts.Log.Warn("the shell exited while locked: starting it again, locked")
	l.opts.Go(func(ctx context.Context) {
		ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
		defer cancel()
		if err := l.opts.StartLocked(ctx); err != nil && ctx.Err() == nil {
			l.opts.Log.Error("restarting the shell locked", "err", err)
		}
	})
}
