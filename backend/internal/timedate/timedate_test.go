package timedate

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// fake is a timedated: its properties, the setters recorded, refusing a
// call that doesn't allow interactive authorization as polkit would
type fake struct {
	conn  *dbus.Conn
	mu    sync.Mutex
	props map[string]any
	calls []string
}

func newFake(t *testing.T, ctx context.Context, bus *dbustest.Bus) *fake {
	t.Helper()
	conn, err := dbus.Dial(ctx, bus.Address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	f := &fake{conn: conn, props: map[string]any{"Timezone": "Europe/Berlin", "LocalRTC": false, "CanNTP": true, "NTP": true, "NTPSynchronized": true}}
	setter := func(apply func(m *dbus.Message)) dbus.Method {
		return dbus.Method{Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			if m.Flags&dbus.FlagAllowInteractiveAuthorization == 0 {
				return nil, dbus.NewError("org.freedesktop.DBus.Error.InteractiveAuthorizationRequired", "no prompt allowed")
			}
			f.mu.Lock()
			f.calls = append(f.calls, m.Member)
			apply(m)
			f.mu.Unlock()
			return nil, nil
		}}
	}
	ntp := setter(func(m *dbus.Message) { f.props["NTP"] = m.Body[0] })
	ntp.In = "bb"
	zone := setter(func(m *dbus.Message) { f.props["Timezone"] = m.Body[0] })
	zone.In = "sb"
	set := setter(func(m *dbus.Message) {})
	set.In = "xbb"
	if _, err := conn.Export(Path, dbus.Interface{Name: Interface, Methods: map[string]dbus.Method{"SetNTP": ntp, "SetTimezone": zone, "SetTime": set}}); err != nil {
		t.Fatal(err)
	}
	if _, err := conn.Export(Path, dbus.Interface{Name: "org.freedesktop.DBus.Properties", Methods: map[string]dbus.Method{
		"GetAll": {In: "s", Out: "a{sv}", Fn: func(context.Context, *dbus.Message) ([]any, error) {
			f.mu.Lock()
			defer f.mu.Unlock()
			out := map[string]dbus.Variant{}
			for k, v := range f.props {
				out[k] = dbus.MakeVariant(v)
			}
			return []any{out}, nil
		}},
	}}); err != nil {
		t.Fatal(err)
	}
	if _, err := conn.RequestName(ctx, BusName, dbus.NameDoNotQueue); err != nil {
		t.Fatal(err)
	}
	return f
}

func clockOn(bus *dbustest.Bus) *Clock {
	return New(Options{SystemBus: func(ctx context.Context) (*dbus.Conn, error) {
		return dbus.Dial(ctx, bus.Address, dbus.Options{})
	}})
}

func TestGetAndSet(t *testing.T) {
	t.Parallel()
	ctx, cancel := context.WithTimeout(context.Background(), testkit.Bound(5*time.Second))
	defer cancel()
	bus := dbustest.New(t)
	f := newFake(t, ctx, bus)
	c := clockOn(bus)
	if got, want := c.Get(ctx), (State{Available: true, Timezone: "Europe/Berlin", CanNTP: true, NTP: true, NTPSynchronized: true}); got != want {
		t.Fatalf("Get = %+v, want %+v", got, want)
	}
	if err := c.SetTimezone(ctx, "America/New_York"); err != nil {
		t.Fatal(err)
	}
	if err := c.SetNTP(ctx, false); err != nil {
		t.Fatal(err)
	}
	if err := c.SetTime(ctx, time.Unix(1762300000, 0)); err != nil {
		t.Fatal(err)
	}
	if got := c.Get(ctx); got.Timezone != "America/New_York" || got.NTP {
		t.Errorf("after the setters: %+v", got)
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(f.calls) != 3 {
		t.Errorf("calls %q", f.calls)
	}
}

func TestBadZones(t *testing.T) {
	t.Parallel()
	c := New(Options{SystemBus: func(context.Context) (*dbus.Conn, error) {
		t.Error("a bad zone reached the bus")
		return nil, axerr.New(axerr.Unavailable, "no bus")
	}})
	for _, zone := range []string{"", "../../etc/passwd", "/etc/localtime", "Europe/Ber lin", "Europe/Berlin;rm"} {
		if err := c.SetTimezone(context.Background(), zone); axerr.KindOf(err) != axerr.BadRequest {
			t.Errorf("SetTimezone(%q): %v, want a bad request", zone, err)
		}
	}
	for _, zone := range []string{"UTC", "America/Argentina/Buenos_Aires", "Etc/GMT+5", "America/Port-au-Prince"} {
		if !validZone(zone) {
			t.Errorf("validZone(%q) = false", zone)
		}
	}
}

func TestWithoutTimedated(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	ctx, cancel := context.WithTimeout(context.Background(), testkit.Bound(5*time.Second))
	defer cancel()
	if got := clockOn(bus).Get(ctx); got.Available {
		t.Errorf("no timedated read as %+v", got)
	}
	noBus := New(Options{SystemBus: func(context.Context) (*dbus.Conn, error) { return nil, axerr.New(axerr.Unavailable, "no bus") }})
	if got := noBus.Get(ctx); got.Available {
		t.Errorf("no bus read as %+v", got)
	}
}

func TestWatch(t *testing.T) {
	t.Parallel()
	ctx, cancel := context.WithTimeout(context.Background(), testkit.Bound(5*time.Second))
	defer cancel()
	bus := dbustest.New(t)
	f := newFake(t, ctx, bus)
	got := make(chan State, 4)
	watching := make(chan error, 1)
	go func() { watching <- clockOn(bus).Watch(ctx, func(s State) { got <- s }) }()
	// The subscription is in once a change reaches it
	if !testkit.Eventually(func() bool {
		f.mu.Lock()
		f.props["Timezone"] = "Asia/Tokyo"
		f.mu.Unlock()
		f.conn.Emit(Path, "org.freedesktop.DBus.Properties", "PropertiesChanged", "sa{sv}as", Interface, map[string]dbus.Variant{"Timezone": dbus.MakeVariant("Asia/Tokyo")}, []string{})
		select {
		case s := <-got:
			return s.Timezone == "Asia/Tokyo"
		case <-time.After(20 * time.Millisecond):
			return false
		}
	}) {
		t.Fatal("no change came through")
	}
	cancel()
	if err := <-watching; err != nil {
		t.Errorf("Watch: %v", err)
	}
}
