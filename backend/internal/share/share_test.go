package share

import (
	"reflect"
	"sort"
	"strconv"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// A user's own config: look, personal, commands and machine values that
// aren't the defaults.
const userConfig = `{"format": 2, "version": 76,
	"Appearance": {"theme": {"name": "nord"}, "wallpaper": {"mode": "rotate", "file": "file:///home/u/a.png", "folder": "~/walls"}},
	"WindowLook": {"gaps": {"inner": 9}},
	"Battery": {"lowThreshold": 12},
	"Weather": {"location": "Oslo"},
	"Apps": {"networkEditor": "foot"},
	"Compositor": {"mode": "managed"},
	"Idle": {"enabled": true},
	"Keybinds": {"binds": [
		{"id": "super-space", "key": "SUPER + space", "action": "launcher"},
		{"id": "mine", "key": "SUPER + T", "action": "exec", "argument": "foot"}
	]}}`

func has(v any, path string) bool {
	_, ok := at(v, strings.Split(path, "."))
	return ok
}

func value(v any, path string) any {
	got, _ := at(v, strings.Split(path, "."))
	return got
}

func bindIDs(v any) []string {
	arr, _ := value(v, "Keybinds.binds").(*jsonx.Array)
	ids := []string{}
	if arr != nil {
		for _, b := range arr.Items {
			id, _ := b.(*jsonx.Object).Value("id").(string)
			ids = append(ids, id)
		}
	}
	return ids
}

// A shared file holds the look; personal parts and commands only when
// asked for; machine values never.
func TestPickTakesScopes(t *testing.T) {
	t.Parallel()
	s := v2(t)
	cfg := filled(t, s, userConfig)
	for _, tc := range []struct {
		name    string
		carry   []string
		in, out []string
		binds   []string
	}{
		{"look", nil, []string{"Appearance.theme.name", "WindowLook.gaps", "Bars.items", "Appearance.wallpaper.transition", "Appearance.wallpaper.fill", "Appearance.wallpaper.parallax"}, []string{"Battery", "Weather", "Keybinds", "Apps.networkEditor", "Appearance.wallpaper.file", "Appearance.wallpaper.folder", "Appearance.wallpaper.mode"}, []string{}},
		{"personal", []string{"personal"}, []string{"Appearance.theme.name", "Keybinds.binds"}, []string{"Battery", "Apps.networkEditor"}, []string{"super-space"}},
		{"everything", Everything, []string{"Keybinds.binds", "Apps.networkEditor"}, []string{"Battery", "Weather.location", "Appearance.wallpaper.file", "Appearance.wallpaper.folder"}, []string{"super-space", "mine"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			picked := Pick(s, cfg, tc.carry, nil)
			for _, p := range tc.in {
				if !has(picked, p) {
					t.Errorf("%s left out", p)
				}
			}
			for _, p := range tc.out {
				if has(picked, p) {
					t.Errorf("%s taken: %s", p, jsonx.MarshalCompact(value(picked, p)))
				}
			}
			// An exec bind is a command (x-scopeIf)
			if got := bindIDs(picked); !reflect.DeepEqual(got, tc.binds) {
				t.Errorf("binds %v, want %v", got, tc.binds)
			}
		})
	}
}

// A takeover setting is never in a shared file, and loading one keeps the
// running value.
func TestTakeovers(t *testing.T) {
	t.Parallel()
	s := v2(t)
	var paths []string
	for _, p := range TakeoverPaths(s) {
		paths = append(paths, strings.Join(p, "."))
	}
	sort.Strings(paths)
	if want := []string{"Compositor.mode", "Greeter.enabled", "Idle.enabled", "Lockscreen.mode", "Polkit.enabled"}; !reflect.DeepEqual(paths, want) {
		t.Errorf("takeover paths %v", paths)
	}
	cfg := filled(t, s, userConfig)
	picked := Pick(s, cfg, Everything, nil)
	for _, p := range paths {
		if has(picked, p) {
			t.Errorf("%s shared", p)
		}
	}
	current := filled(t, s, `{"format": 2, "version": 76, "Compositor": {"mode": "detached"}}`)
	kept := KeepTakeovers(cfg, current, TakeoverPaths(s))
	if value(kept, "Compositor.mode") != "detached" || value(kept, "Idle.enabled") != false {
		t.Errorf("takeovers changed: %v %v", value(kept, "Compositor.mode"), value(kept, "Idle.enabled"))
	}
	if value(cfg, "Compositor.mode") != "managed" {
		t.Error("KeepTakeovers changed its input")
	}
	// A section missing on either side is left as it is (the store fills
	// the defaults' in)
	look, _ := jsonx.Unmarshal([]byte(`{"Battery": {}}`))
	if kept := KeepTakeovers(look, current, TakeoverPaths(s)); has(kept, "Idle") {
		t.Error("made a section the config lacks")
	}
	if kept := KeepTakeovers(cfg, look, TakeoverPaths(s)); value(kept, "Compositor.mode") != "managed" {
		t.Error("changed a takeover the current config lacks")
	}
}

// Applying replaces the parts the file holds and keeps the rest: machine
// values, and personal ones (an exec bind among them) unless asked for.
func TestApplyKeepsWhatIsntShared(t *testing.T) {
	t.Parallel()
	s := v2(t)
	user := filled(t, s, userConfig)
	example := filled(t, s, `{"format": 2, "version": 76,
		"Appearance": {"theme": {"name": "gruvbox-light"}},
		"Battery": {"lowThreshold": 40},
		"Keybinds": {"binds": [{"id": "theirs", "key": "SUPER + X", "action": "launcher"}]}}`)

	look := Apply(s, user, example, nil, nil)
	if value(look, "Appearance.theme.name") != "gruvbox-light" {
		t.Errorf("the theme wasn't taken: %v", value(look, "Appearance.theme.name"))
	}
	if value(look, "Battery.lowThreshold") != 12.0 || value(look, "Weather.location") != "Oslo" || value(look, "Appearance.wallpaper.file") != "file:///home/u/a.png" {
		t.Error("a machine value was replaced")
	}
	if got := bindIDs(look); !reflect.DeepEqual(got, []string{"super-space", "mine"}) {
		t.Errorf("binds without personal: %v", got)
	}

	personal := Apply(s, user, example, []string{"personal"}, nil)
	if got := bindIDs(personal); !reflect.DeepEqual(got, []string{"theirs", "mine"}) {
		t.Errorf("binds with personal (the user's exec bind kept): %v", got)
	}
	if value(personal, "Apps.networkEditor") != "foot" {
		t.Error("a command was taken without commands")
	}
	if errs := config.ValidationErrors(s, personal, s.Root()); len(errs) > 0 {
		t.Errorf("applied config invalid: %v", errs)
	}
}

// An export (Pick, then Sparse) imported (loaded: defaults filled, then
// applied) gives what applying the whole config would, onto the defaults
// and onto a user's own config. saved.Export relies on it.
func TestExportRoundTrips(t *testing.T) {
	t.Parallel()
	s := v2(t)
	cfg := filled(t, s, userConfig)
	defaults := filled(t, s, `{"format": 2, "version": 76}`)
	other := filled(t, s, `{"format": 2, "version": 76, "Battery": {"lowThreshold": 30}, "Apps": {"networkEditor": "alacritty"},
		"Keybinds": {"binds": [{"id": "x", "key": "SUPER + Y", "action": "exec", "argument": "y"}]}}`)
	for _, carry := range [][]string{nil, {"personal"}, Everything} {
		for name, base := range map[string]*jsonx.Object{"defaults": defaults, "other": other} {
			whole := Apply(s, base, cfg, carry, nil)
			file := Sparse(s, Pick(s, cfg, carry, nil))
			loaded, _ := config.ApplyDefaults(s, file, true, s.Root())
			if !jsonx.Equal(whole, Apply(s, base, loaded, carry, nil)) {
				t.Errorf("carry %v onto %s: the export applies differently", carry, name)
			}
		}
	}
}

// A snapshot holds the look, personal parts, commands and the wallpaper
// setup; restoring one (save → apply → WithSnapshot) brings those back and
// leaves the other machine settings.
func TestSnapshotRoundTrip(t *testing.T) {
	t.Parallel()
	s := v2(t)
	cfg := filled(t, s, userConfig)
	snap := Snapshot(s, cfg)
	if !has(snap, "Appearance.wallpaper.folder") || has(snap, "Battery") || has(snap, "Compositor.mode") {
		t.Errorf("snapshot holds the wrong parts: %s", jsonx.MarshalCompact(snap))
	}
	now := filled(t, s, `{"format": 2, "version": 76, "Battery": {"lowThreshold": 30}, "Appearance": {"wallpaper": {"file": "file:///home/u/b.png"}}}`)
	applied := Apply(s, now, snap, Everything, nil)

	restored := WithSnapshot(s, applied, snap, []string{"/home/u/a.png"})
	if value(restored, "Appearance.wallpaper.file") != "file:///home/u/a.png" || value(restored, "Appearance.wallpaper.mode") != "rotate" {
		t.Errorf("wallpaper setup: %s", jsonx.MarshalCompact(value(restored, "Appearance.wallpaper")))
	}
	if value(restored, "Battery.lowThreshold") != 30.0 || value(restored, "Appearance.theme.name") != "nord" || value(restored, "Apps.networkEditor") != "foot" {
		t.Error("machine settings weren't kept, or the look and commands not restored")
	}
	// A wallpaper whose file is gone keeps the current one
	missing := WithSnapshot(s, applied, snap, nil)
	if value(missing, "Appearance.wallpaper.file") != "file:///home/u/b.png" {
		t.Errorf("a missing file replaced the wallpaper: %v", value(missing, "Appearance.wallpaper.file"))
	}
}

func TestSnapshotPathsAndFiles(t *testing.T) {
	t.Parallel()
	s := v2(t)
	var paths []string
	for _, p := range SnapshotPaths(s) {
		paths = append(paths, strings.Join(p, "."))
	}
	sort.Strings(paths)
	want := []string{"Appearance.wallpaper.collection", "Appearance.wallpaper.file", "Appearance.wallpaper.folder", "Appearance.wallpaper.mode", "Appearance.wallpaper.perScreen", "Appearance.wallpaper.rotation", "Appearance.wallpaper.subfolders", "Appearance.wallpaper.variants"}
	if !reflect.DeepEqual(paths, want) {
		t.Errorf("snapshot paths %v", paths)
	}
	cfg := filled(t, s, `{"format": 2, "version": 76, "Appearance": {"wallpaper": {
		"file": "file:///home/u/my%20wall.png", "folder": "~/walls",
		"perScreen": {"DP-1": "file:///home/u/my%20wall.png", "DP-2": "file:///home/u/b.png", "DP-3": "https://x/c.png"}}}}`)
	if got := SnapshotFiles(s, cfg); !reflect.DeepEqual(got, []string{"/home/u/my wall.png", "/home/u/b.png"}) {
		t.Errorf("files %v", got)
	}
	if got := SnapshotFiles(s, jsonx.NewObject()); len(got) != 0 {
		t.Errorf("files of nothing: %v", got)
	}
}

func TestSparse(t *testing.T) {
	t.Parallel()
	s := v2(t)
	if got := jsonx.MarshalCompact(Sparse(s, filled(t, s, `{}`))); string(got) != `{}` {
		t.Errorf("sparse defaults: %s", got)
	}
	got := Sparse(s, filled(t, s, `{"Battery": {"lowThreshold": 12}}`))
	if string(jsonx.MarshalCompact(got)) != `{"Battery":{"lowThreshold":12}}` {
		t.Errorf("sparse: %s", jsonx.MarshalCompact(got))
	}
}

// Dropped names what a pick leaves out, at the highest place, by scope;
// places stay places once monitors is given, and a connector name not
// connected is left out.
func TestDropped(t *testing.T) {
	t.Parallel()
	s := v2(t)
	cfg := Sparse(s, filled(t, s, `{"format": 2,
		"Appearance": {"theme": {"name": "nord"}, "wallpaper": {"folder": "~/walls"}},
		"Apps": {"networkEditor": "foot"},
		"Compositor": {"mode": "managed"},
		"Keybinds": {"binds": [{"id": "mine", "key": "SUPER + T", "action": "exec", "argument": "foot"}]},
		"Bars": {"items": [{"id": "side", "screen": {"mode": "named", "names": ["#2", "DP-3"]}}]}}`))
	for _, tc := range []struct {
		name     string
		carry    []string
		monitors Monitors
		want     []string
	}{
		{"look", nil, nil, []string{"machine Appearance.wallpaper.folder", "commands Apps.networkEditor", "takeover Compositor.mode", "personal Keybinds.binds", "machine Bars.items[side].screen.names"}},
		{"places", nil, Monitors{}, []string{"machine Appearance.wallpaper.folder", "commands Apps.networkEditor", "takeover Compositor.mode", "personal Keybinds.binds", "machine Bars.items[side].screen.names[1]"}},
		{"personal", []string{"personal"}, Monitors{}, []string{"machine Appearance.wallpaper.folder", "commands Apps.networkEditor", "takeover Compositor.mode", "commands Keybinds.binds[mine]", "machine Bars.items[side].screen.names[1]"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got := []string{}
			for _, d := range Dropped(s, cfg, tc.carry, tc.monitors) {
				got = append(got, d.Scope+" "+d.Path)
			}
			if !reflect.DeepEqual(got, tc.want) {
				t.Errorf("dropped %v\nwant    %v", got, tc.want)
			}
			// Given monitors, Pick keeps the place it doesn't report
			picked := Pick(s, cfg, tc.carry, tc.monitors)
			if names := value(picked, "Bars.items"); tc.monitors != nil && !strings.Contains(string(jsonx.MarshalCompact(names)), `"names":["#2"]`) {
				t.Errorf("places: %s", jsonx.MarshalCompact(names))
			}
		})
	}
}

// A config holding a custom widget in each place a CustomWidget item can sit:
// a bar widget, and a module of an overlay page, the desktop and the lock
// screen (and a Clock beside each, which is look).
const customWidgetConfig = `{"format": 2, "version": 76,
	"CustomWidgets": {"items": [{"id": "mine", "name": "Mine", "command": "uptime"}]},
	"Bars": {"items": [{"id": "main", "screen": {"mode": "primary"}, "widgets": {
		"left": [{"id": "cw", "type": "CustomWidget", "properties": {"definition": "mine"}}, {"id": "time", "type": "Time"}]}}]},
	"Overlay": {"items": [{"id": "home", "type": "Custom", "name": "Home", "layout": {"modules": [
		{"id": "cwm", "type": "CustomWidget", "place": {"x": 0, "y": 0, "w": 4, "h": 2}, "properties": {"definition": "mine"}},
		{"id": "clock", "type": "Clock", "place": {"x": 4, "y": 0, "w": 3, "h": 3}}]}}]},
	"Desktop": {"items": [{"id": "primary", "screen": {"mode": "primary"}, "modules": [
		{"id": "cwd", "type": "CustomWidget", "place": {"x": 0, "y": 0, "w": 4, "h": 2}, "properties": {"definition": "mine"}},
		{"id": "clock", "type": "Clock", "place": {"x": 4, "y": 0, "w": 3, "h": 3}}]}]},
	"Lockscreen": {"layout": {"modules": [
		{"id": "cwl", "type": "CustomWidget", "place": {"x": 0, "y": 0, "w": 4, "h": 2}, "properties": {"definition": "mine"}},
		{"id": "clock", "type": "Clock", "place": {"x": 4, "y": 0, "w": 3, "h": 3}}]}}}`

// walk is the value at path, a number selecting an array's item
func walk(v any, path string) any {
	for _, key := range strings.Split(path, ".") {
		switch node := v.(type) {
		case *jsonx.Object:
			v, _ = node.Get(key)
		case *jsonx.Array:
			i, err := strconv.Atoi(key)
			if err != nil || i >= len(node.Items) {
				return nil
			}
			v = node.Items[i]
		default:
			return nil
		}
	}
	return v
}

// ids of the items of the array at path, by id
func idsAt(v any, path string) []string {
	arr, _ := walk(v, path).(*jsonx.Array)
	ids := []string{}
	if arr != nil {
		for _, item := range arr.Items {
			id, _ := item.(*jsonx.Object).Value("id").(string)
			ids = append(ids, id)
		}
	}
	return ids
}

// The arrays a custom widget item can sit in, and the ids it and its look
// neighbour have there.
var customWidgetPlaces = []struct {
	name, path, custom, look string
}{
	{"bar widgets", "Bars.items.0.widgets.left", "cw", "time"},
	{"overlay modules", "Overlay.items.0.layout.modules", "cwm", "clock"},
	{"desktop modules", "Desktop.items.0.modules", "cwd", "clock"},
	{"lock screen modules", "Lockscreen.layout.modules", "cwl", "clock"},
}

// A custom widget (a bar widget, or a module in the overlay, on the
// desktop or the lock screen) is personal: left out of a look-only share,
// reported as dropped, kept when personal is asked for. Its definition,
// the CustomWidgets section, is personal too.
func TestCustomWidgetsArePersonal(t *testing.T) {
	t.Parallel()
	s := v2(t)
	cfg := filled(t, s, customWidgetConfig)
	look := Pick(s, cfg, nil, nil)
	personal := Pick(s, cfg, []string{"personal"}, nil)
	dropped := map[string]string{}
	for _, d := range Dropped(s, cfg, nil, nil) {
		if strings.Contains(d.Path, "[cw") || strings.HasPrefix(d.Path, "CustomWidgets") {
			dropped[d.Path] = d.Scope
		}
	}
	for _, p := range customWidgetPlaces {
		if got := idsAt(look, p.path); !reflect.DeepEqual(got, []string{p.look}) {
			t.Errorf("%s in a look share: %v", p.name, got)
		}
		if got := idsAt(personal, p.path); !reflect.DeepEqual(got, []string{p.custom, p.look}) {
			t.Errorf("%s with personal: %v", p.name, got)
		}
		if !strings.Contains(strings.Join(mapKeys(dropped), " "), "["+p.custom+"]") {
			t.Errorf("%s: %s not reported as dropped: %v", p.name, p.custom, dropped)
		}
	}
	for path, scope := range dropped {
		if scope != "personal" {
			t.Errorf("%s dropped as %s", path, scope)
		}
	}
	if has(look, "CustomWidgets") || !has(personal, "CustomWidgets.items") {
		t.Error("the CustomWidgets section isn't personal")
	}
}

func mapKeys(m map[string]string) []string {
	keys := []string{}
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

// Applying a shared file onto a config keeps the user's own custom widget
// items (a shared file never carries one), and takes the file's look; with
// personal asked for, the file's custom widgets replace them.
func TestApplyKeepsOwnCustomWidgets(t *testing.T) {
	t.Parallel()
	s := v2(t)
	user := filled(t, s, customWidgetConfig)
	shared := filled(t, s, `{"format": 2, "version": 76,
		"Bars": {"items": [{"id": "main", "screen": {"mode": "primary"}, "widgets": {"left": [{"id": "time", "type": "Time", "properties": {"showSeconds": true}}]}}]},
		"Overlay": {"items": [{"id": "home", "type": "Custom", "name": "Home", "layout": {"modules": [{"id": "theirs", "type": "Clock", "place": {"x": 0, "y": 0, "w": 3, "h": 3}}]}}]},
		"Desktop": {"items": [{"id": "primary", "screen": {"mode": "primary"}, "modules": [{"id": "theirs", "type": "Clock", "place": {"x": 0, "y": 0, "w": 3, "h": 3}}]}]},
		"Lockscreen": {"layout": {"modules": [{"id": "theirs", "type": "Clock", "place": {"x": 0, "y": 0, "w": 3, "h": 3}}]}}}`)
	applied := Apply(s, user, shared, nil, nil)
	for _, p := range customWidgetPlaces {
		got := idsAt(applied, p.path)
		if !contains(got, p.custom) {
			t.Errorf("%s: the user's custom widget lost: %v", p.name, got)
		}
	}
	if len(idsAt(applied, "CustomWidgets.items")) != 1 {
		t.Error("the user's definitions changed")
	}
	if errs := config.ValidationErrors(s, applied, s.Root()); len(errs) > 0 {
		t.Errorf("applied config invalid: %v", errs)
	}
}

func contains(list []string, want string) bool {
	for _, s := range list {
		if s == want {
			return true
		}
	}
	return false
}
