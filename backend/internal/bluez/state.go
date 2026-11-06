package bluez

import (
	"os"
	"path"
	"path/filepath"
	"slices"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/dbus"
)

// State is what the shell shows (BluetoothManager). Devices is never
// null.
type State struct {
	// Available: BlueZ runs and has an adapter
	Available bool `json:"available"`
	// Adapter is the default adapter, null when there's none
	Adapter *Adapter `json:"adapter"`
	// Devices are the default adapter's, in the order they turned up
	// (those there at a sync by their path)
	Devices []Device `json:"devices"`
}

// Adapter is the default adapter: the first by its path (hci0 before
// hci1), as Quickshell.Bluetooth's defaultAdapter was the first it knew.
type Adapter struct {
	Address string `json:"address"`
	// Name is its alias (what other devices see), else its system name
	Name    string `json:"name"`
	Powered bool   `json:"powered"`
	// Blocked: rfkill blocks it (PowerState "off-blocked", else
	// /sys/class/rfkill); HardBlocked: a hardware switch does, which
	// bluetooth.unblock can't clear (read from /sys/class/rfkill)
	Blocked      bool `json:"blocked"`
	HardBlocked  bool `json:"hardBlocked"`
	Discovering  bool `json:"discovering"`
	Discoverable bool `json:"discoverable"`
	// DiscoverableTimeout is BlueZ's, in seconds (0: discoverable until
	// turned off); DiscoverableUntil when it ends, in Unix ms, while
	// discoverable with a timeout the daemon saw start (else 0)
	DiscoverableTimeout uint32 `json:"discoverableTimeout"`
	DiscoverableUntil   int64  `json:"discoverableUntil"`
	Pairable            bool   `json:"pairable"`
}

// Device is one device the adapter knows: paired, or seen by a scan.
type Device struct {
	Address string `json:"address"`
	// Name is its alias (the device's own name unless renamed, else its
	// address); DeviceName the name it gives itself, "" when it gave none
	Name       string `json:"name"`
	DeviceName string `json:"deviceName"`
	// Icon is BlueZ's freedesktop icon name ("audio-headset"), "" none
	Icon      string `json:"icon"`
	Paired    bool   `json:"paired"`
	Bonded    bool   `json:"bonded"`
	Trusted   bool   `json:"trusted"`
	Blocked   bool   `json:"blocked"`
	Connected bool   `json:"connected"`
	// State is "connecting", "connected", "disconnecting" or
	// "disconnected": BlueZ has no connecting, so the transitional ones
	// come from the daemon's own calls in flight
	State string `json:"state"`
	// Pairing: a pair asked of the daemon is running
	Pairing bool `json:"pairing"`
	// Battery is its level, 0–100, or -1 when it reports none
	Battery int `json:"battery"`
}

// BlueZ's names
const (
	busName  = "org.bluez"
	rootPath = dbus.ObjectPath("/")

	ifaceAdapter = "org.bluez.Adapter1"
	ifaceDevice  = "org.bluez.Device1"
	ifaceBattery = "org.bluez.Battery1"
)

// What a call in flight is doing to a device
const (
	opConnecting    = "connecting"
	opDisconnecting = "disconnecting"
	opPairing       = "pairing"
)

type props map[string]dbus.Variant

func (p props) str(k string) string {
	switch v := p[k].Value.(type) {
	case string:
		return v
	case dbus.ObjectPath:
		return string(v)
	}
	return ""
}

func (p props) bool(k string) bool {
	b, _ := p[k].Value.(bool)
	return b
}

func (p props) uint32(k string) uint32 {
	n, _ := p[k].Value.(uint32)
	return n
}

// percentage reads Battery1.Percentage (y), -1 when missing.
func (p props) percentage() int {
	switch n := p["Percentage"].Value.(type) {
	case uint8:
		return int(n)
	}
	return -1
}

// defaultAdapter is the first adapter's path by name, "" none.
func defaultAdapter(objs dbus.ManagedObjects) dbus.ObjectPath {
	var paths []dbus.ObjectPath
	for p, i := range objs {
		if _, ok := i[ifaceAdapter]; ok {
			paths = append(paths, p)
		}
	}
	if len(paths) == 0 {
		return ""
	}
	return slices.Min(paths)
}

// build makes the state from BlueZ's objects: the default adapter and
// its devices, ordered by order (their arrival), with the calls in
// flight (ops, by address) and rfkill (read from the folder rfkill,
// "" none) for an adapter whose PowerState doesn't say.
func build(objs dbus.ManagedObjects, order map[dbus.ObjectPath]uint64, ops map[string]string, rfkill string) State {
	st := State{Devices: []Device{}}
	ap := defaultAdapter(objs)
	if ap == "" {
		return st
	}
	a := props(objs[ap][ifaceAdapter])
	name := a.str("Alias")
	if name == "" {
		name = a.str("Name")
	}
	blocked := a.str("PowerState") == "off-blocked"
	var hard bool
	if rfkill != "" && !a.bool("Powered") {
		soft, h := rfkillBlocked(rfkill, path.Base(string(ap)))
		blocked, hard = blocked || soft || h, h
	}
	st.Available = true
	st.Adapter = &Adapter{
		Address: a.str("Address"), Name: name, Powered: a.bool("Powered"), Blocked: blocked, HardBlocked: hard,
		Discovering: a.bool("Discovering"), Discoverable: a.bool("Discoverable"),
		DiscoverableTimeout: a.uint32("DiscoverableTimeout"), Pairable: a.bool("Pairable"),
	}
	var paths []dbus.ObjectPath
	for p, i := range objs {
		if d, ok := i[ifaceDevice]; ok && props(d).str("Adapter") == string(ap) {
			paths = append(paths, p)
		}
	}
	slices.SortFunc(paths, func(x, y dbus.ObjectPath) int {
		if ox, oy := order[x], order[y]; ox != oy {
			if ox < oy {
				return -1
			}
			return 1
		}
		return strings.Compare(string(x), string(y))
	})
	for _, p := range paths {
		d := props(objs[p][ifaceDevice])
		dev := Device{
			Address: d.str("Address"), Name: d.str("Alias"), DeviceName: d.str("Name"), Icon: d.str("Icon"),
			Paired: d.bool("Paired"), Bonded: d.bool("Bonded"), Trusted: d.bool("Trusted"), Blocked: d.bool("Blocked"),
			Connected: d.bool("Connected"), Battery: -1,
		}
		if b, ok := objs[p][ifaceBattery]; ok {
			dev.Battery = props(b).percentage()
		}
		dev.State = "disconnected"
		if dev.Connected {
			dev.State = "connected"
		}
		switch ops[dev.Address] {
		case opConnecting, opDisconnecting:
			dev.State = ops[dev.Address]
		case opPairing:
			dev.Pairing = true
		}
		st.Devices = append(st.Devices, dev)
	}
	return st
}

// rfkillBlocked: an rfkill switch of the adapter (its name hci0) is on,
// soft (software: bluetooth.unblock clears it) or hard (a switch).
func rfkillBlocked(dir, adapter string) (soft, hard bool) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return false, false
	}
	read := func(sw, file string) string {
		b, _ := os.ReadFile(filepath.Join(dir, sw, file))
		return strings.TrimSpace(string(b))
	}
	for _, e := range entries {
		if read(e.Name(), "type") != "bluetooth" || read(e.Name(), "name") != adapter {
			continue
		}
		soft = soft || read(e.Name(), "soft") == "1"
		hard = hard || read(e.Name(), "hard") == "1"
	}
	return soft, hard
}
