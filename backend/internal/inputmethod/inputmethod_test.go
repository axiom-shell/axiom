package inputmethod

import (
	"context"
	"log/slog"
	"reflect"
	"slices"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

func dial(t *testing.T, bus *dbustest.Bus) *dbus.Conn {
	t.Helper()
	conn, err := dbus.Dial(t.Context(), bus.Address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	return conn
}

// fakeFcitx is fcitx5 on a test bus: Controller1's methods the service
// calls, and its StatusNotifierItem on a second connection.
type fakeFcitx struct {
	conn, sni *dbus.Conn

	mu            sync.Mutex
	current       string
	defaultLayout string
	group         []Item
	calls         []string
	configs       map[string]dbus.Variant
}

func newFakeFcitx(t *testing.T, bus *dbustest.Bus) *fakeFcitx {
	t.Helper()
	f := &fakeFcitx{
		conn: dial(t, bus), sni: dial(t, bus),
		current: "keyboard-us", defaultLayout: "us",
		group:   []Item{{"keyboard-us", ""}, {"mozc", ""}},
		configs: map[string]dbus.Variant{},
	}
	none := func(fn func(m *dbus.Message) []any) func(context.Context, *dbus.Message) ([]any, error) {
		return func(_ context.Context, m *dbus.Message) ([]any, error) {
			f.mu.Lock()
			defer f.mu.Unlock()
			f.calls = append(f.calls, m.Member)
			return fn(m), nil
		}
	}
	if _, err := f.conn.Export(fcitxPath, dbus.Interface{Name: fcitxController, Methods: map[string]dbus.Method{
		"CurrentInputMethod":      {Out: "s", Fn: none(func(*dbus.Message) []any { return []any{f.current} })},
		"CurrentInputMethodGroup": {Out: "s", Fn: none(func(*dbus.Message) []any { return []any{"Default"} })},
		"AvailableInputMethods": {Out: "a(ssssssb)", Fn: none(func(*dbus.Message) []any {
			return []any{[]any{
				[]any{"keyboard-us", "Keyboard - English (US)", "", "input-keyboard", "en", "en", true},
				[]any{"mozc", "Mozc", "", "fcitx_mozc", "あ", "ja", true},
				[]any{"keyboard-de", "Keyboard - German", "", "input-keyboard", "de", "de", true},
			}}
		})},
		"FullInputMethodGroupInfo": {In: "s", Out: "sssa{sv}a(sssssssbsa{sv})", Fn: none(func(*dbus.Message) []any {
			items := []any{}
			for _, it := range f.group {
				items = append(items, []any{it.Name, it.Name, "", "icon", "label", "en", "addon", true, it.Layout, map[string]dbus.Variant{}})
			}
			return []any{"Default", "mozc", f.defaultLayout, map[string]dbus.Variant{}, items}
		})},
		"SetCurrentIM": {In: "s", Fn: none(func(m *dbus.Message) []any {
			f.current = m.Body[0].(string)
			// As fcitx5: its item's icon changes, nothing on Controller1
			f.sni.Emit(sniPath, sniIface, "NewIcon", "")
			return nil
		})},
		"SetInputMethodGroupInfo": {In: "ssa(ss)", Fn: none(func(m *dbus.Message) []any {
			f.defaultLayout = m.Body[1].(string)
			f.group = nil
			for _, it := range m.Body[2].([]any) {
				v := it.([]any)
				f.group = append(f.group, Item{v[0].(string), v[1].(string)})
			}
			// As fcitx5 5.1: only its tray menu tells (seen on a real one)
			f.menuChanged()
			return nil
		})},
		"Save": {Fn: none(func(*dbus.Message) []any { return nil })},
		"SetConfig": {In: "sv", Fn: none(func(m *dbus.Message) []any {
			f.configs[m.Body[0].(string)] = m.Body[1].(dbus.Variant)
			return nil
		})},
	}}); err != nil {
		t.Fatal(err)
	}
	if _, err := f.conn.RequestName(t.Context(), fcitxName, dbus.NameDoNotQueue); err != nil {
		t.Fatal(err)
	}
	return f
}

// editOutside changes the group as fcitx5-configtool would.
func (f *fakeFcitx) editOutside(group []Item) {
	f.mu.Lock()
	f.group = group
	f.mu.Unlock()
	f.menuChanged()
}

// menuChanged is what fcitx5 5.1 sends when its group changes, by
// SetInputMethodGroupInfo or its config tool: its tray menu's
// LayoutUpdated, nothing on Controller1.
func (f *fakeFcitx) menuChanged() {
	f.sni.Emit(menuPath, menuIface, "LayoutUpdated", "ui", uint32(1), int32(0))
}

func (f *fakeFcitx) took(member string) bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	return slices.Contains(f.calls, member)
}

// testLog writes the service's log to the test's.
type testLog struct{ t *testing.T }

func (l testLog) Write(p []byte) (int, error) {
	l.t.Log(string(p))
	return len(p), nil
}

type harness struct {
	s *Service

	mu        sync.Mutex
	gsettings [][]string
	// stored is what the fake gsettings holds, by "schema key"
	stored map[string]string
	// outsideEdits counts the states published with OutsideEdit
	outsideEdits int
}

func (h *harness) settingsRun() [][]string {
	h.mu.Lock()
	defer h.mu.Unlock()
	return slices.Clone(h.gsettings)
}

func start(t *testing.T, session *dbustest.Bus, ibusAddr func() string) *harness {
	t.Helper()
	h := &harness{stored: map[string]string{ibusGeneral + " preload-engines": "['xkb:us::eng']"}}
	if ibusAddr == nil {
		ibusAddr = func() string { return "" }
	}
	h.s = New(Options{
		SessionBus: func(ctx context.Context) (*dbus.Conn, error) {
			return dbus.Dial(ctx, session.Address, dbus.Options{})
		},
		IBusAddress: ibusAddr,
		GSettings: func(_ context.Context, args ...string) (string, error) {
			if args[0] == "set" {
				// A process: slower than a D-Bus round trip
				time.Sleep(20 * time.Millisecond)
			}
			h.mu.Lock()
			defer h.mu.Unlock()
			if args[0] == "get" {
				return h.stored[args[1]+" "+args[2]] + "\n", nil
			}
			h.gsettings = append(h.gsettings, args)
			h.stored[args[1]+" "+args[2]] = args[3]
			return "", nil
		},
		OnChange: func(st State) {
			if st.OutsideEdit {
				h.mu.Lock()
				h.outsideEdits++
				h.mu.Unlock()
			}
		},
		Retry: 20 * time.Millisecond,
		Log:   slog.New(slog.NewTextHandler(testLog{t}, &slog.HandlerOptions{Level: slog.LevelDebug})),
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

func (h *harness) await(t *testing.T, what string, cond func(State) bool) State {
	t.Helper()
	var st State
	if !testkit.Eventually(func() bool {
		st = h.s.State()
		return cond(st)
	}) {
		t.Fatalf("%s: never; the state is %+v", what, st)
	}
	return st
}

func TestFcitx(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	f := newFakeFcitx(t, bus)
	h := start(t, bus, nil)
	st := h.await(t, "fcitx5 is followed", func(st State) bool { return st.Running })
	want := State{
		Framework: FrameworkFcitx, Running: true, Current: "keyboard-us", DefaultLayout: "us",
		Group: []Item{{"keyboard-us", ""}, {"mozc", ""}},
		Available: []Engine{
			{Name: "keyboard-us", Label: "en", DisplayName: "Keyboard - English (US)", Icon: "input-keyboard", Lang: "en"},
			{Name: "mozc", Label: "あ", DisplayName: "Mozc", Icon: "fcitx_mozc", Lang: "ja"},
			{Name: "keyboard-de", Label: "de", DisplayName: "Keyboard - German", Icon: "input-keyboard", Lang: "de"},
		},
	}
	if !reflect.DeepEqual(st, want) {
		t.Fatalf("state\n%+v\nwant\n%+v", st, want)
	}

	// A switch is heard through the item's NewIcon
	if err := h.s.Set(t.Context(), "mozc"); err != nil {
		t.Fatal(err)
	}
	h.await(t, "the switch", func(st State) bool { return st.Current == "mozc" })
	f.mu.Lock()
	f.current = "keyboard-us"
	f.mu.Unlock()
	f.sni.Emit(sniPath, sniIface, "NewToolTip", "")
	h.await(t, "a switch made in fcitx5", func(st State) bool { return st.Current == "keyboard-us" })

	// Not edited outside before axiom pushed a list
	f.editOutside([]Item{{"keyboard-us", ""}})
	h.await(t, "the group read again", func(st State) bool { return len(st.Group) == 1 && !st.OutsideEdit })

	items := []Item{{"keyboard-de", ""}, {"mozc", "de"}}
	if err := h.s.Push(t.Context(), "de", items); err != nil {
		t.Fatal(err)
	}
	st = h.await(t, "the push", func(st State) bool { return st.DefaultLayout == "de" })
	if !reflect.DeepEqual(st.Group, items) || st.OutsideEdit {
		t.Errorf("after the push: %+v", st)
	}
	if !f.took("Save") {
		t.Error("the push didn't save the profile")
	}
	f.editOutside([]Item{{"keyboard-de", ""}})
	h.await(t, "an outside edit", func(st State) bool { return st.OutsideEdit })
	if err := h.s.Push(t.Context(), "de", items); err != nil {
		t.Fatal(err)
	}
	h.await(t, "pushed again", func(st State) bool { return !st.OutsideEdit && len(st.Group) == 2 })

	share, on, font := "All", true, "Noto Sans CJK JP 12"
	if err := h.s.Configure(t.Context(), Settings{ShareState: &share, VerticalCandidates: &on, CandidateFont: &font}); err != nil {
		t.Fatal(err)
	}
	f.mu.Lock()
	configs := f.configs
	f.mu.Unlock()
	wantGlobal := dbus.MakeVariant(map[string]dbus.Variant{"Behavior": dbus.MakeVariant(map[string]dbus.Variant{"ShareInputState": dbus.MakeVariant("All")})})
	wantUI := dbus.MakeVariant(map[string]dbus.Variant{"Vertical Candidate List": dbus.MakeVariant("True"), "Font": dbus.MakeVariant(font)})
	if !reflect.DeepEqual(configs[fcitxGlobalConfig], wantGlobal) || !reflect.DeepEqual(configs[fcitxClassicUIConfig], wantUI) {
		t.Errorf("SetConfig got %v", configs)
	}
	bad := "Sometimes"
	if err := h.s.Configure(t.Context(), Settings{ShareState: &bad}); axerr.KindOf(err) != axerr.BadRequest {
		t.Errorf("a bad shareState: %v", err)
	}

	// fcitx5 quitting
	f.conn.Close()
	h.await(t, "fcitx5 gone", func(st State) bool { return !st.Running && st.Framework == "" })
	if err := h.s.Set(t.Context(), "mozc"); axerr.KindOf(err) != axerr.Unavailable {
		t.Errorf("a switch with none running: %v", err)
	}
}

// count is how many times member was called.
func (f *fakeFcitx) count(member string) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	n := 0
	for _, c := range f.calls {
		if c == member {
			n++
		}
	}
	return n
}

// startWatcher runs a tray's StatusNotifierWatcher listing fcitx5's item,
// as fcitx5 registers it once one runs.
func startWatcher(t *testing.T, bus *dbustest.Bus, f *fakeFcitx) *dbus.Conn {
	t.Helper()
	w := dial(t, bus)
	if _, err := w.Export(watcherPath, dbus.Interface{Name: "org.freedesktop.DBus.Properties", Methods: map[string]dbus.Method{
		"Get": {In: "ss", Out: "v", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			if m.Body[1].(string) != "RegisteredStatusNotifierItems" {
				return nil, dbus.NewError(dbus.ErrInvalidArgs, "no property")
			}
			return []any{dbus.MakeVariant([]string{f.sni.UniqueName() + string(sniPath)})}, nil
		}},
	}}); err != nil {
		t.Fatal(err)
	}
	if _, err := w.RequestName(t.Context(), watcherName, dbus.NameDoNotQueue); err != nil {
		t.Fatal(err)
	}
	return w
}

// Without a tray item fcitx5 tells of no switch: Poll reads its current
// input method; with one, Poll reads nothing (its signals do)
func TestFcitxPollsWithoutTrayItem(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	f := newFakeFcitx(t, bus)
	h := start(t, bus, nil)
	h.await(t, "fcitx5 is followed", func(st State) bool { return st.Running && st.Current == "keyboard-us" })

	// A switch made in fcitx5, no signal sent
	f.mu.Lock()
	f.current = "mozc"
	f.mu.Unlock()
	if !testkit.Eventually(func() bool { return h.s.Poll().Polling && h.s.State().Current == "mozc" }) {
		t.Fatalf("no tray item: the poll never saw the switch; the state is %+v", h.s.State())
	}
	// A group edit made in fcitx5, no tray menu to tell of it
	f.mu.Lock()
	f.group = []Item{{"keyboard-us", ""}}
	f.mu.Unlock()
	if !testkit.Eventually(func() bool { return h.s.Poll().Polling && len(h.s.State().Group) == 1 }) {
		t.Fatalf("no tray item: the poll never saw the group edit; the state is %+v", h.s.State())
	}

	w := startWatcher(t, bus, f)
	if !testkit.Eventually(func() bool { return !h.s.Poll().Polling }) {
		t.Fatal("a tray item registered: still polling")
	}
	before := f.count("CurrentInputMethod")
	f.mu.Lock()
	f.current = "keyboard-us"
	f.mu.Unlock()
	for range 5 {
		h.s.Poll()
		time.Sleep(10 * time.Millisecond)
	}
	if n := f.count("CurrentInputMethod"); n != before || h.s.State().Current != "mozc" {
		t.Errorf("with a tray item: %d reads polled, the state %+v", n-before, h.s.State())
	}

	// The watcher gone: fcitx5's item with it
	w.Close()
	if !testkit.Eventually(func() bool { return h.s.Poll().Polling && h.s.State().Current == "keyboard-us" }) {
		t.Fatalf("the watcher gone: the poll never saw the switch; the state is %+v", h.s.State())
	}
}

func TestPushRefusesBadLists(t *testing.T) {
	t.Parallel()
	s := New(Options{})
	for _, items := range [][]Item{nil, {{"", "us"}}, {{"mozc", ""}, {"mozc", "de"}}} {
		if err := s.Push(t.Context(), "us", items); axerr.KindOf(err) != axerr.BadRequest {
			t.Errorf("%v: %v", items, err)
		}
	}
	if err := s.SetFramework("uim"); axerr.KindOf(err) != axerr.BadRequest {
		t.Errorf("framework uim: %v", err)
	}
}

func TestFrameworkNone(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	newFakeFcitx(t, bus)
	h := start(t, bus, nil)
	h.await(t, "fcitx5 is followed", func(st State) bool { return st.Running })
	if err := h.s.SetFramework(FrameworkNone); err != nil {
		t.Fatal(err)
	}
	h.await(t, "none followed", func(st State) bool { return !st.Running })
	if err := h.s.SetFramework(FrameworkIBus); err != nil {
		t.Fatal(err)
	}
	h.await(t, "ibus asked for, none running", func(st State) bool { return st.Framework == FrameworkIBus && !st.Running })
	if err := h.s.SetFramework(FrameworkAuto); err != nil {
		t.Fatal(err)
	}
	h.await(t, "fcitx5 again", func(st State) bool { return st.Running && st.Framework == FrameworkFcitx })
}

// desc is a serialized IBusEngineDesc.
func desc(name, longName, lang, layout, symbol string) dbus.Variant {
	return dbus.Variant{Sig: descSig, Value: []any{"IBusEngineDesc", map[string]dbus.Variant{}, name, longName, "", lang, "GPL", "me", "icon-" + name, layout, uint32(0), "", symbol, "", "", "", "", "", ""}}
}

const descSig = "(sa{sv}ssssssssussssssss)"

// fakeIBus is ibus-daemon on its own test bus.
type fakeIBus struct {
	conn *dbus.Conn

	mu      sync.Mutex
	engines map[string]dbus.Variant
	global  string
}

func newFakeIBus(t *testing.T, bus *dbustest.Bus) *fakeIBus {
	t.Helper()
	f := &fakeIBus{conn: dial(t, bus), engines: map[string]dbus.Variant{
		"xkb:us::eng": desc("xkb:us::eng", "English (US)", "en", "us", ""),
		"mozc-jp":     desc("mozc-jp", "Mozc", "ja", "default", "あ"),
	}}
	list := func(names []string) dbus.Variant {
		out := []any{}
		for _, n := range names {
			out = append(out, f.engines[n])
		}
		return dbus.Variant{Sig: "av", Value: out}
	}
	if _, err := f.conn.Export(ibusPath, dbus.Interface{Name: ibusIface, Methods: map[string]dbus.Method{
		"SetGlobalEngine": {In: "s", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			f.mu.Lock()
			f.global = m.Body[0].(string)
			f.mu.Unlock()
			f.conn.Emit(ibusPath, ibusIface, "GlobalEngineChanged", "s", f.global)
			return nil, nil
		}},
	}}); err != nil {
		t.Fatal(err)
	}
	if _, err := f.conn.Export(ibusPath, dbus.Interface{Name: "org.freedesktop.DBus.Properties", Methods: map[string]dbus.Method{
		"Get": {In: "ss", Out: "v", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			f.mu.Lock()
			defer f.mu.Unlock()
			switch m.Body[1].(string) {
			case "Engines":
				return []any{list([]string{"mozc-jp", "xkb:us::eng"})}, nil
			case "ActiveEngines":
				// The engines of components registered at runtime: none
				return []any{list(nil)}, nil
			case "GlobalEngine":
				if f.global == "" {
					return nil, dbus.NewError(dbus.ErrFailed, "No global engine.")
				}
				return []any{dbus.Variant{Sig: "v", Value: f.engines[f.global]}}, nil
			}
			return nil, dbus.NewError(dbus.ErrInvalidArgs, "no property")
		}},
		"Set": {In: "ssv", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			names := m.Body[2].(dbus.Variant).Value.([]string)
			f.mu.Lock()
			for _, n := range names {
				if _, ok := f.engines[n]; !ok {
					f.mu.Unlock()
					return nil, dbus.NewError(dbus.ErrFailed, "Cannot find engine %s.", n)
				}
			}
			f.mu.Unlock()
			f.conn.Emit(ibusPath, "org.freedesktop.DBus.Properties", "PropertiesChanged", "sa{sv}as", ibusIface, map[string]dbus.Variant{}, []string{"PreloadEngines"})
			return nil, nil
		}},
	}}); err != nil {
		t.Fatal(err)
	}
	if _, err := f.conn.RequestName(t.Context(), ibusName, dbus.NameDoNotQueue); err != nil {
		t.Fatal(err)
	}
	return f
}

func TestIBus(t *testing.T) {
	t.Parallel()
	session, private := dbustest.New(t), dbustest.New(t)
	f := newFakeIBus(t, private)
	h := start(t, session, func() string { return private.Address })
	st := h.await(t, "ibus is followed", func(st State) bool { return st.Running })
	want := State{
		Framework: FrameworkIBus, Running: true, Current: "",
		Group: []Item{{"xkb:us::eng", "us"}},
		Available: []Engine{
			{Name: "mozc-jp", Label: "あ", DisplayName: "Mozc", Icon: "icon-mozc-jp", Lang: "ja"},
			{Name: "xkb:us::eng", Label: "en", DisplayName: "English (US)", Icon: "icon-xkb:us::eng", Lang: "en"},
		},
	}
	if !reflect.DeepEqual(st, want) {
		t.Fatalf("state\n%+v\nwant\n%+v", st, want)
	}
	if err := h.s.Set(t.Context(), "mozc-jp"); err != nil {
		t.Fatal(err)
	}
	h.await(t, "the switch", func(st State) bool { return st.Current == "mozc-jp" })

	if err := h.s.Push(t.Context(), "us", []Item{{"xkb:us::eng", ""}, {"mozc-jp", ""}}); err != nil {
		t.Fatal(err)
	}
	st = h.await(t, "the push", func(st State) bool { return len(st.Group) == 2 })
	// Not even for a moment: the PropertiesChanged the push causes rereads
	// the setting, written before it
	h.mu.Lock()
	edits := h.outsideEdits
	h.mu.Unlock()
	if st.OutsideEdit || edits > 0 {
		t.Errorf("the push reads as an outside edit (%d times): %+v", edits, st)
	}
	wantSet := [][]string{{"set", ibusGeneral, "preload-engines", "['xkb:us::eng', 'mozc-jp']"}}
	if got := h.settingsRun(); !reflect.DeepEqual(got, wantSet) {
		t.Errorf("gsettings %v, want %v", got, wantSet)
	}
	if st.Group[1] != (Item{"mozc-jp", ""}) {
		t.Errorf("the list read back: %+v", st.Group)
	}
	// ibus-setup edits the list: its panel preloads it
	h.mu.Lock()
	h.stored[ibusGeneral+" preload-engines"] = "['mozc-jp']"
	h.mu.Unlock()
	f.conn.Emit(ibusPath, "org.freedesktop.DBus.Properties", "PropertiesChanged", "sa{sv}as", ibusIface, map[string]dbus.Variant{}, []string{"PreloadEngines"})
	h.await(t, "the outside edit", func(st State) bool { return st.OutsideEdit && len(st.Group) == 1 })
	if err := h.s.Push(t.Context(), "us", []Item{{"pinyin", ""}}); axerr.KindOf(err) != axerr.Failed {
		t.Errorf("an engine ibus lacks: %v", err)
	}

	font := "Sans 12"
	if err := h.s.Configure(t.Context(), Settings{CandidateFont: &font}); err != nil {
		t.Fatal(err)
	}
	wantSet = append(wantSet, []string{"set", ibusPanel, "custom-font", "'Sans 12'"}, []string{"set", ibusPanel, "use-custom-font", "true"})
	if got := h.settingsRun(); !reflect.DeepEqual(got, wantSet) {
		t.Errorf("gsettings %v, want %v", got, wantSet)
	}

	// fcitx5 starting wins; ibus's list pushed last is no outside edit of
	// fcitx5's
	newFakeFcitx(t, session)
	st = h.await(t, "fcitx5 takes over", func(st State) bool { return st.Framework == FrameworkFcitx && st.Running })
	if st.OutsideEdit {
		t.Errorf("the list pushed to ibus reads as an outside edit of fcitx5's: %+v", st)
	}
}

func TestIBusAddressFile(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		env  map[string]string
		want string
	}{
		{map[string]string{"HOME": "/h", "WAYLAND_DISPLAY": "wayland-1", "DISPLAY": ":0"}, "/h/.config/ibus/bus/id-unix-wayland-1"},
		{map[string]string{"HOME": "/h", "DISPLAY": ":0"}, "/h/.config/ibus/bus/id-unix-0"},
		{map[string]string{"HOME": "/h", "DISPLAY": "box:1.0"}, "/h/.config/ibus/bus/id-box-1"},
		{map[string]string{"XDG_CONFIG_HOME": "/c"}, "/c/ibus/bus/id-unix-0"},
		{map[string]string{}, ""},
	} {
		if got := ibusAddressFile(func(k string) string { return tc.env[k] }, "id"); got != tc.want {
			t.Errorf("%v: %q, want %q", tc.env, got, tc.want)
		}
	}
	addr, pid := parseIBusAddressFile([]byte("# This file is created by ibus-daemon, please do not modify it.\nIBUS_ADDRESS=unix:path=/home/me/.cache/ibus/dbus-x,guid=abc\nIBUS_DAEMON_PID=1234\n"))
	if addr != "unix:path=/home/me/.cache/ibus/dbus-x,guid=abc" || pid != 1234 {
		t.Errorf("parsed %q %d", addr, pid)
	}
	if _, pid := parseIBusAddressFile([]byte("IBUS_ADDRESS=x\n")); pid != -1 {
		t.Errorf("no pid line: %d", pid)
	}
}

func TestGVariantStrings(t *testing.T) {
	t.Parallel()
	if got := gvariantStrings([]string{"a", `it's`, `b\c`}); got != `['a', 'it\'s', 'b\\c']` {
		t.Errorf("got %s", got)
	}
	for text, want := range map[string][]string{
		"['xkb:us::eng', 'mozc-jp']\n": {"xkb:us::eng", "mozc-jp"},
		"@as []\n":                     {},
		`['it\'s', "b\\c"]`:            {"it's", `b\c`},
	} {
		if got := parseGVariantStrings(text); !reflect.DeepEqual(got, want) {
			t.Errorf("%q: got %q, want %q", text, got, want)
		}
	}
}
