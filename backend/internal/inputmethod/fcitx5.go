package inputmethod

import (
	"context"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
)

// fcitx5's names (its dbus module's Controller1, verified on 5.1)
const (
	fcitxName       = "org.fcitx.Fcitx5"
	fcitxPath       = dbus.ObjectPath("/controller")
	fcitxController = "org.fcitx.Fcitx.Controller1"
	// Its StatusNotifierItem, on a connection of its own: Controller1 has
	// no signal for the input method changing, the item's icon does
	sniPath  = dbus.ObjectPath("/StatusNotifierItem")
	sniIface = "org.kde.StatusNotifierItem"
	// The tray's watcher, which fcitx5 registers that item with: only
	// while one runs (axiom's runs while a bar has a SystemTray)
	watcherName  = "org.kde.StatusNotifierWatcher"
	watcherPath  = dbus.ObjectPath("/StatusNotifierWatcher")
	watcherIface = "org.kde.StatusNotifierWatcher"

	// The configs SetConfig takes (fcitx5's dbusmodule)
	fcitxGlobalConfig    = "fcitx://config/global"
	fcitxClassicUIConfig = "fcitx://config/addon/classicui"
)

// fcitx is fcitx5 followed on the session bus.
type fcitx struct {
	conn *dbus.Conn
}

// followFcitx follows fcitx5 until it stops (again: look again), the
// setting changes (again) or the bus goes. A switch is heard through
// fcitx5's tray item; while it has none registered (no watcher runs) a
// Poll reads the current input method instead.
func (s *Service) followFcitx(ctx context.Context, conn *dbus.Conn, owners *dbus.Subscription) (bool, error) {
	var subs []*dbus.Subscription
	defer func() {
		for _, sub := range subs {
			sub.Close()
		}
	}()
	for _, m := range []dbus.Match{
		{Sender: fcitxName, Path: fcitxPath, Interface: fcitxController, Member: "InputMethodGroupsChanged"},
		// Every item's: fcitx5's is told apart by its process
		{Path: sniPath, Interface: sniIface},
		// The watcher coming, going, and items registering with it
		dbus.NameOwnerChanged(watcherName),
		{Sender: watcherName, Path: watcherPath, Interface: watcherIface},
	} {
		sub, err := conn.Subscribe(ctx, m)
		if err != nil {
			return false, err
		}
		subs = append(subs, sub)
	}
	signals := merge(append(subs, owners)...)
	defer signals.stop()

	f := &fcitx{conn: conn}
	s.setActive(f)
	// The process behind fcitx5's connections, and which items are its
	pid, _ := conn.ConnectionPID(ctx, fcitxName)
	items := map[string]bool{}
	ours := func(sender string) bool {
		known, ok := items[sender]
		if !ok {
			p, err := conn.ConnectionPID(ctx, sender)
			known = err == nil && pid != 0 && p == pid
			items[sender] = known
		}
		return known
	}
	// Whether the watcher lists an item of fcitx5's (an entry is the
	// item's bus name, with its path or not)
	tray := func() bool {
		v, err := conn.GetProperty(ctx, watcherName, watcherPath, watcherIface, "RegisteredStatusNotifierItems")
		if err != nil {
			return false
		}
		list, _ := v.Value.([]string)
		for _, entry := range list {
			name, _, _ := strings.Cut(entry, "/")
			if name != "" && ours(name) {
				return true
			}
		}
		return false
	}
	s.setTray(tray())
	defer s.setTray(false)
	read := func(all bool) error {
		st, err := f.read(ctx, all, s.State())
		if err != nil {
			return err
		}
		s.publish(st)
		return nil
	}
	if err := read(true); err != nil {
		if axerr.KindOf(err) == axerr.Unavailable {
			return true, nil
		}
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
			return false, conn.Err()
		case <-s.refresh:
			err = read(false)
		case <-s.poll:
			// No tray item tells of a switch: one is seen as a new current
			if s.hasTray() {
				continue
			}
			var current string
			var m *dbus.Message
			if m, err = f.call(ctx, "CurrentInputMethod"); err == nil {
				if err = m.Store(&current); err == nil && current != s.State().Current {
					err = read(false)
				}
			}
		case m := <-signals.C:
			switch {
			case m.Member == "NameOwnerChanged":
				var name, old, owner string
				if m.Store(&name, &old, &owner) != nil {
					continue
				}
				if name == watcherName {
					// A watcher came or went: fcitx5 registers with a new one
					s.setTray(tray())
					continue
				}
				if name != fcitxName {
					continue
				}
				// Gone, or replaced (fcitx5 -r): looked for again
				return true, nil
			case m.Interface == watcherIface:
				s.setTray(tray())
			case m.Interface == fcitxController:
				// The groups changed: their input methods may have too
				err = read(true)
			case m.Member == "NewIcon" || m.Member == "NewToolTip":
				if ours(m.Sender) {
					s.setTray(true)
					err = read(false)
				}
			}
		}
		if err != nil {
			if axerr.KindOf(err) == axerr.Unavailable {
				return true, nil
			}
			s.o.Log.Warn("input method: reading fcitx5", "err", err)
		}
	}
}

// read reads fcitx5's state: the current input method and group, and,
// when all, the input methods installed (else prev's).
func (f *fcitx) read(ctx context.Context, all bool, prev State) (State, error) {
	st := State{Framework: FrameworkFcitx, Running: true, Available: prev.Available}
	// Read empty (fcitx5 still loading its addons): again until it names some
	if all || len(st.Available) == 0 {
		m, err := f.call(ctx, "AvailableInputMethods")
		if err != nil {
			return State{}, err
		}
		var list []any
		if err := m.Store(&list); err != nil {
			return State{}, err
		}
		st.Available = []Engine{}
		for _, e := range list {
			// (uniqueName, name, nativeName, icon, label, languageCode, configurable)
			v, _ := e.([]any)
			if len(v) < 6 {
				continue
			}
			st.Available = append(st.Available, Engine{Name: str(v[0]), DisplayName: str(v[1]), Icon: str(v[3]), Label: str(v[4]), Lang: str(v[5])})
		}
	}
	m, err := f.call(ctx, "CurrentInputMethod")
	if err != nil {
		return State{}, err
	}
	if err := m.Store(&st.Current); err != nil {
		return State{}, err
	}
	m, err = f.call(ctx, "CurrentInputMethodGroup")
	if err != nil {
		return State{}, err
	}
	var group string
	if err := m.Store(&group); err != nil {
		return State{}, err
	}
	m, err = f.call(ctx, "FullInputMethodGroupInfo", "s", group)
	if err != nil {
		return State{}, err
	}
	// (name, defaultInputMethod, defaultLayout, properties, items)
	var name, def string
	var props map[string]dbus.Variant
	var items []any
	if err := m.Store(&name, &def, &st.DefaultLayout, &props, &items); err != nil {
		return State{}, err
	}
	st.Group = []Item{}
	for _, it := range items {
		// (uniqueName, name, nativeName, icon, label, languageCode, addon,
		// configurable, layout, properties)
		v, _ := it.([]any)
		if len(v) < 9 {
			continue
		}
		st.Group = append(st.Group, Item{Name: str(v[0]), Layout: str(v[8])})
	}
	return st, nil
}

func str(v any) string {
	s, _ := v.(string)
	return s
}

func (f *fcitx) call(ctx context.Context, member string, sigArgs ...any) (*dbus.Message, error) {
	sig := ""
	var args []any
	if len(sigArgs) > 0 {
		sig, args = sigArgs[0].(string), sigArgs[1:]
	}
	m, err := f.conn.Call(ctx, fcitxName, fcitxPath, fcitxController, member, sig, args...)
	return m, mapError(err)
}

func (f *fcitx) name() string { return FrameworkFcitx }

func (f *fcitx) set(ctx context.Context, name string) error {
	_, err := f.call(ctx, "SetCurrentIM", "s", name)
	return err
}

// push replaces the current group's input methods, and saves the profile
// (SetInputMethodGroupInfo saves it too: Save covers what fcitx5 keeps
// beside it).
func (f *fcitx) push(ctx context.Context, defaultLayout string, items []Item) error {
	m, err := f.call(ctx, "CurrentInputMethodGroup")
	if err != nil {
		return err
	}
	var group string
	if err := m.Store(&group); err != nil {
		return err
	}
	list := make([]any, 0, len(items))
	for _, it := range items {
		list = append(list, []any{it.Name, it.Layout})
	}
	if _, err := f.call(ctx, "SetInputMethodGroupInfo", "ssa(ss)", group, defaultLayout, list); err != nil {
		return err
	}
	_, err = f.call(ctx, "Save")
	return err
}

// settings sets the global config's and classicui's options asked for:
// SetConfig loads what it's given over the rest (a partial config).
func (f *fcitx) settings(ctx context.Context, s Settings) error {
	behavior := map[string]dbus.Variant{}
	if s.ShareState != nil {
		behavior["ShareInputState"] = dbus.MakeVariant(*s.ShareState)
	}
	if s.ShowSwitchPopup != nil {
		behavior["ShowInputMethodInformation"] = dbus.MakeVariant(fcitxBool(*s.ShowSwitchPopup))
	}
	ui := map[string]dbus.Variant{}
	if s.VerticalCandidates != nil {
		ui["Vertical Candidate List"] = dbus.MakeVariant(fcitxBool(*s.VerticalCandidates))
	}
	if s.CandidateFont != nil && *s.CandidateFont != "" {
		ui["Font"] = dbus.MakeVariant(*s.CandidateFont)
	}
	if len(behavior) > 0 {
		global := map[string]dbus.Variant{"Behavior": dbus.MakeVariant(behavior)}
		if _, err := f.call(ctx, "SetConfig", "sv", fcitxGlobalConfig, dbus.MakeVariant(global)); err != nil {
			return err
		}
	}
	if len(ui) > 0 {
		if _, err := f.call(ctx, "SetConfig", "sv", fcitxClassicUIConfig, dbus.MakeVariant(ui)); err != nil {
			return err
		}
	}
	return nil
}

// fcitxBool is a boolean as fcitx5's raw config writes it.
func fcitxBool(b bool) string {
	if b {
		return "True"
	}
	return "False"
}
