package powerprofiles

import (
	"context"
	"fmt"
	"reflect"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// fakePPD is power-profiles-daemon on the fake bus.
type fakePPD struct {
	t    *testing.T
	conn *dbus.Conn
	t0   target

	mu     sync.Mutex
	holds  map[uint32]string // cookie → profile
	next   uint32
	events []string
	refuse string // a profile HoldProfile refuses
	flaky  int    // HoldProfile calls left to fail with no answer (NoReply)
}

// newPPD exports PPD on bus, owning the UPower name, or legacy: the net.hadess one.
func newPPD(t *testing.T, bus *dbustest.Bus, legacy bool) *fakePPD {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	conn, err := dbus.Dial(ctx, bus.Address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	f := &fakePPD{t: t, conn: conn, t0: upower, holds: map[uint32]string{}}
	if legacy {
		f.t0 = hadess
	}
	_, err = conn.Export(f.t0.path, dbus.Interface{Name: f.t0.iface, Methods: map[string]dbus.Method{
		"HoldProfile": {In: "sss", Out: "u", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			profile, reason, app := m.Body[0].(string), m.Body[1].(string), m.Body[2].(string)
			f.mu.Lock()
			defer f.mu.Unlock()
			f.events = append(f.events, fmt.Sprintf("hold %s %s %s", profile, reason, app))
			if f.flaky > 0 {
				f.flaky--
				return nil, dbus.NewError(dbus.ErrNoReply, "no reply")
			}
			if profile == f.refuse {
				return nil, dbus.NewError(dbus.ErrFailed, "no %s profile", profile)
			}
			f.next++
			f.holds[f.next] = profile
			return []any{f.next}, nil
		}},
		"ReleaseProfile": {In: "u", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			cookie := m.Body[0].(uint32)
			f.mu.Lock()
			profile, ok := f.holds[cookie]
			delete(f.holds, cookie)
			if ok {
				f.events = append(f.events, "release "+profile)
			}
			f.mu.Unlock()
			if ok {
				f.conn.Emit(f.t0.path, f.t0.iface, "ProfileReleased", "u", cookie)
			}
			return nil, nil
		}},
	}})
	if err != nil {
		t.Fatal(err)
	}
	f.own()
	return f
}

func (f *fakePPD) own() {
	if _, err := f.conn.RequestName(context.Background(), f.t0.name, 0); err != nil {
		f.t.Fatal(err)
	}
}

// userPicks is the user choosing a profile: PPD drops every hold and says so.
func (f *fakePPD) userPicks() {
	f.mu.Lock()
	var cookies []uint32
	for c := range f.holds {
		cookies = append(cookies, c)
	}
	f.holds = map[uint32]string{}
	f.mu.Unlock()
	for _, c := range cookies {
		f.conn.Emit(f.t0.path, f.t0.iface, "ProfileReleased", "u", c)
	}
}

// restart is the daemon going away and coming back: its holds are gone.
func (f *fakePPD) restart() {
	f.mu.Lock()
	f.holds = map[uint32]string{}
	f.mu.Unlock()
	f.conn.ReleaseName(context.Background(), f.t0.name)
	f.own()
}

func (f *fakePPD) log() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.events...)
}

// expect waits for the events to be exactly want.
func (f *fakePPD) expect(want ...string) {
	f.t.Helper()
	if !testkit.Eventually(func() bool { return reflect.DeepEqual(f.log(), want) }) {
		f.t.Fatalf("events %q, want %q", f.log(), want)
	}
}

type rig struct {
	t          *testing.T
	h          *Holder
	bus        *dbustest.Bus
	dials      atomic.Int32
	overridden atomic.Int32
	cancel     context.CancelFunc
	done       chan error
}

func newRig(t *testing.T) *rig {
	t.Helper()
	r := &rig{t: t, bus: dbustest.New(t), done: make(chan error, 1)}
	r.h = New(Options{
		SystemBus: func(ctx context.Context) (*dbus.Conn, error) {
			r.dials.Add(1)
			return dbus.Dial(ctx, r.bus.Address, dbus.Options{})
		},
		OnOverridden: func() { r.overridden.Add(1) },
		Retry:        20 * time.Millisecond,
	})
	return r
}

func (r *rig) run() {
	ctx, cancel := context.WithCancel(context.Background())
	r.cancel = cancel
	go func() { r.done <- r.h.Run(ctx) }()
	r.t.Cleanup(func() {
		cancel()
		select {
		case <-r.done:
		case <-time.After(testkit.Bound(5 * time.Second)):
			r.t.Error("Run did not end")
		}
	})
}

// settle lets what was asked reach the daemon and its signals come back.
func settle() { time.Sleep(testkit.Bound(150 * time.Millisecond)) }

func TestHold(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	ppd := newPPD(t, r.bus, false)
	r.run()
	r.h.Hold("performance", "Games")
	ppd.expect("hold performance Games axiom")
	settle()
	ppd.expect("hold performance Games axiom")
	if r.overridden.Load() != 0 {
		t.Error("overridden by nothing")
	}
}

func TestChangeTakesTheNewHoldFirst(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	ppd := newPPD(t, r.bus, false)
	r.run()
	r.h.Hold("performance", "Games")
	ppd.expect("hold performance Games axiom")
	r.h.Hold("power-saver", "Movies")
	ppd.expect("hold performance Games axiom", "hold power-saver Movies axiom", "release performance")
	settle()
	if r.overridden.Load() != 0 {
		t.Error("a change read as the user's pick")
	}
}

func TestReleaseIsNotAnOverride(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	ppd := newPPD(t, r.bus, false)
	r.run()
	r.h.Hold("performance", "Games")
	ppd.expect("hold performance Games axiom")
	r.h.Hold("", "")
	ppd.expect("hold performance Games axiom", "release performance")
	settle()
	if r.overridden.Load() != 0 {
		t.Error("a release read as the user's pick")
	}
}

func TestUserPicksOverrides(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	ppd := newPPD(t, r.bus, false)
	r.run()
	r.h.Hold("performance", "Games")
	ppd.expect("hold performance Games axiom")
	ppd.userPicks()
	if !testkit.Eventually(func() bool { return r.overridden.Load() == 1 }) {
		t.Fatal("not overridden")
	}
	// Nothing is held again until the wish changes
	settle()
	ppd.expect("hold performance Games axiom")
	r.h.Hold("power-saver", "Games")
	ppd.expect("hold performance Games axiom", "hold power-saver Games axiom")
	if r.overridden.Load() != 1 {
		t.Errorf("overridden %d times", r.overridden.Load())
	}
}

func TestLegacyName(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	ppd := newPPD(t, r.bus, true)
	r.run()
	r.h.Hold("performance", "Games")
	ppd.expect("hold performance Games axiom")
}

func TestNoDaemonThenOne(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	r.run()
	r.h.Hold("performance", "Games")
	if !testkit.Eventually(func() bool { return r.dials.Load() >= 1 }) {
		t.Fatal("never dialled")
	}
	settle()
	if n := r.dials.Load(); n != 1 {
		t.Errorf("dialled %d times: an error loop", n)
	}
	ppd := newPPD(t, r.bus, false)
	ppd.expect("hold performance Games axiom")
}

func TestDaemonRestartHoldsAgain(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	ppd := newPPD(t, r.bus, false)
	r.run()
	r.h.Hold("performance", "Games")
	ppd.expect("hold performance Games axiom")
	ppd.restart()
	ppd.expect("hold performance Games axiom", "hold performance Games axiom")
	settle()
	if r.overridden.Load() != 0 {
		t.Error("a restart read as the user's pick")
	}
}

func TestRefusedIsNotRetried(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	ppd := newPPD(t, r.bus, false)
	ppd.refuse = "performance"
	r.run()
	r.h.Hold("performance", "Games")
	ppd.expect("hold performance Games axiom")
	settle()
	ppd.expect("hold performance Games axiom")
	r.h.Hold("power-saver", "Games")
	ppd.expect("hold performance Games axiom", "hold power-saver Games axiom")
}

func TestNoAnswerIsRetried(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	ppd := newPPD(t, r.bus, false)
	ppd.flaky = 1
	r.run()
	r.h.Hold("performance", "Games")
	// The first call gets no answer: it is tried again, not given up on
	ppd.expect("hold performance Games axiom", "hold performance Games axiom")
	settle()
	ppd.expect("hold performance Games axiom", "hold performance Games axiom")
}

func TestNothingWantedNeverDials(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	r.run()
	settle()
	r.h.Hold("", "")
	settle()
	if n := r.dials.Load(); n != 0 {
		t.Errorf("dialled %d times", n)
	}
}

func TestStopReleases(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	ppd := newPPD(t, r.bus, false)
	r.run()
	r.h.Hold("performance", "Games")
	ppd.expect("hold performance Games axiom")
	r.cancel()
	select {
	case err := <-r.done:
		if err != nil {
			t.Errorf("Run: %v", err)
		}
	case <-time.After(testkit.Bound(5 * time.Second)):
		t.Fatal("Run did not end")
	}
	ppd.expect("hold performance Games axiom", "release performance")
	if r.overridden.Load() != 0 {
		t.Error("the stop read as the user's pick")
	}
	r.done <- nil // the cleanup's wait
}

func TestName(t *testing.T) {
	t.Parallel()
	for in, want := range map[string]string{"performance": "performance", "powerSaver": "power-saver", "": "", "balanced": ""} {
		if got := Name(in); got != want {
			t.Errorf("Name(%q) = %q, want %q", in, got, want)
		}
	}
}
