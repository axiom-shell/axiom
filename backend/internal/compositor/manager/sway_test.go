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
