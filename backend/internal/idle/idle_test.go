package idle

import (
	"context"
	"fmt"
	"io"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
	"github.com/axiom-shell/axiom/backend/internal/logind/logindtest"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// fakeNotifier records the watches armed; the test fires them.
type fakeNotifier struct {
	mu      sync.Mutex
	watches map[int]*fakeWatch
	next    int
	armed   int // Watch calls, ever
}

type fakeWatch struct {
	timeout          time.Duration
	respect          bool
	onIdle, onResume func()
}

func newNotifier() *fakeNotifier { return &fakeNotifier{watches: map[int]*fakeWatch{}} }

func (n *fakeNotifier) Available() bool { return true }

func (n *fakeNotifier) Watch(timeout time.Duration, respect bool, onIdle, onResume func()) func() {
	n.mu.Lock()
	defer n.mu.Unlock()
	n.next++
	n.armed++
	id := n.next
	n.watches[id] = &fakeWatch{timeout, respect, onIdle, onResume}
	return func() {
		n.mu.Lock()
		defer n.mu.Unlock()
		delete(n.watches, id)
	}
}

// at is the armed watch with that timeout.
func (n *fakeNotifier) at(t *testing.T, timeout time.Duration) *fakeWatch {
	t.Helper()
	var found *fakeWatch
	if !testkit.Eventually(func() bool {
		n.mu.Lock()
		defer n.mu.Unlock()
		for _, w := range n.watches {
			if w.timeout == timeout {
				found = w
			}
		}
		return found != nil
	}) {
		t.Fatalf("no watch at %v", timeout)
	}
	return found
}

func (n *fakeNotifier) count() (int, int) {
	n.mu.Lock()
	defer n.mu.Unlock()
	return len(n.watches), n.armed
}

// recorder records the actions run, in order.
type recorder struct {
	mu   sync.Mutex
	got  []string
	more chan struct{}
}

func (r *recorder) add(s string) {
	r.mu.Lock()
	r.got = append(r.got, s)
	r.mu.Unlock()
	select {
	case r.more <- struct{}{}:
	default:
	}
}

func (r *recorder) actions() Actions {
	return Actions{
		Dim: func(_ context.Context, mode string, p int) error {
			r.add(fmt.Sprintf("dim %s %d", mode, p))
			return nil
		},
		Undim:       func(context.Context) error { r.add("undim"); return nil },
		Lock:        func(context.Context) error { r.add("lock"); return nil },
		ScreenPower: func(_ context.Context, on bool) error { r.add(fmt.Sprintf("screen %v", on)); return nil },
		Command:     func(line string) error { r.add("run " + line); return nil },
	}
}

// expect waits for the actions recorded to be want.
func (r *recorder) expect(t *testing.T, want ...string) {
	t.Helper()
	deadline := time.After(testkit.Bound(3 * time.Second))
	for {
		r.mu.Lock()
		got := fmt.Sprint(r.got)
		r.mu.Unlock()
		if got == fmt.Sprint(want) {
			return
		}
		select {
		case <-r.more:
		case <-time.After(20 * time.Millisecond):
		case <-deadline:
			t.Fatalf("actions %s, want %v", got, want)
		}
	}
}

type harness struct {
	svc    *Service
	n      *fakeNotifier
	rec    *recorder
	states chan State
	logind *logindtest.Fake
	bus    *dbustest.Bus
}

// start runs a service; buses: a fake system bus with logind, and the
// session bus on the same fake.
func start(t *testing.T, buses bool) *harness {
	t.Helper()
	h := &harness{n: newNotifier(), rec: &recorder{more: make(chan struct{}, 1)}, states: make(chan State, 64)}
	o := Options{
		Notifier: h.n,
		Actions:  h.rec.actions(),
		Getenv:   logindtest.Getenv,
		Retry:    50 * time.Millisecond,
		OnState: func(s State) {
			select {
			case h.states <- s:
			default:
			}
		},
	}
	if buses {
		h.bus = dbustest.New(t)
		h.logind = logindtest.New(t, h.bus)
		dial := func(ctx context.Context) (*dbus.Conn, error) { return dbus.Dial(ctx, h.bus.Address, dbus.Options{}) }
		o.SystemBus, o.SessionBus = dial, dial
	}
	h.svc = New(o)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- h.svc.Run(ctx) }()
	t.Cleanup(func() { cancel(); <-done })
	return h
}

// until waits for a state that cond accepts.
func (h *harness) until(t *testing.T, cond func(State) bool) State {
	t.Helper()
	deadline := time.After(testkit.Bound(3 * time.Second))
	for {
		if s := h.svc.State(); cond(s) {
			return s
		}
		select {
		case <-h.states:
		case <-time.After(20 * time.Millisecond):
		case <-deadline:
			t.Fatalf("state %+v", h.svc.State())
		}
	}
}

func TestIdleRunsTheStepsAndTheirReturn(t *testing.T) {
	t.Parallel()
	h := start(t, false)
	s := defaults()
	s.Items = []Item{{Timeout: 10 * time.Minute, OnTimeout: "notify-send away", OnResume: "notify-send back", Enabled: true}}
	h.svc.Configure(s)
	h.until(t, func(s State) bool { return s.Armed == 4 })
	dim, lock, off, own := h.n.at(t, 150*time.Second), h.n.at(t, 300*time.Second), h.n.at(t, 330*time.Second), h.n.at(t, 10*time.Minute)
	if !dim.respect {
		t.Error("inhibitors not respected")
	}
	dim.onIdle()
	lock.onIdle()
	off.onIdle()
	own.onIdle()
	h.rec.expect(t, "dim to 30", "lock", "screen false", "run notify-send away")
	h.until(t, func(s State) bool { return len(s.Fired) == 4 })
	for _, w := range []*fakeWatch{dim, lock, off, own} {
		w.onResume()
	}
	// The lock has no return: only PAM unlocks
	h.rec.expect(t, "dim to 30", "lock", "screen false", "run notify-send away", "undim", "screen true", "run notify-send back")
	// A resume without an idle runs nothing
	dim.onResume()
	h.until(t, func(s State) bool { return len(s.Fired) == 0 })
}

func TestConfigureRearmsOnlyAnotherPlan(t *testing.T) {
	t.Parallel()
	h := start(t, false)
	s := defaults()
	h.svc.Configure(s)
	h.until(t, func(s State) bool { return s.Armed == 3 })
	// The same plan again: nothing armed anew
	h.svc.Configure(s)
	s2 := s
	s2.LockBeforeSleep = false
	h.svc.Configure(s2)
	h.until(t, func(s State) bool { return s.Armed == 3 })
	if _, armed := h.n.count(); armed != 3 {
		t.Errorf("armed %d times", armed)
	}
	s2.DimTimeout = time.Minute
	h.svc.Configure(s2)
	h.n.at(t, time.Minute)
	// Turned off while dimmed, the screens come back
	h.n.at(t, time.Minute).onIdle()
	h.rec.expect(t, "dim to 30")
	s2.Enabled = false
	h.svc.Configure(s2)
	h.until(t, func(s State) bool { return !s.Enabled && s.Armed == 0 })
	h.rec.expect(t, "dim to 30", "undim")
	if live, _ := h.n.count(); live != 0 {
		t.Errorf("%d watches left armed", live)
	}
}

func TestCaffeineCountsOnlyWhereInhibitorsAreIgnored(t *testing.T) {
	t.Parallel()
	h := start(t, false)
	s := defaults()
	h.svc.Configure(s)
	h.svc.SetCaffeine(true)
	// Respected: the compositor holds off for caffeine's own inhibitor
	h.until(t, func(s State) bool { return s.Armed == 3 && !s.Inhibited })
	s.RespectInhibitors = false
	h.svc.Configure(s)
	st := h.until(t, func(s State) bool { return s.Inhibited && s.Armed == 0 })
	if len(st.Inhibitors) != 1 || st.Inhibitors[0].Source != "caffeine" {
		t.Errorf("inhibitors %+v", st.Inhibitors)
	}
	h.svc.SetCaffeine(false)
	h.until(t, func(s State) bool { return s.Armed == 3 })
	if w := h.n.at(t, 150*time.Second); w.respect {
		t.Error("input-only notifications weren't asked for")
	}
}

func TestScreenSaverAndLogindHoldIdleOff(t *testing.T) {
	t.Parallel()
	h := start(t, true)
	h.svc.Configure(defaults())
	h.until(t, func(s State) bool { return s.Logind && s.ScreenSaver.Owned && s.Armed == 3 })

	// Dimmed, then a video starts: the screens come back
	h.n.at(t, 150*time.Second).onIdle()
	h.rec.expect(t, "dim to 30")
	app, err := dbus.Dial(context.Background(), h.bus.Address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	defer app.Close()
	if _, err := app.Call(context.Background(), "org.freedesktop.ScreenSaver", "/org/freedesktop/ScreenSaver", "org.freedesktop.ScreenSaver", "Inhibit", "ss", "mpv", "Playing"); err != nil {
		t.Fatal(err)
	}
	st := h.until(t, func(s State) bool { return s.Inhibited && s.Armed == 0 })
	if len(st.Inhibitors) != 1 || st.Inhibitors[0].App != "mpv" {
		t.Errorf("inhibitors %+v", st.Inhibitors)
	}
	h.rec.expect(t, "dim to 30", "undim")
	app.Close()
	h.until(t, func(s State) bool { return !s.Inhibited && s.Armed == 3 })

	// systemd-inhibit --what=idle
	h.logind.SetInhibitors([]any{"idle", "systemd-inhibit", "Testing", "block", uint32(1000), uint32(1)})
	h.logind.SetBlocked(t, "idle")
	st = h.until(t, func(s State) bool { return s.Inhibited && s.Armed == 0 })
	if len(st.Inhibitors) != 1 || st.Inhibitors[0].Source != "logind" || st.Inhibitors[0].App != "systemd-inhibit" {
		t.Errorf("inhibitors %+v", st.Inhibitors)
	}
	h.logind.SetBlocked(t, "")
	h.until(t, func(s State) bool { return !s.Inhibited && s.Armed == 3 })
}

func TestLogindLockAndSleep(t *testing.T) {
	t.Parallel()
	h := start(t, true)
	h.svc.Configure(defaults())
	h.until(t, func(s State) bool { return s.Logind })
	held := <-h.logind.Inhibited
	defer held.Close()

	h.logind.Lock()
	h.rec.expect(t, "lock")

	// Sleep: lock, then the inhibitor is let go
	h.logind.PrepareForSleep(true)
	h.rec.expect(t, "lock", "lock")
	held.SetReadDeadline(time.Now().Add(3 * time.Second))
	if _, err := io.ReadAll(held); err != nil {
		t.Errorf("the sleep inhibitor wasn't let go: %v", err)
	}
	// Waking: a new inhibitor, the screens on
	h.logind.PrepareForSleep(false)
	again := <-h.logind.Inhibited
	again.Close()
	h.rec.expect(t, "lock", "lock", "screen true")

	// Idle off: logind's Lock isn't axiom's to answer
	s := defaults()
	s.Enabled = false
	h.svc.Configure(s)
	h.until(t, func(s State) bool { return !s.Logind })
	h.logind.Lock()
	time.Sleep(100 * time.Millisecond)
	h.rec.expect(t, "lock", "lock", "screen true")
}

func TestSuspendThroughLogind(t *testing.T) {
	t.Parallel()
	h := start(t, true)
	s := defaults()
	s.DimTimeout, s.LockTimeout, s.ScreenOffTimeout, s.SuspendTimeout = 0, 0, 0, time.Hour
	h.svc.Configure(s)
	h.until(t, func(s State) bool { return s.Logind && s.Armed == 1 })
	h.n.at(t, time.Hour).onIdle()
	if !testkit.Eventually(func() bool { return h.logind.Suspended() == 1 }) {
		t.Fatal("not suspended")
	}
}
