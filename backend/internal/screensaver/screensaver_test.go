package screensaver

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

func ctx(t *testing.T) context.Context {
	t.Helper()
	c, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	t.Cleanup(cancel)
	return c
}

func dial(t *testing.T, bus *dbustest.Bus) *dbus.Conn {
	t.Helper()
	c, err := dbus.Dial(ctx(t), bus.Address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { c.Close() })
	return c
}

// serve runs a server on its own connection; changes come on the channel.
func serve(t *testing.T, bus *dbustest.Bus) (*Server, chan struct{}) {
	t.Helper()
	changes := make(chan struct{}, 32)
	s := New(Options{OnChange: func() { changes <- struct{}{} }})
	conn := dial(t, bus)
	runCtx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- s.Run(runCtx, conn) }()
	t.Cleanup(func() { cancel(); <-done })
	return s, changes
}

// until waits for a change after which cond holds.
func until(t *testing.T, changes chan struct{}, cond func() bool) {
	t.Helper()
	deadline := time.After(testkit.Bound(3 * time.Second))
	for !cond() {
		select {
		case <-changes:
		case <-deadline:
			t.Fatal("timed out")
		}
	}
}

func TestInhibitAndRelease(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	s, changes := serve(t, bus)
	until(t, changes, func() bool { owned, _ := s.Owned(); return owned })

	app, other := dial(t, bus), dial(t, bus)
	m, err := app.Call(ctx(t), busName, "/org/freedesktop/ScreenSaver", iface, "Inhibit", "ss", "Firefox", "Playing video")
	if err != nil {
		t.Fatal(err)
	}
	var cookie uint32
	m.Store(&cookie)
	if _, err := app.Call(ctx(t), busName, "/ScreenSaver", iface, "Inhibit", "ss", "Firefox", "Another tab"); err != nil {
		t.Fatal(err)
	}
	if got := s.Inhibitors(); len(got) != 2 || got[0].App != "Firefox" || got[0].Reason != "Playing video" {
		t.Errorf("inhibitors %+v", got)
	}
	// Another app can't release Firefox's
	other.Call(ctx(t), busName, "/org/freedesktop/ScreenSaver", iface, "UnInhibit", "u", cookie)
	if len(s.Inhibitors()) != 2 {
		t.Error("another app released an inhibitor")
	}
	if _, err := app.Call(ctx(t), busName, "/org/freedesktop/ScreenSaver", iface, "UnInhibit", "u", cookie); err != nil {
		t.Fatal(err)
	}
	if got := s.Inhibitors(); len(got) != 1 || got[0].Reason != "Another tab" {
		t.Errorf("after UnInhibit %+v", got)
	}
	// Leaving the bus releases the rest
	app.Close()
	until(t, changes, func() bool { return len(s.Inhibitors()) == 0 })
}

func TestNameHeldElsewhere(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	holder := dial(t, bus)
	if _, err := holder.RequestName(ctx(t), busName, dbus.NameDoNotQueue); err != nil {
		t.Fatal(err)
	}
	s, changes := serve(t, bus)
	until(t, changes, func() bool { _, o := s.Owned(); return o != nil })
	if _, owner := s.Owned(); owner.PID != uint32(os.Getpid()) || owner.Name == "" {
		t.Errorf("owner %+v", owner)
	}
	// Once it lets go, the name is the server's
	holder.Close()
	until(t, changes, func() bool { owned, _ := s.Owned(); return owned })
}
