package mimeapps

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
)

func TestWindowAppIDs(t *testing.T) {
	home, sys := t.TempDir(), t.TempDir()
	put := func(dir, id, body string) {
		t.Helper()
		path := filepath.Join(dir, "applications", id)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte("[Desktop Entry]\nType=Application\nExec=x\n"+body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	put(sys, "org.gnome.Calculator.desktop", "StartupWMClass=gnome-calculator\n")
	put(sys, "plain.desktop", "")
	put(sys, "hidden.desktop", "Hidden=true\n")
	put(home, "both.desktop", "StartupWMClass=home-class\n")
	put(sys, "both.desktop", "StartupWMClass=sys-class\n")
	o := Options{DataHome: home, DataDirs: []string{sys}}
	for _, c := range []struct {
		id   string
		want []string
	}{
		{"org.gnome.Calculator.desktop", []string{"org.gnome.Calculator", "gnome-calculator"}},
		{"plain.desktop", []string{"plain"}},
		{"missing.desktop", nil},
		{"hidden.desktop", nil},
		{"both.desktop", []string{"both", "home-class"}},
	} {
		if got := WindowAppIDs(o, c.id); !slices.Equal(got, c.want) {
			t.Errorf("%s: %v, want %v", c.id, got, c.want)
		}
	}
}
