package cli

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"slices"
	"testing"
)

// `axiom log` runs `qs log -p <qml>`, debug output hidden unless --debug,
// -f and the extra arguments after them.
func TestLogArgv(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name          string
		follow, debug bool
		extra         []string
		want          []string
	}{
		{"plain", false, false, nil, []string{"qs", "log", "-p", "/t/qml", "-r", "*.debug=false"}},
		{"follow", true, false, nil, []string{"qs", "log", "-p", "/t/qml", "-r", "*.debug=false", "-f"}},
		{"debug", false, true, nil, []string{"qs", "log", "-p", "/t/qml"}},
		{"extra", true, true, []string{"-t", "50"}, []string{"qs", "log", "-p", "/t/qml", "-f", "-t", "50"}},
	} {
		if got := logArgv("qs", "/t/qml", tc.follow, tc.debug, tc.extra); !slices.Equal(got, tc.want) {
			t.Errorf("%s: %q, want %q", tc.name, got, tc.want)
		}
	}
}

// Without a daemon (or with --offline, or --tree) the log is the found
// tree's QML folder's.
func TestLogQMLDirWithoutDaemon(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "qml", "config"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "qml", "shell.qml"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	runtime := t.TempDir() // no daemon runs here
	env := func(offline bool) *Env {
		return &Env{Stdout: &bytes.Buffer{}, Stderr: &bytes.Buffer{}, Globals: Globals{Offline: offline},
			Getenv: func(k string) string {
				switch k {
				case "AXIOM_TREE":
					return root
				case "XDG_RUNTIME_DIR":
					return runtime
				}
				return ""
			}}
	}
	want := filepath.Join(root, "qml")
	for _, tc := range []struct {
		name    string
		offline bool
		dir     string
	}{
		{"no daemon", false, ""},
		{"offline", true, ""},
		{"tree", false, root},
	} {
		got, err := logQMLDir(context.Background(), env(tc.offline), tc.dir)
		if err != nil || got != want {
			t.Errorf("%s: %q, %v; want %q", tc.name, got, err, want)
		}
	}
}
