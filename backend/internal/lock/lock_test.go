package lock

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

func TestLockConfirmedByTheShell(t *testing.T) {
	t.Parallel()
	var l *Locker
	l = New(Options{
		Confirm:  time.Second,
		AskShell: func(ctx context.Context) error { go l.Report(State{Locked: true, Surfaces: 2, Outputs: 2}); return nil },
	})
	if err := l.Lock(context.Background()); err != nil {
		t.Fatal(err)
	}
	// Already locked: nothing asked again
	l.opts.AskShell = func(ctx context.Context) error { t.Error("asked again"); return nil }
	if err := l.Lock(context.Background()); err != nil {
		t.Fatal(err)
	}
}

func TestPartialLockIsNotConfirmed(t *testing.T) {
	t.Parallel()
	var started atomic.Bool
	var l *Locker
	l = New(Options{
		Confirm:  50 * time.Millisecond,
		AskShell: func(ctx context.Context) error { l.Report(State{Locked: true, Surfaces: 1, Outputs: 2}); return nil },
		StartLocked: func(ctx context.Context) error {
			started.Store(true)
			go l.Report(State{Locked: true, Surfaces: 2, Outputs: 2})
			return nil
		},
	})
	if err := l.Lock(context.Background()); err != nil {
		t.Fatal(err)
	}
	if !started.Load() {
		t.Error("a lock missing an output counted as locked")
	}
}

func TestConfirmRule(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		name  string
		state State
		want  bool
	}{
		{"locked on every output", State{Locked: true, Surfaces: 2, Outputs: 2}, true},
		{"an output without a surface", State{Locked: true, Surfaces: 1, Outputs: 2}, false},
		{"more surfaces than outputs", State{Locked: true, Surfaces: 1, Outputs: 0}, true},
		{"no output connected", State{Locked: true, Surfaces: 0, Outputs: 0}, true},
		{"not locked", State{Locked: false, Surfaces: 1, Outputs: 1}, false},
		{"not locked, no output", State{}, false},
	} {
		if got := c.state.confirmed(); got != c.want {
			t.Errorf("%s: confirmed(%+v) = %v, want %v", c.name, c.state, got, c.want)
		}
	}
}

// With no monitor connected the session lock alone confirms `axiom lock`.
func TestLockWithNoOutputConnected(t *testing.T) {
	t.Parallel()
	var l *Locker
	l = New(Options{
		Confirm:     time.Second,
		AskShell:    func(ctx context.Context) error { go l.Report(State{Locked: true}); return nil },
		StartLocked: func(ctx context.Context) error { t.Error("started the shell locked"); return nil },
	})
	if err := l.Lock(context.Background()); err != nil {
		t.Fatal(err)
	}
}

// A stopped shell's report confirms nothing, even with no output connected,
// until the next shell reports.
func TestStoppedShellConfirmsNothing(t *testing.T) {
	t.Parallel()
	l := New(Options{Confirm: 20 * time.Millisecond})
	l.Report(State{Locked: true})
	if !l.confirmed() {
		t.Fatal("a lock with no output connected wasn't confirmed")
	}
	l.ShellStopped()
	if l.confirmed() {
		t.Error("still confirmed with the shell gone")
	}
	if err := l.Lock(context.Background()); err == nil {
		t.Error("a stopped shell's lock counted")
	}
	l.Report(State{Locked: true})
	if !l.confirmed() {
		t.Error("the next shell's report wasn't confirmed")
	}
}

func TestBuiltinLockerNeverFallsBackToACommand(t *testing.T) {
	t.Parallel()
	marker := filepath.Join(t.TempDir(), "ran")
	l := New(Options{
		Confirm:     20 * time.Millisecond,
		AskShell:    func(ctx context.Context) error { return errors.New("no shell") },
		StartLocked: func(ctx context.Context) error { return nil },
		Mode:        func() string { return "quickshell" },
		Command:     func() string { return "touch " + marker },
	})
	if err := l.Lock(context.Background()); axerr.KindOf(err) != axerr.Unavailable {
		t.Fatalf("an unconfirmed lock succeeded: %v", err)
	}
	time.Sleep(50 * time.Millisecond)
	if _, err := os.Stat(marker); err == nil {
		t.Error("ran a command while the built-in locker is in charge")
	}
}

func TestOwnLockerRunsItsCommandButNotLoginctl(t *testing.T) {
	t.Parallel()
	marker := filepath.Join(t.TempDir(), "ran")
	command := "touch " + marker
	l := New(Options{Mode: func() string { return "none" }, Command: func() string { return command }})
	if err := l.Lock(context.Background()); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 50; i++ {
		if _, err := os.Stat(marker); err == nil {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if _, err := os.Stat(marker); err != nil {
		t.Error("the lock command didn't run")
	}
	command = "loginctl lock-session"
	if err := l.Lock(context.Background()); err == nil {
		t.Error("loginctl lock-session (which loops back to axiom) was run")
	}
}

func TestNoWayToLockFails(t *testing.T) {
	t.Parallel()
	l := New(Options{Confirm: 10 * time.Millisecond})
	if err := l.Lock(context.Background()); err == nil {
		t.Error("succeeded with nothing to lock with")
	}
}

func TestShellDyingWhileLockedRelocks(t *testing.T) {
	t.Parallel()
	restarted := make(chan struct{}, 1)
	l := New(Options{StartLocked: func(ctx context.Context) error { restarted <- struct{}{}; return nil }})
	l.Report(State{Locked: true, Surfaces: 1, Outputs: 1})
	l.ShellExited()
	select {
	case <-restarted:
	case <-time.After(time.Second):
		t.Fatal("not restarted locked")
	}
	if l.confirmed() {
		t.Error("still confirmed with the shell gone")
	}
	// Unlocked, an exit is just an exit
	l.Report(State{Locked: false})
	l.ShellExited()
	select {
	case <-restarted:
		t.Error("restarted locked while unlocked")
	case <-time.After(50 * time.Millisecond):
	}
}

// A stop axiom asked for (a restart, which locks the next shell itself)
// never relaunches: relaunching from it restarted the shell in a loop.
func TestRequestedStopDoesNotRelock(t *testing.T) {
	t.Parallel()
	restarted := make(chan struct{}, 1)
	l := New(Options{StartLocked: func(ctx context.Context) error { restarted <- struct{}{}; return nil }})
	l.Report(State{Locked: true, Surfaces: 1, Outputs: 1})
	if !l.ShellStopped() {
		t.Error("ShellStopped didn't report the lock")
	}
	if st := l.State(); st.Surfaces != 0 || !st.Locked {
		t.Errorf("state %+v, want locked with no surfaces", st)
	}
	select {
	case <-restarted:
		t.Error("relaunched after a requested stop")
	case <-time.After(50 * time.Millisecond):
	}
}
