package share

import (
	"reflect"
	"sort"
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
	"Apps": {"terminal": "foot"},
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
		{"look", nil, []string{"Appearance.theme.name", "WindowLook.gaps", "Bars.items"}, []string{"Battery", "Weather", "Keybinds", "Apps.terminal", "Appearance.wallpaper"}, []string{}},
		{"personal", []string{"personal"}, []string{"Appearance.theme.name", "Keybinds.binds"}, []string{"Battery", "Apps.terminal"}, []string{"super-space"}},
		{"everything", Everything, []string{"Keybinds.binds", "Apps.terminal"}, []string{"Battery", "Weather.location", "Appearance.wallpaper"}, []string{"super-space", "mine"}},
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
	if value(personal, "Apps.terminal") != "foot" {
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
	other := filled(t, s, `{"format": 2, "version": 76, "Battery": {"lowThreshold": 30}, "Apps": {"terminal": "alacritty"},
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
	if value(restored, "Battery.lowThreshold") != 30.0 || value(restored, "Appearance.theme.name") != "nord" || value(restored, "Apps.terminal") != "foot" {
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
	want := []string{"Appearance.wallpaper.file", "Appearance.wallpaper.folder", "Appearance.wallpaper.mode", "Appearance.wallpaper.perScreen", "Appearance.wallpaper.rotation", "Appearance.wallpaper.variants"}
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
