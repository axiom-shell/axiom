package manager

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
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
// isn't the managed path blocks managed (its file would never load)
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
