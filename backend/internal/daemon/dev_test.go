package daemon

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
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

// buildsAxiom is a fake go build whose output (-o's argument, $3) answers
// `version --json` as a binary of handoff generation handoff.
func buildsAxiom(handoff int) string {
	return fmt.Sprintf(`printf '#!/bin/sh\necho "{\\"handoff\\": %d, \\"protocol\\": 7}"\n' > "$3"; chmod +x "$3"`, handoff)
}

// fakeTree makes an axiom tree with the Go source's module file.
func fakeTree(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	for path, data := range map[string]string{
		"backend/go.mod":                      "module x\n",
		"backend/main.go":                     "package main\n",
		"qml/shell.qml":                       "",
		"qml/config/json/backend.json":        `{"protocol": 1}`,
		"qml/config/json/theme-defaults.json": "{}",
	} {
		p := filepath.Join(dir, path)
		os.MkdirAll(filepath.Dir(p), 0o755)
		if err := os.WriteFile(p, []byte(data), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

// reexecCall is a re-exec a test's daemon asked for.
type reexecCall struct {
	exe string
	img image
}

// devFixture is dev mode, on, with a dev tree, in the installed image on
// scratch folders; a test records its re-execs (recordReexecs).
func devFixture(t *testing.T, goBin string) *devMode {
	t.Helper()
	treeDir := fakeTree(t)
	home := t.TempDir()
	d := &Daemon{opts: Options{Tree: "/install", Go: goBin, Log: slog.New(slog.DiscardHandler)}}
	d.dirs = xdg.Dirs{Config: home + "/config/", State: home + "/state/", UI: home + "/ui/"}
	d.installed = filepath.Join(home, "bin", "axiom")
	d.executable = d.installed
	d.installTree, d.configDir = "/install", d.dirs.Config
	ctx, cancel := context.WithCancel(context.Background())
	d.tasks = &tasks{ctx: ctx}
	t.Cleanup(func() {
		cancel()
		d.tasks.Wait()
	})
	d.opts.reexec = func(exe string, img image) error {
		t.Errorf("an unexpected re-exec into %s", exe)
		return nil
	}
	d.dev = newDevMode(d, true)
	d.dev.tree = treeDir
	return d.dev
}

// recordReexecs makes the fixture's re-execs go to the channel returned.
func recordReexecs(m *devMode) <-chan reexecCall {
	ch := make(chan reexecCall, 8)
	m.d.opts.reexec = func(exe string, img image) error {
		ch <- reexecCall{exe, img}
		return nil
	}
	return ch
}

// noReexec fails when a re-exec was asked for within a moment.
func noReexec(t *testing.T, ch <-chan reexecCall) {
	t.Helper()
	select {
	case c := <-ch:
		t.Errorf("re-exec'd into %s (%+v)", c.exe, c.img)
	case <-time.After(200 * time.Millisecond):
	}
}

func wantReexec(t *testing.T, ch <-chan reexecCall, exe string, img image) {
	t.Helper()
	select {
	case c := <-ch:
		if c.exe != exe || c.img != img {
			t.Errorf("re-exec'd into %s (%+v), want %s (%+v)", c.exe, c.img, exe, img)
		}
	case <-time.After(testkit.Bound(5 * time.Second)):
		t.Errorf("no re-exec into %s", exe)
	}
}

func TestDevBuild(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name  string
		build string
		ok    bool
	}{
		{"builds", buildsAxiom(2), true},
		{"doesn't compile", `echo 'main.go:1: syntax error' >&2; exit 1`, false},
		{"doesn't run", `printf '#!/bin/sh\nexit 3\n' > "$3"; chmod +x "$3"`, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			m := devFixture(t, fakeGo(t, tc.build))
			if reason := m.unavailable(m.tree); reason != "" {
				t.Fatal(reason)
			}
			info, out, err := m.compile(context.Background(), m.tree)
			if (err == nil) != tc.ok {
				t.Fatalf("err %v, output %s", err, out)
			}
			if tc.ok && (info.Handoff != 2 || info.Protocol != 7) {
				t.Errorf("version %+v", info)
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
	os.RemoveAll(filepath.Join(m.tree, "backend"))
	if m.unavailable(m.tree) == "" || m.State().Available {
		t.Error("builds offered without the source")
	}
	if m.unavailable("") == "" {
		t.Error("builds offered without a dev tree")
	}
}

// A build the source changed under (a pull while a branch switch's build
// ran) doesn't re-exec into the stale image: the edits' kick builds again.
func TestDevBuildSourceChangedMeanwhile(t *testing.T) {
	t.Parallel()
	// The build edits a source file, as the pull did, while it runs
	m := devFixture(t, fakeGo(t, `sleep 0.3; echo 'package x' > edited.go; sleep 0.3; `+buildsAxiom(2)))
	reexecs := recordReexecs(m)
	var logged syncBuffer
	m.d.opts.Log = slog.New(slog.NewTextHandler(&logged, nil))
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go m.watchSource(ctx, m.tree)
	m.build(ctx)
	if out := logged.String(); !strings.Contains(out, "building again") {
		t.Fatalf("the stale build was taken:\n%s", out)
	}
	noReexec(t, reexecs)
	select {
	case <-m.builds.ch:
	case <-time.After(testkit.Bound(5 * time.Second)):
		t.Fatal("the edit didn't kick another build")
	}
}

// A build switches into the dev image (and records itself) only when
// nothing changed meanwhile: a new dev tree (gen), dev mode off, or a
// binary older than dev trees never re-execs.
func TestDevBuildSwitchesOnlyWhenCurrent(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name      string
		handoff   int
		meanwhile func(m *devMode)
		switches  bool
	}{
		{"current", 2, nil, true},
		{"the tree changed", 2, func(m *devMode) { m.gen++ }, false},
		{"turned off", 2, func(m *devMode) { m.enabled = false }, false},
		{"another switch scheduled", 2, func(m *devMode) { m.switching = true }, false},
		{"predates dev trees", 1, nil, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			m := devFixture(t, fakeGo(t, "sleep 0.3; "+buildsAxiom(tc.handoff)))
			reexecs := recordReexecs(m)
			done := make(chan struct{})
			go func() {
				m.build(context.Background())
				close(done)
			}()
			if tc.meanwhile != nil {
				if !testkit.Eventually(func() bool { return m.State().Building }) {
					t.Fatal("never building")
				}
				m.mu.Lock()
				tc.meanwhile(m)
				m.mu.Unlock()
			}
			<-done
			if tc.switches {
				wantReexec(t, reexecs, DevBinary(m.d.dirs), m.devImage(m.tree))
			} else {
				noReexec(t, reexecs)
			}
			b, recorded := readBuild(m.d.dirs)
			if want := tc.handoff >= minDevHandoff; recorded != want || (recorded && (b.Tree != m.tree || b.Handoff != tc.handoff)) {
				t.Errorf("build.json %+v (recorded %v)", b, recorded)
			}
			st := m.State()
			if st.Building || st.LastBuild == nil || st.LastBuild.OK != (tc.handoff >= minDevHandoff) {
				t.Fatalf("state %+v", st)
			}
			if tc.handoff < minDevHandoff && !strings.Contains(st.LastBuild.Output, "predates dev trees") {
				t.Errorf("output %q", st.LastBuild.Output)
			}
		})
	}
}

// A client newer than the daemon has it re-exec into the binary on disk
// that speaks its protocol, when the tree's files do too, once per binary:
// the dev build while the dev image runs, else the installed one (dev
// mode on or not); an older client, or one no binary here speaks,
// re-execs nothing.
func TestNewerClientFindsItsBinary(t *testing.T) {
	t.Parallel()
	own := buildinfo.Protocol()
	m := devFixture(t, fakeGo(t, "exit 0"))
	d := m.d
	d.opts.Tree = m.tree
	tree := func(protocol int) {
		os.WriteFile(filepath.Join(d.opts.Tree, "qml", "config", "json", "backend.json"), []byte(fmt.Sprintf(`{"protocol": %d}`, protocol)), 0o644)
	}
	binary := func(path string, protocol int) {
		os.MkdirAll(filepath.Dir(path), 0o700)
		if err := writeExecutable(path, []byte(fmt.Sprintf("#!/bin/sh\necho '{\"protocol\": %d}'\n", protocol))); err != nil {
			t.Fatal(err)
		}
	}
	ctx := context.Background()

	target := func(want int) string {
		exe, _ := d.upgradeTarget(ctx, want)
		return exe
	}

	tree(own + 1)
	binary(d.installed, own) // not updated: nothing speaks it
	binary(DevBinary(d.dirs), own+1)
	if exe := target(own + 1); exe != "" {
		t.Errorf("not the dev image, yet the dev build: %q", exe)
	}
	binary(d.installed, own+1) // updated in place: a new file, tried afresh
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

	// The dev image: only the dev build
	d.configDir = devConfigDir(d.dirs)
	binary(d.installed, own+1)
	binary(DevBinary(d.dirs), own)
	if exe := target(own + 1); exe != "" {
		t.Errorf("the dev image took another binary: %q", exe)
	}
	binary(DevBinary(d.dirs), own+1)
	if exe := target(own + 1); exe != DevBinary(d.dirs) {
		t.Errorf("the dev image's build: %q", exe)
	}
	d.upgrading = ""
	if exe := target(own - 1); exe != "" {
		t.Errorf("an older client: %q", exe)
	}
	binary(DevBinary(d.dirs), own+2)
	tree(own + 1)
	if exe := target(own + 2); exe != "" {
		t.Errorf("the tree's files speak another protocol: %q", exe)
	}
}

// syncBuffer is a log the build's goroutines write while a test reads it.
type syncBuffer struct {
	mu sync.Mutex
	b  strings.Builder
}

func (s *syncBuffer) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.Write(p)
}

func (s *syncBuffer) String() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.String()
}
