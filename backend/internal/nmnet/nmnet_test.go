package nmnet

import (
	"context"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
)

type settings = map[string]map[string]dbus.Variant

// fakeNM is NetworkManager on a test bus: a wired and a Wi-Fi device
// with their configs, and saved profiles that can be read, updated,
// added and activated.
type fakeNM struct {
	mu        sync.Mutex
	profiles  map[dbus.ObjectPath]settings
	secrets   map[dbus.ObjectPath]settings
	added     []settings
	activated []dbus.ObjectPath
}

func newFakeNM(t *testing.T) *Service {
	svc, _ := startFake(t)
	return svc
}

func startFake(t *testing.T) (*Service, *fakeNM) {
	t.Helper()
	bus := dbustest.New(t)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	conn, err := dbus.Dial(ctx, bus.Address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	f := &fakeNM{
		profiles: map[dbus.ObjectPath]settings{
			"/c/1": {
				"connection": {"uuid": dbus.MakeVariant("home"), "id": dbus.MakeVariant("Home"), "type": dbus.MakeVariant(wifiType)},
				wifiType:     {"ssid": dbus.MakeVariant([]byte("Home"))},
				wifiSecurity: {"key-mgmt": dbus.MakeVariant("wpa-psk")},
				"ipv4":       {"method": dbus.MakeVariant("manual")},
			},
			"/c/2": {"connection": {"uuid": dbus.MakeVariant("eth"), "id": dbus.MakeVariant("Wired"), "type": dbus.MakeVariant("802-3-ethernet")}},
		},
		secrets: map[dbus.ObjectPath]settings{
			"/c/1": {wifiSecurity: {"psk": dbus.MakeVariant("hunter22")}},
		},
	}
	export := func(path dbus.ObjectPath, iface string, methods map[string]dbus.Method) {
		if _, err := conn.Export(path, dbus.Interface{Name: iface, Methods: methods}); err != nil {
			t.Fatal(err)
		}
	}
	devices := map[string]dbus.ObjectPath{"enp1s0": "/d/1", "wlan0": "/d/2"}
	export(managerPath, ifaceManager, map[string]dbus.Method{
		"GetDeviceByIpIface": {In: "s", Out: "o", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			if p, ok := devices[m.Body[0].(string)]; ok {
				return []any{p}, nil
			}
			return nil, dbus.NewError("org.freedesktop.NetworkManager.UnknownDevice", "no device")
		}},
		"GetDevices": {Out: "ao", Fn: func(context.Context, *dbus.Message) ([]any, error) {
			return []any{[]dbus.ObjectPath{"/d/1", "/d/2"}}, nil
		}},
		"ActivateConnection": {In: "ooo", Out: "o", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			f.mu.Lock()
			defer f.mu.Unlock()
			f.activated = append(f.activated, m.Body[0].(dbus.ObjectPath))
			return []any{dbus.ObjectPath("/a/1")}, nil
		}},
		"AddAndActivateConnection": {In: "a{sa{sv}}oo", Out: "oo", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			f.mu.Lock()
			defer f.mu.Unlock()
			f.added = append(f.added, decoded(m.Body[0]))
			return []any{dbus.ObjectPath("/c/9"), dbus.ObjectPath("/a/1")}, nil
		}},
	})
	export(settingsPath, ifaceSettings, map[string]dbus.Method{
		"ListConnections": {Out: "ao", Fn: func(context.Context, *dbus.Message) ([]any, error) {
			return []any{[]dbus.ObjectPath{"/c/1", "/c/2"}}, nil
		}},
		"GetConnectionByUuid": {In: "s", Out: "o", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			f.mu.Lock()
			defer f.mu.Unlock()
			for p, s := range f.profiles {
				if s["connection"]["uuid"].Value == m.Body[0] {
					return []any{p}, nil
				}
			}
			return nil, dbus.NewError("org.freedesktop.NetworkManager.Settings.InvalidConnection", "no such connection")
		}},
	})
	for _, p := range []dbus.ObjectPath{"/c/1", "/c/2"} {
		export(p, ifaceConn, map[string]dbus.Method{
			"GetSettings": {Out: "a{sa{sv}}", Fn: func(context.Context, *dbus.Message) ([]any, error) {
				f.mu.Lock()
				defer f.mu.Unlock()
				return []any{f.profiles[p]}, nil
			}},
			"GetSecrets": {In: "s", Out: "a{sa{sv}}", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
				f.mu.Lock()
				defer f.mu.Unlock()
				name := m.Body[0].(string)
				if sec, ok := f.secrets[p][name]; ok {
					return []any{settings{name: sec}}, nil
				}
				return []any{settings{}}, nil
			}},
			// As NetworkManager: settings sent without their secrets lose them
			"Update": {In: "a{sa{sv}}", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
				f.mu.Lock()
				defer f.mu.Unlock()
				s := decoded(m.Body[0])
				f.profiles[p] = s
				f.secrets[p] = settings{}
				if psk, ok := s[wifiSecurity]["psk"]; ok {
					f.secrets[p][wifiSecurity] = map[string]dbus.Variant{"psk": psk}
				}
				return nil, nil
			}},
		})
	}
	props := map[dbus.ObjectPath]map[string]map[string]dbus.Variant{
		"/d/1": {
			ifaceDevice: {"HwAddress": dbus.MakeVariant("AA:BB:CC:00:11:22"), "DeviceType": dbus.MakeVariant(uint32(deviceEthernet)), "Ip4Config": dbus.MakeVariant(dbus.ObjectPath("/ip4/1")), "Ip6Config": dbus.MakeVariant(dbus.ObjectPath("/ip6/1"))},
			ifaceWired:  {"Speed": dbus.MakeVariant(uint32(1000))},
		},
		"/d/2": {
			ifaceDevice:   {"HwAddress": dbus.MakeVariant("AA:BB:CC:33:44:55"), "DeviceType": dbus.MakeVariant(uint32(deviceWifi)), "Ip4Config": dbus.MakeVariant(noObject), "Ip6Config": dbus.MakeVariant(noObject)},
			ifaceWireless: {"Bitrate": dbus.MakeVariant(uint32(866700)), "ActiveAccessPoint": dbus.MakeVariant(dbus.ObjectPath("/ap/1"))},
		},
		"/ap/1": {ifaceAP: {"Frequency": dbus.MakeVariant(uint32(5180))}},
		"/ip4/1": {ifaceIP4Config: {
			"AddressData":    {Sig: "aa{sv}", Value: []map[string]dbus.Variant{{"address": dbus.MakeVariant("192.168.1.5"), "prefix": dbus.MakeVariant(uint32(24))}}},
			"Gateway":        dbus.MakeVariant("192.168.1.1"),
			"NameserverData": {Sig: "aa{sv}", Value: []map[string]dbus.Variant{{"address": dbus.MakeVariant("1.1.1.1")}, {"address": dbus.MakeVariant("9.9.9.9")}}},
		}},
		"/ip6/1": {ifaceIP6Config: {
			"AddressData": {Sig: "aa{sv}", Value: []map[string]dbus.Variant{{"address": dbus.MakeVariant("fe80::1"), "prefix": dbus.MakeVariant(uint32(64))}, {"address": dbus.MakeVariant("2001:db8::5"), "prefix": dbus.MakeVariant(uint32(64))}}},
		}},
	}
	propMethods := map[string]dbus.Method{
		"Get": {In: "ss", Out: "v", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			v, ok := props[m.Path][m.Body[0].(string)][m.Body[1].(string)]
			if !ok {
				return nil, dbus.NewError(dbus.ErrInvalidArgs, "no such property")
			}
			return []any{v}, nil
		}},
		"GetAll": {In: "s", Out: "a{sv}", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			p, ok := props[m.Path][m.Body[0].(string)]
			if !ok {
				return nil, dbus.NewError(dbus.ErrUnknownObject, "no such object")
			}
			return []any{p}, nil
		}},
	}
	for p := range props {
		export(p, "org.freedesktop.DBus.Properties", propMethods)
	}
	if _, err := conn.RequestName(ctx, busName, dbus.NameDoNotQueue); err != nil {
		t.Fatal(err)
	}
	return New(Options{SystemBus: func(ctx context.Context) (*dbus.Conn, error) {
		return dbus.Dial(ctx, bus.Address, dbus.Options{})
	}}), f
}

// decoded is an a{sa{sv}} argument as the fake keeps it.
func decoded(v any) settings {
	out := settings{}
	all, _ := v.(map[any]any)
	for k, s := range all {
		out[k.(string)] = s.(map[string]dbus.Variant)
	}
	return out
}

func TestDetails(t *testing.T) {
	t.Parallel()
	svc := newFakeNM(t)
	ctx := context.Background()
	got, err := svc.Details(ctx, "enp1s0")
	if err != nil {
		t.Fatal(err)
	}
	want := Details{Device: "enp1s0", Kind: "ethernet", MAC: "AA:BB:CC:00:11:22", IPv4: "192.168.1.5/24", IPv6: "2001:db8::5/64", Gateway: "192.168.1.1", DNS: []string{"1.1.1.1", "9.9.9.9"}, Speed: 1000}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("wired\n got %+v\nwant %+v", got, want)
	}
	got, err = svc.Details(ctx, "wlan0")
	if err != nil {
		t.Fatal(err)
	}
	want = Details{Device: "wlan0", Kind: "wifi", MAC: "AA:BB:CC:33:44:55", DNS: []string{}, Bitrate: 866, Frequency: 5180, Band: "5", Channel: 36}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("wifi\n got %+v\nwant %+v", got, want)
	}
	if _, err := svc.Details(ctx, "nope0"); axerr.KindOf(err) != axerr.NotFound {
		t.Errorf("a missing device: %v", err)
	}
}

func TestSavedWifiAndAutoconnect(t *testing.T) {
	t.Parallel()
	svc, f := startFake(t)
	ctx := context.Background()
	saved, err := svc.SavedWifi(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if want := []SavedNetwork{{SSID: "Home", UUID: "home", Autoconnect: true}}; !reflect.DeepEqual(saved, want) {
		t.Fatalf("saved %+v", saved)
	}
	if err := svc.SetAutoconnect(ctx, "home", false); err != nil {
		t.Fatal(err)
	}
	f.mu.Lock()
	p, sec := f.profiles["/c/1"], f.secrets["/c/1"]
	f.mu.Unlock()
	if p["connection"]["autoconnect"].Value != false {
		t.Errorf("autoconnect still on: %+v", p["connection"])
	}
	if sec[wifiSecurity]["psk"].Value != "hunter22" {
		t.Errorf("the update dropped the password: %+v", sec)
	}
	if err := svc.SetAutoconnect(ctx, "nope", true); axerr.KindOf(err) != axerr.NotFound {
		t.Errorf("an unknown profile: %v", err)
	}
}

func TestJoin(t *testing.T) {
	t.Parallel()
	svc, f := startFake(t)
	ctx := context.Background()
	// A new network is added and activated
	if err := svc.Join(ctx, JoinRequest{SSID: "Office", Security: "eap", EAP: "peap", Identity: "me", Password: "pw", SystemCA: true}); err != nil {
		t.Fatal(err)
	}
	// A saved one is updated in place, keeping its uuid, and activated
	if err := svc.Join(ctx, JoinRequest{Device: "wlan0", SSID: "Home", Security: "psk", Password: "correct horse"}); err != nil {
		t.Fatal(err)
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(f.added) != 1 || f.added[0][eapSetting]["identity"].Value != "me" || f.added[0][wifiSecurity]["key-mgmt"].Value != "wpa-eap" {
		t.Errorf("added %+v", f.added)
	}
	if p := f.profiles["/c/1"]; p["connection"]["uuid"].Value != "home" || p[wifiSecurity]["psk"].Value != "correct horse" {
		t.Errorf("updated %+v", p)
	}
	// The rest of the saved profile (its addresses) stays
	if p := f.profiles["/c/1"]; p["ipv4"]["method"].Value != "manual" {
		t.Errorf("the update dropped the profile's other settings: %+v", p)
	}
	if !reflect.DeepEqual(f.activated, []dbus.ObjectPath{"/c/1"}) {
		t.Errorf("activated %v", f.activated)
	}
}

func TestWifiSettings(t *testing.T) {
	t.Parallel()
	str := func(s settings, sec, key string) any { return s[sec][key].Value }
	cases := []struct {
		name  string
		req   JoinRequest
		check func(settings) bool
		bad   bool
	}{
		{"open", JoinRequest{SSID: "Cafe"}, func(s settings) bool { return s[wifiSecurity] == nil && s[wifiType]["security"].Value == nil }, false},
		{"hidden", JoinRequest{SSID: "Secret", Hidden: true, Security: "open"}, func(s settings) bool { return str(s, wifiType, "hidden") == true }, false},
		{"psk", JoinRequest{SSID: "A", Security: "psk", Password: "12345678"}, func(s settings) bool {
			return str(s, wifiSecurity, "key-mgmt") == "wpa-psk" && str(s, wifiSecurity, "psk") == "12345678" && str(s, wifiType, "security") == wifiSecurity
		}, false},
		{"psk short", JoinRequest{SSID: "A", Security: "psk", Password: "1234567"}, nil, true},
		{"psk hex", JoinRequest{SSID: "A", Security: "psk", Password: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"}, func(s settings) bool { return true }, false},
		{"psk 64 not hex", JoinRequest{SSID: "A", Security: "psk", Password: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdeg"}, nil, true},
		{"wep key", JoinRequest{SSID: "A", Security: "wep", Password: "0123456789"}, func(s settings) bool {
			return str(s, wifiSecurity, "key-mgmt") == "none" && str(s, wifiSecurity, "wep-key-type") == uint32(1)
		}, false},
		{"wep passphrase", JoinRequest{SSID: "A", Security: "wep", Password: "a longer passphrase"}, func(s settings) bool { return str(s, wifiSecurity, "wep-key-type") == uint32(2) }, false},
		{"wep empty", JoinRequest{SSID: "A", Security: "wep"}, nil, true},
		{"peap", JoinRequest{SSID: "Uni", Security: "eap", EAP: "peap", Identity: "me", Password: "pw", AnonymousIdentity: "anon", CACert: "/etc/ca.pem"}, func(s settings) bool {
			return reflect.DeepEqual(str(s, eapSetting, "eap"), []string{"peap"}) && str(s, eapSetting, "phase2-auth") == "mschapv2" &&
				str(s, eapSetting, "anonymous-identity") == "anon" && string(str(s, eapSetting, "ca-cert").([]byte)) == "file:///etc/ca.pem\x00" &&
				str(s, wifiSecurity, "key-mgmt") == "wpa-eap"
		}, false},
		{"ttls system CA", JoinRequest{SSID: "Uni", Security: "eap", EAP: "ttls", Phase2: "pap", Identity: "me", SystemCA: true}, func(s settings) bool {
			return str(s, eapSetting, "system-ca-certs") == true && str(s, eapSetting, "phase2-auth") == "pap" && s[eapSetting]["ca-cert"].Value == nil
		}, false},
		{"dynamic wep", JoinRequest{SSID: "Old", Security: "dynamic-wep", EAP: "peap", Identity: "me"}, func(s settings) bool { return str(s, wifiSecurity, "key-mgmt") == "ieee8021x" }, false},
		{"leap", JoinRequest{SSID: "Old", Security: "leap", Identity: "me", Password: "pw"}, func(s settings) bool {
			return str(s, wifiSecurity, "auth-alg") == "leap" && str(s, wifiSecurity, "leap-username") == "me"
		}, false},
		{"eap tls", JoinRequest{SSID: "Uni", Security: "eap", EAP: "tls", Identity: "me"}, nil, true},
		{"eap bad phase2", JoinRequest{SSID: "Uni", Security: "eap", EAP: "peap", Phase2: "md5", Identity: "me"}, nil, true},
		{"eap no identity", JoinRequest{SSID: "Uni", Security: "eap", EAP: "peap"}, nil, true},
		{"relative CA", JoinRequest{SSID: "Uni", Security: "eap", EAP: "peap", Identity: "me", CACert: "ca.pem"}, nil, true},
		{"no ssid", JoinRequest{Security: "open"}, nil, true},
		{"long ssid", JoinRequest{SSID: "0123456789012345678901234567890123"}, nil, true},
		{"unknown security", JoinRequest{SSID: "A", Security: "wpa4"}, nil, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got, err := wifiSettings(tc.req)
			if tc.bad {
				if axerr.KindOf(err) != axerr.BadRequest {
					t.Errorf("want a bad request, got %v", err)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if string(got[wifiType]["ssid"].Value.([]byte)) != tc.req.SSID || got["connection"]["type"].Value != wifiType {
				t.Errorf("profile %+v", got)
			}
			if !tc.check(got) {
				t.Errorf("settings %+v", got)
			}
		})
	}
}

func TestBand(t *testing.T) {
	t.Parallel()
	cases := []struct {
		mhz     int
		band    string
		channel int
	}{
		{2412, "2.4", 1}, {2462, "2.4", 11}, {2484, "2.4", 14},
		{5180, "5", 36}, {5825, "5", 165},
		{5955, "6", 1}, {6115, "6", 33},
		{0, "", 0}, {900, "", 0},
	}
	for _, tc := range cases {
		if b, c := band(tc.mhz); b != tc.band || c != tc.channel {
			t.Errorf("%d MHz: %s %d, want %s %d", tc.mhz, b, c, tc.band, tc.channel)
		}
	}
}
