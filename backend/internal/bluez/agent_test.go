package bluez

import (
	"context"
	"slices"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// shell records the agent's requests and dones, as the daemon's shell
// would see them; connected false is no shell.
type shell struct {
	connected atomic.Bool

	mu       sync.Mutex
	requests []AgentRequest
	done     []string
}

func (sh *shell) options(o *Options) {
	o.OnAgentRequest = func(r AgentRequest) bool {
		if !sh.connected.Load() {
			return false
		}
		sh.mu.Lock()
		sh.requests = append(sh.requests, r)
		sh.mu.Unlock()
		return true
	}
	o.OnAgentDone = func(id string) {
		sh.mu.Lock()
		sh.done = append(sh.done, id)
		sh.mu.Unlock()
	}
}

// last waits for a request after the n first, and returns it.
func (sh *shell) last(t *testing.T, n int) AgentRequest {
	t.Helper()
	var r AgentRequest
	if !testkit.Eventually(func() bool {
		sh.mu.Lock()
		defer sh.mu.Unlock()
		if len(sh.requests) <= n {
			return false
		}
		r = sh.requests[len(sh.requests)-1]
		return true
	}) {
		t.Fatalf("no request after %d", n)
	}
	return r
}

func (sh *shell) count() int {
	sh.mu.Lock()
	defer sh.mu.Unlock()
	return len(sh.requests)
}

func (sh *shell) isDone(id string) bool {
	sh.mu.Lock()
	defer sh.mu.Unlock()
	return slices.Contains(sh.done, id)
}

func (sh *shell) waitDone(t *testing.T, id string) {
	t.Helper()
	if !testkit.Eventually(func() bool { return sh.isDone(id) }) {
		t.Fatalf("request %s not done", id)
	}
}

// agentCall is BlueZ calling the agent; its answer comes on the channel.
type agentAnswer struct {
	m   *dbus.Message
	err error
}

func (f *fakeBlueZ) callAgent(member, sig string, args ...any) <-chan agentAnswer {
	f.mu.Lock()
	agent := f.agent
	f.mu.Unlock()
	out := make(chan agentAnswer, 1)
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), testkit.Bound(5*time.Second))
		defer cancel()
		m, err := f.conn.Call(ctx, agent, agentPath, ifaceAgent, member, sig, args...)
		out <- agentAnswer{m, err}
	}()
	return out
}

func answer(t *testing.T, ch <-chan agentAnswer) agentAnswer {
	t.Helper()
	select {
	case a := <-ch:
		return a
	case <-time.After(testkit.Bound(5 * time.Second)):
		t.Fatal("the agent never answered")
	}
	return agentAnswer{}
}

func pending(t *testing.T, ch <-chan agentAnswer) {
	t.Helper()
	select {
	case a := <-ch:
		t.Fatalf("answered before the user did: %+v", a)
	case <-time.After(30 * time.Millisecond):
	}
}

func agentHarness(t *testing.T) (*fakeBlueZ, *harness, *shell, *dbustest.Bus) {
	t.Helper()
	bus := dbustest.New(t)
	f := newFakeBlueZ(t, bus, fixture())
	sh := &shell{}
	sh.connected.Store(true)
	h := startWith(t, bus, sh.options)
	h.wait(t, "sync", func(st State) bool { return len(st.Devices) == 3 })
	h.s.SetAgent(true)
	waitRegistered(t, f)
	return f, h, sh, bus
}

func waitRegistered(t *testing.T, f *fakeBlueZ) {
	t.Helper()
	if !testkit.Eventually(func() bool {
		f.mu.Lock()
		defer f.mu.Unlock()
		return f.agent != "" && slices.Contains(f.calls, "RequestDefaultAgent "+string(agentPath))
	}) {
		t.Fatalf("not registered: %v", f.takeCalls())
	}
	if got := f.takeCalls(); !slices.Equal(got, []string{"RegisterAgent " + string(agentPath) + " KeyboardDisplay", "RequestDefaultAgent " + string(agentPath)}) {
		t.Errorf("calls %v", got)
	}
}

// Each request that asks waits for the user's answer, and the answer
// reaches BlueZ in its type
func TestAgentAsks(t *testing.T) {
	t.Parallel()
	f, h, sh, _ := agentHarness(t)
	ph := devPath(hci0, phone)

	// A passkey: a bad one is refused and the request still waits
	ch := f.callAgent("RequestPasskey", "o", ph)
	r := sh.last(t, 0)
	if r.Kind != KindPasskey || r.Device.Address != phone || r.Device.Icon != "audio-headset" || r.Entered != -1 {
		t.Errorf("passkey request %+v", r)
	}
	pending(t, ch)
	if err := h.s.AgentReply(r.ID, true, "1234567"); axerr.KindOf(err) != axerr.BadRequest {
		t.Errorf("bad passkey: %v", err)
	}
	if err := h.s.AgentReply(r.ID, true, "012345"); err != nil {
		t.Fatal(err)
	}
	a := answer(t, ch)
	var key uint32
	if a.err != nil || a.m.Store(&key) != nil || key != 12345 {
		t.Errorf("passkey answer %v %d", a.err, key)
	}
	sh.waitDone(t, r.ID)
	// Answered: gone
	if err := h.s.AgentReply(r.ID, true, "1"); axerr.KindOf(err) != axerr.NotFound {
		t.Errorf("answered twice: %v", err)
	}

	// A PIN
	ch = f.callAgent("RequestPinCode", "o", ph)
	r = sh.last(t, 1)
	if r.Kind != KindPin {
		t.Errorf("pin request %+v", r)
	}
	if err := h.s.AgentReply(r.ID, true, ""); axerr.KindOf(err) != axerr.BadRequest {
		t.Errorf("empty PIN: %v", err)
	}
	h.s.AgentReply(r.ID, true, "0000")
	var pin string
	if a := answer(t, ch); a.err != nil || a.m.Store(&pin) != nil || pin != "0000" {
		t.Errorf("pin answer %v %q", a.err, pin)
	}

	// A confirmation, accepted then declined
	ch = f.callAgent("RequestConfirmation", "ou", ph, uint32(1234))
	r = sh.last(t, 2)
	if r.Kind != KindConfirm || r.Code != "001234" {
		t.Errorf("confirm request %+v", r)
	}
	h.s.AgentReply(r.ID, true, "")
	if a := answer(t, ch); a.err != nil {
		t.Errorf("confirmed: %v", a.err)
	}
	ch = f.callAgent("RequestConfirmation", "ou", ph, uint32(999999))
	r = sh.last(t, 3)
	h.s.AgentReply(r.ID, false, "")
	if a := answer(t, ch); dbus.ErrorName(a.err) != errRejected {
		t.Errorf("declined: %v", a.err)
	}

	// An authorization, declined
	ch = f.callAgent("RequestAuthorization", "o", ph)
	r = sh.last(t, 4)
	if r.Kind != KindAuthorize {
		t.Errorf("authorize request %+v", r)
	}
	h.s.AgentReply(r.ID, false, "")
	if a := answer(t, ch); dbus.ErrorName(a.err) != errRejected {
		t.Errorf("authorization declined: %v", a.err)
	}

	// A service: asked for the untrusted phone, not the trusted headset
	const uuid = "0000110b-0000-1000-8000-00805f9b34fb"
	if a := answer(t, f.callAgent("AuthorizeService", "os", devPath(hci0, headset), uuid)); a.err != nil {
		t.Errorf("trusted service: %v", a.err)
	}
	if sh.count() != 5 {
		t.Errorf("asked for a trusted device's service")
	}
	ch = f.callAgent("AuthorizeService", "os", ph, uuid)
	r = sh.last(t, 5)
	if r.Kind != KindAuthorizeService || r.Service != uuid {
		t.Errorf("service request %+v", r)
	}
	h.s.AgentReply(r.ID, true, "")
	if a := answer(t, ch); a.err != nil {
		t.Errorf("service allowed: %v", a.err)
	}
}

// A code shown is updated in place as the keyboard types, and hidden
// when the device pairs; Cancel and Release end whatever is open
func TestAgentDisplayAndCancel(t *testing.T) {
	t.Parallel()
	f, h, sh, _ := agentHarness(t)
	ph := devPath(hci0, phone)

	if a := answer(t, f.callAgent("DisplayPasskey", "ouq", ph, uint32(42), uint16(0))); a.err != nil {
		t.Fatal(a.err)
	}
	r := sh.last(t, 0)
	if r.Kind != KindDisplay || r.Code != "000042" || r.Entered != 0 {
		t.Errorf("display %+v", r)
	}
	answer(t, f.callAgent("DisplayPasskey", "ouq", ph, uint32(42), uint16(3)))
	if r2 := sh.last(t, 1); r2.ID != r.ID || r2.Entered != 3 {
		t.Errorf("update %+v, first %+v", r2, r)
	}
	f.changed(ph, ifaceDevice, "Paired", true)
	sh.waitDone(t, r.ID)

	// A PIN shown, then BlueZ cancels it and a passkey asked meanwhile
	answer(t, f.callAgent("DisplayPinCode", "os", ph, "1234"))
	shown := sh.last(t, 2)
	if shown.Kind != KindDisplay || shown.Code != "1234" || shown.Entered != -1 {
		t.Errorf("pin shown %+v", shown)
	}
	ch := f.callAgent("RequestPasskey", "o", ph)
	asked := sh.last(t, 3)
	if a := answer(t, f.callAgent("Cancel", "")); a.err != nil {
		t.Fatal(a.err)
	}
	if a := answer(t, ch); dbus.ErrorName(a.err) != errCanceled {
		t.Errorf("canceled: %v", a.err)
	}
	sh.waitDone(t, shown.ID)
	sh.waitDone(t, asked.ID)

	// The shell hides a display (its Cancel ends the pair separately)
	answer(t, f.callAgent("DisplayPasskey", "ouq", ph, uint32(7), uint16(0)))
	r = sh.last(t, 4)
	if err := h.s.AgentReply(r.ID, false, ""); err != nil {
		t.Error(err)
	}
	sh.waitDone(t, r.ID)

	// Released: what was open ends
	ch = f.callAgent("RequestAuthorization", "o", ph)
	asked = sh.last(t, 5)
	answer(t, f.callAgent("Release", ""))
	if a := answer(t, ch); a.err == nil {
		t.Error("released, yet answered yes")
	}
	sh.waitDone(t, asked.ID)
}

// The last shell gone: what it was asked is rejected, nobody to answer
func TestAgentRejectAgents(t *testing.T) {
	t.Parallel()
	f, h, sh, _ := agentHarness(t)
	ch := f.callAgent("RequestConfirmation", "ou", devPath(hci0, phone), uint32(123456))
	asked := sh.last(t, 0)
	pending(t, ch)
	h.s.RejectAgents()
	if a := answer(t, ch); dbus.ErrorName(a.err) != errRejected {
		t.Errorf("rejected: %v", a.err)
	}
	sh.waitDone(t, asked.ID)
}

// With no shell BlueZ hears rejected at once; only BlueZ may ask
func TestAgentNobody(t *testing.T) {
	t.Parallel()
	f, _, sh, bus := agentHarness(t)
	ph := devPath(hci0, phone)
	sh.connected.Store(false)
	if a := answer(t, f.callAgent("RequestPasskey", "o", ph)); dbus.ErrorName(a.err) != errRejected {
		t.Errorf("no shell: %v", a.err)
	}
	if a := answer(t, f.callAgent("DisplayPasskey", "ouq", ph, uint32(1), uint16(0))); dbus.ErrorName(a.err) != errRejected {
		t.Errorf("no shell, display: %v", a.err)
	}
	sh.connected.Store(true)

	app, err := dbus.Dial(t.Context(), bus.Address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	defer app.Close()
	f.mu.Lock()
	agent := f.agent
	f.mu.Unlock()
	if _, err := app.Call(t.Context(), agent, agentPath, ifaceAgent, "RequestConfirmation", "ou", ph, uint32(1)); dbus.ErrorName(err) != errRejected {
		t.Errorf("another app asked: %v", err)
	}
	if sh.count() != 0 {
		t.Errorf("shown %d requests", sh.count())
	}
}

// Turned off: unregistered, and what was asked is rejected; BlueZ coming
// back finds it registered again
func TestAgentRegistration(t *testing.T) {
	t.Parallel()
	f, h, sh, bus := agentHarness(t)
	ch := f.callAgent("RequestPasskey", "o", devPath(hci0, phone))
	r := sh.last(t, 0)
	h.s.SetAgent(false)
	if a := answer(t, ch); dbus.ErrorName(a.err) != errRejected {
		t.Errorf("turned off: %v", a.err)
	}
	sh.waitDone(t, r.ID)
	if !testkit.Eventually(func() bool {
		f.mu.Lock()
		defer f.mu.Unlock()
		return f.agent == ""
	}) {
		t.Fatal("not unregistered")
	}
	if got := f.takeCalls(); !slices.Equal(got, []string{"UnregisterAgent " + string(agentPath)}) {
		t.Errorf("calls %v", got)
	}

	// Off, BlueZ restarting registers nothing
	f.conn.Close()
	h.wait(t, "gone", func(st State) bool { return !st.Available })
	f2 := newFakeBlueZ(t, bus, fixture())
	h.wait(t, "back", func(st State) bool { return st.Available })
	time.Sleep(30 * time.Millisecond)
	if got := f2.takeCalls(); len(got) > 0 {
		t.Errorf("off, yet %v", got)
	}

	// On, it registers, and again with the next BlueZ
	h.s.SetAgent(true)
	waitRegistered(t, f2)
	ch = f2.callAgent("RequestPasskey", "o", devPath(hci0, phone))
	r = sh.last(t, 1)
	f2.conn.Close()
	sh.waitDone(t, r.ID)
	<-ch
	f3 := newFakeBlueZ(t, bus, fixture())
	waitRegistered(t, f3)
}
