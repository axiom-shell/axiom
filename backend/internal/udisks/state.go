package udisks

import (
	"path/filepath"
	"slices"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/dbus"
)

// State is what the shell shows (DrivesManager). Lists are never null.
type State struct {
	// Available: UDisks2 is on the system bus
	Available bool    `json:"available"`
	Drives    []Drive `json:"drives"`
}

// Drive is one removable drive with media in it.
type Drive struct {
	// ID is its UDisks2 Drive object (a loop device's Block object)
	ID     string `json:"id"`
	Vendor string `json:"vendor"`
	Model  string `json:"model"`
	// Label is its first volume's label, else its model, else its vendor
	Label string `json:"label"`
	Size  int64  `json:"size"`
	// Bus is how it's connected: "usb", "sdio", "ieee1394", "loop", "" …
	Bus         string   `json:"bus"`
	Optical     bool     `json:"optical"`
	Removable   bool     `json:"removable"`
	CanEject    bool     `json:"canEject"`
	CanPowerOff bool     `json:"canPowerOff"`
	Volumes     []Volume `json:"volumes"`

	// What Eject does last: eject the media, or delete the loop device
	mediaRemovable, loop bool
}

// Volume is a filesystem or encrypted container on a drive.
type Volume struct {
	// ID is its Block object
	ID string `json:"id"`
	// Device is its device file (/dev/sdb1)
	Device string `json:"device"`
	Label  string `json:"label"`
	UUID   string `json:"uuid"`
	// FSType is the filesystem (an unlocked LUKS volume's cleartext's)
	FSType string `json:"fsType"`
	Size   int64  `json:"size"`
	// MountPoints are where it's mounted (an unlocked LUKS volume's
	// cleartext's)
	MountPoints []string `json:"mountPoints"`
	ReadOnly    bool     `json:"readOnly"`
	Encrypted   bool     `json:"encrypted"`
	Unlocked    bool     `json:"unlocked"`
	// CleartextID is an unlocked LUKS volume's cleartext Block object
	CleartextID string `json:"cleartextId"`
	// Mountable: it has a filesystem (itself, or its cleartext)
	Mountable bool `json:"mountable"`
}

// UDisks2's interfaces
const (
	ifaceDrive     = "org.freedesktop.UDisks2.Drive"
	ifaceBlock     = "org.freedesktop.UDisks2.Block"
	ifacePartition = "org.freedesktop.UDisks2.Partition"
	ifaceFS        = "org.freedesktop.UDisks2.Filesystem"
	ifaceEncrypted = "org.freedesktop.UDisks2.Encrypted"
	ifaceLoop      = "org.freedesktop.UDisks2.Loop"
	ifaceSwap      = "org.freedesktop.UDisks2.Swapspace"
)

type props map[string]dbus.Variant

func (p props) str(k string) string {
	switch v := p[k].Value.(type) {
	case string:
		return strings.TrimSpace(v)
	case dbus.ObjectPath:
		return string(v)
	}
	return ""
}

func (p props) path(k string) string {
	if s := p.str(k); s != "/" {
		return s
	}
	return ""
}

func (p props) bool(k string) bool {
	b, _ := p[k].Value.(bool)
	return b
}

func (p props) size(k string) int64 {
	n, _ := p[k].Value.(uint64)
	return int64(min(n, 1<<63-1))
}

// bytes reads an ay holding a NUL-terminated string.
func bytestring(v any) string {
	b, _ := v.([]byte)
	return strings.TrimRight(string(b), "\x00")
}

func (p props) bytes(k string) string { return bytestring(p[k].Value) }

// mountPoints reads Filesystem.MountPoints (aay).
func (p props) mountPoints() []string {
	out := []string{}
	switch v := p["MountPoints"].Value.(type) {
	case []any:
		for _, b := range v {
			if s := bytestring(b); s != "" {
				out = append(out, s)
			}
		}
	case [][]byte:
		for _, b := range v {
			if s := bytestring(b); s != "" {
				out = append(out, s)
			}
		}
	}
	return out
}

// build is the drives the shell is shown among UDisks2's objects: those
// removable, on USB or an SD slot, with media in, and their volumes;
// with includeLoop, loop devices backed by a file too.
func build(objs dbus.ManagedObjects, includeLoop bool) []Drive {
	// Blocks by the drive they belong to, and cleartexts by their
	// encrypted container
	byDrive := map[string][]dbus.ObjectPath{}
	byTable := map[string][]dbus.ObjectPath{}
	cleartext := map[string]dbus.ObjectPath{}
	for path, ifaces := range objs {
		b := props(ifaces[ifaceBlock])
		if b == nil {
			continue
		}
		if backing := b.path("CryptoBackingDevice"); backing != "" {
			cleartext[backing] = path
			continue
		}
		if d := b.path("Drive"); d != "" {
			byDrive[d] = append(byDrive[d], path)
		}
		if t := props(ifaces[ifacePartition]).path("Table"); t != "" {
			byTable[t] = append(byTable[t], path)
		}
	}

	drives := []Drive{}
	for path, ifaces := range objs {
		if d, ok := ifaces[ifaceDrive]; ok {
			p := props(d)
			if !p.bool("Removable") && !p.bool("MediaRemovable") && p.str("ConnectionBus") != "usb" && p.str("ConnectionBus") != "sdio" {
				continue
			}
			// An empty card reader or optical drive: nothing to show
			if p.bool("MediaRemovable") && !p.bool("MediaAvailable") {
				continue
			}
			blocks := byDrive[string(path)]
			if slices.ContainsFunc(blocks, func(b dbus.ObjectPath) bool {
				_, part := objs[b][ifacePartition]
				return !part && hinted(props(objs[b][ifaceBlock]), true)
			}) {
				continue
			}
			drive := Drive{
				ID: string(path), Vendor: p.str("Vendor"), Model: p.str("Model"), Size: p.size("Size"),
				Bus: p.str("ConnectionBus"), Optical: p.bool("Optical"), Removable: p.bool("Removable"),
				CanEject: p.bool("Ejectable"), CanPowerOff: p.bool("CanPowerOff"), mediaRemovable: p.bool("MediaRemovable"),
			}
			drive.Volumes = volumes(objs, blocks, cleartext, true)
			drives = append(drives, labelled(drive))
			continue
		}
		loop, ok := ifaces[ifaceLoop]
		if !ok || !includeLoop {
			continue
		}
		b := props(ifaces[ifaceBlock])
		backing := props(loop).bytes("BackingFile")
		if b == nil || backing == "" || b.path("Drive") != "" || b.path("CryptoBackingDevice") != "" || hinted(b, false) {
			continue
		}
		drive := Drive{ID: string(path), Model: filepath.Base(backing), Size: b.size("Size"), Bus: "loop", Removable: true, loop: true}
		drive.Volumes = volumes(objs, append([]dbus.ObjectPath{path}, byTable[string(path)]...), cleartext, false)
		drives = append(drives, labelled(drive))
	}
	slices.SortFunc(drives, func(a, b Drive) int { return strings.Compare(a.ID, b.ID) })
	return drives
}

// hinted: UDisks2 says the block is the system's or not to be shown.
// A loop device set up for the fixtures may be a system one: only
// HintIgnore counts for them.
func hinted(b props, system bool) bool {
	return b.bool("HintIgnore") || system && b.bool("HintSystem")
}

func labelled(d Drive) Drive {
	for _, v := range d.Volumes {
		if v.Label != "" {
			d.Label = v.Label
			return d
		}
	}
	d.Label = d.Model
	if d.Label == "" {
		d.Label = d.Vendor
	}
	return d
}

// volumes are the filesystems and encrypted containers among blocks,
// sorted by device: no partition tables, extended partitions, swap or
// hinted blocks.
func volumes(objs dbus.ManagedObjects, blocks []dbus.ObjectPath, cleartext map[string]dbus.ObjectPath, system bool) []Volume {
	out := []Volume{}
	for _, path := range blocks {
		ifaces := objs[path]
		b := props(ifaces[ifaceBlock])
		_, fs := ifaces[ifaceFS]
		enc, encrypted := ifaces[ifaceEncrypted]
		usage := b.str("IdUsage")
		if hinted(b, system) || props(ifaces[ifacePartition]).bool("IsContainer") || b.str("IdType") == "swap" {
			continue
		}
		if _, swap := ifaces[ifaceSwap]; swap || !fs && !encrypted && usage != "filesystem" && usage != "crypto" {
			continue
		}
		v := Volume{
			ID: string(path), Device: b.bytes("PreferredDevice"), Label: b.str("IdLabel"), UUID: b.str("IdUUID"),
			FSType: b.str("IdType"), Size: b.size("Size"), MountPoints: props(ifaces[ifaceFS]).mountPoints(),
			ReadOnly: b.bool("ReadOnly"), Encrypted: encrypted || usage == "crypto", Mountable: fs,
		}
		if v.Device == "" {
			v.Device = b.bytes("Device")
		}
		if v.Encrypted {
			ct := dbus.ObjectPath(props(enc).path("CleartextDevice"))
			if _, ok := objs[ct]; !ok {
				ct = cleartext[string(path)]
			}
			if c, ok := objs[ct]; ok && ct != "" {
				cb := props(c[ifaceBlock])
				_, cfs := c[ifaceFS]
				v.Unlocked, v.CleartextID = true, string(ct)
				v.FSType, v.MountPoints, v.Mountable = cb.str("IdType"), props(c[ifaceFS]).mountPoints(), cfs
				if l := cb.str("IdLabel"); l != "" {
					v.Label = l
				}
			}
		}
		out = append(out, v)
	}
	slices.SortFunc(out, func(a, b Volume) int { return strings.Compare(a.Device, b.Device) })
	return out
}
