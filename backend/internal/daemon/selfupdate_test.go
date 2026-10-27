package daemon

import (
	"context"
	"log/slog"
	"os"
	"path/filepath"
	"testing"
)

func TestRebuildInstalled(t *testing.T) {
	t.Parallel()
	builds := `printf '#!/bin/sh\necho axiom\n' > "$3"; chmod +x "$3"`
	for _, tc := range []struct {
		name      string
		build     string
		installed func(t *testing.T) string
		rebuilt   bool
		failed    bool
	}{
		{"replaceable", builds, func(t *testing.T) string { return writeBin(t, t.TempDir(), 0o755) }, true, false},
		{"none", builds, func(t *testing.T) string { return "" }, false, false},
		{"read-only (a package's)", builds, func(t *testing.T) string { return writeBin(t, t.TempDir(), 0o555) }, false, false},
		{"doesn't compile", `echo 'main.go:1: syntax error' >&2; exit 1`, func(t *testing.T) string { return writeBin(t, t.TempDir(), 0o755) }, false, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if tc.name == "read-only (a package's)" && os.Geteuid() == 0 {
				t.Skip("root writes anywhere")
			}
			tree := t.TempDir()
			os.MkdirAll(filepath.Join(tree, "backend"), 0o755)
			d := &Daemon{opts: Options{Tree: tree, Go: fakeGo(t, tc.build), Log: slog.New(slog.DiscardHandler)}}
			d.installed = tc.installed(t)
			before, _ := os.ReadFile(d.installed)
			rebuilt, reason := d.rebuildInstalled(context.Background())
			if rebuilt != tc.rebuilt || (reason != "") != tc.failed {
				t.Fatalf("rebuilt %v, reason %q", rebuilt, reason)
			}
			after, _ := os.ReadFile(d.installed)
			if (string(before) != string(after)) != tc.rebuilt {
				t.Errorf("binary replaced: %v", string(before) != string(after))
			}
		})
	}
}

// writeBin is an installed binary in dir, with mode.
func writeBin(t *testing.T, dir string, mode os.FileMode) string {
	t.Helper()
	path := filepath.Join(dir, "axiom")
	if err := os.WriteFile(path, []byte("#!/bin/sh\necho old\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, mode); err != nil {
		t.Fatal(err)
	}
	return path
}
