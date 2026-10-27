package greeterinstall

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/greeterinstall/rules"
)

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
}

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
	return New(Options{Root: f.root, Environ: func() []string { return f.env }})
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
	f.git(f.repo, "remote", "set-url", "origin", "git@github.com:axiom-shell/axiom.git")
	if got := f.installer().git(f.repo, nil).upstreamURL(context.Background(), rules.Origin{}); got != "https://github.com/axiom-shell/axiom.git" {
		t.Errorf("url %q", got)
	}
	// Unreachable: nothing to compare with, so never behind
	f.git(f.repo, "remote", "set-url", "origin", filepath.Join(f.tmp, "missing.git"))
	if r := f.status(rules.SourceGit, rules.ChannelTags); r.CurrentHash != "" {
		t.Errorf("current hash %q for an unreachable remote", r.CurrentHash)
	}
	// A recorded git install's url wins over the clone's remote
	f.write(f.root, "usr/share/axiom-greeter/.greeter-source", "git main "+f.upstream+"\n", 0o644)
	f.write(f.root, "usr/share/axiom-greeter/.greeter-hash", "abc\n", 0o644)
	r := f.status(rules.SourceGit, rules.ChannelMain)
	if r.URL != f.upstream || r.CurrentHash != f.git(f.repo, "rev-parse", "main") || r.InstalledSource != "git:main" || !r.Installed || r.InstalledHash != "abc" {
		t.Errorf("report %+v", r)
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

// fakePkexec is a pkexec that logs its arguments to $FAKE_LOG, runs
// $FAKE_OUT and exits $FAKE_CODE. One for every case, written before any
// of them runs (a program written while another test forks is busy).
func fakePkexec(t *testing.T) string {
	t.Helper()
	pkexec := filepath.Join(t.TempDir(), "pkexec")
	script := "#!/bin/sh\nprintf '%s\\n' \"$*\" >\"$FAKE_LOG\"\neval \"$FAKE_OUT\"\nexit \"$FAKE_CODE\"\n"
	if err := os.WriteFile(pkexec, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	return pkexec
}

// Not parallel: its fake pkexec is written while no other test runs
func TestElevate(t *testing.T) {
	pkexec := fakePkexec(t)
	req := rules.Request{Action: rules.ActionUpdate, Repo: "/r", User: "me", Source: "git", Channel: "tags"}
	first := []string{"/usr/bin/bash", "/r/scripts/greeter/greeter_install.sh"}
	for _, tc := range []struct {
		name    string
		helper  string // root's helper's text ("" for none)
		out     string
		code    int
		program string
		want    Elevated
	}{
		{"first install", "", `echo '{"ok": true, "changed": ["/x"], "backup": "/b", "error": ""}'`, 0,
			"/usr/bin/bash /r/scripts/greeter/greeter_install.sh update", Elevated{Result: rules.Result{OK: true, Changed: []string{"/x"}, Backup: "/b"}}},
		{"root's helper", "#!/bin/sh\n" + binariesMarker + " ...)\n", `echo '{"ok": true}'`, 0,
			"ROOT" + HelperPath + " update", Elevated{Result: rules.Result{OK: true}}},
		{"a helper from before the binary", "#!/bin/sh\n", `echo '{"ok": true}'`, 0,
			"/usr/bin/bash /r/scripts/greeter/greeter_install.sh update", Elevated{Result: rules.Result{OK: true}}},
		{"the installer's refusal", "", `echo '{"ok": false, "changed": [], "backup": "", "error": "no such user: me"}'; exit 1`, 0,
			"", Elevated{Result: rules.Result{Changed: []string{}, Error: "no such user: me"}}},
		{"dismissed", "", "", 126, "", Elevated{Dismissed: true}},
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
			got, err := in.Elevate(context.Background(), req, first)
			if err != nil {
				t.Fatal(err)
			}
			if got.OK != tc.want.OK || got.Error != tc.want.Error || got.Backup != tc.want.Backup ||
				got.Dismissed != tc.want.Dismissed || strings.Join(got.Changed, ",") != strings.Join(tc.want.Changed, ",") {
				t.Errorf("got %+v, want %+v", got, tc.want)
			}
			if tc.program != "" {
				ran, _ := os.ReadFile(log)
				want := strings.Replace(tc.program, "ROOT", root, 1) + " /r me  git tags "
				if strings.TrimSuffix(string(ran), "\n") != want {
					t.Errorf("ran %q, want %q", ran, want)
				}
			}
		})
	}
}
