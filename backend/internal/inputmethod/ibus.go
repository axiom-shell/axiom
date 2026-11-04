package inputmethod

import (
	"bufio"
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
)

// ibus-daemon's names, on its own bus (bus/ibusimpl.c)
const (
	ibusName  = "org.freedesktop.IBus"
	ibusPath  = dbus.ObjectPath("/org/freedesktop/IBus")
	ibusIface = "org.freedesktop.IBus"

	// Where ibus keeps its engine list and panel font
	ibusGeneral = "org.freedesktop.ibus.general"
	ibusPanel   = "org.freedesktop.ibus.panel"
)

// ibusAddress is the running ibus-daemon's bus address, as libibus finds
// it (ibus_get_address): $IBUS_ADDRESS, else the address file
// ($IBUS_ADDRESS_FILE, else ~/.config/ibus/bus/<machine-id>-<host>-<display>)
// when the process it names is an ibus-daemon that runs; "" for none.
func ibusAddress(getenv func(string) string) string {
	if a := getenv("IBUS_ADDRESS"); a != "" {
		return a
	}
	path := getenv("IBUS_ADDRESS_FILE")
	if path == "" {
		id := machineID()
		if id == "" {
			return ""
		}
		path = ibusAddressFile(getenv, id)
	}
	if path == "" {
		return ""
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	addr, pid := parseIBusAddressFile(data)
	if addr == "" || !isIBusDaemon(pid) {
		return ""
	}
	return addr
}

// isIBusDaemon: pid is a running ibus-daemon. Not just any process (as
// libibus checks): fcitx5's ibus frontend writes the same file, naming
// the session bus and itself, and a daemon gone leaves its file behind.
func isIBusDaemon(pid int) bool {
	if pid <= 0 {
		return false
	}
	comm, err := os.ReadFile("/proc/" + strconv.Itoa(pid) + "/comm")
	return err == nil && strings.TrimSpace(string(comm)) == "ibus-daemon"
}

func machineID() string {
	for _, p := range []string{"/var/lib/dbus/machine-id", "/etc/machine-id"} {
		if b, err := os.ReadFile(p); err == nil {
			if id := strings.TrimSpace(string(b)); id != "" {
				return id
			}
		}
	}
	return ""
}

// ibusAddressFile is the address file's path for machine id (libibus's
// ibus_get_socket_path): the Wayland display's name whole, else X's
// display split into host ("unix" for none) and number (the screen
// dropped).
func ibusAddressFile(getenv func(string) string, id string) string {
	host, number := "unix", "0"
	if w := getenv("WAYLAND_DISPLAY"); w != "" {
		number = w
	} else if d := getenv("DISPLAY"); d != "" {
		h, n, ok := strings.Cut(d, ":")
		if ok {
			if h != "" {
				host = h
			}
			n, _, _ = strings.Cut(n, ".")
			if n != "" {
				number = n
			}
		}
	}
	config := getenv("XDG_CONFIG_HOME")
	if config == "" {
		home := getenv("HOME")
		if home == "" {
			return ""
		}
		config = filepath.Join(home, ".config")
	}
	return filepath.Join(config, "ibus", "bus", id+"-"+host+"-"+number)
}

// parseIBusAddressFile reads the address file's IBUS_ADDRESS= and
// IBUS_DAEMON_PID= lines.
func parseIBusAddressFile(data []byte) (addr string, pid int) {
	pid = -1
	sc := bufio.NewScanner(bytes.NewReader(data))
	for sc.Scan() {
		line := sc.Text()
		if strings.HasPrefix(line, "#") {
			continue
		}
		if v, ok := strings.CutPrefix(line, "IBUS_ADDRESS="); ok {
			addr = v
		} else if v, ok := strings.CutPrefix(line, "IBUS_DAEMON_PID="); ok {
			if n, err := strconv.Atoi(strings.TrimSpace(v)); err == nil {
				pid = n
			}
		}
	}
	return addr, pid
}

// ibus is ibus-daemon followed on its bus.
type ibus struct {
	conn      *dbus.Conn
	gsettings func(ctx context.Context, args ...string) (string, error)
}

// followIBus follows ibus-daemon at addr until it stops (again), the
// setting changes (again) or fcitx5 starts (owners, in auto: again).
func (s *Service) followIBus(ctx context.Context, addr string, owners *dbus.Subscription) (bool, error) {
	conn, err := dbus.Dial(ctx, addr, dbus.Options{Log: s.o.Log})
	if err != nil {
		return false, err
	}
	defer conn.Close()
	var subs []*dbus.Subscription
	defer func() {
		for _, sub := range subs {
			sub.Close()
		}
	}()
	// Every signal of its: GlobalEngineChanged, RegistryChanged, and the
	// properties changing (PreloadEngines set)
	for _, m := range []dbus.Match{
		{Path: ibusPath, Interface: ibusIface},
		dbus.PropertiesChangedMatch("", ibusPath, ""),
	} {
		sub, err := conn.Subscribe(ctx, m)
		if err != nil {
			return false, err
		}
		subs = append(subs, sub)
	}
	signals := merge(append(subs, owners)...)
	defer signals.stop()

	b := &ibus{conn: conn, gsettings: s.o.GSettings}
	s.setActive(b)
	read := func() error {
		st, err := b.read(ctx)
		if err != nil {
			return err
		}
		s.publish(st)
		return nil
	}
	if err := read(); err != nil {
		return false, err
	}
	for {
		var err error
		select {
		case <-ctx.Done():
			return false, nil
		case <-s.kick:
			return true, nil
		case <-conn.Done():
			// ibus-daemon exited (or restarted, with a new address)
			return true, nil
		case <-s.refresh:
			err = read()
		case m := <-signals.C:
			if m.Member == "NameOwnerChanged" {
				// fcitx5 started: it wins
				if ownerOf(m) != "" {
					return true, nil
				}
				continue
			}
			err = read()
		}
		if err != nil {
			if axerr.KindOf(err) == axerr.Unavailable {
				return true, nil
			}
			s.o.Log.Warn("input method: reading ibus", "err", err)
		}
	}
}

func (b *ibus) read(ctx context.Context) (State, error) {
	st := State{Framework: FrameworkIBus, Running: true, Group: []Item{}, Available: []Engine{}}
	engines, err := b.engines(ctx, "Engines")
	if err != nil {
		return State{}, err
	}
	for _, d := range engines {
		st.Available = append(st.Available, d.engine())
	}
	active, err := b.engines(ctx, "ActiveEngines")
	if err != nil {
		return State{}, err
	}
	for _, d := range active {
		st.Group = append(st.Group, Item{Name: d.name, Layout: d.layout})
	}
	// An error when there is none ("No global engine.")
	if v, err := b.conn.GetProperty(ctx, ibusName, ibusPath, ibusIface, "GlobalEngine"); err == nil {
		if d, ok := engineDesc(v); ok {
			st.Current = d.name
		}
	} else if axerr.KindOf(err) == axerr.Unavailable {
		return State{}, err
	}
	return st, nil
}

// engines reads a property listing engines (av of IBusEngineDesc).
func (b *ibus) engines(ctx context.Context, prop string) ([]ibusEngine, error) {
	v, err := b.conn.GetProperty(ctx, ibusName, ibusPath, ibusIface, prop)
	if err != nil {
		return nil, mapError(err)
	}
	list, _ := v.Value.([]any)
	out := []ibusEngine{}
	for _, e := range list {
		if d, ok := engineDesc(e); ok {
			out = append(out, d)
		}
	}
	return out, nil
}

// ibusEngine is what's read of an IBusEngineDesc.
type ibusEngine struct {
	name, longName, lang, icon, layout, symbol string
}

func (d ibusEngine) engine() Engine {
	label := d.symbol
	if label == "" {
		label = d.lang
	}
	return Engine{Name: d.name, Label: label, DisplayName: d.longName, Icon: d.icon, Lang: d.lang}
}

// engineDesc reads a serialized IBusEngineDesc (in variants): its type
// name and attachments (IBusSerializable's), then name, longname,
// description, language, license, author, icon, layout, rank, hotkeys,
// symbol, … (ibusenginedesc.c, an order it keeps).
func engineDesc(v any) (ibusEngine, bool) {
	for {
		x, ok := v.(dbus.Variant)
		if !ok {
			break
		}
		v = x.Value
	}
	f, ok := v.([]any)
	if !ok || len(f) < 10 || str(f[0]) != "IBusEngineDesc" || str(f[2]) == "" {
		return ibusEngine{}, false
	}
	d := ibusEngine{name: str(f[2]), longName: str(f[3]), lang: str(f[5]), icon: str(f[8]), layout: str(f[9])}
	if d.layout == "default" {
		d.layout = ""
	}
	if len(f) > 12 {
		d.symbol = str(f[12])
	}
	return d, true
}

func (b *ibus) set(ctx context.Context, name string) error {
	_, err := b.conn.Call(ctx, ibusName, ibusPath, ibusIface, "SetGlobalEngine", "s", name)
	return mapError(err)
}

// push preloads the items' engines now (the PreloadEngines property,
// which refuses an engine it doesn't know), and keeps them in ibus's
// settings, which its panel and the next start read. ibus engines carry
// their layouts: defaultLayout and the items' layouts aren't ibus's.
func (b *ibus) push(ctx context.Context, _ string, items []Item) error {
	names := make([]string, 0, len(items))
	for _, it := range items {
		names = append(names, it.Name)
	}
	if err := b.conn.SetProperty(ctx, ibusName, ibusPath, ibusIface, "PreloadEngines", dbus.MakeVariant(names)); err != nil {
		return mapError(err)
	}
	return b.setting(ctx, ibusGeneral, "preload-engines", gvariantStrings(names))
}

// settings sets what ibus has of them: the candidate font.
func (b *ibus) settings(ctx context.Context, s Settings) error {
	if s.CandidateFont == nil {
		return nil
	}
	if *s.CandidateFont == "" {
		return b.setting(ctx, ibusPanel, "use-custom-font", "false")
	}
	if err := b.setting(ctx, ibusPanel, "custom-font", gvariantString(*s.CandidateFont)); err != nil {
		return err
	}
	return b.setting(ctx, ibusPanel, "use-custom-font", "true")
}

func (b *ibus) setting(ctx context.Context, schema, key, value string) error {
	if b.gsettings == nil {
		return nil
	}
	if out, err := b.gsettings(ctx, "set", schema, key, value); err != nil {
		return axerr.Wrap(axerr.Failed, err, "gsettings set %s %s: %s", schema, key, strings.TrimSpace(out))
	}
	return nil
}

// gvariantString is s in GVariant's text format (gsettings parses it).
func gvariantString(s string) string {
	return "'" + strings.NewReplacer(`\`, `\\`, `'`, `\'`).Replace(s) + "'"
}

func gvariantStrings(list []string) string {
	quoted := make([]string, len(list))
	for i, s := range list {
		quoted[i] = gvariantString(s)
	}
	return "[" + strings.Join(quoted, ", ") + "]"
}
