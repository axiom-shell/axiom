package tree

import (
	"os"
	"path/filepath"
	"testing"
)

func makeTree(t *testing.T, dir string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Join(dir, qmlDir, "config"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, qmlDir, shellQML), nil, 0o644); err != nil {
		t.Fatal(err)
	}
}

// Found from the folder a command runs in first, then where an install
// puts it: an autostart's `axiom run` runs from $HOME.
func TestFind(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	clone := filepath.Join(root, "work", "axiom")
	user := filepath.Join(root, "data", "axiom-shell")
	system := filepath.Join(root, "share", "axiom-shell")
	for _, d := range []string{clone, user, system} {
		makeTree(t, d)
	}
	// An old install's place, never looked in
	makeTree(t, filepath.Join(root, "config", "quickshell", "axiom"))
	// A tree without qml/ isn't one
	old := filepath.Join(root, "old")
	os.MkdirAll(filepath.Join(old, "config"), 0o755)
	os.WriteFile(filepath.Join(old, shellQML), nil, 0o644)
	nowhere := filepath.Join(root, "home")
	os.MkdirAll(nowhere, 0o755)
	env := func(vars map[string]string) func(string) string {
		return func(k string) string { return vars[k] }
	}
	cases := []struct {
		name  string
		vars  map[string]string
		start string
		want  string
	}{
		{"inside a clone", map[string]string{"XDG_DATA_HOME": filepath.Join(root, "data")}, filepath.Join(clone, "qml", "config"), clone},
		{"the user's", map[string]string{"XDG_DATA_HOME": filepath.Join(root, "data"), "XDG_DATA_DIRS": filepath.Join(root, "share")}, nowhere, user},
		{"the system's", map[string]string{"HOME": nowhere, "XDG_DATA_DIRS": filepath.Join(root, "share")}, nowhere, system},
		{"AXIOM_TREE first", map[string]string{"AXIOM_TREE": system, "XDG_DATA_HOME": filepath.Join(root, "data")}, clone, system},
		{"not the old config folder", map[string]string{"HOME": nowhere, "XDG_CONFIG_HOME": filepath.Join(root, "config"), "XDG_DATA_DIRS": filepath.Join(root, "none")}, nowhere, ""},
		{"not the old layout", map[string]string{"HOME": nowhere, "XDG_DATA_DIRS": filepath.Join(root, "none")}, old, ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			got, err := Find("", env(c.vars), c.start)
			if c.want == "" {
				if err == nil {
					t.Errorf("found %s", got)
				}
				return
			}
			if err != nil || got != c.want {
				t.Errorf("got %q %v, want %q", got, err, c.want)
			}
		})
	}
}
