package sysinfo

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
)

func write(t *testing.T, root string, files map[string]string) {
	t.Helper()
	for p, text := range files {
		full := filepath.Join(root, p)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

// gpu makes /sys/class/drm/<card> → a PCI device with the ids given.
func gpu(t *testing.T, root, card, slot, vendor, device string) {
	t.Helper()
	dev := filepath.Join(root, "sys/devices/pci0000:00", slot)
	write(t, root, map[string]string{
		filepath.Join("sys/devices/pci0000:00", slot, "vendor"): "0x" + vendor + "\n",
		filepath.Join("sys/devices/pci0000:00", slot, "device"): "0x" + device + "\n",
	})
	if err := os.MkdirAll(filepath.Join(root, "sys/class/drm", card), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(dev, filepath.Join(root, "sys/class/drm", card, "device")); err != nil {
		t.Fatal(err)
	}
}

func TestRead(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	write(t, root, map[string]string{
		"proc/sys/kernel/hostname":  "box\n",
		"proc/sys/kernel/osrelease": "7.2.14-arch1-1\n",
		"arch":                      "x86_64\n",
		"etc/machine-info":          "PRETTY_HOSTNAME=\"Alex's Box\"\nCHASSIS=desktop\n",
		"usr/lib/os-release":        "NAME=\"Arch Linux\"\nPRETTY_NAME=\"Arch Linux\"\nID=arch\nLOGO=archlinux-logo\nHOME_URL=\"https://archlinux.org/\"\n",
		"proc/cpuinfo":              "processor\t: 0\nmodel name\t: AMD Ryzen 9 7950X 16-Core Processor\n\nprocessor\t: 1\nmodel name\t: AMD Ryzen 9 7950X 16-Core Processor\n",
		"proc/meminfo":              "MemTotal:       65536000 kB\nMemFree: 1 kB\n",
		"proc/stat":                 "cpu  1 2 3\nbtime 1762300000\n",
		"usr/share/hwdata/pci.ids":  "# comment\n1002  Advanced Micro Devices, Inc. [AMD/ATI]\n\t744c  Navi 31 [Radeon RX 7900 XT/7900 XTX]\n\t\t1002 0e3b  sub\n10de  NVIDIA Corporation\n\t2684  AD102 [GeForce RTX 4090]\nC 00  Unclassified device\n",
	})
	gpu(t, root, "card0", "0000:03:00.0", "1002", "744c")
	gpu(t, root, "card1", "0000:04:00.0", "10de", "2684")
	gpu(t, root, "card2", "0000:05:00.0", "8086", "ffff")
	if err := os.MkdirAll(filepath.Join(root, "sys/class/drm/card0-DP-1"), 0o755); err != nil {
		t.Fatal(err)
	}
	info := New(Options{Root: root}).Read()
	if info.DiskTotal == 0 {
		t.Error("the root filesystem's size wasn't read")
	}
	info.DiskTotal, info.DiskFree = 0, 0
	want := Info{
		Hostname: "box", PrettyHostname: "Alex's Box", Chassis: "desktop",
		OS: "Arch Linux", OSID: "arch", Logo: "archlinux-logo", OSURL: "https://archlinux.org/",
		Kernel: "7.2.14-arch1-1", Arch: "x86_64", CPU: "AMD Ryzen 9 7950X", Cores: 2,
		GPUs:        []string{"AMD Radeon RX 7900 XT/7900 XTX", "Intel (device 0xffff)", "NVIDIA GeForce RTX 4090"},
		MemoryTotal: 65536000 * 1024, Boot: 1762300000,
	}
	if !reflect.DeepEqual(info, want) {
		t.Errorf("Read:\n got %+v\nwant %+v", info, want)
	}
}

func TestReadsNothing(t *testing.T) {
	t.Parallel()
	info := New(Options{Root: filepath.Join(t.TempDir(), "missing")}).Read()
	if info.Hostname != "" || info.OS != "" || info.GPUs != nil || info.Cores != 0 {
		t.Errorf("an empty machine read as %+v", info)
	}
}

func TestTidy(t *testing.T) {
	t.Parallel()
	for in, want := range map[string]string{
		"Intel(R) Core(TM) i7-8550U CPU @ 1.80GHz":   "Intel Core i7-8550U",
		"AMD Ryzen 7 5800X 8-Core Processor":         "AMD Ryzen 7 5800X",
		"AMD Ryzen 5 PRO 4650U with Radeon Graphics": "AMD Ryzen 5 PRO 4650U with Radeon Graphics",
		"Raspberry Pi 4 Model B Rev 1.4":             "Raspberry Pi 4 Model B Rev 1.4",
	} {
		if got := tidyCPU(in); got != want {
			t.Errorf("tidyCPU(%q) = %q, want %q", in, got, want)
		}
	}
	for in, want := range map[string]string{
		"Advanced Micro Devices, Inc. [AMD/ATI]": "AMD",
		"NVIDIA Corporation":                     "NVIDIA",
		"Intel Corporation":                      "Intel",
		"Red Hat, Inc.":                          "Red Hat",
	} {
		if got := shortVendor(in); got != want {
			t.Errorf("shortVendor(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestHostnames(t *testing.T) {
	t.Parallel()
	for _, c := range []struct{ in, static, pretty string }{
		{"box", "box", ""},
		{"  Alex's Laptop ", "alexs-laptop", "Alex's Laptop"},
		{"Work PC #2", "work-pc-2", "Work PC #2"},
		{"my-box", "my-box", ""},
	} {
		static, pretty, err := hostnames(c.in)
		if err != nil || static != c.static || pretty != c.pretty {
			t.Errorf("hostnames(%q) = %q, %q, %v; want %q, %q", c.in, static, pretty, err, c.static, c.pretty)
		}
	}
	for _, bad := range []string{"", "   ", "!!!", "日本"} {
		if _, _, err := hostnames(bad); axerr.KindOf(err) != axerr.BadRequest {
			t.Errorf("hostnames(%q): %v, want a bad request", bad, err)
		}
	}
}

func TestRename(t *testing.T) {
	t.Parallel()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	bus := dbustest.New(t)
	fake, err := dbus.Dial(ctx, bus.Address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	defer fake.Close()
	var mu sync.Mutex
	var calls []string
	record := func(_ context.Context, m *dbus.Message) ([]any, error) {
		mu.Lock()
		defer mu.Unlock()
		if m.Flags&dbus.FlagAllowInteractiveAuthorization == 0 {
			return nil, dbus.NewError("org.freedesktop.DBus.Error.InteractiveAuthorizationRequired", "no prompt allowed")
		}
		calls = append(calls, m.Member+" "+m.Body[0].(string))
		return nil, nil
	}
	if _, err := fake.Export(hostnamePath, dbus.Interface{Name: hostnameIface, Methods: map[string]dbus.Method{
		"SetStaticHostname": {In: "sb", Fn: record},
		"SetPrettyHostname": {In: "sb", Fn: record},
	}}); err != nil {
		t.Fatal(err)
	}
	if _, err := fake.RequestName(ctx, hostnameBus, dbus.NameDoNotQueue); err != nil {
		t.Fatal(err)
	}
	r := New(Options{SystemBus: func(ctx context.Context) (*dbus.Conn, error) {
		return dbus.Dial(ctx, bus.Address, dbus.Options{})
	}})
	if err := r.Rename(ctx, "Alex's Laptop"); err != nil {
		t.Fatal(err)
	}
	mu.Lock()
	defer mu.Unlock()
	if want := []string{"SetStaticHostname alexs-laptop", "SetPrettyHostname Alex's Laptop"}; !reflect.DeepEqual(calls, want) {
		t.Errorf("calls %q, want %q", calls, want)
	}
}
