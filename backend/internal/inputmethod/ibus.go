package inputmethod

import (
	"bufio"
	"bytes"
	"context"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/footprint"
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
	ledger    *footprint.Ledger
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

	b := &ibus{conn: conn, gsettings: s.o.GSettings, ledger: s.o.Ledger}
	s.setActive(b)
	read := func(list bool) error {
		st, err := b.read(ctx, list, s.State())
		if err != nil {
			return err
		}
		s.publish(st)
		return nil
	}
	if err := read(true); err != nil {
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
			err = read(true)
		case m := <-signals.C:
			if m.Member == "NameOwnerChanged" {
				// fcitx5 started: it wins
				if ownerOf(m) != "" {
					return true, nil
				}
				continue
			}
			// A switch leaves the list as it was
			err = read(m.Member != "GlobalEngineChanged")
		}
		if err != nil {
			if axerr.KindOf(err) == axerr.Unavailable {
				return true, nil
			}
			s.o.Log.Warn("input method: reading ibus", "err", err)
		}
	}
}

// read reads ibus's state: the engines installed, the current one and,
// when list, its list (else prev's, while that is ibus's).
func (b *ibus) read(ctx context.Context, list bool, prev State) (State, error) {
	st := State{Framework: FrameworkIBus, Running: true, Group: []Item{}, Available: []Engine{}}
	engines, err := b.engines(ctx, "Engines")
	if err != nil {
		return State{}, err
	}
	for _, d := range engines {
		st.Available = append(st.Available, d.engine())
	}
	if !list && prev.Framework == FrameworkIBus && prev.Running {
		st.Group = prev.Group
	} else {
		st.Group = b.list(ctx, engines)
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

// list is ibus's list: its preload-engines setting, which a push and
// ibus-setup write and its panel preloads (the daemon has no readable list:
// PreloadEngines is write-only, ActiveEngines the engines of components
// registered while it runs), each with the layout its engine carries.
// Empty without gsettings, or when it fails (ibus is followed all the same).
func (b *ibus) list(ctx context.Context, engines []ibusEngine) []Item {
	out := []Item{}
	if b.gsettings == nil {
		return out
	}
	text, err := b.gsettings(ctx, "get", ibusGeneral, "preload-engines")
	if err != nil {
		return out
	}
	layouts := map[string]string{}
	for _, d := range engines {
		layouts[d.name] = d.layout
	}
	for _, name := range parseGVariantStrings(text) {
		out = append(out, Item{Name: name, Layout: layouts[name]})
	}
	return out
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

func (b *ibus) name() string { return FrameworkIBus }

func (b *ibus) set(ctx context.Context, name string) error {
	_, err := b.conn.Call(ctx, ibusName, ibusPath, ibusIface, "SetGlobalEngine", "s", name)
	return mapError(err)
}

// push keeps the items' engines in ibus's settings, which its panel and
// the next start read, then preloads them now (the PreloadEngines
// property). The setting goes first: the property's PropertiesChanged
// rereads the list from it, which would otherwise read the old one and
// show the push as an outside edit. An engine ibus doesn't have is
// refused before either (as the property would). ibus engines carry
// their layouts: defaultLayout and the items' layouts aren't ibus's.
func (b *ibus) push(ctx context.Context, _ string, items []Item, owner string) error {
	engines, err := b.engines(ctx, "Engines")
	if err != nil {
		return err
	}
	names := make([]string, 0, len(items))
	for _, it := range items {
		if !slices.ContainsFunc(engines, func(d ibusEngine) bool { return d.name == it.Name }) {
			return axerr.New(axerr.Failed, "ibus has no engine %s", it.Name)
		}
		names = append(names, it.Name)
	}
	// preload-engines is the system's own choice (the engines it offers)
	if err := b.setting(ctx, ibusGeneral, "preload-engines", gvariantStrings(names), owner, true); err != nil {
		return err
	}
	return mapError(b.conn.SetProperty(ctx, ibusName, ibusPath, ibusIface, "PreloadEngines", dbus.MakeVariant(names)))
}

// settings sets what ibus has of them: the candidate font.
func (b *ibus) settings(ctx context.Context, s Settings) error {
	if s.CandidateFont == nil {
		return nil
	}
	if *s.CandidateFont == "" {
		return b.setting(ctx, ibusPanel, "use-custom-font", "false", s.Owner, false)
	}
	if err := b.setting(ctx, ibusPanel, "custom-font", gvariantString(*s.CandidateFont), s.Owner, false); err != nil {
		return err
	}
	return b.setting(ctx, ibusPanel, "use-custom-font", "true", s.Owner, false)
}

// setting sets an ibus gsettings key, recorded first (what it held, what
// it's set to).
func (b *ibus) setting(ctx context.Context, schema, key, value, owner string, system bool) error {
	if b.gsettings == nil {
		return nil
	}
	id, err := b.ledger.Begin(footprint.Row{Kind: footprint.KindGSetting, Target: footprint.GSettingTarget(schema, key), Owner: owner, System: system},
		b.ledger.PriorGSetting(ctx, b.gsettings, schema, key))
	if err != nil {
		return axerr.Wrap(axerr.Failed, err, "recording gsettings %s %s", schema, key)
	}
	if _, err := b.gsettings(ctx, "set", schema, key, value); err != nil {
		return axerr.Wrap(axerr.Failed, err, "gsettings set %s %s", schema, key)
	}
	b.ledger.Done(id, footprint.Raw(value))
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

// parseGVariantStrings reads a string array in GVariant's text format, as
// gsettings prints it ("['xkb:us::eng', 'mozc-jp']", "@as []").
func parseGVariantStrings(text string) []string {
	out := []string{}
	for i := 0; i < len(text); i++ {
		q := text[i]
		if q != '\'' && q != '"' {
			continue
		}
		var b strings.Builder
		for i++; i < len(text) && text[i] != q; i++ {
			if text[i] == '\\' && i+1 < len(text) {
				i++
			}
			b.WriteByte(text[i])
		}
		out = append(out, b.String())
	}
	return out
}
