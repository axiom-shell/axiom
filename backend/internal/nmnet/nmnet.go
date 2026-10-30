// Package nmnet is what the shell asks NetworkManager about its network
// devices and Wi-Fi profiles beyond what Quickshell.Networking shows
// (NetworkingManager): a device's addresses, gateway, DNS, link speed and
// band; joining a network that needs more than a password (hidden,
// WEP, enterprise); and the saved networks' autoconnect. Each call dials
// the system bus anew: they're rare, and nothing here is followed.
package nmnet

import (
	"context"
	"log/slog"
	"strconv"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
)

// NetworkManager's names
const (
	busName        = "org.freedesktop.NetworkManager"
	managerPath    = dbus.ObjectPath("/org/freedesktop/NetworkManager")
	settingsPath   = dbus.ObjectPath("/org/freedesktop/NetworkManager/Settings")
	ifaceManager   = "org.freedesktop.NetworkManager"
	ifaceSettings  = "org.freedesktop.NetworkManager.Settings"
	ifaceConn      = "org.freedesktop.NetworkManager.Settings.Connection"
	ifaceDevice    = "org.freedesktop.NetworkManager.Device"
	ifaceWired     = "org.freedesktop.NetworkManager.Device.Wired"
	ifaceWireless  = "org.freedesktop.NetworkManager.Device.Wireless"
	ifaceAP        = "org.freedesktop.NetworkManager.AccessPoint"
	ifaceIP4Config = "org.freedesktop.NetworkManager.IP4Config"
	ifaceIP6Config = "org.freedesktop.NetworkManager.IP6Config"
	wifiType       = "802-11-wireless"
	wifiSecurity   = "802-11-wireless-security"
	eapSetting     = "802-1x"
	deviceEthernet = 1
	deviceWifi     = 2
	noObject       = dbus.ObjectPath("/")
)

// Options are what a Service needs.
type Options struct {
	// SystemBus connects to the system bus (a new connection each call)
	SystemBus func(ctx context.Context) (*dbus.Conn, error)
	Log       *slog.Logger
}

// Service answers the shell's questions to NetworkManager.
type Service struct {
	o Options
}

// New makes a Service.
func New(o Options) *Service {
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	return &Service{o: o}
}

func (s *Service) dial(ctx context.Context) (*dbus.Conn, error) {
	conn, err := s.o.SystemBus(ctx)
	if err != nil {
		return nil, axerr.Wrap(axerr.Unavailable, err, "the system bus isn't reachable")
	}
	return conn, nil
}

// Details is one device's connection, as the Wi-Fi menu's details show it.
// Unknown values are empty or 0; lists are never null.
type Details struct {
	Device string `json:"device"`
	// Kind is "wifi", "ethernet" or "" (another kind of device)
	Kind string `json:"kind"`
	MAC  string `json:"mac"`
	// IPv4 with its prefix ("192.168.1.5/24"), and IPv6's first global
	// address the same way
	IPv4    string   `json:"ipv4"`
	IPv6    string   `json:"ipv6"`
	Gateway string   `json:"gateway"`
	DNS     []string `json:"dns"`
	// Speed is a wire's link speed, Bitrate Wi-Fi's (both Mb/s)
	Speed   int `json:"speed"`
	Bitrate int `json:"bitrate"`
	// Frequency (MHz) of the access point, its band ("2.4", "5", "6"
	// GHz) and channel
	Frequency int    `json:"frequency"`
	Band      string `json:"band"`
	Channel   int    `json:"channel"`
}

// Details reads the device named iface (its interface name).
func (s *Service) Details(ctx context.Context, iface string) (Details, error) {
	conn, err := s.dial(ctx)
	if err != nil {
		return Details{}, err
	}
	defer conn.Close()
	dev, err := deviceByIface(ctx, conn, iface)
	if err != nil {
		return Details{}, err
	}
	props, err := conn.GetAll(ctx, busName, dev, ifaceDevice)
	if err != nil {
		return Details{}, axerr.Wrap(axerr.NotFound, err, "no device %s", iface)
	}
	d := Details{Device: iface, DNS: []string{}}
	d.MAC, _ = props["HwAddress"].Value.(string)
	switch t, _ := props["DeviceType"].Value.(uint32); t {
	case deviceEthernet:
		d.Kind = "ethernet"
		if v, err := conn.GetProperty(ctx, busName, dev, ifaceWired, "Speed"); err == nil {
			speed, _ := v.Value.(uint32)
			d.Speed = int(speed)
		}
	case deviceWifi:
		d.Kind = "wifi"
		if w, err := conn.GetAll(ctx, busName, dev, ifaceWireless); err == nil {
			rate, _ := w["Bitrate"].Value.(uint32) // Kb/s
			d.Bitrate = int(rate / 1000)
			if ap, ok := w["ActiveAccessPoint"].Value.(dbus.ObjectPath); ok && ap != noObject {
				if v, err := conn.GetProperty(ctx, busName, ap, ifaceAP, "Frequency"); err == nil {
					f, _ := v.Value.(uint32)
					d.Frequency = int(f)
					d.Band, d.Channel = band(d.Frequency)
				}
			}
		}
	}
	if p, ok := props["Ip4Config"].Value.(dbus.ObjectPath); ok && p != noObject {
		if c, err := conn.GetAll(ctx, busName, p, ifaceIP4Config); err == nil {
			d.IPv4 = firstAddress(c["AddressData"].Value, false)
			d.Gateway, _ = c["Gateway"].Value.(string)
			for _, e := range dicts(c["NameserverData"].Value) {
				if a, ok := e["address"].Value.(string); ok {
					d.DNS = append(d.DNS, a)
				}
			}
		}
	}
	if p, ok := props["Ip6Config"].Value.(dbus.ObjectPath); ok && p != noObject {
		if c, err := conn.GetAll(ctx, busName, p, ifaceIP6Config); err == nil {
			d.IPv6 = firstAddress(c["AddressData"].Value, true)
		}
	}
	return d, nil
}

func deviceByIface(ctx context.Context, conn *dbus.Conn, iface string) (dbus.ObjectPath, error) {
	if iface == "" {
		return "", axerr.New(axerr.BadRequest, "no device named")
	}
	m, err := conn.Call(ctx, busName, managerPath, ifaceManager, "GetDeviceByIpIface", "s", iface)
	var dev dbus.ObjectPath
	if err == nil {
		err = m.Store(&dev)
	}
	if err != nil {
		return "", axerr.Wrap(axerr.NotFound, err, "no device %s", iface)
	}
	return dev, nil
}

// firstWifi is the first Wi-Fi device NetworkManager has.
func firstWifi(ctx context.Context, conn *dbus.Conn) (dbus.ObjectPath, error) {
	m, err := conn.Call(ctx, busName, managerPath, ifaceManager, "GetDevices", "")
	var devs []dbus.ObjectPath
	if err == nil {
		err = m.Store(&devs)
	}
	if err != nil {
		return "", axerr.Wrap(axerr.Unavailable, err, "NetworkManager isn't running")
	}
	for _, dev := range devs {
		if v, err := conn.GetProperty(ctx, busName, dev, ifaceDevice, "DeviceType"); err == nil && v.Value == uint32(deviceWifi) {
			return dev, nil
		}
	}
	return "", axerr.New(axerr.NotFound, "no Wi-Fi device")
}

// dicts is an aa{sv} as decoded.
func dicts(v any) []map[string]dbus.Variant {
	list, _ := v.([]any)
	out := make([]map[string]dbus.Variant, 0, len(list))
	for _, e := range list {
		if d, ok := e.(map[string]dbus.Variant); ok {
			out = append(out, d)
		}
	}
	return out
}

// firstAddress is an AddressData's first address with its prefix; with
// global, the first that isn't link-local (fe80::).
func firstAddress(data any, global bool) string {
	for _, d := range dicts(data) {
		a, _ := d["address"].Value.(string)
		if a == "" || global && strings.HasPrefix(strings.ToLower(a), "fe80:") {
			continue
		}
		if p, ok := d["prefix"].Value.(uint32); ok {
			return a + "/" + strconv.Itoa(int(p))
		}
		return a
	}
	return ""
}

// band is the band (GHz) and channel of a frequency (MHz), "" and 0 for
// one outside Wi-Fi's.
func band(mhz int) (string, int) {
	switch {
	case mhz == 2484:
		return "2.4", 14
	case mhz >= 2412 && mhz < 2484:
		return "2.4", (mhz - 2407) / 5
	case mhz >= 5160 && mhz <= 5885:
		return "5", (mhz - 5000) / 5
	case mhz >= 5955 && mhz <= 7115:
		return "6", (mhz - 5950) / 5
	}
	return "", 0
}

// SavedNetwork is a saved Wi-Fi profile.
type SavedNetwork struct {
	SSID        string `json:"ssid"`
	UUID        string `json:"uuid"`
	Autoconnect bool   `json:"autoconnect"`
}

// SavedWifi lists the saved Wi-Fi profiles. A list, never null.
func (s *Service) SavedWifi(ctx context.Context) ([]SavedNetwork, error) {
	conn, err := s.dial(ctx)
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	out := []SavedNetwork{}
	for _, p := range wifiProfiles(ctx, conn) {
		out = append(out, p.SavedNetwork)
	}
	return out, nil
}

type wifiProfile struct {
	SavedNetwork
	path     dbus.ObjectPath
	settings map[string]map[string]dbus.Variant
}

func wifiProfiles(ctx context.Context, conn *dbus.Conn) []wifiProfile {
	m, err := conn.Call(ctx, busName, settingsPath, ifaceSettings, "ListConnections", "")
	var paths []dbus.ObjectPath
	if err == nil {
		err = m.Store(&paths)
	}
	if err != nil {
		return nil
	}
	var out []wifiProfile
	for _, p := range paths {
		settings, err := getSettings(ctx, conn, p)
		if err != nil {
			continue
		}
		c := settings["connection"]
		if c["type"].Value != wifiType {
			continue
		}
		ssid, _ := settings[wifiType]["ssid"].Value.([]byte)
		pr := wifiProfile{path: p, settings: settings, SavedNetwork: SavedNetwork{SSID: string(ssid), Autoconnect: true}}
		pr.UUID, _ = c["uuid"].Value.(string)
		if a, ok := c["autoconnect"].Value.(bool); ok {
			pr.Autoconnect = a
		}
		out = append(out, pr)
	}
	return out
}

// getSettings reads a profile's settings (a{sa{sv}}), or its secrets for
// one setting with secrets set.
func getSettings(ctx context.Context, conn *dbus.Conn, path dbus.ObjectPath, secrets ...string) (map[string]map[string]dbus.Variant, error) {
	var m *dbus.Message
	var err error
	if len(secrets) > 0 {
		m, err = conn.Call(ctx, busName, path, ifaceConn, "GetSecrets", "s", secrets[0])
	} else {
		m, err = conn.Call(ctx, busName, path, ifaceConn, "GetSettings", "")
	}
	if err != nil {
		return nil, err
	}
	var raw any
	if err := m.Store(&raw); err != nil {
		return nil, err
	}
	all, _ := raw.(map[any]any)
	out := map[string]map[string]dbus.Variant{}
	for k, v := range all {
		name, _ := k.(string)
		if sec, ok := v.(map[string]dbus.Variant); ok && name != "" {
			out[name] = sec
		}
	}
	return out, nil
}

// SetAutoconnect turns the saved profile uuid's autoconnect on or off,
// keeping its secrets (read back and sent with the update, as nmcli does:
// an update without them would drop those NetworkManager keeps).
func (s *Service) SetAutoconnect(ctx context.Context, uuid string, on bool) error {
	conn, err := s.dial(ctx)
	if err != nil {
		return err
	}
	defer conn.Close()
	m, err := conn.Call(ctx, busName, settingsPath, ifaceSettings, "GetConnectionByUuid", "s", uuid)
	var path dbus.ObjectPath
	if err == nil {
		err = m.Store(&path)
	}
	if err != nil {
		return axerr.Wrap(axerr.NotFound, err, "no saved network %s", uuid)
	}
	settings, err := getSettings(ctx, conn, path)
	if err != nil {
		return axerr.Wrap(axerr.NotFound, err, "no saved network %s", uuid)
	}
	keepSecrets(ctx, conn, path, settings)
	settings["connection"]["autoconnect"] = dbus.MakeVariant(on)
	if _, err := conn.Call(ctx, busName, path, ifaceConn, "Update", "a{sa{sv}}", settings); err != nil {
		return axerr.Wrap(axerr.Refused, err, "NetworkManager refused the change")
	}
	return nil
}

// keepSecrets merges the profile's secrets into settings (those it has:
// an open network has none, which isn't an error).
func keepSecrets(ctx context.Context, conn *dbus.Conn, path dbus.ObjectPath, settings map[string]map[string]dbus.Variant) {
	for _, name := range []string{wifiSecurity, eapSetting} {
		if settings[name] == nil {
			continue
		}
		secrets, err := getSettings(ctx, conn, path, name)
		if err != nil {
			continue
		}
		for k, v := range secrets[name] {
			settings[name][k] = v
		}
	}
}
