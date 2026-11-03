package daemon

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
)

// fakeGo writes a go that runs script (sh) for build, after a generate
// that does nothing.
func fakeGo(t *testing.T, build string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "go")
	script := "#!/bin/sh\ncase \"$1\" in\ngenerate) exit 0 ;;\nbuild) " + build + " ;;\nesac\n"
	// A parallel test's fork would leave it busy (writeExecutable)
	if err := writeExecutable(path, []byte(script)); err != nil {
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

// A build the source changed under (a pull while a branch switch's build
// ran) doesn't re-exec into the stale image: the edits' kick builds again.
func TestDevBuildSourceChangedMeanwhile(t *testing.T) {
	t.Parallel()
	// The build edits a source file, as the pull did, while it runs
	m := devFixture(t, fakeGo(t, `sleep 0.3; echo 'package x' > edited.go; sleep 0.3; printf '#!/bin/sh\necho axiom\n' > "$3"; chmod +x "$3"`))
	var logged strings.Builder
	m.d.opts.Log = slog.New(slog.NewTextHandler(&logged, nil))
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go m.watchSource(ctx)
	m.build(ctx)
	if out := logged.String(); !strings.Contains(out, "building again") || strings.Contains(out, "re-executing") {
		t.Fatalf("the stale build was re-exec'd into:\n%s", out)
	}
	select {
	case <-m.builds.ch:
	case <-time.After(5 * time.Second):
		t.Fatal("the edit didn't kick another build")
	}
}

// A client newer than the daemon has it re-exec into the binary on disk
// that speaks its protocol, when the tree's files do too, once per binary;
// an older client, or one no binary here speaks, re-execs nothing.
func TestNewerClientFindsItsBinary(t *testing.T) {
	t.Parallel()
	own := buildinfo.Protocol()
	m := devFixture(t, fakeGo(t, "exit 0"))
	d := m.d
	tree := func(protocol int) {
		os.MkdirAll(filepath.Join(d.opts.Tree, "qml", "config", "json"), 0o755)
		os.WriteFile(filepath.Join(d.opts.Tree, "qml", "config", "json", "backend.json"), []byte(fmt.Sprintf(`{"protocol": %d}`, protocol)), 0o644)
	}
	binary := func(path string, protocol int) {
		os.MkdirAll(filepath.Dir(path), 0o700)
		if err := writeExecutable(path, []byte(fmt.Sprintf("#!/bin/sh\necho '{\"protocol\": %d}'\n", protocol))); err != nil {
			t.Fatal(err)
		}
	}
	d.installed = filepath.Join(t.TempDir(), "axiom")
	ctx := context.Background()

	target := func(want int) string {
		exe, _ := d.upgradeTarget(ctx, want)
		return exe
	}

	tree(own + 1)
	binary(d.installed, own) // not updated: nothing speaks it
	if exe := target(own + 1); exe != "" {
		t.Errorf("no binary speaks it: %q", exe)
	}
	binary(d.installed, own+1) // updated in place: a new file, tried afresh
	binary(DevBinary(d.dirs), own)
	if exe, start := d.upgradeTarget(ctx, own+1); exe != d.installed || !start {
		t.Errorf("the updated binary: %q (start %v), want %q", exe, start, d.installed)
	}
	// Until the exec, another newer hello gets it too, without a second
	if exe, start := d.upgradeTarget(ctx, own+1); exe != d.installed || start {
		t.Errorf("a hello meanwhile: %q (start %v)", exe, start)
	}
	d.upgrading = "" // as a new image starts
	if exe := target(own + 1); exe != "" {
		t.Errorf("the same binary tried twice: %q", exe)
	}
	binary(DevBinary(d.dirs), own+1)
	if exe := target(own + 1); exe != DevBinary(d.dirs) {
		t.Errorf("dev mode's build first: %q", exe)
	}
	d.upgrading = ""
	if exe := target(own - 1); exe != "" {
		t.Errorf("an older client: %q", exe)
	}
	binary(d.installed, own+2)
	tree(own + 1)
	if exe := target(own + 2); exe != "" {
		t.Errorf("the tree's files speak another protocol: %q", exe)
	}
}
