package greeterinstall

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"runtime"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/greeterinstall/rules"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// tools holds the fake programs the tests run (pkexec, tar), written by
// TestMain before any test forks: a program written while another test
// forks can't be run ("text file busy").
var tools string

func TestMain(m *testing.M) {
	dir, err := os.MkdirTemp("", "greeterinstall-tools-")
	if err != nil {
		panic(err)
	}
	tools = dir
	write := func(name, script string) {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(script), 0o755); err != nil {
			panic(err)
		}
	}
	// pkexec, logging its arguments to $FAKE_LOG, running $FAKE_OUT and
	// exiting $FAKE_CODE
	write("pkexec", "#!/bin/sh\nprintf '%s\\n' \"$*\" >\"$FAKE_LOG\"\neval \"$FAKE_OUT\"\nexit \"$FAKE_CODE\"\n")
	// tar/tar, the real tar's archive cut before its end and followed by
	// $FAKE_TAR_JUNK bytes that aren't a tar header
	if tar, err := exec.LookPath("tar"); err == nil {
		os.Mkdir(filepath.Join(dir, "tar"), 0o755)
		write("tar/tar", "#!/bin/sh\n"+tar+" -b 1 \"$@\" | head -c -1024\nhead -c \"$FAKE_TAR_JUNK\" /dev/zero | tr '\\0' x\n")
	}
	code := m.Run()
	os.RemoveAll(dir)
	os.Exit(code)
}

// fixture is a scratch root with greetd, agreety and sway, and a clone of
// axiom (release v1.0) with an upstream it was cloned from: the current
// user stands in for both the user and greetd's user.
type fixture struct {
	t        *testing.T
	tmp      string
	root     string
	repo     string
	upstream string
	user     string
	env      []string
	original string
	// The releases' download url, and the commit the edge prerelease
	// names ("" for no edge build; setEdge)
	releases string
	edge     atomic.Value
}

// setEdge publishes an edge build of commit.
func (f *fixture) setEdge(commit string) { f.edge.Store(commit) }

func newFixture(t *testing.T) *fixture {
	t.Helper()
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git isn't installed")
	}
	me, err := user.Current()
	if err != nil {
		t.Skip(err)
	}
	tmp := t.TempDir()
	f := &fixture{t: t, tmp: tmp, root: filepath.Join(tmp, "root"), repo: filepath.Join(tmp, "repo"),
		upstream: filepath.Join(tmp, "upstream.git"), user: me.Username}
	f.env = append(os.Environ(), "HOME="+tmp, "XDG_CONFIG_HOME="+tmp, "GIT_CONFIG_NOSYSTEM=1",
		"GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@t", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@t")
	f.original = "[terminal]\nvt = 1\n\n[default_session]\n# the greeter\n" +
		"command = \"agreety --cmd /bin/sh\"\nuser = \"" + f.user + "\"\n"
	f.write(f.root, "etc/greetd/config.toml", f.original, 0o644)
	for _, name := range []string{"greetd", "agreety", "sway"} {
		f.write(f.root, "usr/bin/"+name, "#!/bin/sh\n", 0o755)
	}
	if err := os.MkdirAll(filepath.Join(f.root, "etc/systemd/system"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("/usr/lib/systemd/system/sddm.service", filepath.Join(f.root, "etc/systemd/system/display-manager.service")); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"greeter.qml", "shell.qml", "scripts/greeter/greeter-session.sh",
		"scripts/greeter/org.axiom.greeter.policy", "tests/tst_x.qml", "docs/notes.md", "backend/go.mod"} {
		f.write(f.repo, name, name, 0o644)
	}
	f.git(tmp, "init", "-q", "-b", "main", f.repo)
	f.git(f.repo, "add", ".")
	f.git(f.repo, "commit", "-q", "-m", "x")
	f.git(f.repo, "tag", "-a", "v1.0", "-m", "v1.0")
	f.git(tmp, "clone", "-q", "--bare", f.repo, f.upstream)
	f.git(f.repo, "remote", "add", "origin", f.upstream)
	f.edge.Store("")
	f.releases = releasesWithEdge(t, released, "", func() string { return f.edge.Load().(string) })
	return f
}

func (f *fixture) write(dir, name, text string, mode os.FileMode) {
	f.t.Helper()
	path := filepath.Join(dir, name)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		f.t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), mode); err != nil {
		f.t.Fatal(err)
	}
}

func (f *fixture) git(dir string, args ...string) string {
	f.t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir, cmd.Env = dir, f.env
	out, err := cmd.CombinedOutput()
	if err != nil {
		f.t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

func (f *fixture) installer() *Installer {
	return New(Options{Root: f.root, Releases: f.releases, Upstream: f.upstream, Environ: func() []string { return f.env }})
}

func (f *fixture) status(source, channel string) Report {
	f.t.Helper()
	r, err := f.installer().Status(context.Background(), f.repo, source, channel)
	if err != nil {
		f.t.Fatal(err)
	}
	return r
}

func TestStatusBeforeInstall(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	r := f.status(rules.SourceGit, rules.ChannelTags)
	if !r.Greetd || !r.Agreety || r.Compositor != "sway" || r.DisplayManager != "sddm" || r.Installed || r.Configured || r.Helper {
		t.Errorf("report %+v", r)
	}
	if r.GreeterUser != f.user || r.URL != f.upstream {
		t.Errorf("greeter user %q, url %q", r.GreeterUser, r.URL)
	}
	if want := f.git(f.repo, "rev-parse", "v1.0^{commit}"); r.CurrentHash != want {
		t.Errorf("current hash %q, want %q", r.CurrentHash, want)
	}
	local := f.status(rules.SourceLocal, rules.ChannelTags)
	if len(local.CurrentHash) != 64 || local.URL != "" {
		t.Errorf("local: %+v", local)
	}
	// The docs aren't the copy's code; the binary's source is
	f.write(f.repo, "docs/notes.md", "more", 0o644)
	if again := f.status(rules.SourceLocal, rules.ChannelTags); again.CurrentHash != local.CurrentHash {
		t.Error("a docs edit changed the local hash")
	}
	f.write(f.repo, "backend/go.mod", "changed", 0o644)
	if again := f.status(rules.SourceLocal, rules.ChannelTags); again.CurrentHash == local.CurrentHash {
		t.Error("a backend edit didn't change the local hash")
	}
	if _, err := f.installer().Status(context.Background(), filepath.Join(f.tmp, "missing"), "git", "tags"); err == nil {
		t.Error("no error for a missing repo")
	}
}

func TestStatusCompositor(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	os.Remove(filepath.Join(f.root, "usr/bin/sway"))
	f.write(f.root, "usr/local/bin/start-hyprland", "#!/bin/sh\n", 0o755)
	if got := f.status(rules.SourcePackage, rules.ChannelTags).Compositor; got != "hyprland" {
		t.Errorf("compositor %q, want hyprland", got)
	}
	os.Remove(filepath.Join(f.root, "usr/local/bin/start-hyprland"))
	if got := f.status(rules.SourcePackage, rules.ChannelTags).Compositor; got != "" {
		t.Errorf("compositor %q, want none", got)
	}
}

func TestStatusURL(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	// The clone's remote never counts: the official repository does
	f.git(f.repo, "remote", "set-url", "origin", filepath.Join(f.tmp, "missing.git"))
	if r := f.status(rules.SourceGit, rules.ChannelTags); r.URL != f.upstream || r.CurrentHash == "" {
		t.Errorf("report %+v", r)
	}
	// A git install recorded from a fork (before the pin) shows as behind
	f.write(f.root, "usr/share/axiom-greeter/.greeter-source", "git main https://github.com/me/fork.git\n", 0o644)
	f.write(f.root, "usr/share/axiom-greeter/.greeter-hash", "abc\n", 0o644)
	f.setEdge(f.git(f.repo, "rev-parse", "main"))
	r := f.status(rules.SourceGit, rules.ChannelMain)
	if r.URL != f.upstream || r.CurrentHash != f.git(f.repo, "rev-parse", "main") || r.InstalledSource != "git:main" || !r.Installed || r.InstalledHash != "abc" {
		t.Errorf("report %+v", r)
	}
	// Unreachable: nothing to compare with, so never behind
	in := New(Options{Root: f.root, Upstream: filepath.Join(f.tmp, "missing.git"), Environ: func() []string { return f.env }})
	if r, err := in.Status(context.Background(), f.repo, rules.SourceGit, rules.ChannelTags); err != nil || r.CurrentHash != "" {
		t.Errorf("current hash %q for an unreachable repository (%v)", r.CurrentHash, err)
	}
}

// A tree with no .git (a release's source unpacked by hand) has no git
// or local source: it runs no git, and says so
func TestStatusWithoutAClone(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	if !f.status(rules.SourceGit, rules.ChannelTags).Clone {
		t.Error("a clone isn't one")
	}
	if err := os.RemoveAll(filepath.Join(f.repo, ".git")); err != nil {
		t.Fatal(err)
	}
	for _, source := range []string{rules.SourceGit, rules.SourceLocal} {
		r := f.status(source, rules.ChannelTags)
		if r.Clone || r.URL != "" || r.CurrentHash != "" || !r.Greetd {
			t.Errorf("%s: %+v", source, r)
		}
	}
}

func TestStatusPackage(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	f.write(f.root, "usr/share/axiom/.packaged", "1.2.0-1\n", 0o644)
	if got := f.status(rules.SourcePackage, rules.ChannelTags).CurrentHash; got != "1.2.0-1" {
		t.Errorf("package hash %q", got)
	}
}

func TestElevate(t *testing.T) {
	t.Parallel()
	pkexec := filepath.Join(tools, "pkexec")
	req := rules.Request{Action: rules.ActionUpdate, Repo: "/r", User: "me", Source: "local", Channel: "tags", Binary: "/home/me/axiom"}
	for _, tc := range []struct {
		name    string
		helper  string // root's helper's text ("" for none)
		out     string
		code    int
		program string
		want    Elevated
	}{
		{"first install", "", `echo '{"ok": true, "changed": ["/x"], "backup": "/b", "error": ""}'`, 0,
			"/home/me/axiom greeter-install update", Elevated{Result: rules.Result{OK: true, Changed: []string{"/x"}, Backup: "/b"}}},
		{"root's helper", "#!/bin/sh\n" + binariesMarker + " ...)\n", `echo '{"ok": true}'`, 0,
			"ROOT" + HelperPath + " update", Elevated{Result: rules.Result{OK: true}}},
		{"a helper from before the binary", "#!/bin/sh\n", `echo '{"ok": true}'`, 0,
			"/home/me/axiom greeter-install update", Elevated{Result: rules.Result{OK: true}}},
		{"the installer's refusal", "", `echo '{"ok": false, "changed": [], "backup": "", "error": "no such user: me"}'; exit 1`, 0,
			"", Elevated{Result: rules.Result{Changed: []string{}, Error: "no such user: me"}}},
		{"dismissed", "", "", 126, "", Elevated{Dismissed: true}},
		{"a refusal without a reason", "", `echo '{"ok": false}'`, 0, "", Elevated{Result: rules.Result{Error: "pkexec failed (0)"}}},
		{"no agent", "", "echo 'Error executing command as another user: No authentication agent found.' >&2", 127,
			"", Elevated{Result: rules.Result{Error: "Error executing command as another user: No authentication agent found."}}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			root := t.TempDir()
			if tc.helper != "" {
				helper := filepath.Join(root, HelperPath)
				os.MkdirAll(filepath.Dir(helper), 0o755)
				os.WriteFile(helper, []byte(tc.helper), 0o755)
				policy := filepath.Join(root, "usr/share/polkit-1/actions/org.axiom.greeter.policy")
				os.MkdirAll(filepath.Dir(policy), 0o755)
				os.WriteFile(policy, nil, 0o644)
			}
			log := filepath.Join(root, "log")
			env := []string{"FAKE_LOG=" + log, "FAKE_OUT=" + tc.out, fmt.Sprintf("FAKE_CODE=%d", tc.code)}
			in := New(Options{Root: root, Pkexec: pkexec, Environ: func() []string { return env }})
			got, err := in.Elevate(context.Background(), req, nil)
			if err != nil {
				t.Fatal(err)
			}
			if got.OK != tc.want.OK || got.Error != tc.want.Error || got.Backup != tc.want.Backup ||
				got.Dismissed != tc.want.Dismissed || strings.Join(got.Changed, ",") != strings.Join(tc.want.Changed, ",") {
				t.Errorf("got %+v, want %+v", got, tc.want)
			}
			if tc.program != "" {
				ran, _ := os.ReadFile(log)
				want := strings.Replace(tc.program, "ROOT", root, 1) + " /r me  local tags /home/me/axiom"
				if strings.TrimSuffix(string(ran), "\n") != want {
					t.Errorf("ran %q, want %q", ran, want)
				}
			}
		})
	}
}

// Authorized once pkexec has run its program (it execs it after the
// password), never while it only asks
func TestElevateAuthorized(t *testing.T) {
	t.Parallel()
	// The watcher stops with pkexec, authorized or not (after every case)
	t.Cleanup(func() {
		if !testkit.Eventually(func() bool {
			buf := make([]byte, 1<<20)
			return !bytes.Contains(buf[:runtime.Stack(buf, true)], []byte("watchAuthorized"))
		}) {
			t.Error("the watcher outlived pkexec")
		}
	})
	pkexec := filepath.Join(tools, "pkexec")
	req := rules.Request{Action: rules.ActionUpdate, Repo: "/r", User: "me", Source: "local", Channel: "tags", Binary: "/home/me/axiom"}
	for _, tc := range []struct {
		name string
		out  string
		code int
		want bool
	}{
		{"the program runs", `exec sh -c 'sleep 0.6; echo "{\"ok\": true}"'`, 0, true},
		{"dismissed after a while", "sleep 0.6", 126, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			root := t.TempDir()
			env := []string{"FAKE_LOG=" + filepath.Join(root, "log"), "FAKE_OUT=" + tc.out, fmt.Sprintf("FAKE_CODE=%d", tc.code)}
			in := New(Options{Root: root, Pkexec: pkexec, Environ: func() []string { return env }})
			var authorized atomic.Int32
			if _, err := in.Elevate(context.Background(), req, func() { authorized.Add(1) }); err != nil {
				t.Fatal(err)
			}
			if got := authorized.Load(); (got == 1) != tc.want || got > 1 {
				t.Errorf("authorized %d times, want %v", got, tc.want)
			}
		})
	}
}

// For main, a helper older than main's builds (it refuses main) isn't
// run: the first-install program is, here refused for want of an edge
// build, before any prompt
func TestElevateMainNeedsAnEdgeHelper(t *testing.T) {
	t.Parallel()
	pkexec := filepath.Join(tools, "pkexec")
	for _, tc := range []struct {
		name, channel, helper string
		ranHelper             bool
	}{
		{"a helper from before main's builds", rules.ChannelMain, "#!/bin/sh\n" + binariesMarker + " ...)\n", false},
		{"a helper taking main's builds", rules.ChannelMain, "#!/bin/sh\n" + binariesMarker + " ...)\n" + edgeMarker + " ...)\n", true},
		{"tags with a helper from before main's builds", rules.ChannelTags, "#!/bin/sh\n" + binariesMarker + " ...)\n", true},
	} {
		req := rules.Request{Action: rules.ActionUpdate, Repo: "/r", User: "me", Source: rules.SourceGit, Channel: tc.channel}
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			root := t.TempDir()
			helper := filepath.Join(root, HelperPath)
			os.MkdirAll(filepath.Dir(helper), 0o755)
			os.WriteFile(helper, []byte(tc.helper), 0o755)
			policy := filepath.Join(root, "usr/share/polkit-1/actions/org.axiom.greeter.policy")
			os.MkdirAll(filepath.Dir(policy), 0o755)
			os.WriteFile(policy, nil, 0o644)
			log := filepath.Join(root, "log")
			env := []string{"FAKE_LOG=" + log, "FAKE_OUT=echo '{\"ok\": true}'", "FAKE_CODE=0"}
			in := New(Options{Root: root, Pkexec: pkexec, Releases: releases(t, "x", ""), Upstream: filepath.Join(root, "none.git"), Environ: func() []string { return env }})
			got, err := in.Elevate(context.Background(), req, nil)
			if err != nil {
				t.Fatal(err)
			}
			ran, _ := os.ReadFile(log)
			if tc.ranHelper != strings.HasPrefix(string(ran), helper+" ") || tc.ranHelper != got.OK {
				t.Errorf("ran %q, got %+v", ran, got)
			}
			if !tc.ranHelper && !strings.Contains(got.Error, "nothing to fetch") {
				t.Errorf("error %q", got.Error)
			}
		})
	}
}

// Before root has a helper, pkexec runs only a binary root owns or one
// checked against its release's SHA256SUMS (local: the user's own)
func TestFirstProgram(t *testing.T) {
	t.Parallel()
	// (a script, so the check root runs it through can run it)
	released := "#!/bin/sh\necho ran \"$@\"\n"
	for _, tc := range []struct {
		name, source, channel string
		releases              func(t *testing.T, f *fixture) string // nil: the fixture's
		packaged              os.FileMode                           // /usr/bin/axiom's mode (0: none)
		want                  string                                // the program, or the refusal's text
		refused               bool
	}{
		{"local reuses the user's binary", rules.SourceLocal, rules.ChannelTags, nil, 0, "/home/me/axiom greeter-install", false},
		{"the package's binary", rules.SourcePackage, rules.ChannelTags, nil, 0o755, "ROOT/usr/bin/axiom greeter-install", false},
		{"a package binary others can write", rules.SourcePackage, rules.ChannelTags, nil, 0o775, "isn't root's", true},
		{"no package binary", rules.SourcePackage, rules.ChannelTags, nil, 0, "isn't root's", true},
		// (the fixture's remote isn't GitHub's: the release is the official one's)
		{"the release's binary, checked", rules.SourceGit, rules.ChannelTags, func(t *testing.T, _ *fixture) string { return releases(t, released, "") }, 0, "", false},
		{"a release binary its sums don't match", rules.SourceGit, rules.ChannelTags,
			func(t *testing.T, _ *fixture) string { return releases(t, released, strings.Repeat("0", 64)) }, 0, "doesn't match its SHA256SUMS", true},
		{"a release without a binary", rules.SourceGit, rules.ChannelTags, func(t *testing.T, _ *fixture) string { return releases(t, "", "-") }, 0, "no official binary", true},
		{"main's edge build, checked", rules.SourceGit, rules.ChannelMain, func(t *testing.T, f *fixture) string {
			return releasesWithEdge(t, released, "", func() string { return f.edge.Load().(string) })
		}, 0, "", false},
		{"main without an edge build", rules.SourceGit, rules.ChannelMain, func(t *testing.T, _ *fixture) string { return releases(t, released, "") }, 0, "nothing to fetch", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			f := newFixture(t)
			if tc.packaged != 0 {
				f.write(f.root, "usr/bin/axiom", "\x7fELF packaged", tc.packaged)
				os.Chmod(filepath.Join(f.root, "usr/bin/axiom"), tc.packaged)
			}
			opts := Options{Root: f.root, Releases: f.releases, Upstream: f.upstream, Environ: func() []string { return f.env }}
			f.setEdge(f.git(f.repo, "rev-parse", "main"))
			if tc.releases != nil {
				opts.Releases = tc.releases(t, f)
			}
			in := New(opts)
			req := rules.Request{Action: rules.ActionInstall, Repo: f.repo, User: f.user, Source: tc.source, Channel: tc.channel, Binary: "/home/me/axiom"}
			program, stdin, err := in.firstProgram(context.Background(), req)
			if tc.refused {
				if err == nil || !strings.Contains(err.Error(), tc.want) {
					t.Fatalf("program %q, err %v; want a refusal saying %q", program, err, tc.want)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if tc.source != rules.SourceGit {
				if got := strings.Join(program, " "); got != strings.Replace(tc.want, "ROOT", f.root, 1) {
					t.Errorf("program %q, want %q", got, tc.want)
				}
				return
			}
			// The release's bytes on stdin, checked against its sum where
			// root runs them
			if string(stdin) != released {
				t.Errorf("the release binary is %q", stdin)
			}
			for _, tamper := range []bool{false, true} {
				data := stdin
				if tamper {
					data = append([]byte(released), '#')
				}
				cmd := exec.Command(program[0], append(program[1:], "update", "/r")...)
				cmd.Stdin = bytes.NewReader(data)
				out, err := cmd.CombinedOutput()
				if tamper && (err == nil || strings.Contains(string(out), "ran")) {
					t.Errorf("a changed binary ran: %s", out)
				}
				if !tamper && (err != nil || strings.TrimSpace(string(out)) != "ran greeter-install update /r") {
					t.Errorf("the checked binary: %v %s", err, out)
				}
			}
			// Its folder was root's own under the greeter's, and is gone
			if left, err := os.ReadDir(filepath.Join(f.root, "var/lib/axiom-greeter")); err != nil || len(left) != 0 {
				t.Errorf("the greeter's folder: %v %v", left, err)
			}
			// A link there is never followed
			os.Remove(filepath.Join(f.root, "var/lib/axiom-greeter"))
			os.Symlink(t.TempDir(), filepath.Join(f.root, "var/lib/axiom-greeter"))
			cmd := exec.Command(program[0], append(program[1:], "update", "/r")...)
			cmd.Stdin = bytes.NewReader(stdin)
			if out, err := cmd.CombinedOutput(); err == nil || !strings.Contains(string(out), "is a link or isn't root's") {
				t.Errorf("ran through a link: %v %s", err, out)
			}
		})
	}
}

func TestElevateWithoutPkexec(t *testing.T) {
	t.Parallel()
	in := New(Options{Root: t.TempDir(), Pkexec: filepath.Join(t.TempDir(), "pkexec")})
	req := rules.Request{Action: rules.ActionUpdate, Repo: "/r", User: "me", Source: rules.SourceLocal, Channel: rules.ChannelTags, Binary: "/home/me/axiom"}
	if got, err := in.Elevate(context.Background(), req, nil); err == nil {
		t.Errorf("ran without pkexec: %+v", got)
	}
}

// Root's helper counts only with its polkit action beside it.
func TestHelperInstalled(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name                string
		helper              string // "" for none
		policy              bool
		installed, binaries bool
	}{
		{"none", "", false, false, false},
		{"no polkit action", "#!/bin/sh\n" + binariesMarker + "\n", false, false, false},
		{"only the polkit action", "", true, false, false},
		{"from before the binary", "#!/bin/sh\n", true, true, false},
		{"installing the binary", "#!/bin/sh\n" + binariesMarker + " ...)\n", true, true, true},
	} {
		root := t.TempDir()
		in := New(Options{Root: root})
		if tc.helper != "" {
			os.MkdirAll(filepath.Dir(in.path(HelperPath)), 0o755)
			os.WriteFile(in.path(HelperPath), []byte(tc.helper), 0o755)
		}
		if tc.policy {
			os.MkdirAll(filepath.Dir(in.policy()), 0o755)
			os.WriteFile(in.policy(), nil, 0o644)
		}
		if installed, binaries := in.helper(); installed != tc.installed || binaries != tc.binaries {
			t.Errorf("%s: helper() = %v, %v", tc.name, installed, binaries)
		}
	}
}

// Only a regular file root owns and no one else may write counts as
// root's (on a test root, the user running the tests).
func TestRootOwned(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	in := New(Options{Root: root})
	for _, tc := range []struct {
		name string
		mode os.FileMode // 0: missing
		dir  bool
		want bool
	}{
		{"root's", 0o755, false, true},
		{"group-writable", 0o775, false, false},
		{"writable by all", 0o757, false, false},
		{"a folder", 0o755, true, false},
		{"missing", 0, false, false},
	} {
		path := filepath.Join(root, tc.name)
		switch {
		case tc.dir:
			os.Mkdir(path, tc.mode)
		case tc.mode != 0:
			os.WriteFile(path, nil, tc.mode)
			os.Chmod(path, tc.mode)
		}
		if got := in.rootOwned(path); got != tc.want {
			t.Errorf("%s: rootOwned = %v", tc.name, got)
		}
	}
	// On the real root, the user's own file isn't root's
	if os.Getuid() != 0 && New(Options{}).rootOwned(filepath.Join(root, "root's")) {
		t.Error("a user's file counted as root's")
	}
}

// A command's failure is an error, saying its first line of stderr when
// it has one.
func TestCommandErrors(t *testing.T) {
	t.Parallel()
	in := New(Options{Environ: func() []string { return []string{"PATH=/usr/bin:/bin"} }})
	for _, tc := range []struct {
		script, out, err string // err "-": any error
	}{
		{"echo hi", "hi\n", ""},
		{"echo out; echo first >&2; echo second >&2; exit 3", "", "first"},
		{"exit 3", "", "-"},
	} {
		out, err := in.command(context.Background(), cmd{}, "sh", "-c", tc.script)
		switch {
		case tc.err == "" && (err != nil || string(out) != tc.out):
			t.Errorf("%q: %q, %v", tc.script, out, err)
		case tc.err == "-" && err == nil, tc.err != "" && tc.err != "-" && (err == nil || err.Error() != tc.err):
			t.Errorf("%q: error %v, want %q", tc.script, err, tc.err)
		}
	}
}

// Programs come from the environment's PATH, executable regular files only.
func TestLookPath(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "prog"), nil, 0o755)
	os.WriteFile(filepath.Join(dir, "plain"), nil, 0o644)
	os.Mkdir(filepath.Join(dir, "folder"), 0o755)
	path := "::" + filepath.Join(dir, "none") + ":" + dir
	for name, want := range map[string]string{
		"prog":    filepath.Join(dir, "prog"),
		"plain":   "plain",
		"folder":  "folder",
		"missing": "missing",
		"/bin/sh": "/bin/sh",
		"a/prog":  "a/prog",
	} {
		if got := lookPath(name, path); got != want {
			t.Errorf("lookPath(%q) = %q, want %q", name, got, want)
		}
	}
	env := []string{"PATH=/first", "A=1", "AB=x", "A=2"}
	for key, want := range map[string]string{"PATH": "/first", "A": "2", "B": ""} {
		if got := lookupEnv(env, key); got != want {
			t.Errorf("lookupEnv(%q) = %q, want %q", key, got, want)
		}
	}
}
