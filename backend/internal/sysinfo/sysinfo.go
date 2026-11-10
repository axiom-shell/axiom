// Package sysinfo describes this machine for Settings › System › System
// info: its name, operating system, kernel, processor, graphics, memory,
// root disk and boot time, read from /proc, /sys and /etc, and renames it
// through systemd-hostnamed (polkit asks the user). The parts a bug report
// shares are buginfo's; this adds the personal ones (the hostname) the
// card shows but never copies. Docs: docs/dev/features/system-info.md.
package sysinfo

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
)

// systemd-hostnamed's names
const (
	hostnameBus   = "org.freedesktop.hostname1"
	hostnamePath  = dbus.ObjectPath("/org/freedesktop/hostname1")
	hostnameIface = "org.freedesktop.hostname1"
)

// How long a rename waits, polkit's prompt included
const renameTimeout = 2 * time.Minute

// Info is the machine, one field per line of the card; a field that
// couldn't be read is empty (0 for numbers).
type Info struct {
	Hostname       string   `json:"hostname"`
	PrettyHostname string   `json:"prettyHostname"`
	OS             string   `json:"os"`     // os-release's PRETTY_NAME, else NAME
	OSID           string   `json:"osId"`   // its ID
	Logo           string   `json:"logo"`   // its LOGO: an icon name
	OSURL          string   `json:"osUrl"`  // its HOME_URL
	Kernel         string   `json:"kernel"` // the release, as uname -r
	Arch           string   `json:"arch"`   // as uname -m
	CPU            string   `json:"cpu"`
	Cores          int      `json:"cores"` // logical processors
	GPUs           []string `json:"gpus"`
	MemoryTotal    uint64   `json:"memoryTotal"` // bytes
	DiskTotal      uint64   `json:"diskTotal"`   // bytes, the root filesystem's
	DiskFree       uint64   `json:"diskFree"`    // bytes available to the user
	Boot           int64    `json:"boot"`        // unix seconds
	Chassis        string   `json:"chassis"`     // laptop, desktop, …: an icon hint
}

// Options are where the machine is read from.
type Options struct {
	// Root prefixes every path read (tests: a temp dir; "" is /)
	Root string
	// SystemBus dials the system bus (renaming); nil: renaming is
	// unavailable
	SystemBus func(ctx context.Context) (*dbus.Conn, error)
}

// Reader reads Info.
type Reader struct{ o Options }

// New is a Reader.
func New(o Options) *Reader { return &Reader{o: o} }

func (r *Reader) path(p string) string { return filepath.Join(r.o.Root, p) }

func (r *Reader) read(p string) string {
	data, err := os.ReadFile(r.path(p))
	if err != nil {
		return ""
	}
	return string(data)
}

// Read describes the machine now.
func (r *Reader) Read() Info {
	var info Info
	info.Hostname = strings.TrimSpace(r.read("/proc/sys/kernel/hostname"))
	info.PrettyHostname = keyValues(r.read("/etc/machine-info"))["PRETTY_HOSTNAME"]
	info.Chassis = keyValues(r.read("/etc/machine-info"))["CHASSIS"]
	if info.Chassis == "" {
		info.Chassis = chassisOf(strings.TrimSpace(r.read("/sys/class/dmi/id/chassis_type")))
	}
	osr := r.read("/etc/os-release")
	if osr == "" {
		osr = r.read("/usr/lib/os-release")
	}
	fields := keyValues(osr)
	info.OS = first(fields["PRETTY_NAME"], fields["NAME"])
	info.OSID, info.Logo, info.OSURL = fields["ID"], fields["LOGO"], fields["HOME_URL"]
	info.Kernel = strings.TrimSpace(r.read("/proc/sys/kernel/osrelease"))
	info.Arch = r.arch()
	info.CPU, info.Cores = cpuOf(r.read("/proc/cpuinfo"))
	if info.CPU == "" {
		info.CPU = strings.TrimSpace(strings.ReplaceAll(r.read("/sys/firmware/devicetree/base/model"), "\x00", ""))
	}
	info.GPUs = r.gpus()
	info.MemoryTotal = memTotal(r.read("/proc/meminfo"))
	info.Boot = bootTime(r.read("/proc/stat"))
	var st syscall.Statfs_t
	if err := syscall.Statfs(r.path("/"), &st); err == nil {
		info.DiskTotal = st.Blocks * uint64(st.Bsize)
		info.DiskFree = st.Bavail * uint64(st.Bsize)
	}
	return info
}

func (r *Reader) arch() string {
	if r.o.Root != "" {
		return strings.TrimSpace(r.read("/arch")) // tests only
	}
	var u syscall.Utsname
	if err := syscall.Uname(&u); err != nil {
		return ""
	}
	var b strings.Builder
	for _, c := range u.Machine {
		if c == 0 {
			break
		}
		b.WriteByte(byte(c))
	}
	return b.String()
}

// Rename sets the static hostname (and the pretty one, when pretty isn't
// what the static one would be shown as), asking through polkit.
func (r *Reader) Rename(ctx context.Context, name string) error {
	static, pretty, err := hostnames(name)
	if err != nil {
		return err
	}
	if r.o.SystemBus == nil {
		return axerr.New(axerr.Unavailable, "no system bus")
	}
	ctx, cancel := context.WithTimeout(ctx, renameTimeout)
	defer cancel()
	conn, err := r.o.SystemBus(ctx)
	if err != nil {
		return err
	}
	defer conn.Close()
	if _, err := conn.CallInteractive(ctx, hostnameBus, hostnamePath, hostnameIface, "SetStaticHostname", "sb", static, true); err != nil {
		return err
	}
	_, err = conn.CallInteractive(ctx, hostnameBus, hostnamePath, hostnameIface, "SetPrettyHostname", "sb", pretty, true)
	return err
}

// A valid static hostname: lowercase letters, digits and dashes, in dot
// separated labels (hostname(7))
var (
	hostnameLabel = regexp.MustCompile(`^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$`)
	notHostname   = regexp.MustCompile(`[^a-z0-9-]+`)
)

// hostnames is the static hostname a name the user typed becomes, and the
// pretty one to keep beside it ("" when the static one says it all):
// "Alex's Laptop" → "alexs-laptop", "Alex's Laptop".
func hostnames(name string) (static, pretty string, err error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return "", "", axerr.New(axerr.BadRequest, "the name is empty")
	}
	static = strings.ToLower(name)
	static = strings.ReplaceAll(static, "'", "")
	static = notHostname.ReplaceAllString(static, "-")
	static = strings.Trim(static, "-")
	if len(static) > 64 {
		static = strings.TrimRight(static[:64], "-")
	}
	if !hostnameLabel.MatchString(static) {
		return "", "", axerr.New(axerr.BadRequest, "%q makes no hostname", name)
	}
	if name != static {
		pretty = name
	}
	return static, pretty, nil
}

// keyValues reads KEY=value lines (os-release, machine-info), unquoting.
func keyValues(text string) map[string]string {
	fields := map[string]string{}
	for line := range strings.Lines(text) {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if k, v, ok := strings.Cut(line, "="); ok {
			if u, err := strconv.Unquote(v); err == nil && strings.HasPrefix(v, `"`) {
				v = u
			} else {
				v = strings.Trim(v, `"'`)
			}
			fields[k] = v
		}
	}
	return fields
}

// cpuOf is /proc/cpuinfo's model name (x86's "model name", ARM's
// "Model"/"Hardware"), tidied, and how many processors it lists.
func cpuOf(cpuinfo string) (string, int) {
	model, cores := "", 0
	for line := range strings.Lines(cpuinfo) {
		k, v, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		k, v = strings.TrimSpace(k), strings.TrimSpace(v)
		switch k {
		case "processor":
			cores++
		case "model name", "Model", "Hardware", "cpu model":
			if model == "" {
				model = v
			}
		}
	}
	return tidyCPU(model), cores
}

var (
	cpuNoise  = regexp.MustCompile(`\((R|TM|tm|r)\)|\bCPU\b|\b(\d+|Eight|Six|Twelve|Sixteen|Quad|Dual)-Core Processor\b|\bProcessor\b|@ .*$`)
	manySpace = regexp.MustCompile(`\s+`)
)

// tidyCPU drops the trademark marks and filler: "Intel(R) Core(TM)
// i7-8550U CPU @ 1.80GHz" → "Intel Core i7-8550U"
func tidyCPU(model string) string {
	return strings.TrimSpace(manySpace.ReplaceAllString(cpuNoise.ReplaceAllString(model, " "), " "))
}

// memTotal is /proc/meminfo's MemTotal in bytes.
func memTotal(meminfo string) uint64 {
	for line := range strings.Lines(meminfo) {
		if rest, ok := strings.CutPrefix(line, "MemTotal:"); ok {
			f := strings.Fields(rest)
			if len(f) > 0 {
				kb, _ := strconv.ParseUint(f[0], 10, 64)
				return kb * 1024
			}
		}
	}
	return 0
}

// bootTime is /proc/stat's btime.
func bootTime(stat string) int64 {
	for line := range strings.Lines(stat) {
		if rest, ok := strings.CutPrefix(line, "btime "); ok {
			t, _ := strconv.ParseInt(strings.TrimSpace(rest), 10, 64)
			return t
		}
	}
	return 0
}

// chassisOf names a DMI chassis type (SMBIOS 3.x table 17) the way
// hostnamed does.
func chassisOf(dmi string) string {
	switch dmi {
	case "3", "4", "6", "7", "13", "15", "16", "24":
		return "desktop"
	case "8", "9", "10", "14", "31", "32":
		return "laptop"
	case "11":
		return "handset"
	case "17", "23", "28", "29":
		return "server"
	case "30":
		return "tablet"
	}
	return ""
}

// gpus names each graphics card under /sys/class/drm (card0, card1, …;
// not their connectors), from pci.ids when it's installed, else by vendor.
func (r *Reader) gpus() []string {
	matches, _ := filepath.Glob(r.path("/sys/class/drm/card[0-9]*"))
	type pci struct{ vendor, device, subVendor, subDevice string }
	var cards []pci
	seen := map[string]bool{}
	for _, m := range matches {
		if strings.Contains(filepath.Base(m), "-") {
			continue
		}
		dev, err := filepath.EvalSymlinks(filepath.Join(m, "device"))
		if err != nil || seen[dev] {
			continue
		}
		seen[dev] = true
		id := func(name string) string {
			data, _ := os.ReadFile(filepath.Join(dev, name))
			return strings.TrimPrefix(strings.TrimSpace(string(data)), "0x")
		}
		if v := id("vendor"); v != "" {
			cards = append(cards, pci{v, id("device"), id("subsystem_vendor"), id("subsystem_device")})
		}
	}
	if len(cards) == 0 {
		return nil
	}
	want := map[string]bool{}
	for _, c := range cards {
		want[c.vendor] = true
	}
	names := pciNames(r.path("/usr/share/hwdata/pci.ids"), want)
	if len(names.vendors) == 0 {
		names = pciNames(r.path("/usr/share/misc/pci.ids"), want)
	}
	var out []string
	for _, c := range cards {
		vendor := first(shortVendor(names.vendors[c.vendor]), knownVendors[c.vendor], "0x"+c.vendor)
		device := names.devices[c.vendor+":"+c.device]
		if device == "" {
			out = append(out, fmt.Sprintf("%s (device 0x%s)", vendor, c.device))
			continue
		}
		out = append(out, vendor+" "+tidyDevice(device))
	}
	slices.Sort(out)
	return slices.Compact(out)
}

// knownVendors names the GPU vendors without pci.ids
var knownVendors = map[string]string{"1002": "AMD", "10de": "NVIDIA", "8086": "Intel", "1af4": "Virtio", "15ad": "VMware", "1234": "QEMU"}

type pciTable struct {
	vendors map[string]string // "10de" → "NVIDIA Corporation"
	devices map[string]string // "10de:2684" → "AD102 [GeForce RTX 4090]"
}

// pciNames reads the vendors in want and their devices from a pci.ids
// file, skipping the rest of it.
func pciNames(path string, want map[string]bool) pciTable {
	t := pciTable{vendors: map[string]string{}, devices: map[string]string{}}
	f, err := os.Open(path)
	if err != nil {
		return t
	}
	defer f.Close()
	vendor := ""
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		switch {
		case line == "" || line[0] == '#':
		case line[0] != '\t':
			if strings.HasPrefix(line, "C ") {
				return t // the device classes follow the vendors
			}
			vendor = ""
			if id, name, ok := strings.Cut(line, "  "); ok && want[id] {
				vendor = id
				t.vendors[id] = name
			}
		case vendor != "" && !strings.HasPrefix(line, "\t\t"):
			if id, name, ok := strings.Cut(line[1:], "  "); ok {
				t.devices[vendor+":"+id] = name
			}
		}
	}
	return t
}

// shortVendor: "Advanced Micro Devices, Inc. [AMD/ATI]" → "AMD",
// "NVIDIA Corporation" → "NVIDIA", "Intel Corporation" → "Intel".
func shortVendor(name string) string {
	if i := strings.Index(name, "["); i >= 0 {
		inner := strings.TrimSuffix(name[i+1:], "]")
		inner, _, _ = strings.Cut(inner, "/")
		return inner
	}
	for _, suffix := range []string{" Corporation", " Corp.", ", Inc.", " Inc.", " Limited", " Ltd."} {
		name = strings.TrimSuffix(name, suffix)
	}
	return name
}

// tidyDevice prefers the marketing name pci.ids brackets: "AD102
// [GeForce RTX 4090]" → "GeForce RTX 4090".
func tidyDevice(name string) string {
	if i := strings.LastIndex(name, "["); i >= 0 && strings.HasSuffix(name, "]") {
		return name[i+1 : len(name)-1]
	}
	return name
}

func first(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}
