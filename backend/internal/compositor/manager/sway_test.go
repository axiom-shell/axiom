package manager

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
)

// A sway config file that's there but can't be read (here an include) is
// the Runtime problem, as a missing config is: axiom's binds may cover
// keys it holds
func TestSwayUnreadableIncludeIsUnread(t *testing.T) {
	t.Parallel()
	tables, schema := repo(t)
	home := t.TempDir()
	conf := filepath.Join(home, ".config", "sway")
	if err := os.MkdirAll(conf, 0o755); err != nil {
		t.Fatal(err)
	}
	for name, text := range map[string]string{"config": "include keys.conf\n", "keys.conf": "bindsym Mod4+a exec a\n"} {
		if err := os.WriteFile(filepath.Join(conf, name), []byte(text), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	vars := map[string]string{"HOME": home, "XDG_CONFIG_HOME": filepath.Join(home, ".config")}
	w := newSway(env2(tables, schema, func(k string) string { return vars[k] }), nil)
	w.userBinds()
	if w.unread != "" {
		t.Fatalf("readable config reported unread: %q", w.unread)
	}
	if err := os.Chmod(filepath.Join(conf, "keys.conf"), 0); err != nil {
		t.Fatal(err)
	}
	if _, err := os.ReadFile(filepath.Join(conf, "keys.conf")); err == nil {
		t.Skip("running as root: every file is readable")
	}
	w.userBinds()
	if !strings.Contains(w.unread, "keys.conf") {
		t.Fatalf("unread = %q, want it to name keys.conf", w.unread)
	}
}

// sway's include and autostart go into the config sway runs; one that
// isn't the managed path blocks managed (its file would never load), and
// one in i3's folder gets a note that i3 would read axiom's lines too
func TestSwayTargetsTheConfigSwayRuns(t *testing.T) {
	t.Parallel()
	tables, schema := repo(t)
	home := t.TempDir()
	vars := map[string]string{"HOME": home, "XDG_CONFIG_HOME": filepath.Join(home, ".config")}
	w := newSway(env2(tables, schema, func(k string) string { return vars[k] }), nil)
	managed := filepath.Join(home, ".config", "sway", "config")
	i3 := filepath.Join(home, ".config", "i3", "config")
	check := func(target, elsewhere string) {
		t.Helper()
		f := w.files(Inputs{})
		if got := f.IncludeTarget.Value("file"); got != target {
			t.Fatalf("include target %v, want %s", got, target)
		}
		if got := f.AutostartTarget.Value("file"); got != target {
			t.Fatalf("autostart target %v, want %s", got, target)
		}
		if f.RunsElsewhere != elsewhere {
			t.Fatalf("runs elsewhere %q, want %q", f.RunsElsewhere, elsewhere)
		}
		if got := strings.Contains(f.IncludeTarget.Value("note").(string), "i3's folder"); got != (target == i3) {
			t.Fatalf("include note names i3: %v, want %v", got, target == i3)
		}
	}
	// None of the user's yet: the managed path
	check(managed, "")
	os.MkdirAll(filepath.Dir(i3), 0o755)
	os.WriteFile(i3, []byte("bindsym Mod4+a exec a\n"), 0o644)
	check(i3, i3)
	// sway looks in sway/ before i3/
	os.MkdirAll(filepath.Dir(managed), 0o755)
	os.WriteFile(managed, []byte("# mine\n"), 0o644)
	check(managed, "")
}

// The monitor-conflict check sees an output line by every name sway takes
// (bare, double- or single-quoted) and the block form, not other settings
func TestSwayMonitorPattern(t *testing.T) {
	t.Parallel()
	pattern, _ := (&swayWriter{}).monitorPattern()
	for line, want := range map[string]bool{
		`output DP-1 mode 1920x1080`:                        true,
		`output "Dell Inc. DELL U2720Q 123" mode 3840x2160`: true,
		`output DP-1 {`:                             true,
		`output 'LG 27' pos 0 0`:                    true,
		`  output "Dell Inc. DELL U2720Q 123" {`:    true,
		`output * bg ~/wall.png fill`:               false,
		`# output DP-1 mode 1920x1080`:              false,
		`bindsym $mod+o output DP-1 mode 1920x1080`: false,
	} {
		if got := pattern.MatchString(line); got != want {
			t.Errorf("%q: matched %v, want %v", line, got, want)
		}
	}
}

// The runtime layer's unbind list stays what sway holds: kept when it
// couldn't be sent, and none once sway reloaded (the reload dropped those
// binds; the user's config may hold the keys now)
func TestSwayUnbindListFollowsSway(t *testing.T) {
	t.Parallel()
	tables, schema := repo(t)
	w := newSway(env2(tables, schema, func(string) string { return "" }), &ipc.Sway{Path: filepath.Join(t.TempDir(), "none.sock")})
	w.setUnbind([]render.SwayUnbind{{Key: "k", Line: "unbindsym Mod4+x"}})
	w.runtimeApply(context.Background(), Inputs{}, func() []string { return nil })
	if got := w.unbinds(); len(got) != 1 || got[0].Line != "unbindsym Mod4+x" {
		t.Fatalf("an apply sway never got dropped the list: %v", got)
	}
	w.runtimeClear(context.Background())
	if len(w.unbinds()) != 1 {
		t.Fatalf("a clear sway never got dropped the list: %v", w.unbinds())
	}
	w.seenReload()
	if got := w.unbinds(); got != nil {
		t.Fatalf("a reload since left the list to send: %v", got)
	}
	w.configReloaded(context.Background(), Inputs{})
	if w.state.SwayUnbinds != nil {
		t.Fatalf("the stale list kept for a re-exec: %v", w.state.SwayUnbinds)
	}
}

// swayWith is a sway writer whose user config is text, its saved unbinds
// list, carried or fresh, and no sway to talk to
func swayWith(t *testing.T, config string, carried bool, saved []render.SwayUnbind) *swayWriter {
	t.Helper()
	tables, schema := repo(t)
	home := t.TempDir()
	if err := os.MkdirAll(filepath.Join(home, "sway"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(home, "sway", "config"), []byte(config), 0o600); err != nil {
		t.Fatal(err)
	}
	vars := map[string]string{"HOME": home, "XDG_CONFIG_HOME": home}
	e := env2(tables, schema, func(k string) string { return vars[k] })
	e.carried = carried
	w := newSway(e, &ipc.Sway{Path: filepath.Join(t.TempDir(), "none.sock")})
	w.state.SwayUnbinds = saved
	return w
}

var swaySaved = func() []render.SwayUnbind {
	return []render.SwayUnbind{
		{Key: render.KeyID("SUPER + x"), Line: "unbindsym Mod4+x"},
		{Key: render.KeyID("SUPER + y"), Line: "unbindsym Mod4+y"},
	}
}

// A daemon that isn't carried over trusts no saved unbind: one of a key the
// user's config binds now would take their bind out
func TestSwayFreshDaemonDropsUnbindsOfKeysTheUserNowBinds(t *testing.T) {
	t.Parallel()
	w := swayWith(t, "bindsym Mod4+x exec true\n", false, swaySaved())
	w.runtimeApply(context.Background(), Inputs{}, func() []string { return nil })
	if got := w.state.SwayUnbinds; len(got) != 1 || got[0].Line != "unbindsym Mod4+y" {
		t.Fatalf("unbinds = %v, want only y's", got)
	}
}

func TestSwayCarriedDaemonKeepsTheSavedUnbinds(t *testing.T) {
	t.Parallel()
	w := swayWith(t, "bindsym Mod4+x exec true\n", true, swaySaved())
	w.runtimeApply(context.Background(), Inputs{}, func() []string { return nil })
	if got := w.state.SwayUnbinds; len(got) != 2 {
		t.Fatalf("unbinds = %v, want both kept", got)
	}
}

func TestSwayFreshDaemonRecomputesTheFloatingModifierLine(t *testing.T) {
	t.Parallel()
	w := swayWith(t, "floating_modifier Mod4 normal\n", false, []render.SwayUnbind{{Key: "", Line: "floating_modifier Mod1 normal"}})
	w.runtimeApply(context.Background(), Inputs{}, func() []string { return nil })
	if got := w.state.SwayUnbinds; len(got) != 1 || got[0].Line != "floating_modifier Mod4 normal" {
		t.Fatalf("unbinds = %v, want the user's floating line", got)
	}
}

func TestSwayOldFormatUnbindListIsDropped(t *testing.T) {
	t.Parallel()
	path := filepath.Join(t.TempDir(), "compositor.json")
	if err := os.WriteFile(path, []byte(`{"instance":"sway:a","swayUnbind":["unbindsym Mod4+x"]}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if got := loadState(path, "sway:a"); got.Instance != "sway:a" || got.SwayUnbinds != nil {
		t.Fatalf("state = %+v, want the old list dropped", got)
	}
}

func TestSwayFreshClearDropsTakenKeys(t *testing.T) {
	t.Parallel()
	w := swayWith(t, "bindsym Mod4+x exec true\n", false, swaySaved())
	w.runtimeClear(context.Background())
	// sway isn't there, so the list stays, less the key the user binds
	if got := w.state.SwayUnbinds; len(got) != 1 || got[0].Line != "unbindsym Mod4+y" {
		t.Fatalf("unbinds = %v, want only y's", got)
	}
}
