package daemon

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

func TestXkbRegistry(t *testing.T) {
	t.Parallel()
	if got := xkbRoot(func(string) string { return "" }); got != "/usr/share/X11/xkb" {
		t.Errorf("default root %q", got)
	}
	if got := xkbRoot(func(k string) string { return map[string]string{"XKB_CONFIG_ROOT": "/x"}[k] }); got != "/x" {
		t.Errorf("$XKB_CONFIG_ROOT: %q", got)
	}
	dir := t.TempDir()
	if _, err := readXkbRegistry(dir); axerr.KindOf(err) != axerr.Unavailable {
		t.Errorf("no file: %v", err)
	}
	data, err := os.ReadFile("../xkb/testdata/evdev.xml")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(dir, "rules"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, xkbRules), data, 0o644); err != nil {
		t.Fatal(err)
	}
	r, err := readXkbRegistry(dir)
	if err != nil || len(r.Layouts) != 2 || r.Layouts[1].Description != "German" {
		t.Errorf("got %+v, %v", r, err)
	}
	if err := os.WriteFile(filepath.Join(dir, xkbRules), []byte("<cut"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := readXkbRegistry(dir); axerr.KindOf(err) != axerr.Failed {
		t.Errorf("a broken file: %v", err)
	}
	// The real one, where it's installed
	if _, err := os.Stat("/usr/share/X11/xkb/" + xkbRules); err == nil {
		r, err := readXkbRegistry("/usr/share/X11/xkb")
		if err != nil || len(r.Layouts) < 50 {
			t.Errorf("the installed registry: %d layouts, %v", len(r.Layouts), err)
		}
	}
}
