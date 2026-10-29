package daemon

import (
	"context"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
)

// fakeGo writes a go that runs script (sh) for build, after a generate
// that does nothing.
func fakeGo(t *testing.T, build string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "go")
	script := "#!/bin/sh\ncase \"$1\" in\ngenerate) exit 0 ;;\nbuild) " + build + " ;;\nesac\n"
	// Written with forks held off: a child forked by a parallel test while
	// the file is open for writing keeps that descriptor until it execs,
	// and exec'ing the script meanwhile fails with ETXTBSY (text file busy).
	// A rename wouldn't help (same inode); os/exec forks under ForkLock
	syscall.ForkLock.RLock()
	err := os.WriteFile(path, []byte(script), 0o755)
	syscall.ForkLock.RUnlock()
	if err != nil {
		t.Fatal(err)
	}
	return path
}

func devFixture(t *testing.T, goBin string) *devMode {
	t.Helper()
	tree := t.TempDir()
	os.MkdirAll(filepath.Join(tree, "backend"), 0o755)
	os.WriteFile(filepath.Join(tree, "backend", "go.mod"), []byte("module x\n"), 0o644)
	d := &Daemon{opts: Options{Tree: tree, Go: goBin, Log: slog.New(slog.DiscardHandler)}}
	d.dirs.State = t.TempDir() + "/"
	d.dev = newDevMode(d, true)
	return d.dev
}

func TestDevBuild(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name  string
		build string
		ok    bool
	}{
		// The output (-o's argument, $3) answers `version`
		{"builds", `printf '#!/bin/sh\necho axiom\n' > "$3"; chmod +x "$3"`, true},
		{"doesn't compile", `echo 'main.go:1: syntax error' >&2; exit 1`, false},
		{"doesn't run", `printf '#!/bin/sh\nexit 3\n' > "$3"; chmod +x "$3"`, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			m := devFixture(t, fakeGo(t, tc.build))
			if reason := m.unavailable(); reason != "" {
				t.Fatal(reason)
			}
			out, err := m.compile(context.Background())
			if (err == nil) != tc.ok {
				t.Fatalf("err %v, output %s", err, out)
			}
			_, statErr := os.Stat(m.binary())
			if tc.ok != (statErr == nil) {
				t.Errorf("binary in place: %v", statErr)
			}
			if _, err := os.Stat(m.binary() + ".new"); err == nil {
				t.Error("the temporary build was left behind")
			}
			if tc.name == "doesn't compile" && !strings.Contains(string(out), "syntax error") {
				t.Errorf("output %q", out)
			}
		})
	}
}

func TestDevUnavailableWithoutSource(t *testing.T) {
	t.Parallel()
	m := devFixture(t, fakeGo(t, "exit 0"))
	os.RemoveAll(filepath.Join(m.d.opts.Tree, "backend"))
	if m.unavailable() == "" || m.State().Available {
		t.Error("builds offered without the source")
	}
}
