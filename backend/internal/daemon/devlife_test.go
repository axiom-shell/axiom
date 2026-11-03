package daemon

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

func TestIsBuildInput(t *testing.T) {
	t.Parallel()
	const root = "/clone"
	for path, want := range map[string]bool{
		"/clone/backend/go.mod":                                  true,
		"/clone/backend/go.sum":                                  true,
		"/clone/backend/internal/daemon/dev.go":                  true,
		"/clone/backend/internal/migrate/legacy/legacy.js":       true,
		"/clone/backend/internal/compositor/actions/table.json":  true,
		"/clone/qml/config/json/backend.json":                    true,
		"/clone/qml/config/json/theme-defaults.json":             true,
		"/clone/backend/internal/daemon/dev_test.go":             false,
		"/clone/backend/internal/daemon/.dev.go.swp":             false,
		"/clone/backend/internal/daemon/testdata/x.json":         false,
		"/clone/backend/.cache/x.go":                             false,
		"/clone/backend/internal/assets/data/config/json/a.json": false,
		"/clone/backend/README.md":                               false,
		"/clone/qml/config/json/config.schema.json":              false,
		"/clone/qml/shell.qml":                                   false,
		"/other/backend/main.go":                                 false,
	} {
		if got := isBuildInput(root, path); got != want {
			t.Errorf("%s: %v, want %v", path, got, want)
		}
	}
}

// The fingerprint follows the build inputs, and only them.
func TestFingerprint(t *testing.T) {
	t.Parallel()
	dir := fakeTree(t)
	fp := func() string {
		t.Helper()
		s, err := fingerprint(dir)
		if err != nil {
			t.Fatal(err)
		}
		return s
	}
	write := func(rel, data string) {
		p := filepath.Join(dir, rel)
		os.MkdirAll(filepath.Dir(p), 0o755)
		os.WriteFile(p, []byte(data), 0o644)
	}
	first := fp()
	write("backend/main_test.go", "package main\n")
	write("backend/internal/assets/data/x.json", "{}")
	write("backend/testdata/x.go", "package x\n")
	write("qml/Foo.qml", "")
	if got := fp(); got != first {
		t.Error("a file that isn't a build input changed the fingerprint")
	}
	write("backend/main.go", "package main // edited\n")
	second := fp()
	if second == first {
		t.Error("a source edit kept the fingerprint")
	}
	write("qml/config/json/backend.json", `{"protocol": 2}`)
	if fp() == second {
		t.Error("an embedded file's edit kept the fingerprint")
	}
}

func TestBuildVerdict(t *testing.T) {
	t.Parallel()
	good := devBuild{Tree: "/clone", Fingerprint: "f", Handoff: 2}
	with := func(change func(*devBuild)) *devBuild {
		b := good
		change(&b)
		return &b
	}
	for _, tc := range []struct {
		name   string
		b      *devBuild
		fp     string
		binary bool
		fresh  bool
		why    string
	}{
		{"fresh", &good, "f", true, true, ""},
		{"none", nil, "f", true, false, "no dev build"},
		{"stale", &good, "g", true, false, "source changed"},
		{"wrong tree", with(func(b *devBuild) { b.Tree = "/other" }), "f", true, false, "another tree"},
		{"low handoff", with(func(b *devBuild) { b.Handoff = 1 }), "f", true, false, "predates dev trees"},
		{"no handoff (an old binary)", with(func(b *devBuild) { b.Handoff = 0 }), "f", true, false, "predates dev trees"},
		{"binary gone", &good, "f", false, false, "gone"},
		{"unreadable tree", &good, "", true, false, "source changed"},
	} {
		fresh, why := buildVerdict(tc.b, "/clone", tc.fp, tc.binary)
		if fresh != tc.fresh || !strings.Contains(why, tc.why) {
			t.Errorf("%s: %v %q", tc.name, fresh, why)
		}
	}
}

// buildFresh on disk: build.json, the binary and the tree's inputs.
func TestBuildFresh(t *testing.T) {
	t.Parallel()
	m := devFixture(t, fakeGo(t, "exit 0"))
	dirs, dir := m.d.dirs, m.tree
	if c := buildFresh(dirs, dir); c.Fresh || !strings.Contains(c.Why, "no dev build") {
		t.Errorf("no build: %+v", c)
	}
	fp, _ := fingerprint(dir)
	writeBuild(dirs, devBuild{Tree: dir, Fingerprint: fp, Handoff: 2, At: time.Now()})
	if c := buildFresh(dirs, dir); c.Fresh || !strings.Contains(c.Why, "gone") {
		t.Errorf("no binary: %+v", c)
	}
	os.MkdirAll(filepath.Dir(DevBinary(dirs)), 0o700)
	writeExecutable(DevBinary(dirs), []byte("#!/bin/sh\n"))
	if c := buildFresh(dirs, dir); !c.Fresh || c.Build.Tree != dir {
		t.Errorf("fresh: %+v", c)
	}
	os.WriteFile(filepath.Join(dir, "backend", "main.go"), []byte("package main // edited\n"), 0o644)
	if c := buildFresh(dirs, dir); c.Fresh {
		t.Errorf("edited: %+v", c)
	}
	if c := buildFresh(dirs, filepath.Join(dir, "gone")); !c.Gone {
		t.Errorf("a tree that isn't one: %+v", c)
	}
}

func TestParseGitStatus(t *testing.T) {
	t.Parallel()
	clean := "# branch.oid 0123456789abcdef\n# branch.head restructure\n# branch.upstream origin/restructure\n"
	if got := parseGitStatus([]byte(clean)); got != (gitState{Branch: "restructure", Commit: "0123456789abcdef"}) {
		t.Errorf("clean: %+v", got)
	}
	if got := parseGitStatus([]byte(clean + "1 .M N... 100644 100644 100644 a b backend/x.go\n")); !got.Dirty {
		t.Errorf("changed: %+v", got)
	}
	if got := parseGitStatus([]byte("# branch.oid abc\n# branch.head (detached)\n")); got.Branch != "" || got.Commit != "abc" {
		t.Errorf("detached: %+v", got)
	}
	if got := parseGitStatus([]byte("# branch.oid (initial)\n# branch.head main\n")); got.Commit != "" {
		t.Errorf("no commit yet: %+v", got)
	}
}

func TestStartPlan(t *testing.T) {
	t.Parallel()
	on := devChoice{Enabled: true, Tree: "/clone"}
	fresh := buildCheck{Fresh: true}
	for _, tc := range []struct {
		name     string
		choice   devChoice
		build    buildCheck
		h        *handoff
		override bool
		want     startAction
	}{
		{"dev off", devChoice{Tree: "/clone"}, fresh, nil, false, startAsIs},
		{"no dev tree", devChoice{Enabled: true}, fresh, nil, false, startAsIs},
		{"a re-exec", on, fresh, &handoff{Tree: "/t"}, false, startAsIs},
		{"the dev image's own start", on, fresh, &handoff{Fresh: true}, false, startAsIs},
		{"a re-exec of the install image, build stale", on, buildCheck{Why: "stale"}, &handoff{Tree: "/t", Dev: true}, false, startBuild},
		{"a re-exec of the install image, build fresh", on, fresh, &handoff{Tree: "/t", Dev: true}, false, startAsIs},
		{"a re-exec of the dev image, build stale", on, buildCheck{Why: "stale"}, &handoff{Tree: "/clone", Dev: true, ConfigDir: "/dev"}, false, startAsIs},
		{"a re-exec of the install image, dev tree given over", on, buildCheck{Why: "stale"}, &handoff{Tree: "/t", Dev: true}, true, startAsIs},
		{"--tree wins", on, fresh, nil, true, startAsIs},
		{"--tree wins over a stale build", on, buildCheck{Why: "stale"}, nil, true, startAsIs},
		{"fresh", on, fresh, nil, false, startExec},
		{"stale", on, buildCheck{Why: "the source changed"}, nil, false, startBuild},
		{"no build", on, buildCheck{Why: "no dev build yet"}, nil, false, startBuild},
		{"the guard tripped", on, buildCheck{Fresh: true, Guarded: true}, nil, false, startStayLive},
		{"the guard of an older build", on, buildCheck{Why: "the source changed", Guarded: false}, nil, false, startBuild},
		{"the dev tree is gone", on, buildCheck{Gone: true, Why: "gone"}, nil, false, startStayLive},
	} {
		if got := startPlan(tc.choice, tc.build, tc.h, tc.override); got.Action != tc.want {
			t.Errorf("%s: %+v, want %v", tc.name, got, tc.want)
		}
	}
}

// startFixture is the installed image at session start, dev mode on with
// a fresh dev build, the instance lock held; its execs are recorded.
type startFixture struct {
	m     *devMode
	build devBuild
	execs chan []string // exe, then the env
}

func newStartFixture(t *testing.T) *startFixture {
	t.Helper()
	m := devFixture(t, fakeGo(t, "exit 0"))
	d := m.d
	lock, err := fsx.TryLock(filepath.Join(t.TempDir(), "daemon.lock"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { lock.Release() })
	d.instance = lock
	fp, _ := fingerprint(m.tree)
	b := devBuild{Tree: m.tree, Fingerprint: fp, Handoff: 2, At: time.Now().Round(0)}
	if err := writeBuild(d.dirs, b); err != nil {
		t.Fatal(err)
	}
	os.MkdirAll(filepath.Dir(DevBinary(d.dirs)), 0o700)
	writeExecutable(DevBinary(d.dirs), []byte("#!/bin/sh\n"))
	f := &startFixture{m: m, build: b, execs: make(chan []string, 4)}
	d.opts.exec = func(exe string, argv, env []string) error {
		f.execs <- append([]string{exe}, env...)
		return nil
	}
	return f
}

func (f *startFixture) choice() devChoice { return devChoice{Enabled: true, Tree: f.m.tree} }

func handoffIn(env []string) (handoff, bool) {
	for _, kv := range env {
		if v, ok := strings.CutPrefix(kv, ReexecEnv+"="); ok {
			var h handoff
			return h, json.Unmarshal([]byte(v), &h) == nil
		}
	}
	return handoff{}, false
}

// The session start execs into a fresh dev build with a Fresh handoff
// (the lock, the installed binary and the install tree), the boot guard
// written first; the dev image's shell clears it; a marker left for the
// same build keeps the next start live.
func TestSessionStartAndBootGuard(t *testing.T) {
	t.Parallel()
	f := newStartFixture(t)
	d := f.m.d
	if plan := d.sessionStart(nil, f.choice()); plan.Action != startExec {
		t.Fatalf("plan %+v", plan)
	}
	var call []string
	select {
	case call = <-f.execs:
	default:
		t.Fatal("no exec")
	}
	h, ok := handoffIn(call[1:])
	if call[0] != DevBinary(d.dirs) || !ok || !h.Fresh || h.Lock != int(d.instance.File().Fd()) || h.Installed != d.installed || h.InstallTree != d.opts.Tree || !h.wellFormed() {
		t.Errorf("exec %s with %+v", call[0], h)
	}
	if !guarded(d.dirs, f.build) {
		t.Error("no boot guard before the exec")
	}
	// The exec returned (a test's): the lock is close-on-exec again
	if flags, err := unix.FcntlInt(d.instance.File().Fd(), unix.F_GETFD, 0); err != nil || flags&unix.FD_CLOEXEC == 0 {
		t.Errorf("the lock left without close-on-exec: %v", err)
	}

	// The next start, the marker still there: live, told why
	if plan := d.sessionStart(nil, f.choice()); plan.Action != startStayLive || !strings.Contains(plan.Why, "didn't come up") {
		t.Errorf("guarded: %+v", plan)
	}
	select {
	case <-f.execs:
		t.Error("exec'd past the guard")
	default:
	}
	// A new build: the marker isn't its
	if guarded(d.dirs, devBuild{Tree: f.build.Tree, Fingerprint: f.build.Fingerprint, At: f.build.At.Add(time.Second)}) {
		t.Error("the guard holds another build")
	}

	// The installed image's shell doesn't clear it; the dev image's does
	f.m.shellHello()
	if !guarded(d.dirs, f.build) {
		t.Error("the installed image's shell cleared the guard")
	}
	d.configDir = devConfigDir(d.dirs)
	f.m.shellHello()
	if guarded(d.dirs, f.build) {
		t.Error("the dev shell's hello left the guard")
	}

	// --tree wins
	d.opts.TreeOverride = true
	if plan := d.sessionStart(nil, f.choice()); plan.Action != startAsIs {
		t.Errorf("--tree: %+v", plan)
	}
}

// An exec that fails leaves no guard and builds again.
func TestSessionStartExecFails(t *testing.T) {
	t.Parallel()
	f := newStartFixture(t)
	d := f.m.d
	d.opts.exec = func(string, []string, []string) error { return axerr.New(axerr.Unavailable, "no") }
	if plan := d.sessionStart(nil, f.choice()); plan.Action != startBuild {
		t.Errorf("plan %+v", plan)
	}
	if guarded(d.dirs, f.build) {
		t.Error("a guard left after a failed exec")
	}
	// begin takes it: the build runs once the builds do
	f.m.enabled = true
	f.m.begin(context.Background(), f.choice(), startDecision{Action: startBuild})
	if !f.m.startKick {
		t.Error("the stale build isn't kicked")
	}
	f.m.begin(context.Background(), f.choice(), startDecision{Action: startStayLive, Why: "the dev build didn't come up"})
	if st := f.m.State(); st.LastBuild == nil || st.LastBuild.OK || !strings.Contains(st.LastBuild.Output, "didn't come up") {
		t.Errorf("the guard isn't told: %+v", st.LastBuild)
	}
}

// A dev image that fails before it serves execs back into the installed
// binary without a handoff, the instance lock released for it.
func TestFallBackLive(t *testing.T) {
	t.Parallel()
	f := newStartFixture(t)
	d := f.m.d
	d.fallBackLive(&handoff{Fresh: true, Lock: 3, Installed: "/installed/axiom"}, axerr.New(axerr.Internal, "boom"))
	select {
	case call := <-f.execs:
		if _, carried := handoffIn(call[1:]); call[0] != "/installed/axiom" || carried {
			t.Errorf("exec %v", call)
		}
	default:
		t.Fatal("no way back")
	}
	if d.instance.File() != nil {
		t.Error("the instance lock is still held")
	}
	// Only a session start's exec goes back
	d.fallBackLive(&handoff{Lock: 3, Listener: 4, ConfigLock: 5, Installed: "/installed/axiom"}, axerr.New(axerr.Internal, "boom"))
	select {
	case call := <-f.execs:
		t.Errorf("a re-exec's image went back: %v", call)
	default:
	}
}

// `axiom run --dev` (dev mode on for one run, no dev tree): the options
// still change, and neither they nor a tree set save dev mode on.
func TestDevSetUnderForcedDev(t *testing.T) {
	t.Parallel()
	m := devFixture(t, fakeGo(t, "exit 1"))
	m.tree = "" // enabled by --dev, nothing saved
	ctx := context.Background()
	yes := true
	if err := m.Set(ctx, DevSetParams{Options: &yes}); err != nil {
		t.Fatalf("options under --dev: %v", err)
	}
	if got := loadDevChoice(m.d.dirs); got != (devChoice{Options: true}) {
		t.Errorf("saved %+v", got)
	}
	if err := m.Set(ctx, DevSetParams{Enabled: &yes}); axerr.KindOf(err) != axerr.Refused {
		t.Errorf("on without a tree: %v", err)
	}
}

// dev.set: the dev tree checked (absolute, an axiom tree with the Go
// source, symlinks resolved) and saved with the rest of dev.json; on
// needs a tree.
func TestDevSetValidates(t *testing.T) {
	t.Parallel()
	m := devFixture(t, fakeGo(t, "exit 1"))
	m.enabled, m.tree = false, ""
	ctx := context.Background()
	str := func(s string) *string { return &s }
	yes, no := true, false

	noSource := fakeTree(t)
	os.Remove(filepath.Join(noSource, "backend", "go.mod"))
	for _, tc := range []struct {
		name string
		p    DevSetParams
		kind axerr.Kind
		msg  string
	}{
		{"relative", DevSetParams{Tree: str("clone")}, axerr.BadRequest, "absolute"},
		{"missing", DevSetParams{Tree: str("/nowhere/clone")}, axerr.NotFound, ""},
		{"not a tree", DevSetParams{Tree: str(t.TempDir())}, axerr.NotFound, "isn't an axiom tree"},
		{"no Go source", DevSetParams{Tree: str(noSource)}, axerr.NotFound, "go.mod"},
		{"on without a tree", DevSetParams{Enabled: &yes}, axerr.Refused, "set a dev tree first: axiom dev set <clone>"},
	} {
		err := m.Set(ctx, tc.p)
		if axerr.KindOf(err) != tc.kind || !strings.Contains(errString(err), tc.msg) {
			t.Errorf("%s: %v", tc.name, err)
		}
	}
	if got := loadDevChoice(m.d.dirs); got != (devChoice{}) {
		t.Errorf("a refused set was saved: %+v", got)
	}

	// Through a symlink, off: saved resolved, nothing built
	clone := fakeTree(t)
	link := filepath.Join(t.TempDir(), "link")
	os.Symlink(clone, link)
	if err := m.Set(ctx, DevSetParams{Tree: &link, Options: &yes}); err != nil {
		t.Fatal(err)
	}
	if got := loadDevChoice(m.d.dirs); got != (devChoice{Tree: clone, Options: true}) {
		t.Errorf("saved %+v", got)
	}
	if st := m.State(); st.Tree != clone || !st.Options || st.Enabled {
		t.Errorf("state %+v", st)
	}
	select {
	case <-m.builds.ch:
		t.Error("a build kicked with dev mode off")
	default:
	}
	gen := m.gen

	// On: the build is stale, so it's built, by the builds the watchers
	// restart with (never kicked into the old ones)
	if err := m.Set(ctx, DevSetParams{Enabled: &yes}); err != nil {
		t.Fatal(err)
	}
	m.mu.Lock()
	kick := m.startKick
	m.mu.Unlock()
	if !kick {
		t.Error("dev on didn't ask for a build")
	}
	select {
	case <-m.builds.ch:
		t.Error("dev on kicked the old builds")
	default:
	}
	// A cleared tree while on is refused; off and cleared at once isn't
	if err := m.Set(ctx, DevSetParams{Tree: str("")}); axerr.KindOf(err) != axerr.Refused {
		t.Errorf("cleared while on: %v", err)
	}
	if err := m.Set(ctx, DevSetParams{Enabled: &no, Tree: str("")}); err != nil {
		t.Fatal(err)
	}
	if got := loadDevChoice(m.d.dirs); got != (devChoice{Options: true}) {
		t.Errorf("saved %+v", got)
	}
	if m.gen == gen {
		t.Error("the tree changed, gen didn't")
	}
}

func errString(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

// dev on with a fresh build switches into the dev image at once; a switch
// scheduled refuses others; off from the dev image goes back to the
// installed binary on the install tree and live config.
func TestDevSetSwitches(t *testing.T) {
	t.Parallel()
	f := newStartFixture(t)
	m := f.m
	reexecs := recordReexecs(m)
	ctx := context.Background()
	yes, no := true, false
	m.enabled = false
	if err := m.Set(ctx, DevSetParams{Enabled: &yes}); err != nil {
		t.Fatal(err)
	}
	if !m.State().Enabled {
		t.Error("not on")
	}
	if err := m.Set(ctx, DevSetParams{Enabled: &no}); axerr.KindOf(err) != axerr.Unavailable {
		t.Errorf("a set while switching: %v", err)
	}
	wantReexec(t, reexecs, DevBinary(m.d.dirs), m.devImage(m.tree))
	select {
	case <-m.builds.ch:
		t.Error("a fresh build built again")
	default:
	}

	// The dev image, turned off
	m.switching = false
	m.d.configDir = devConfigDir(m.d.dirs)
	m.d.executable = DevBinary(m.d.dirs)
	if err := m.Set(ctx, DevSetParams{Enabled: &no}); err != nil {
		t.Fatal(err)
	}
	wantReexec(t, reexecs, m.d.installed, image{Tree: "/install", ConfigDir: m.d.dirs.Config})
	// A failed switch lets the next one through
	m.switchFailed()
	if err := m.Set(ctx, DevSetParams{Options: &yes}); err != nil {
		t.Errorf("after a failed switch: %v", err)
	}
}

// The watchers follow dev mode and its tree: a stale build at the start
// is built once the builds run, not before.
func TestDevWatchersTakeTheStartKick(t *testing.T) {
	t.Parallel()
	m := devFixture(t, fakeGo(t, "exit 1"))
	m.d.installed = "" // no binary watch
	m.startKick = true
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	stop := m.watch(ctx, watchKey{enabled: true, tree: m.tree})
	defer stop()
	if !testkit.Eventually(func() bool { st := m.State(); return st.LastBuild != nil && !st.Building }) {
		t.Fatal("the start's build didn't run")
	}
	m.mu.Lock()
	pending := m.startKick
	m.mu.Unlock()
	if pending {
		t.Error("the start's kick is still pending")
	}
}

// With dev mode off, a dev tree set still builds (dev.rebuild): the dev
// build is recorded, fresh for the next dev on, and never run.
func TestDevRebuildWhileOff(t *testing.T) {
	t.Parallel()
	m := devFixture(t, fakeGo(t, buildsAxiom(2)))
	m.enabled = false
	reexecs := recordReexecs(m)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	stop := m.watch(ctx, watchKey{enabled: false, tree: m.tree})
	defer stop()
	m.builds.Kick()
	if !testkit.Eventually(func() bool { st := m.State(); return st.LastBuild != nil && !st.Building }) {
		t.Fatal("the rebuild didn't run")
	}
	st := m.State()
	if !st.LastBuild.OK || !st.Build.Fresh {
		t.Errorf("state after the rebuild %+v", st)
	}
	if b, recorded := readBuild(m.d.dirs); !recorded || b.Tree != m.tree {
		t.Errorf("build.json %+v (recorded %v)", b, recorded)
	}
	noReexec(t, reexecs)
}
