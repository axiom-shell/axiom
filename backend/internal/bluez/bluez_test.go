package bluez

import (
	"context"
	"maps"
	"os"
	"path"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

const (
	hci0 = dbus.ObjectPath("/org/bluez/hci0")
	hci1 = dbus.ObjectPath("/org/bluez/hci1")
)

func v(x any) dbus.Variant { return dbus.MakeVariant(x) }

func adapter(addr string, powered bool, extra map[string]dbus.Variant) dbus.Interfaces {
	p := map[string]dbus.Variant{
		"Address": v(addr), "Name": v("host"), "Alias": v("calibrum"), "Powered": v(powered),
		"PowerState":  v(map[bool]string{true: "on", false: "off"}[powered]),
		"Discovering": v(false), "Discoverable": v(false), "Pairable": v(true),
	}
	maps.Copy(p, extra)
	return dbus.Interfaces{ifaceAdapter: p}
}

// devPath is a device's path under an adapter, from its address.
func devPath(ap dbus.ObjectPath, addr string) dbus.ObjectPath {
	return ap + "/dev_" + dbus.ObjectPath(strings.ReplaceAll(addr, ":", "_"))
}

func device(ap dbus.ObjectPath, addr, name string, paired, connected bool, extra map[string]dbus.Variant) dbus.Interfaces {
	p := map[string]dbus.Variant{
		"Adapter": v(ap), "Address": v(addr), "Alias": v(name), "Icon": v("audio-headset"),
		"Paired": v(paired), "Bonded": v(paired), "Trusted": v(paired), "Blocked": v(false), "Connected": v(connected),
	}
	if name != "" {
		p["Name"] = v(name)
	} else {
		p["Alias"] = v(strings.ReplaceAll(addr, ":", "-"))
	}
	maps.Copy(p, extra)
	return dbus.Interfaces{ifaceDevice: p}
}

func withBattery(ifaces dbus.Interfaces, level uint8) dbus.Interfaces {
	ifaces[ifaceBattery] = map[string]dbus.Variant{"Percentage": v(level)}
	return ifaces
}

const (
	headset = "AA:00:00:00:00:01"
	mouse   = "AA:00:00:00:00:02"
	phone   = "AA:00:00:00:00:03"
	other   = "BB:00:00:00:00:01"
)

// fixture: hci0 with a connected headset reporting its battery, a paired
// mouse and an unpaired phone; hci1 with one device of its own.
func fixture() dbus.ManagedObjects {
	return dbus.ManagedObjects{
		hci0:                   adapter("C0:00:00:00:00:00", true, nil),
		devPath(hci0, headset): withBattery(device(hci0, headset, "Headset", true, true, nil), 80),
		devPath(hci0, mouse):   device(hci0, mouse, "Mouse", true, false, map[string]dbus.Variant{"Icon": v("input-mouse")}),
		devPath(hci0, phone):   device(hci0, phone, "", false, false, nil),
		hci1:                   adapter("C1:00:00:00:00:00", false, nil),
		devPath(hci1, other):   device(hci1, other, "Other", true, false, nil),
	}
}

func addrs(st State) []string {
	out := []string{}
	for _, d := range st.Devices {
		out = append(out, d.Address)
	}
	return out
}

func TestBuild(t *testing.T) {
	t.Parallel()
	objs := fixture()
	order := map[dbus.ObjectPath]uint64{devPath(hci0, phone): 0, devPath(hci0, mouse): 1, devPath(hci0, headset): 2}
	st := build(objs, order, map[string]string{mouse: opConnecting, phone: opPairing}, "")
	want := Adapter{Address: "C0:00:00:00:00:00", Name: "calibrum", Powered: true, Pairable: true}
	if !st.Available || st.Adapter == nil || *st.Adapter != want {
		t.Fatalf("adapter %+v", st.Adapter)
	}
	// hci1's device isn't the default adapter's; the order is arrival
	if got := addrs(st); !slices.Equal(got, []string{phone, mouse, headset}) {
		t.Errorf("devices %v", got)
	}
	ph, mo, hs := st.Devices[0], st.Devices[1], st.Devices[2]
	if hs != (Device{Address: headset, Name: "Headset", DeviceName: "Headset", Icon: "audio-headset", Paired: true, Bonded: true, Trusted: true, Connected: true, State: "connected", Battery: 80}) {
		t.Errorf("headset %+v", hs)
	}
	if mo.State != "connecting" || mo.Pairing || mo.Battery != -1 {
		t.Errorf("mouse %+v", mo)
	}
	if !ph.Pairing || ph.State != "disconnected" || ph.DeviceName != "" || ph.Name != "AA-00-00-00-00-03" {
		t.Errorf("phone %+v", ph)
	}

	// No adapter: not available, no devices
	if st := build(dbus.ManagedObjects{}, nil, nil, ""); st.Available || st.Adapter != nil || st.Devices == nil || len(st.Devices) > 0 {
		t.Errorf("empty: %+v", st)
	}
}

func TestBlocked(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	sw := func(name, typ, adapter, soft, hard string) {
		p := filepath.Join(dir, name)
		os.MkdirAll(p, 0o755)
		for f, s := range map[string]string{"type": typ, "name": adapter, "soft": soft, "hard": hard} {
			os.WriteFile(filepath.Join(p, f), []byte(s+"\n"), 0o644)
		}
	}
	sw("rfkill0", "wlan", "phy0", "1", "0")
	sw("rfkill1", "bluetooth", "hci0", "0", "0")
	off := dbus.ManagedObjects{hci0: adapter("C0", false, nil)}
	blocked := func(objs dbus.ManagedObjects) bool { return build(objs, nil, nil, dir).Adapter.Blocked }
	if blocked(off) {
		t.Error("blocked with no switch on (Wi-Fi's is someone else's)")
	}
	sw("rfkill1", "bluetooth", "hci0", "0", "1")
	if !blocked(off) {
		t.Error("not blocked by a hard switch")
	}
	// PowerState says it alone, without rfkill
	if !build(dbus.ManagedObjects{hci0: adapter("C0", false, map[string]dbus.Variant{"PowerState": v("off-blocked")})}, nil, nil, "").Adapter.Blocked {
		t.Error("off-blocked not blocked")
	}
}

func TestMapError(t *testing.T) {
	t.Parallel()
	reply := func(name string) error {
		return axerr.Wrap(axerr.Internal, &dbus.Error{Name: name, Message: "msg"}, "call")
	}
	for name, want := range map[string]axerr.Kind{
		errPrefix + "InProgress":             axerr.Busy,
		errPrefix + "NotReady":               axerr.Unavailable,
		errPrefix + "AuthenticationCanceled": axerr.Refused,
		errPrefix + "AuthenticationFailed":   axerr.Failed,
		errPrefix + "Failed":                 axerr.Failed,
		errPrefix + "DoesNotExist":           axerr.NotFound,
		errPrefix + "NotAuthorized":          axerr.NotAuthorized,
	} {
		if got := axerr.KindOf(mapError(reply(name))); got != want {
			t.Errorf("%s: %s, want %s", name, got, want)
		}
	}
	// The bus's own errors keep their kind
	gone := axerr.Wrap(axerr.Unavailable, &dbus.Error{Name: dbus.ErrServiceUnknown}, "call")
	if got := axerr.KindOf(mapError(gone)); got != axerr.Unavailable {
		t.Errorf("service unknown: %s", got)
	}
}

// fakeBlueZ is BlueZ on a test bus: its objects, the methods the service
// calls, and the signals it sends when they change.
type fakeBlueZ struct {
	t    *testing.T
	conn *dbus.Conn

	mu       sync.Mutex
	objs     dbus.ManagedObjects
	unexport map[dbus.ObjectPath][]func()
	calls    []string
	// hold keeps a call ("Connect AA:…:01") from answering until closed
	hold map[string]chan struct{}
	// fail makes a call answer this error
	fail map[string]*dbus.Error
	// discovery are the clients with a scan running
	discovery map[string]bool
}

func newFakeBlueZ(t *testing.T, bus *dbustest.Bus, objs dbus.ManagedObjects) *fakeBlueZ {
	t.Helper()
	conn, err := dbus.Dial(t.Context(), bus.Address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	f := &fakeBlueZ{t: t, conn: conn, objs: dbus.ManagedObjects{}, unexport: map[dbus.ObjectPath][]func(){},
		hold: map[string]chan struct{}{}, fail: map[string]*dbus.Error{}, discovery: map[string]bool{}}
	if _, err := conn.Export(rootPath, dbus.Interface{Name: dbus.IfaceObjectManager, Methods: map[string]dbus.Method{
		"GetManagedObjects": {Out: "a{oa{sa{sv}}}", Fn: func(context.Context, *dbus.Message) ([]any, error) {
			f.mu.Lock()
			defer f.mu.Unlock()
			out := map[dbus.ObjectPath]map[string]map[string]dbus.Variant{}
			for p, i := range f.objs {
				out[p] = map[string]map[string]dbus.Variant{}
				for n, props := range i {
					out[p][n] = maps.Clone(props)
				}
			}
			return []any{out}, nil
		}},
	}}); err != nil {
		t.Fatal(err)
	}
	for _, p := range slices.Sorted(maps.Keys(objs)) {
		f.add(p, objs[p], false)
	}
	if _, err := conn.RequestName(t.Context(), busName, dbus.NameDoNotQueue); err != nil {
		t.Fatal(err)
	}
	return f
}

// add adds an object (with an InterfacesAdded signal when signal) and
// exports its methods and properties.
func (f *fakeBlueZ) add(p dbus.ObjectPath, ifaces dbus.Interfaces, signal bool) {
	f.mu.Lock()
	f.objs[p] = ifaces
	f.mu.Unlock()
	exports := []dbus.Interface{{Name: "org.freedesktop.DBus.Properties", Methods: map[string]dbus.Method{
		"Set": {In: "ssv", Fn: f.set(p)},
	}}}
	if _, ok := ifaces[ifaceAdapter]; ok {
		exports = append(exports, dbus.Interface{Name: ifaceAdapter, Methods: map[string]dbus.Method{
			"StartDiscovery": {Fn: f.discover(p, true)},
			"StopDiscovery":  {Fn: f.discover(p, false)},
			"RemoveDevice":   {In: "o", Fn: f.removeDevice},
		}})
	}
	if _, ok := ifaces[ifaceDevice]; ok {
		exports = append(exports, dbus.Interface{Name: ifaceDevice, Methods: map[string]dbus.Method{
			"Connect":    {Defer: f.deferred(p, "Connect", func() { f.changed(p, ifaceDevice, "Connected", true) })},
			"Disconnect": {Defer: f.deferred(p, "Disconnect", func() { f.changed(p, ifaceDevice, "Connected", false) })},
			"Pair":       {Defer: f.deferred(p, "Pair", func() { f.changed(p, ifaceDevice, "Paired", true) })},
			"CancelPairing": {Fn: func(context.Context, *dbus.Message) ([]any, error) {
				f.record("CancelPairing " + f.addr(p))
				return nil, nil
			}},
		}})
	}
	for _, i := range exports {
		un, err := f.conn.Export(p, i)
		if err != nil {
			f.t.Error(err)
			continue
		}
		f.mu.Lock()
		f.unexport[p] = append(f.unexport[p], un)
		f.mu.Unlock()
	}
	if signal {
		f.conn.Emit(rootPath, dbus.IfaceObjectManager, "InterfacesAdded", "oa{sa{sv}}", p, map[string]map[string]dbus.Variant(ifaces))
	}
}

func (f *fakeBlueZ) addr(p dbus.ObjectPath) string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return props(f.objs[p][ifaceDevice]).str("Address")
}

func (f *fakeBlueZ) record(call string) *dbus.Error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls = append(f.calls, call)
	return f.fail[call]
}

func (f *fakeBlueZ) set(p dbus.ObjectPath) func(context.Context, *dbus.Message) ([]any, error) {
	return func(_ context.Context, m *dbus.Message) ([]any, error) {
		var iface, key string
		var value dbus.Variant
		if err := m.Store(&iface, &key, &value); err != nil {
			return nil, dbus.NewError(dbus.ErrInvalidArgs, "%v", err)
		}
		if e := f.record("Set " + key + " " + path.Base(string(p))); e != nil {
			return nil, e
		}
		f.changed(p, iface, key, value.Value)
		if key == "Powered" {
			f.changed(p, iface, "PowerState", map[bool]string{true: "on", false: "off"}[value.Value.(bool)])
		}
		return nil, nil
	}
}

func (f *fakeBlueZ) discover(p dbus.ObjectPath, on bool) func(context.Context, *dbus.Message) ([]any, error) {
	return func(_ context.Context, m *dbus.Message) ([]any, error) {
		name := map[bool]string{true: "StartDiscovery", false: "StopDiscovery"}[on]
		if e := f.record(name); e != nil {
			return nil, e
		}
		f.mu.Lock()
		if on == f.discovery[m.Sender] {
			f.mu.Unlock()
			if on {
				return nil, dbus.NewError(errPrefix+"InProgress", "Operation already in progress")
			}
			return nil, dbus.NewError(errPrefix+"Failed", "No discovery started")
		}
		if on {
			f.discovery[m.Sender] = true
		} else {
			delete(f.discovery, m.Sender)
		}
		scanning := len(f.discovery) > 0
		f.mu.Unlock()
		f.changed(p, ifaceAdapter, "Discovering", scanning)
		return nil, nil
	}
}

func (f *fakeBlueZ) removeDevice(_ context.Context, m *dbus.Message) ([]any, error) {
	var p dbus.ObjectPath
	m.Store(&p)
	if e := f.record("RemoveDevice " + f.addr(p)); e != nil {
		return nil, e
	}
	f.drop(p)
	return nil, nil
}

// deferred answers a call once its hold (if any) is released: effect
// first, as BlueZ sends its signals before the reply.
func (f *fakeBlueZ) deferred(p dbus.ObjectPath, member string, effect func()) func(context.Context, *dbus.Message, func([]any, error)) {
	return func(_ context.Context, _ *dbus.Message, reply func([]any, error)) {
		key := member + " " + f.addr(p)
		e := f.record(key)
		f.mu.Lock()
		hold := f.hold[key]
		f.mu.Unlock()
		go func() {
			if hold != nil {
				<-hold
			}
			if e != nil {
				reply(nil, e)
				return
			}
			effect()
			reply(nil, nil)
		}()
	}
}

func (f *fakeBlueZ) changed(p dbus.ObjectPath, iface, key string, value any) {
	f.mu.Lock()
	props := maps.Clone(f.objs[p][iface])
	props[key] = v(value)
	f.objs[p][iface] = props
	f.mu.Unlock()
	f.conn.Emit(p, "org.freedesktop.DBus.Properties", "PropertiesChanged", "sa{sv}as", iface, map[string]dbus.Variant{key: v(value)}, []string{})
}

func (f *fakeBlueZ) drop(p dbus.ObjectPath) {
	f.mu.Lock()
	ifaces := slices.Collect(maps.Keys(f.objs[p]))
	delete(f.objs, p)
	un := f.unexport[p]
	delete(f.unexport, p)
	f.mu.Unlock()
	for _, u := range un {
		u()
	}
	f.conn.Emit(rootPath, dbus.IfaceObjectManager, "InterfacesRemoved", "oas", p, ifaces)
}

func (f *fakeBlueZ) takeCalls() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	out := f.calls
	f.calls = nil
	return out
}

// harness runs a service against a bus, recording every state it hands
// on.
type harness struct {
	s *Service

	mu     sync.Mutex
	states []State
}

func start(t *testing.T, bus *dbustest.Bus) *harness {
	t.Helper()
	h := &harness{}
	h.s = New(Options{
		SystemBus: func(ctx context.Context) (*dbus.Conn, error) {
			return dbus.Dial(ctx, bus.Address, dbus.Options{})
		},
		OnChange: func(st State) {
			h.mu.Lock()
			h.states = append(h.states, st)
			h.mu.Unlock()
		},
		Rfkill: t.TempDir(),
		Settle: 10 * time.Millisecond,
		Retry:  20 * time.Millisecond,
	})
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		h.s.Run(ctx)
	}()
	t.Cleanup(func() {
		cancel()
		<-done
	})
	return h
}

func (h *harness) wait(t *testing.T, what string, cond func(State) bool) {
	t.Helper()
	if !testkit.Eventually(func() bool { return cond(h.s.State()) }) {
		t.Fatalf("%s: state %+v", what, h.s.State())
	}
}

// history says, for one device, each state handed on in turn (repeats
// gathered): "disconnected", "pairing", "connecting", …
func (h *harness) history(address string) []string {
	h.mu.Lock()
	defer h.mu.Unlock()
	out := []string{}
	for _, st := range h.states {
		for _, d := range st.Devices {
			if d.Address != address {
				continue
			}
			s := d.State
			if d.Pairing {
				s = "pairing"
			}
			if len(out) == 0 || out[len(out)-1] != s {
				out = append(out, s)
			}
		}
	}
	return out
}

func (h *harness) clearStates() {
	h.mu.Lock()
	h.states = nil
	h.mu.Unlock()
}

func dev(st State, address string) Device {
	for _, d := range st.Devices {
		if d.Address == address {
			return d
		}
	}
	return Device{}
}

// The sync, then each signal kind; BlueZ restarting is read afresh
func TestFollow(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	f := newFakeBlueZ(t, bus, fixture())
	h := start(t, bus)
	h.wait(t, "sync", func(st State) bool { return len(st.Devices) == 3 })
	if st := h.s.State(); !st.Available || st.Adapter.Address != "C0:00:00:00:00:00" || dev(st, headset).Battery != 80 {
		t.Fatalf("synced %+v", st)
	}

	// A device found: at the end
	late := "AA:00:00:00:00:09"
	f.add(devPath(hci0, late), device(hci0, late, "Speaker", false, false, nil), true)
	h.wait(t, "added", func(st State) bool { return slices.Equal(addrs(st), []string{headset, mouse, phone, late}) })
	// Its battery, then a property, then it's gone
	f.mu.Lock()
	f.objs[devPath(hci0, late)][ifaceBattery] = map[string]dbus.Variant{"Percentage": v(uint8(40))}
	f.mu.Unlock()
	f.conn.Emit(rootPath, dbus.IfaceObjectManager, "InterfacesAdded", "oa{sa{sv}}", devPath(hci0, late), map[string]map[string]dbus.Variant{ifaceBattery: {"Percentage": v(uint8(40))}})
	h.wait(t, "battery", func(st State) bool { return dev(st, late).Battery == 40 })
	f.changed(devPath(hci0, late), ifaceDevice, "Alias", "Kitchen")
	h.wait(t, "alias", func(st State) bool { return dev(st, late).Name == "Kitchen" && dev(st, late).DeviceName == "Speaker" })
	f.conn.Emit(rootPath, dbus.IfaceObjectManager, "InterfacesRemoved", "oas", devPath(hci0, late), []string{ifaceBattery})
	h.wait(t, "battery gone", func(st State) bool { return dev(st, late).Battery == -1 })
	f.drop(devPath(hci0, late))
	h.wait(t, "removed", func(st State) bool { return len(st.Devices) == 3 })
	// The adapter's own properties
	f.changed(hci0, ifaceAdapter, "Powered", false)
	h.wait(t, "powered off", func(st State) bool { return !st.Adapter.Powered })

	// BlueZ goes away, and comes back with another adapter
	f.conn.Close()
	h.wait(t, "gone", func(st State) bool { return !st.Available && st.Adapter == nil && len(st.Devices) == 0 })
	newFakeBlueZ(t, bus, dbus.ManagedObjects{hci1: adapter("C1:00:00:00:00:00", true, nil), devPath(hci1, other): device(hci1, other, "Other", true, true, nil)})
	h.wait(t, "back", func(st State) bool { return st.Available && slices.Equal(addrs(st), []string{other}) })
}

// BlueZ not running: unavailable, and the methods say so; started later,
// it's found
func TestUnavailable(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	h := start(t, bus)
	time.Sleep(30 * time.Millisecond)
	if st := h.s.State(); st.Available || st.Devices == nil {
		t.Errorf("state %+v", st)
	}
	if err := h.s.Connect(t.Context(), headset); axerr.KindOf(err) != axerr.Unavailable {
		t.Errorf("Connect: %v", err)
	}
	newFakeBlueZ(t, bus, fixture())
	h.wait(t, "found", func(st State) bool { return st.Available && len(st.Devices) == 3 })
}

func TestMethods(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	f := newFakeBlueZ(t, bus, fixture())
	h := start(t, bus)
	h.wait(t, "sync", func(st State) bool { return len(st.Devices) == 3 })
	ctx := t.Context()

	if err := h.s.SetPowered(ctx, false); err != nil {
		t.Error(err)
	}
	h.wait(t, "off", func(st State) bool { return !st.Adapter.Powered })
	if err := h.s.SetPowered(ctx, true); err != nil {
		t.Error(err)
	}
	h.wait(t, "on", func(st State) bool { return st.Adapter.Powered })
	if got := f.takeCalls(); !slices.Equal(got, []string{"Set Powered hci0", "Set Powered hci0"}) {
		t.Errorf("calls %v", got)
	}

	// Connect and disconnect, each through its transitional state
	h.clearStates()
	if err := h.s.Connect(ctx, mouse); err != nil {
		t.Error(err)
	}
	h.wait(t, "connected", func(st State) bool { return dev(st, mouse).State == "connected" })
	if err := h.s.Disconnect(ctx, strings.ToLower(mouse)); err != nil {
		t.Error(err)
	}
	h.wait(t, "disconnected", func(st State) bool { return dev(st, mouse).State == "disconnected" })
	if got := h.history(mouse); !slices.Equal(got, []string{"connecting", "connected", "disconnecting", "disconnected"}) {
		t.Errorf("mouse went %v", got)
	}
	// Connected already, disconnected already: nothing asked
	if err := h.s.Connect(ctx, headset); err != nil {
		t.Error(err)
	}
	if err := h.s.Disconnect(ctx, phone); err != nil {
		t.Error(err)
	}
	if got := f.takeCalls(); !slices.Equal(got, []string{"Connect " + mouse, "Disconnect " + mouse}) {
		t.Errorf("calls %v", got)
	}

	// Pair: trusted, paired, then connected, showing pairing then
	// connecting
	h.clearStates()
	if err := h.s.Pair(ctx, phone); err != nil {
		t.Error(err)
	}
	h.wait(t, "paired", func(st State) bool {
		d := dev(st, phone)
		return d.Paired && d.Trusted && d.State == "connected" && !d.Pairing
	})
	if got := h.history(phone); !slices.Equal(got, []string{"pairing", "connecting", "connected"}) {
		t.Errorf("phone went %v", got)
	}
	if got := f.takeCalls(); !slices.Equal(got, []string{"Set Trusted " + path.Base(string(devPath(hci0, phone))), "Pair " + phone, "Connect " + phone}) {
		t.Errorf("pair calls %v", got)
	}

	// A pair refused stops there, and the state comes back
	f.add(devPath(hci0, "AA:00:00:00:00:04"), device(hci0, "AA:00:00:00:00:04", "Watch", false, false, nil), true)
	h.wait(t, "watch", func(st State) bool { return len(st.Devices) == 4 })
	f.mu.Lock()
	f.fail["Pair AA:00:00:00:00:04"] = dbus.NewError(errPrefix+"AuthenticationCanceled", "Authentication Canceled")
	f.mu.Unlock()
	if err := h.s.Pair(ctx, "AA:00:00:00:00:04"); axerr.KindOf(err) != axerr.Refused {
		t.Errorf("refused pair: %v", err)
	}
	h.wait(t, "not pairing", func(st State) bool { d := dev(st, "AA:00:00:00:00:04"); return !d.Pairing && d.State == "disconnected" })
	if got := f.takeCalls(); slices.Contains(got, "Connect AA:00:00:00:00:04") {
		t.Errorf("connected after a refused pair: %v", got)
	}

	// Cancel and forget
	if err := h.s.CancelPair(ctx, "AA:00:00:00:00:04"); err != nil {
		t.Error(err)
	}
	if err := h.s.Forget(ctx, "AA:00:00:00:00:04"); err != nil {
		t.Error(err)
	}
	h.wait(t, "forgotten", func(st State) bool { return len(st.Devices) == 3 })
	if got := f.takeCalls(); !slices.Equal(got, []string{"CancelPairing AA:00:00:00:00:04", "RemoveDevice AA:00:00:00:00:04"}) {
		t.Errorf("calls %v", got)
	}
	// Not the default adapter's, or no such device
	for _, a := range []string{other, "nope"} {
		if err := h.s.Connect(ctx, a); axerr.KindOf(err) != axerr.NotFound {
			t.Errorf("Connect %s: %v", a, err)
		}
	}
}

// A connect waiting on BlueZ shows connecting until it answers, and a
// second call on the device meanwhile is busy
func TestInFlight(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	f := newFakeBlueZ(t, bus, fixture())
	h := start(t, bus)
	h.wait(t, "sync", func(st State) bool { return len(st.Devices) == 3 })
	gate := make(chan struct{})
	f.mu.Lock()
	f.hold["Connect "+mouse] = gate
	f.mu.Unlock()
	done := make(chan error, 1)
	go func() { done <- h.s.Connect(context.Background(), mouse) }()
	h.wait(t, "connecting", func(st State) bool { return dev(st, mouse).State == "connecting" })
	if err := h.s.Disconnect(t.Context(), headset); err != nil {
		t.Errorf("another device: %v", err)
	}
	if err := h.s.Pair(t.Context(), mouse); axerr.KindOf(err) != axerr.Busy {
		t.Errorf("pair while connecting: %v", err)
	}
	close(gate)
	if err := <-done; err != nil {
		t.Error(err)
	}
	h.wait(t, "connected", func(st State) bool { return dev(st, mouse).State == "connected" })

	// A failed connect goes back to disconnected
	f.mu.Lock()
	f.fail["Connect "+phone] = dbus.NewError(errPrefix+"Failed", "Page Timeout")
	f.mu.Unlock()
	if err := h.s.Connect(t.Context(), phone); axerr.KindOf(err) != axerr.Failed || !strings.Contains(err.Error(), "Page Timeout") {
		t.Errorf("failed connect: %v", err)
	}
	h.wait(t, "back", func(st State) bool { return dev(st, phone).State == "disconnected" })
}

// Discovery is this client's session: stopping it leaves another's
// running, and it starts again when BlueZ comes back
func TestDiscovery(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	f := newFakeBlueZ(t, bus, fixture())
	h := start(t, bus)
	h.wait(t, "sync", func(st State) bool { return st.Available })
	ctx := t.Context()

	if err := h.s.Discovery(ctx, true); err != nil {
		t.Fatal(err)
	}
	h.wait(t, "scanning", func(st State) bool { return st.Adapter.Discovering })
	// Asked twice: one call
	if err := h.s.Discovery(ctx, true); err != nil {
		t.Error(err)
	}
	// Another app scans too
	app, err := dbus.Dial(ctx, bus.Address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	defer app.Close()
	if _, err := app.Call(ctx, busName, hci0, ifaceAdapter, "StartDiscovery", ""); err != nil {
		t.Fatal(err)
	}
	if err := h.s.Discovery(ctx, false); err != nil {
		t.Error(err)
	}
	// Stopping ours twice: nothing to stop
	if err := h.s.Discovery(ctx, false); err != nil {
		t.Error(err)
	}
	time.Sleep(30 * time.Millisecond)
	if !h.s.State().Adapter.Discovering {
		t.Error("stopping ours stopped the other app's")
	}
	if got := f.takeCalls(); !slices.Equal(got, []string{"StartDiscovery", "StartDiscovery", "StopDiscovery"}) {
		t.Errorf("calls %v", got)
	}

	// Wanted while BlueZ restarts: asked of the new one
	if err := h.s.Discovery(ctx, true); err != nil {
		t.Fatal(err)
	}
	f.conn.Close()
	h.wait(t, "gone", func(st State) bool { return !st.Available })
	f2 := newFakeBlueZ(t, bus, fixture())
	h.wait(t, "scanning again", func(st State) bool { return st.Available && st.Adapter.Discovering })
	if got := f2.takeCalls(); !slices.Equal(got, []string{"StartDiscovery"}) {
		t.Errorf("calls after the restart %v", got)
	}
}
