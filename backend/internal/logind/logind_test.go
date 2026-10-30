package logind

import (
	"context"
	"io"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
	"github.com/axiom-shell/axiom/backend/internal/logind/logindtest"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

func ctx(t *testing.T) context.Context {
	t.Helper()
	c, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	t.Cleanup(cancel)
	return c
}

func open(t *testing.T, bus *dbustest.Bus, getenv func(string) string) (*Logind, error) {
	t.Helper()
	conn, err := dbus.Dial(ctx(t), bus.Address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	return Open(ctx(t), conn, getenv)
}

func TestFindsTheSession(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	logindtest.New(t, bus)
	l, err := open(t, bus, logindtest.Getenv)
	if err != nil {
		t.Fatal(err)
	}
	if l.Session() != logindtest.SessionPath {
		t.Errorf("session %q", l.Session())
	}
	// Without the id, and no session for the pid, the user's display
	// session is asked for; the fake has no Display property
	if _, err := open(t, bus, func(string) string { return "" }); err == nil {
		t.Error("found a session without a way to")
	}
}

func TestCallsAndInhibitors(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	f := logindtest.New(t, bus)
	l, err := open(t, bus, logindtest.Getenv)
	if err != nil {
		t.Fatal(err)
	}
	if err := l.Suspend(ctx(t)); err != nil {
		t.Fatal(err)
	}
	if f.Suspended() != 1 {
		t.Errorf("suspended %d times", f.Suspended())
	}
	if d, err := l.InhibitDelayMax(ctx(t)); err != nil || d != 5*time.Second {
		t.Errorf("delay %v, %v", d, err)
	}
	f.SetInhibitors(
		[]any{"idle", "mpv", "Playing", "block", uint32(1000), uint32(42)},
		[]any{"sleep", "NetworkManager", "", "delay", uint32(0), uint32(7)},
		[]any{"idle:sleep", "Firefox", "Video", "block", uint32(1000), uint32(43)},
	)
	ins, err := l.IdleInhibitors(ctx(t))
	if err != nil {
		t.Fatal(err)
	}
	if len(ins) != 2 || ins[0].Who != "mpv" || ins[1].Who != "Firefox" || ins[1].PID != 43 {
		t.Errorf("inhibitors %+v", ins)
	}

	fd, err := l.InhibitSleep(ctx(t), "axiom", "Lock the screen before sleep")
	if err != nil {
		t.Fatal(err)
	}
	r := <-f.Inhibited
	defer r.Close()
	fd.Close()
	// Once logind's copy is gone too, closing ours ends the pipe
	r.SetReadDeadline(time.Now().Add(3 * time.Second))
	if _, err := io.ReadAll(r); err != nil {
		t.Errorf("the inhibitor wasn't released: %v", err)
	}
}

func TestWatch(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	f := logindtest.New(t, bus)
	l, err := open(t, bus, logindtest.Getenv)
	if err != nil {
		t.Fatal(err)
	}
	events := make(chan Event, 8)
	wctx, cancel := context.WithCancel(ctx(t))
	done := make(chan error, 1)
	go func() { done <- l.Watch(wctx, func(e Event) { events <- e }) }()
	next := func() Event {
		t.Helper()
		select {
		case e := <-events:
			return e
		case <-time.After(testkit.Bound(3 * time.Second)):
			t.Fatal("no event")
		}
		return Event{}
	}
	if e := next(); !e.IdleChanged || e.IdleBlocked {
		t.Errorf("first %+v", e)
	}
	f.Lock()
	if e := next(); !e.Lock {
		t.Errorf("lock %+v", e)
	}
	f.PrepareForSleep(true)
	if e := next(); !e.SleepChanged || !e.Sleep {
		t.Errorf("sleep %+v", e)
	}
	f.SetBlocked(t, "idle:sleep")
	if e := next(); !e.IdleChanged || !e.IdleBlocked {
		t.Errorf("blocked %+v", e)
	}
	// Another session's Lock isn't ours
	f.LockSession("/org/freedesktop/login1/session/_2")
	f.PrepareForSleep(false)
	if e := next(); !e.SleepChanged || e.Sleep {
		t.Errorf("woke %+v", e)
	}
	cancel()
	if err := <-done; err != nil {
		t.Errorf("Watch: %v", err)
	}
}
