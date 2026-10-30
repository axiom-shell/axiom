package nmvpn

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// fakeNM is NetworkManager on a test bus: a few profiles, activating and
// deactivating them, and calling the registered agent.
type fakeNM struct {
	conn *dbus.Conn

	mu      sync.Mutex
	conns   map[dbus.ObjectPath]map[string]map[string]dbus.Variant
	actives map[dbus.ObjectPath]fakeActive
	agent   string // the agent's unique name
	next    int
}

type fakeActive struct {
	uuid, kind string
	state      uint32
}

func vpnSettings(uuid, name, service string, data map[string]string) map[string]map[string]dbus.Variant {
	return map[string]map[string]dbus.Variant{
		"connection": {"uuid": dbus.MakeVariant(uuid), "id": dbus.MakeVariant(name), "type": dbus.MakeVariant("vpn"), "autoconnect": dbus.MakeVariant(false)},
		"vpn":        {"service-type": dbus.MakeVariant(service), "data": dbus.MakeVariant(data)},
	}
}

func newFakeNM(t *testing.T, bus *dbustest.Bus) *fakeNM {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	conn, err := dbus.Dial(ctx, bus.Address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	f := &fakeNM{conn: conn, actives: map[dbus.ObjectPath]fakeActive{}, conns: map[dbus.ObjectPath]map[string]map[string]dbus.Variant{
		"/c/1": {
			"connection": {"uuid": dbus.MakeVariant("wg-1"), "id": dbus.MakeVariant("Home WG"), "type": dbus.MakeVariant("wireguard")},
			"wireguard":  {"private-key-flags": dbus.MakeVariant(uint32(1))},
		},
		"/c/2": vpnSettings("ovpn-1", "Work", "org.freedesktop.NetworkManager.openvpn", map[string]string{"username": "me", "password-flags": "2", "cert-pass-flags": "4"}),
		"/c/3": vpnSettings("oc-1", "Missing plugin", "org.freedesktop.NetworkManager.openconnect", map[string]string{}),
		"/c/4": {"connection": {"uuid": dbus.MakeVariant("eth"), "id": dbus.MakeVariant("Wired"), "type": dbus.MakeVariant("802-3-ethernet")}},
	}}
	export := func(path dbus.ObjectPath, iface string, methods map[string]dbus.Method) {
		if _, err := conn.Export(path, dbus.Interface{Name: iface, Methods: methods}); err != nil {
			t.Fatal(err)
		}
	}
	export(settingsPath, ifaceSettings, map[string]dbus.Method{
		"ListConnections": {Out: "ao", Fn: func(context.Context, *dbus.Message) ([]any, error) {
			f.mu.Lock()
			defer f.mu.Unlock()
			var out []dbus.ObjectPath
			for p := range f.conns {
				out = append(out, p)
			}
			return []any{out}, nil
		}},
		"GetConnectionByUuid": {In: "s", Out: "o", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			if p := f.path(m.Body[0].(string)); p != "" {
				return []any{p}, nil
			}
			return nil, dbus.NewError("org.freedesktop.NetworkManager.Settings.InvalidConnection", "no such connection")
		}},
	})
	for p := range f.conns {
		export(p, ifaceConn, map[string]dbus.Method{
			"GetSettings": {Out: "a{sa{sv}}", Fn: func(context.Context, *dbus.Message) ([]any, error) {
				f.mu.Lock()
				defer f.mu.Unlock()
				return []any{f.conns[p]}, nil
			}},
		})
	}
	export(managerPath, ifaceManager, map[string]dbus.Method{
		"ActivateConnection": {In: "ooo", Out: "o", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			f.mu.Lock()
			defer f.mu.Unlock()
			c := f.conns[m.Body[0].(dbus.ObjectPath)]
			f.next++
			ap := dbus.ObjectPath("/a/" + string(rune('0'+f.next)))
			kind := c["connection"]["type"].Value.(string)
			f.actives[ap] = fakeActive{uuid: c["connection"]["uuid"].Value.(string), kind: kind, state: activeActivated}
			return []any{ap}, nil
		}},
		"DeactivateConnection": {In: "o", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			f.mu.Lock()
			defer f.mu.Unlock()
			ap := m.Body[0].(dbus.ObjectPath)
			if _, ok := f.actives[ap]; !ok {
				return nil, dbus.NewError("org.freedesktop.NetworkManager.ConnectionNotActive", "not active")
			}
			delete(f.actives, ap)
			return nil, nil
		}},
	})
	export(agentMgrPath, ifaceAgentMgr, map[string]dbus.Method{
		"RegisterWithCapabilities": {In: "su", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			f.mu.Lock()
			f.agent = m.Sender
			f.mu.Unlock()
			return nil, nil
		}},
	})
	// Properties of the manager, every active connection and IP config
	// (exported at the root of each path NetworkManager would use)
	props := func(path dbus.ObjectPath, iface string) map[string]dbus.Variant {
		f.mu.Lock()
		defer f.mu.Unlock()
		switch {
		case path == managerPath:
			var list []dbus.ObjectPath
			for ap := range f.actives {
				list = append(list, ap)
			}
			return map[string]dbus.Variant{"ActiveConnections": dbus.MakeVariant(list)}
		case path == "/ip4" && iface == ifaceIP4Config:
			return map[string]dbus.Variant{"AddressData": {Sig: "aa{sv}", Value: []map[string]dbus.Variant{{"address": dbus.MakeVariant("10.99.0.2"), "prefix": dbus.MakeVariant(uint32(24))}}}}
		case path == "/dev/wg":
			return map[string]dbus.Variant{"Interface": dbus.MakeVariant("wg0")}
		}
		a, ok := f.actives[path]
		if !ok {
			return nil
		}
		return map[string]dbus.Variant{
			"Uuid": dbus.MakeVariant(a.uuid), "Type": dbus.MakeVariant(a.kind), "State": dbus.MakeVariant(a.state),
			"Ip4Config": dbus.MakeVariant(dbus.ObjectPath("/ip4")), "Devices": dbus.MakeVariant([]dbus.ObjectPath{"/dev/wg"}),
		}
	}
	propMethods := map[string]dbus.Method{
		"Get": {In: "ss", Out: "v", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			v, ok := props(m.Path, m.Body[0].(string))[m.Body[1].(string)]
			if !ok {
				return nil, dbus.NewError(dbus.ErrInvalidArgs, "no such property")
			}
			return []any{v}, nil
		}},
		"GetAll": {In: "s", Out: "a{sv}", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			p := props(m.Path, m.Body[0].(string))
			if p == nil {
				return nil, dbus.NewError(dbus.ErrUnknownObject, "no such object")
			}
			return []any{p}, nil
		}},
	}
	// Active connections are /a/1 to /a/9 (ActivateConnection's names)
	paths := []dbus.ObjectPath{managerPath, "/ip4", "/dev/wg"}
	for i := 1; i <= 9; i++ {
		paths = append(paths, dbus.ObjectPath("/a/"+string(rune('0'+i))))
	}
	for _, p := range paths {
		export(p, "org.freedesktop.DBus.Properties", propMethods)
	}
	if _, err := conn.RequestName(ctx, busName, dbus.NameDoNotQueue); err != nil {
		t.Fatal(err)
	}
	return f
}

func (f *fakeNM) path(uuid string) dbus.ObjectPath {
	f.mu.Lock()
	defer f.mu.Unlock()
	for p, c := range f.conns {
		if c["connection"]["uuid"].Value == uuid {
			return p
		}
	}
	return ""
}

// activeChanged tells the service an active connection changed, as
// NetworkManager does.
func (f *fakeNM) activeChanged(t *testing.T, ap dbus.ObjectPath, state, reason uint32) {
	t.Helper()
	f.mu.Lock()
	if state == activeDeactivated {
		delete(f.actives, ap)
	}
	f.mu.Unlock()
	if err := f.conn.Emit(ap, ifaceActive, "StateChanged", "uu", state, reason); err != nil {
		t.Fatal(err)
	}
}

// pluginDir has an OpenVPN plugin and no other.
func pluginDir(t *testing.T) []string {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "nm-openvpn-service.name"), []byte("[VPN Connection]\nname=openvpn\nservice=org.freedesktop.NetworkManager.openvpn\n"), 0o644)
	return []string{dir}
}

type harness struct {
	svc     *Service
	nm      *fakeNM
	client  *dbus.Conn
	mu      sync.Mutex
	asked   []SecretRequest
	done    []string
	noShell bool
}

func start(t *testing.T) *harness {
	t.Helper()
	bus := dbustest.New(t)
	h := &harness{nm: newFakeNM(t, bus)}
	h.svc = New(Options{
		SystemBus: func(ctx context.Context) (*dbus.Conn, error) {
			c, err := dbus.Dial(ctx, bus.Address, dbus.Options{})
			h.mu.Lock()
			h.client = c
			h.mu.Unlock()
			return c, err
		},
		PluginDirs: pluginDir(t),
		OnSecret: func(r SecretRequest) bool {
			h.mu.Lock()
			defer h.mu.Unlock()
			h.asked = append(h.asked, r)
			return !h.noShell
		},
		OnSecretDone: func(id string) {
			h.mu.Lock()
			defer h.mu.Unlock()
			h.done = append(h.done, id)
		},
		Settle: time.Millisecond,
	})
	ctx, cancel := context.WithCancel(context.Background())
	stopped := make(chan struct{})
	go func() { h.svc.Run(ctx); close(stopped) }()
	t.Cleanup(func() { cancel(); <-stopped })
	if !testkit.Eventually(func() bool { return len(h.svc.State().Connections) == 3 }) {
		t.Fatalf("state %+v", h.svc.State())
	}
	return h
}

func (h *harness) conn(uuid string) Connection {
	for _, c := range h.svc.State().Connections {
		if c.UUID == uuid {
			return c
		}
	}
	return Connection{}
}

func TestListsVPNsOnly(t *testing.T) {
	t.Parallel()
	h := start(t)
	got := h.svc.State()
	want := State{Available: true, Connections: []Connection{
		{UUID: "wg-1", Name: "Home WG", Kind: "wireguard", Plugin: true, Autoconnect: true, State: "off"},
		{UUID: "oc-1", Name: "Missing plugin", Kind: "openconnect", State: "off", Error: "plugin-missing"},
		{UUID: "ovpn-1", Name: "Work", Kind: "openvpn", Plugin: true, State: "off"},
	}}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("state\n got %+v\nwant %+v", got, want)
	}
	h.nm.mu.Lock()
	agent := h.nm.agent
	h.nm.mu.Unlock()
	if agent == "" {
		t.Error("the agent didn't register")
	}
}

func TestUpDownAndFailures(t *testing.T) {
	t.Parallel()
	h := start(t)
	ctx := context.Background()
	if err := h.svc.Up(ctx, "wg-1"); err != nil {
		t.Fatal(err)
	}
	if !testkit.Eventually(func() bool { return h.conn("wg-1").State == "on" }) {
		t.Fatalf("not on: %+v", h.conn("wg-1"))
	}
	if c := h.conn("wg-1"); c.IPv4 != "10.99.0.2" || c.Device != "wg0" {
		t.Errorf("up: %+v", c)
	}
	if err := h.svc.Down(ctx, "wg-1"); err != nil {
		t.Fatal(err)
	}
	if !testkit.Eventually(func() bool { return h.conn("wg-1").State == "off" }) {
		t.Fatalf("not off: %+v", h.conn("wg-1"))
	}
	if h.conn("wg-1").Error != "" {
		t.Errorf("a disconnect asked for is no error: %+v", h.conn("wg-1"))
	}

	// A connection failing for want of secrets says so, until tried again
	if err := h.svc.Up(ctx, "ovpn-1"); err != nil {
		t.Fatal(err)
	}
	h.nm.activeChanged(t, "/a/2", activeDeactivated, 9)
	if !testkit.Eventually(func() bool { return h.conn("ovpn-1").Error == "no-secrets" }) {
		t.Fatalf("no error: %+v", h.conn("ovpn-1"))
	}
	if err := h.svc.Up(ctx, "ovpn-1"); err != nil {
		t.Fatal(err)
	}
	if !testkit.Eventually(func() bool { c := h.conn("ovpn-1"); return c.State == "on" && c.Error == "" }) {
		t.Fatalf("still failed: %+v", h.conn("ovpn-1"))
	}

	if err := h.svc.Up(ctx, "oc-1"); err == nil {
		t.Error("a VPN whose plugin is missing came up")
	}
	if err := h.svc.Up(ctx, "nope"); err == nil {
		t.Error("an unknown VPN came up")
	}
}

// Each connection leaves its path behind (a failure may still come for
// it): a later Down still takes the live one down, every time
func TestDownAfterReconnects(t *testing.T) {
	t.Parallel()
	h := start(t)
	ctx := context.Background()
	for i := range 5 {
		if err := h.svc.Up(ctx, "wg-1"); err != nil {
			t.Fatal(err)
		}
		if !testkit.Eventually(func() bool { return h.conn("wg-1").State == "on" }) {
			t.Fatalf("round %d: not on: %+v", i, h.conn("wg-1"))
		}
		if err := h.svc.Down(ctx, "wg-1"); err != nil {
			t.Fatalf("round %d: %v", i, err)
		}
		if !testkit.Eventually(func() bool { return h.conn("wg-1").State == "off" }) {
			t.Fatalf("round %d: not off: %+v", i, h.conn("wg-1"))
		}
	}
}

// getSecrets calls the agent as NetworkManager does, in the background.
func (h *harness) getSecrets(t *testing.T, path dbus.ObjectPath, setting string, flags uint32) <-chan *dbus.Message {
	t.Helper()
	h.nm.mu.Lock()
	settings, agent := h.nm.conns[path], h.nm.agent
	h.nm.mu.Unlock()
	out := make(chan *dbus.Message, 1)
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), testkit.Bound(5*time.Second))
		defer cancel()
		m, err := h.nm.conn.Call(ctx, agent, agentPath, ifaceAgent, "GetSecrets", "a{sa{sv}}osasu", settings, path, setting, []string{}, flags)
		if err != nil {
			m = &dbus.Message{ErrorName: dbus.ErrorName(err)}
		}
		out <- m
	}()
	return out
}

func wait(t *testing.T, ch <-chan *dbus.Message) *dbus.Message {
	t.Helper()
	select {
	case m := <-ch:
		return m
	case <-time.After(testkit.Bound(5 * time.Second)):
		t.Fatal("no answer")
		return nil
	}
}

func (h *harness) lastAsked(t *testing.T, n int) SecretRequest {
	t.Helper()
	if !testkit.Eventually(func() bool { h.mu.Lock(); defer h.mu.Unlock(); return len(h.asked) == n }) {
		t.Fatalf("asked %d times, want %d", len(h.asked), n)
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.asked[n-1]
}

func TestSecretAgent(t *testing.T) {
	t.Parallel()
	h := start(t)

	// Asked and answered: the secrets go back in the vpn setting
	reply := h.getSecrets(t, "/c/2", "vpn", allowInteraction)
	req := h.lastAsked(t, 1)
	if req.Name != "Work" || req.User != "me" || !reflect.DeepEqual(req.Fields, []string{"password"}) {
		t.Errorf("request %+v", req)
	}
	if err := h.svc.Answer(req.ID, map[string]string{"password": "hunter2", "other": "x"}, false); err != nil {
		t.Fatal(err)
	}
	m := wait(t, reply)
	if m.ErrorName != "" {
		t.Fatal(m.ErrorName)
	}
	secrets := m.Body[0].(map[any]any)["vpn"].(map[string]dbus.Variant)["secrets"].Value.(map[any]any)
	if !reflect.DeepEqual(secrets, map[any]any{"password": "hunter2"}) {
		t.Errorf("secrets %v", secrets)
	}
	if err := h.svc.Answer(req.ID, nil, true); err == nil {
		t.Error("answered twice")
	}

	// Declined
	reply = h.getSecrets(t, "/c/1", "wireguard", allowInteraction)
	req = h.lastAsked(t, 2)
	if !reflect.DeepEqual(req.Fields, []string{"private-key"}) {
		t.Errorf("wireguard fields %v", req.Fields)
	}
	h.svc.Answer(req.ID, nil, true)
	if m := wait(t, reply); m.ErrorName != errUserCanceled {
		t.Errorf("declined: %q", m.ErrorName)
	}

	// Canceled by NetworkManager: the shell is told to hide it
	reply = h.getSecrets(t, "/c/2", "vpn", allowInteraction)
	req = h.lastAsked(t, 3)
	h.nm.mu.Lock()
	agent := h.nm.agent
	h.nm.mu.Unlock()
	if _, err := h.nm.conn.Call(context.Background(), agent, agentPath, ifaceAgent, "CancelGetSecrets", "os", dbus.ObjectPath("/c/2"), "vpn"); err != nil {
		t.Fatal(err)
	}
	if m := wait(t, reply); m.ErrorName != errAgentCanceled {
		t.Errorf("canceled: %q", m.ErrorName)
	}
	if !testkit.Eventually(func() bool { h.mu.Lock(); defer h.mu.Unlock(); return len(h.done) == 3 && h.done[2] == req.ID }) {
		t.Errorf("done %v", h.done)
	}

	// Not ours to ask, no interaction allowed, or nobody to ask: no secrets
	h.nm.mu.Lock()
	h.nm.conns["/c/4"]["802-11-wireless-security"] = map[string]dbus.Variant{}
	h.nm.mu.Unlock()
	if m := wait(t, h.getSecrets(t, "/c/4", "802-11-wireless-security", allowInteraction)); m.ErrorName != errNoSecrets {
		t.Errorf("wifi: %q", m.ErrorName)
	}
	if m := wait(t, h.getSecrets(t, "/c/2", "vpn", 0)); m.ErrorName != errNoSecrets {
		t.Errorf("no interaction: %q", m.ErrorName)
	}
	h.mu.Lock()
	h.noShell = true
	h.mu.Unlock()
	if m := wait(t, h.getSecrets(t, "/c/2", "vpn", allowInteraction)); m.ErrorName != errNoSecrets {
		t.Errorf("no shell: %q", m.ErrorName)
	}
}

func TestReasonError(t *testing.T) {
	t.Parallel()
	for reason, want := range map[uint32]string{0: "", 2: "", 11: "", 3: "failed", 6: "timeout", 7: "timeout", 8: "service-failed", 9: "no-secrets", 10: "login-failed", 14: "failed"} {
		if got := reasonError(reason); got != want {
			t.Errorf("reason %d: %q, want %q", reason, got, want)
		}
	}
}

func TestSecretRequestFields(t *testing.T) {
	t.Parallel()
	asMap := func(s map[string]map[string]dbus.Variant) any {
		out := map[any]any{}
		for k, v := range s {
			out[k] = v
		}
		return out
	}
	// a{ss} decodes to map[any]any
	data := func(d map[string]string) map[string]map[string]dbus.Variant {
		s := vpnSettings("u", "n", "org.freedesktop.NetworkManager.openvpn", nil)
		m := map[any]any{}
		for k, v := range d {
			m[k] = v
		}
		s["vpn"]["data"] = dbus.Variant{Sig: "a{ss}", Value: m}
		return s
	}
	for _, tc := range []struct {
		name     string
		settings any
		setting  string
		hints    []string
		want     []string
		message  string
	}{
		{"not-saved password", asMap(data(map[string]string{"password-flags": "2"})), "vpn", nil, []string{"password"}, ""},
		{"agent-owned and saved-by-system", asMap(data(map[string]string{"password-flags": "1", "cert-pass-flags": "0"})), "vpn", nil, []string{"password"}, ""},
		{"not required", asMap(data(map[string]string{"cert-pass-flags": "6"})), "vpn", nil, nil, ""},
		{"hints win", asMap(data(map[string]string{"password-flags": "2"})), "vpn", []string{"x-vpn-message:Token please", "token"}, []string{"token"}, "Token please"},
		{"wifi isn't ours", asMap(data(map[string]string{"password-flags": "2"})), "802-11-wireless-security", nil, nil, ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			req, ok := secretRequest(tc.settings, tc.setting, tc.hints)
			if ok != (tc.want != nil) || (ok && !reflect.DeepEqual(req.Fields, tc.want)) || req.Message != tc.message {
				t.Errorf("got %v %+v, want %v %q", ok, req, tc.want, tc.message)
			}
		})
	}
}
