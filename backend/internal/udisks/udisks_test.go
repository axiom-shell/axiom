package udisks

import (
	"bytes"
	"context"
	"log/slog"
	"maps"
	"path"
	"reflect"
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
	pathBlocks = "/org/freedesktop/UDisks2/block_devices/"
	pathDrives = "/org/freedesktop/UDisks2/drives/"
	rightPass  = "correct horse"
	wrongPass  = "hunter2-wrong"
)

func v(x any) dbus.Variant { return dbus.MakeVariant(x) }

func bs(s string) []byte { return append([]byte(s), 0) }

// drive is a Drive object's interfaces.
func drive(bus string, removable, mediaRemovable bool, extra map[string]dbus.Variant) dbus.Interfaces {
	p := map[string]dbus.Variant{
		"Vendor": v("Acme"), "Model": v("Stick "), "Size": v(uint64(32e9)), "ConnectionBus": v(bus),
		"Removable": v(removable), "MediaRemovable": v(mediaRemovable), "MediaAvailable": v(true),
		"Optical": v(false), "Ejectable": v(false), "CanPowerOff": v(bus == "usb"),
	}
	maps.Copy(p, extra)
	return dbus.Interfaces{ifaceDrive: p}
}

// block is a Block object's interfaces: of drv (a drives/ name, "" none),
// with fsType ("" none, crypto_LUKS encrypted), a partition when part.
func block(dev, drv, fsType, label string, part bool, mounts ...string) dbus.Interfaces {
	d := dbus.ObjectPath("/")
	if drv != "" {
		d = dbus.ObjectPath(pathDrives + drv)
	}
	usage := ""
	switch fsType {
	case "crypto_LUKS":
		usage = "crypto"
	case "swap":
		usage = "other"
	case "":
	default:
		usage = "filesystem"
	}
	out := dbus.Interfaces{ifaceBlock: {
		"Device": v(bs("/dev/" + dev)), "PreferredDevice": v(bs("/dev/" + dev)), "Drive": v(d),
		"IdLabel": v(label), "IdUUID": v("uuid-" + dev), "IdType": v(fsType), "IdUsage": v(usage),
		"Size": v(uint64(1e9)), "ReadOnly": v(false), "HintSystem": v(false), "HintIgnore": v(false),
		"CryptoBackingDevice": v(dbus.ObjectPath("/")),
	}}
	if part {
		out[ifacePartition] = map[string]dbus.Variant{"Table": v(dbus.ObjectPath(pathBlocks + strings.TrimRight(dev, "0123456789"))), "IsContainer": v(false)}
	}
	switch usage {
	case "filesystem":
		mp := [][]byte{}
		for _, m := range mounts {
			mp = append(mp, bs(m))
		}
		out[ifaceFS] = map[string]dbus.Variant{"MountPoints": v(mp)}
	case "crypto":
		out[ifaceEncrypted] = map[string]dbus.Variant{"CleartextDevice": v(dbus.ObjectPath("/"))}
	}
	return out
}

func set(ifaces dbus.Interfaces, iface, key string, value any) dbus.Interfaces {
	ifaces[iface][key] = v(value)
	return ifaces
}

// fixture is a USB stick with two filesystems, a swap and an extended
// partition; a locked and an unlocked LUKS stick; an SD card; an empty
// card reader; an internal disk; a USB disk UDisks2 calls the system's;
// and a loop device.
func fixture() dbus.ManagedObjects {
	objs := dbus.ManagedObjects{
		pathDrives + "stick":    drive("usb", true, false, nil),
		pathBlocks + "sdb":      block("sdb", "stick", "", "", false),
		pathBlocks + "sdb1":     block("sdb1", "stick", "vfat", "STICK", true),
		pathBlocks + "sdb2":     block("sdb2", "stick", "ext4", "", true, "/run/media/me/data"),
		pathBlocks + "sdb3":     block("sdb3", "stick", "swap", "", true),
		pathBlocks + "sdb4":     set(block("sdb4", "stick", "", "", true), ifacePartition, "IsContainer", true),
		pathDrives + "luks":     drive("usb", true, false, map[string]dbus.Variant{"Model": v("Vault")}),
		pathBlocks + "sdc1":     block("sdc1", "luks", "crypto_LUKS", "", true),
		pathDrives + "open":     drive("usb", true, false, map[string]dbus.Variant{"Model": v("Open")}),
		pathBlocks + "sdd1":     set(block("sdd1", "open", "crypto_LUKS", "", true), ifaceEncrypted, "CleartextDevice", dbus.ObjectPath(pathBlocks+"dm_2d1")),
		pathBlocks + "dm_2d1":   set(block("dm-1", "", "ext4", "SECRET", false, "/run/media/me/SECRET"), ifaceBlock, "CryptoBackingDevice", dbus.ObjectPath(pathBlocks+"sdd1")),
		pathDrives + "sd":       drive("sdio", false, true, map[string]dbus.Variant{"Vendor": v(""), "Model": v("SD32G"), "Ejectable": v(true)}),
		pathBlocks + "mmcblk0":  block("mmcblk0", "sd", "exfat", "CAMERA", false),
		pathDrives + "reader":   drive("usb", true, true, map[string]dbus.Variant{"MediaAvailable": v(false)}),
		pathBlocks + "sde":      block("sde", "reader", "", "", false),
		pathDrives + "internal": drive("", false, false, nil),
		pathBlocks + "nvme0n1":  block("nvme0n1", "internal", "ext4", "root", false, "/"),
		pathDrives + "sysusb":   drive("usb", false, false, nil),
		pathBlocks + "sdf":      set(block("sdf", "sysusb", "ext4", "", false), ifaceBlock, "HintSystem", true),
		pathBlocks + "loop0":    set(block("loop0", "", "vfat", "FIXTURE", false), ifaceBlock, "HintSystem", true),
	}
	objs[pathBlocks+"loop0"][ifaceLoop] = map[string]dbus.Variant{"BackingFile": v(bs("/tmp/fixtures/fat.img"))}
	return objs
}

func ids(drives []Drive) []string {
	out := []string{}
	for _, d := range drives {
		out = append(out, strings.TrimPrefix(strings.TrimPrefix(d.ID, pathDrives), pathBlocks))
	}
	return out
}

func TestBuildFilters(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		loop bool
		want []string
	}{
		{false, []string{"luks", "open", "sd", "stick"}},
		{true, []string{"loop0", "luks", "open", "sd", "stick"}},
	} {
		if got := ids(build(fixture(), tc.loop)); !slices.Equal(got, tc.want) {
			t.Errorf("loop %v: drives %v, want %v", tc.loop, got, tc.want)
		}
	}
}

func TestBuildDrives(t *testing.T) {
	t.Parallel()
	got := map[string]Drive{}
	for _, d := range build(fixture(), true) {
		got[d.ID] = d
	}
	vol := func(dev, fsType, label string, mountable bool, mounts ...string) Volume {
		if mounts == nil {
			mounts = []string{}
		}
		return Volume{ID: pathBlocks + dev, Device: "/dev/" + dev, Label: label, UUID: "uuid-" + dev, FSType: fsType, Size: 1e9, MountPoints: mounts, Mountable: mountable}
	}
	stick := Drive{
		ID: pathDrives + "stick", Vendor: "Acme", Model: "Stick", Size: 32e9, Bus: "usb", Removable: true, CanPowerOff: true,
		Volumes: []Volume{vol("sdb1", "vfat", "STICK", true), vol("sdb2", "ext4", "", true, "/run/media/me/data")},
	}
	if !reflect.DeepEqual(got[stick.ID], stick) {
		t.Errorf("stick:\n%+v\nwant\n%+v", got[stick.ID], stick)
	}

	locked := vol("sdc1", "crypto_LUKS", "", false)
	locked.Encrypted = true
	if d := got[pathDrives+"luks"]; !reflect.DeepEqual(d.Volumes, []Volume{locked}) {
		t.Errorf("locked LUKS: %+v", d)
	}

	open := vol("sdd1", "ext4", "SECRET", true, "/run/media/me/SECRET")
	open.Encrypted, open.Unlocked, open.CleartextID = true, true, pathBlocks+"dm_2d1"
	if d := got[pathDrives+"open"]; !reflect.DeepEqual(d.Volumes, []Volume{open}) {
		t.Errorf("unlocked LUKS: %+v", d)
	}

	if d := got[pathDrives+"sd"]; d.Bus != "sdio" || !d.CanEject || !reflect.DeepEqual(d.Volumes, []Volume{vol("mmcblk0", "exfat", "CAMERA", true)}) {
		t.Errorf("SD card: %+v", d)
	}

	if d := got[pathBlocks+"loop0"]; d.Bus != "loop" || d.Model != "fat.img" || d.CanPowerOff || len(d.Volumes) != 1 || d.Volumes[0].ID != pathBlocks+"loop0" {
		t.Errorf("loop: %+v", d)
	}
}

func TestMapError(t *testing.T) {
	t.Parallel()
	reply := func(name, msg string) error {
		return axerr.Wrap(axerr.Internal, &dbus.Error{Name: name, Message: msg}, "call")
	}
	for _, tc := range []struct {
		err  error
		pass string
		want axerr.Kind
	}{
		{reply(errDeviceBusy, "busy"), "", axerr.Busy},
		{reply(errPrefix+"Failed", "Error unmounting /dev/sdb1: target is busy"), "", axerr.Busy},
		{reply(errPrefix+"NotAuthorizedDismissed", "dismissed"), "", axerr.NotAuthorized},
		{reply(errPrefix+"NotAuthorizedCanObtain", "no"), "", axerr.NotAuthorized},
		{reply(errPrefix+"Failed", "Error unlocking /dev/sdc1: Failed to activate device: Incorrect passphrase."), "x", axerr.WrongPassphrase},
		{reply(errPrefix+"Failed", "Error unlocking /dev/sdc1: Failed to activate device: Operation not permitted"), "x", axerr.WrongPassphrase},
		{reply(errPrefix+"Failed", "Error unlocking /dev/sdc1: Failed to activate device: Incorrect passphrase."), "pass", axerr.WrongPassphrase},
		{reply(errPrefix+"Failed", "Error mounting: wrong fs type"), "", axerr.Failed},
		{axerr.New(axerr.Unavailable, "gone"), "", axerr.Unavailable},
		{axerr.Wrap(axerr.Unavailable, &dbus.Error{Name: dbus.ErrServiceUnknown}, "call"), "", axerr.Unavailable},
	} {
		if got := axerr.KindOf(mapError(tc.err, tc.pass)); got != tc.want {
			t.Errorf("%v: %s, want %s", tc.err, got, tc.want)
		}
	}
	err := mapError(reply(errPrefix+"Failed", "bad key 's3cret' for /dev/sdc1"), "s3cret")
	if strings.Contains(err.Error(), "s3cret") {
		t.Errorf("the passphrase is in %q", err)
	}
}

// fakeUDisks is UDisks2 on a test bus: its objects, the methods the
// service calls on them, and the signals it sends when they change.
type fakeUDisks struct {
	t    *testing.T
	conn *dbus.Conn

	mu       sync.Mutex
	objs     dbus.ManagedObjects
	unexport map[dbus.ObjectPath][]func()
	calls    []string
	// fail makes a method ("Unmount sdb2") answer this error
	fail map[string]*dbus.Error
}

func newFakeUDisks(t *testing.T, bus *dbustest.Bus, objs dbus.ManagedObjects) *fakeUDisks {
	t.Helper()
	conn, err := dbus.Dial(t.Context(), bus.Address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	f := &fakeUDisks{t: t, conn: conn, objs: dbus.ManagedObjects{}, unexport: map[dbus.ObjectPath][]func(){}, fail: map[string]*dbus.Error{}}
	if _, err := conn.Export(rootPath, dbus.Interface{Name: dbus.IfaceObjectManager, Methods: map[string]dbus.Method{
		"GetManagedObjects": {Out: "a{oa{sa{sv}}}", Fn: func(context.Context, *dbus.Message) ([]any, error) {
			f.mu.Lock()
			defer f.mu.Unlock()
			out := map[dbus.ObjectPath]map[string]map[string]dbus.Variant{}
			for p, i := range f.objs {
				out[p] = i
			}
			return []any{out}, nil
		}},
	}}); err != nil {
		t.Fatal(err)
	}
	for p, i := range objs {
		f.add(p, i, false)
	}
	if _, err := conn.RequestName(t.Context(), busName, dbus.NameDoNotQueue); err != nil {
		t.Fatal(err)
	}
	return f
}

// add adds an object (with an InterfacesAdded signal when signal), and
// exports the methods of its interfaces.
func (f *fakeUDisks) add(p dbus.ObjectPath, ifaces dbus.Interfaces, signal bool) {
	f.mu.Lock()
	f.objs[p] = ifaces
	f.mu.Unlock()
	none := "a{sv}"
	methods := map[string]map[string]dbus.Method{
		ifaceFS: {
			"Mount":   {In: none, Out: "s", Fn: f.method(p, "Mount", f.mount)},
			"Unmount": {In: none, Fn: f.method(p, "Unmount", f.unmount)},
		},
		ifaceEncrypted: {
			"Unlock": {In: "s" + none, Out: "o", Fn: f.method(p, "Unlock", f.unlock)},
			"Lock":   {In: none, Fn: f.method(p, "Lock", f.lock)},
		},
		ifaceDrive: {
			"Eject":    {In: none, Fn: f.method(p, "Eject", f.remove)},
			"PowerOff": {In: none, Fn: f.method(p, "PowerOff", f.remove)},
		},
		ifaceLoop: {"Delete": {In: none, Fn: f.method(p, "Delete", f.remove)}},
	}
	for name := range ifaces {
		if m, ok := methods[name]; ok {
			un, err := f.conn.Export(p, dbus.Interface{Name: name, Methods: m})
			if err != nil {
				f.t.Error(err)
				continue
			}
			f.mu.Lock()
			f.unexport[p] = append(f.unexport[p], un)
			f.mu.Unlock()
		}
	}
	if signal {
		f.conn.Emit(rootPath, dbus.IfaceObjectManager, "InterfacesAdded", "oa{sa{sv}}", p, map[string]map[string]dbus.Variant(ifaces))
	}
}

// method records a call by its member and the object's last name, and
// answers it with fail's error or fn.
func (f *fakeUDisks) method(p dbus.ObjectPath, member string, fn func(dbus.ObjectPath, *dbus.Message) ([]any, error)) func(context.Context, *dbus.Message) ([]any, error) {
	return func(_ context.Context, m *dbus.Message) ([]any, error) {
		key := member + " " + path.Base(string(p))
		f.mu.Lock()
		f.calls = append(f.calls, key)
		e := f.fail[key]
		f.mu.Unlock()
		if e != nil {
			return nil, e
		}
		return fn(p, m)
	}
}

func (f *fakeUDisks) changed(p dbus.ObjectPath, iface, key string, value any) {
	f.mu.Lock()
	f.objs[p][iface][key] = v(value)
	f.mu.Unlock()
	f.conn.Emit(p, "org.freedesktop.DBus.Properties", "PropertiesChanged", "sa{sv}as", iface, map[string]dbus.Variant{key: v(value)}, []string{})
}

func (f *fakeUDisks) mount(p dbus.ObjectPath, _ *dbus.Message) ([]any, error) {
	at := "/run/media/me/" + path.Base(string(p))
	f.changed(p, ifaceFS, "MountPoints", [][]byte{bs(at)})
	return []any{at}, nil
}

func (f *fakeUDisks) unmount(p dbus.ObjectPath, _ *dbus.Message) ([]any, error) {
	f.changed(p, ifaceFS, "MountPoints", [][]byte{})
	return nil, nil
}

// unlock fails with the passphrase in its message, so the test sees it
// isn't passed on
func (f *fakeUDisks) unlock(p dbus.ObjectPath, m *dbus.Message) ([]any, error) {
	if pass := m.Body[0].(string); pass != rightPass {
		return nil, dbus.NewError(errPrefix+"Failed", "Error unlocking %s: Failed to activate device: Incorrect passphrase %q.", path.Base(string(p)), pass)
	}
	ct := dbus.ObjectPath(pathBlocks + "dm_2d9")
	f.add(ct, set(block("dm-9", "", "ext4", "", false), ifaceBlock, "CryptoBackingDevice", p), true)
	f.changed(p, ifaceEncrypted, "CleartextDevice", ct)
	return []any{ct}, nil
}

func (f *fakeUDisks) lock(p dbus.ObjectPath, _ *dbus.Message) ([]any, error) {
	f.mu.Lock()
	var ct dbus.ObjectPath
	for q, i := range f.objs {
		if props(i[ifaceBlock]).path("CryptoBackingDevice") == string(p) {
			ct = q
		}
	}
	f.mu.Unlock()
	f.changed(p, ifaceEncrypted, "CleartextDevice", dbus.ObjectPath("/"))
	if ct != "" {
		f.drop(ct)
	}
	return nil, nil
}

// remove drops a drive and its blocks (a loop device: itself)
func (f *fakeUDisks) remove(p dbus.ObjectPath, _ *dbus.Message) ([]any, error) {
	f.mu.Lock()
	gone := []dbus.ObjectPath{p}
	for q, i := range f.objs {
		if props(i[ifaceBlock]).path("Drive") == string(p) {
			gone = append(gone, q)
		}
	}
	f.mu.Unlock()
	for _, q := range gone {
		f.drop(q)
	}
	return nil, nil
}

func (f *fakeUDisks) drop(p dbus.ObjectPath) {
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

func (f *fakeUDisks) takeCalls() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	out := f.calls
	f.calls = nil
	return out
}

// harness runs a service against a fake, collecting its events and logs.
type harness struct {
	s   *Service
	bus *dbustest.Bus
	log *bytes.Buffer

	mu     sync.Mutex
	events []Event
	logMu  sync.Mutex
}

func (h *harness) Write(p []byte) (int, error) {
	h.logMu.Lock()
	defer h.logMu.Unlock()
	return h.log.Write(p)
}

func (h *harness) logs() string {
	h.logMu.Lock()
	defer h.logMu.Unlock()
	return h.log.String()
}

func (h *harness) count() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.events)
}

func (h *harness) takeEvents() []Event {
	h.mu.Lock()
	defer h.mu.Unlock()
	out := h.events
	h.events = nil
	return out
}

func start(t *testing.T, bus *dbustest.Bus, settle time.Duration) *harness {
	t.Helper()
	h := &harness{bus: bus, log: &bytes.Buffer{}}
	h.s = New(Options{
		SystemBus: func(ctx context.Context) (*dbus.Conn, error) {
			return dbus.Dial(ctx, bus.Address, dbus.Options{})
		},
		OnEvent: func(e Event) {
			h.mu.Lock()
			h.events = append(h.events, e)
			h.mu.Unlock()
		},
		Settle: settle,
		Retry:  20 * time.Millisecond,
		Log:    slog.New(slog.NewTextHandler(h, &slog.HandlerOptions{Level: slog.LevelDebug})),
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

func (h *harness) waitDrives(t *testing.T, want ...string) {
	t.Helper()
	if !testkit.Eventually(func() bool { return slices.Equal(ids(h.s.State().Drives), want) }) {
		t.Fatalf("drives %v, want %v", ids(h.s.State().Drives), want)
	}
}

func eventsOf(es []Event) []string {
	out := []string{}
	for _, e := range es {
		s := e.Kind + " " + path.Base(e.DriveID)
		if e.Drive != nil {
			s += " " + strings.Join(func() []string {
				var vs []string
				for _, v := range e.Drive.Volumes {
					vs = append(vs, path.Base(v.ID))
				}
				return vs
			}(), ",")
		}
		out = append(out, strings.TrimSpace(s))
	}
	return out
}

// Drives already there, and those there again after UDisks2 restarts, are
// no news; drives plugged in and pulled out are
func TestEvents(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	start0 := dbus.ManagedObjects{pathDrives + "stick": drive("usb", true, false, nil), pathBlocks + "sdb1": block("sdb1", "stick", "vfat", "STICK", true)}
	f := newFakeUDisks(t, bus, start0)
	h := start(t, bus, time.Hour)
	h.waitDrives(t, "stick")
	if !h.s.State().Available {
		t.Error("not available")
	}

	// Plugged in: announced once its volume is known
	f.add(pathDrives+"new", drive("usb", true, false, nil), true)
	h.waitDrives(t, "new", "stick")
	f.add(pathBlocks+"sdc1", block("sdc1", "new", "ext4", "NEW", true), true)
	if !testkit.Eventually(func() bool { return len(h.s.State().Drives[0].Volumes) == 1 }) {
		t.Fatal("no volume")
	}
	// A card put in a reader
	f.add(pathDrives+"reader", drive("usb", true, true, map[string]dbus.Variant{"MediaAvailable": v(false)}), true)
	f.add(pathBlocks+"sdd", block("sdd", "reader", "", "", false), true)
	f.changed(pathDrives+"reader", ifaceDrive, "MediaAvailable", true)
	f.add(pathBlocks+"sdd1", block("sdd1", "reader", "vfat", "CARD", true), true)
	h.waitDrives(t, "new", "reader", "stick")
	// Pulled out
	f.remove(pathDrives+"stick", nil)
	h.waitDrives(t, "new", "reader")
	want := []string{"added new sdc1", "added reader sdd1", "removed stick"}
	testkit.Eventually(func() bool { return h.count() >= 3 })
	if got := eventsOf(h.takeEvents()); !slices.Equal(got, want) {
		t.Errorf("events %v, want %v", got, want)
	}

	// UDisks2 restarts with another drive: no news
	f.conn.Close()
	if !testkit.Eventually(func() bool { return !h.s.State().Available }) {
		t.Fatal("still available")
	}
	newFakeUDisks(t, bus, dbus.ManagedObjects{pathDrives + "other": drive("usb", true, false, nil), pathBlocks + "sdx1": block("sdx1", "other", "vfat", "", true)})
	h.waitDrives(t, "other")
	time.Sleep(50 * time.Millisecond)
	if es := h.takeEvents(); len(es) > 0 {
		t.Errorf("a restart announced %v", eventsOf(es))
	}
}

// A drive whose volumes don't come is announced after Settle anyway; one
// pulled out before it was announced is never announced
func TestEventSettle(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	f := newFakeUDisks(t, bus, nil)
	h := start(t, bus, 30*time.Millisecond)
	if !testkit.Eventually(func() bool { return h.s.State().Available }) {
		t.Fatal("not available")
	}
	f.add(pathDrives+"blank", drive("usb", true, false, nil), true)
	if !testkit.Eventually(func() bool { return h.count() == 1 }) {
		t.Fatal("blank drive never announced")
	}
	if got := eventsOf(h.takeEvents()); !slices.Equal(got, []string{"added blank"}) {
		t.Errorf("events %v", got)
	}
}

func TestEventPulledBeforeAnnounced(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	f := newFakeUDisks(t, bus, nil)
	h := start(t, bus, time.Hour)
	if !testkit.Eventually(func() bool { return h.s.State().Available }) {
		t.Fatal("not available")
	}
	f.add(pathDrives+"blip", drive("usb", true, false, nil), true)
	h.waitDrives(t, "blip")
	f.remove(pathDrives+"blip", nil)
	h.waitDrives(t)
	time.Sleep(50 * time.Millisecond)
	if es := h.takeEvents(); len(es) > 0 {
		t.Errorf("events %v", eventsOf(es))
	}
}

func TestMethods(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	f := newFakeUDisks(t, bus, fixture())
	h := start(t, bus, time.Hour)
	h.waitDrives(t, "luks", "open", "sd", "stick")
	ctx := t.Context()

	at, err := h.s.Mount(ctx, pathBlocks+"sdb1")
	if err != nil || at != "/run/media/me/sdb1" {
		t.Errorf("Mount = %q, %v", at, err)
	}
	// Mounted already: its place, no call
	if at, err := h.s.Mount(ctx, pathBlocks+"sdb2"); err != nil || at != "/run/media/me/data" {
		t.Errorf("Mount mounted = %q, %v", at, err)
	}
	if err := h.s.Unmount(ctx, pathBlocks+"sdb2"); err != nil {
		t.Error(err)
	}
	if got := f.takeCalls(); !slices.Equal(got, []string{"Mount sdb1", "Unmount sdb2"}) {
		t.Errorf("calls %v", got)
	}

	// Only shown volumes: not the internal disk, not a made-up path
	for _, id := range []string{pathBlocks + "nvme0n1", "/nope"} {
		if _, err := h.s.Mount(ctx, id); axerr.KindOf(err) != axerr.NotFound {
			t.Errorf("Mount %s: %v", id, err)
		}
	}
	if err := h.s.Eject(ctx, pathDrives+"internal"); axerr.KindOf(err) != axerr.NotFound {
		t.Errorf("Eject internal: %v", err)
	}

	// Error kinds
	f.mu.Lock()
	f.fail["Unmount sdb2"] = dbus.NewError(errDeviceBusy, "Error unmounting /dev/sdb2: target is busy")
	f.fail["Mount mmcblk0"] = dbus.NewError(errPrefix+"NotAuthorizedDismissed", "dismissed")
	f.fail["Eject sd"] = dbus.NewError(errPrefix+"Failed", "it broke")
	f.mu.Unlock()
	h.s.Mount(ctx, pathBlocks+"sdb2")
	if !testkit.Eventually(func() bool { return len(h.s.State().Drives[3].Volumes[1].MountPoints) == 1 }) {
		t.Fatal("not mounted")
	}
	if err := h.s.Unmount(ctx, pathBlocks+"sdb2"); axerr.KindOf(err) != axerr.Busy {
		t.Errorf("busy unmount: %v", err)
	}
	if _, err := h.s.Mount(ctx, pathBlocks+"mmcblk0"); axerr.KindOf(err) != axerr.NotAuthorized {
		t.Errorf("dismissed mount: %v", err)
	}
	if err := h.s.Eject(ctx, pathDrives+"sd"); axerr.KindOf(err) != axerr.Failed || !strings.Contains(err.Error(), "it broke") {
		t.Errorf("failed eject: %v", err)
	}
	f.takeCalls()

	// Unlocking: the wrong passphrase, which never shows, then the right one
	luks := pathBlocks + "sdc1"
	if _, err := h.s.Mount(ctx, luks); axerr.KindOf(err) != axerr.BadRequest {
		t.Errorf("mounting a locked volume: %v", err)
	}
	_, err = h.s.Unlock(ctx, luks, wrongPass)
	if axerr.KindOf(err) != axerr.WrongPassphrase || strings.Contains(err.Error(), wrongPass) {
		t.Errorf("wrong passphrase: %v", err)
	}
	unlocked, err := h.s.Unlock(ctx, luks, rightPass)
	ct := unlocked.CleartextID
	if err != nil || ct != pathBlocks+"dm_2d9" || !unlocked.Mountable {
		t.Errorf("Unlock = %+v, %v", unlocked, err)
	}
	// Shown unlocked once it answers: the cleartext mounts by its own id
	if v := h.s.State().Drives[0].Volumes[0]; !v.Unlocked || v.CleartextID != ct {
		t.Fatalf("not shown unlocked: %+v", v)
	}
	if at, err := h.s.Mount(ctx, ct); err != nil || at != "/run/media/me/dm_2d9" {
		t.Errorf("Mount unlocked = %q, %v", at, err)
	}
	if !testkit.Eventually(func() bool { return len(h.s.State().Drives[0].Volumes[0].MountPoints) == 1 }) {
		t.Fatal("cleartext not mounted")
	}
	if got := f.takeCalls(); !slices.Equal(got, []string{"Unlock sdc1", "Unlock sdc1", "Mount dm_2d9"}) {
		t.Errorf("calls %v", got)
	}
	// Ejecting: unmount, lock, then power off
	if err := h.s.Eject(ctx, pathDrives+"luks"); err != nil {
		t.Error(err)
	}
	if got := f.takeCalls(); !slices.Equal(got, []string{"Unmount dm_2d9", "Lock sdc1", "PowerOff luks"}) {
		t.Errorf("eject calls %v", got)
	}
	h.waitDrives(t, "open", "sd", "stick")
	if l := h.logs(); strings.Contains(l, wrongPass) || strings.Contains(l, rightPass) {
		t.Errorf("a passphrase is in the log:\n%s", l)
	}

	// Lock unmounts first; the SD card ejects its media
	if err := h.s.Lock(ctx, pathBlocks+"sdd1"); err != nil {
		t.Error(err)
	}
	f.mu.Lock()
	delete(f.fail, "Eject sd")
	f.mu.Unlock()
	if err := h.s.Eject(ctx, pathDrives+"sd"); err != nil {
		t.Error(err)
	}
	if got := f.takeCalls(); !slices.Equal(got, []string{"Unmount dm_2d1", "Lock sdd1", "Eject sd"}) {
		t.Errorf("calls %v", got)
	}
}

// UDisks2 not on the bus: unavailable, and the methods say so
func TestUnavailable(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	h := start(t, bus, time.Hour)
	time.Sleep(50 * time.Millisecond)
	if st := h.s.State(); st.Available || st.Drives == nil {
		t.Errorf("state %+v", st)
	}
	if _, err := h.s.Mount(t.Context(), "/x"); axerr.KindOf(err) != axerr.Unavailable {
		t.Errorf("Mount: %v", err)
	}
	// Started later: found
	newFakeUDisks(t, bus, fixture())
	h.waitDrives(t, "luks", "open", "sd", "stick")
	if es := h.takeEvents(); len(es) > 0 {
		t.Errorf("events %v", eventsOf(es))
	}
}
