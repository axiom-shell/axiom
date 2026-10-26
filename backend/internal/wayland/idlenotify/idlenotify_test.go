package idlenotify

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/wayland/client"
	"github.com/axiom-shell/axiom/backend/internal/wayland/seat"
	"github.com/axiom-shell/axiom/backend/internal/wayland/wire/wiretest"
)

// request is one get_*_notification the fake got.
type request struct {
	op          uint16
	id, timeout uint32
}

type fake struct {
	*wiretest.Compositor
	mu        sync.Mutex
	seat      uint32
	notifier  uint32
	requests  chan request
	destroyed chan uint32
}

func newFake(t *testing.T, version uint32) *fake {
	f := &fake{requests: make(chan request, 16), destroyed: make(chan uint32, 16)}
	f.Compositor = wiretest.New(t, []wiretest.Global{
		{Name: 1, Interface: "wl_seat", Version: 7},
		{Name: 2, Interface: ifaceNotifier, Version: version},
	}, f.request)
	return f
}

func (f *fake) request(c *wiretest.Compositor, r wiretest.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	switch {
	case r.Interface == "wl_seat":
		f.seat = r.Args.Uint()
	case r.Interface == ifaceNotifier:
		f.notifier = r.Args.Uint()
	case r.Object == f.notifier && (r.Opcode == opGetIdleNotification || r.Opcode == opGetInputIdleNotification):
		id, timeout, s := r.Args.Uint(), r.Args.Uint(), r.Args.Uint()
		if s != f.seat {
			panic("not the seat")
		}
		f.requests <- request{op: r.Opcode, id: id, timeout: timeout}
	case r.Opcode == opNotificationDestroy:
		f.destroyed <- r.Object
	}
}

func next[T any](t *testing.T, ch chan T) T {
	t.Helper()
	select {
	case v := <-ch:
		return v
	case <-time.After(3 * time.Second):
		t.Fatal("timed out")
	}
	var zero T
	return zero
}

func start(t *testing.T, f *fake) *Notifier {
	t.Helper()
	st := seat.New()
	n := New(Options{Seat: st})
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- client.Run(ctx, f.Socket, st, n) }()
	t.Cleanup(func() { cancel(); <-done })
	return n
}

func TestWatchIdlesAndResumes(t *testing.T) {
	t.Parallel()
	f := newFake(t, 2)
	n := start(t, f)
	events := make(chan string, 4)
	cancel := n.Watch(90*time.Second, false, func() { events <- "idle" }, func() { events <- "resume" })
	r := next(t, f.requests)
	if r.op != opGetInputIdleNotification || r.timeout != 90000 {
		t.Fatalf("got %+v", r)
	}
	f.Send(r.id, evIdled)
	f.Send(r.id, evResumed)
	if a, b := next(t, events), next(t, events); a != "idle" || b != "resume" {
		t.Errorf("got %s, %s", a, b)
	}
	if !n.Available() {
		t.Error("not available")
	}
	cancel()
	if got := next(t, f.destroyed); got != r.id {
		t.Errorf("destroyed %d, want %d", got, r.id)
	}
}

func TestRespectingInhibitorsAndVersion1(t *testing.T) {
	t.Parallel()
	f := newFake(t, 1)
	n := start(t, f)
	n.Watch(time.Second, true, func() {}, func() {})
	if r := next(t, f.requests); r.op != opGetIdleNotification {
		t.Errorf("respecting: op %d", r.op)
	}
	// v1 has no input-only notification: it falls back
	n.Watch(time.Second, false, func() {}, func() {})
	if r := next(t, f.requests); r.op != opGetIdleNotification {
		t.Errorf("v1: op %d", r.op)
	}
}

func TestRearmsWhenTheNotifierReturns(t *testing.T) {
	t.Parallel()
	f := newFake(t, 2)
	n := start(t, f)
	n.Watch(5*time.Second, true, func() {}, func() {})
	first := next(t, f.requests)
	f.RemoveGlobal(2)
	if got := next(t, f.destroyed); got != first.id {
		t.Errorf("destroyed %d", got)
	}
	f.AddGlobal(wiretest.Global{Name: 3, Interface: ifaceNotifier, Version: 2})
	if again := next(t, f.requests); again.timeout != 5000 {
		t.Errorf("rearmed %+v", again)
	}
}

// Watches made before the connection arm when it binds the notifier
func TestWatchBeforeTheConnection(t *testing.T) {
	t.Parallel()
	f := newFake(t, 2)
	st := seat.New()
	n := New(Options{Seat: st})
	n.Watch(time.Minute, true, func() {}, func() {})
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- client.Run(ctx, f.Socket, st, n) }()
	t.Cleanup(func() { cancel(); <-done })
	if r := next(t, f.requests); r.timeout != 60000 {
		t.Errorf("got %+v", r)
	}
}
