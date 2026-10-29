package greeterinstall

import (
	"archive/tar"
	"bytes"
	"context"
	"crypto/sha256"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/greeterinstall/rules"
	"github.com/axiom-shell/axiom/backend/internal/release"
)

// The binary the shell runs, which a local copy takes
const localBinary = "\x7fELF local binary"

// run runs action as the root side would, from source on channel.
func (f *fixture) run(action, source, channel string, edit ...func(*rules.Request)) rules.Result {
	f.t.Helper()
	return f.runWith(f.installer(), action, source, channel, edit...)
}

func (f *fixture) runWith(in *Installer, action, source, channel string, edit ...func(*rules.Request)) rules.Result {
	f.t.Helper()
	binary := filepath.Join(f.tmp, "axiom-bin")
	if _, err := os.Stat(binary); err != nil {
		f.write(f.tmp, "axiom-bin", localBinary, 0o755)
	}
	req := rules.Request{Action: action, Repo: f.repo, User: f.user, Source: source, Channel: channel, Binary: binary}
	for _, e := range edit {
		e(&req)
	}
	return in.Run(context.Background(), req)
}

// ok runs action and fails the test unless it worked.
func (f *fixture) ok(action, source, channel string, edit ...func(*rules.Request)) rules.Result {
	f.t.Helper()
	r := f.run(action, source, channel, edit...)
	if !r.OK {
		f.t.Fatalf("%s from %s: %s", action, source, r.Error)
	}
	return r
}

// refused runs action and fails the test unless it was refused saying want.
func (f *fixture) refused(want, action, source, channel string, edit ...func(*rules.Request)) {
	f.t.Helper()
	r := f.run(action, source, channel, edit...)
	if r.OK || !strings.Contains(r.Error, want) {
		f.t.Fatalf("%s from %s: %+v, want an error saying %q", action, source, r, want)
	}
}

func (f *fixture) copied(name string) string {
	f.t.Helper()
	data, err := os.ReadFile(filepath.Join(f.root, "usr/share/axiom-greeter", name))
	if err != nil {
		f.t.Fatal(err)
	}
	return string(data)
}

func (f *fixture) exists(name string) bool {
	_, err := os.Lstat(filepath.Join(f.root, name))
	return err == nil
}

func (f *fixture) config() string { return readText(filepath.Join(f.root, "etc/greetd/config.toml")) }

// publish commits text to name on the upstream's main (and tags it).
func (f *fixture) publish(name, text, tag string) {
	f.t.Helper()
	f.write(f.repo, name, text, 0o644)
	f.git(f.repo, "commit", "-qam", name+": "+text)
	if tag != "" {
		f.git(f.repo, "tag", "-a", tag, "-m", tag)
	}
	f.git(f.repo, "push", "-q", "origin", "main", "--tags")
}

func newInstallFixture(t *testing.T) *fixture {
	t.Helper()
	f := newFixture(t)
	for name, mode := range map[string]os.FileMode{"org.axiom.greeter.policy": 0o644, "greeter_install.sh": 0o755} {
		data, err := os.ReadFile("../../../scripts/greeter/" + name)
		if err != nil {
			t.Fatal(err)
		}
		f.write(f.repo, "scripts/greeter/"+name, string(data), mode)
	}
	f.git(f.repo, "add", ".")
	f.git(f.repo, "commit", "-qm", "the policy and the helper")
	f.git(f.repo, "tag", "-f", "-a", "v1.0", "-m", "v1.0")
	f.git(f.repo, "push", "-q", "-f", "origin", "main", "--tags")
	return f
}

// released is every release's binary in the install tests.
const released = "\x7fELF released"

func TestInstallCopiesPointsGreetdAndBacksUp(t *testing.T) {
	t.Parallel()
	f := newInstallFixture(t)
	f.write(f.root, "var/lib/axiom-greeter/config/greeter.json", "{}", 0o644)
	r := f.ok(rules.ActionInstall, rules.SourceGit, rules.ChannelTags)
	if !f.exists("usr/share/axiom-greeter/greeter.qml") || f.exists("usr/share/axiom-greeter/tests") ||
		f.exists("usr/share/axiom-greeter/docs") || f.exists("usr/share/axiom-greeter/backend") {
		t.Error("the copy isn't the shipped files")
	}
	if f.copied("fallback/greeter.json") != "{}" {
		t.Error("no snapshot of the bundle")
	}
	config := f.config()
	if rules.GreetdValue(config, "command") != rules.Session || rules.GreetdValue(config, "user") != f.user || !strings.Contains(config, "vt = 1") {
		t.Errorf("greetd's config:\n%s", config)
	}
	if readText(filepath.Join(f.root, "etc/greetd/config.toml.axiom-original")) != f.original || readText(r.Backup) != f.original {
		t.Error("the original isn't backed up")
	}
	if !f.exists("var/lib/axiom-greeter/state") || !slices.Contains(r.Changed, filepath.Join(f.root, "usr/share/axiom-greeter")) {
		t.Errorf("changed %v", r.Changed)
	}
	s := f.status(rules.SourceGit, rules.ChannelTags)
	if !s.Installed || !s.Configured || !s.BundleWritable || !s.Helper || s.InstalledHash != s.CurrentHash || s.InstalledSource != "git:tags" {
		t.Errorf("status %+v", s)
	}
	// Again: greetd is left alone
	r = f.ok(rules.ActionUpdate, rules.SourceGit, rules.ChannelTags)
	if backups, _ := filepath.Glob(filepath.Join(f.root, "etc/greetd/config.toml.axiom-bak-*")); r.Backup != "" || len(backups) != 1 {
		t.Errorf("backup %q, %d backups", r.Backup, len(backups))
	}
}

func TestInstallSnapshotsAStagedBundle(t *testing.T) {
	t.Parallel()
	f := newInstallFixture(t)
	staged := filepath.Join(f.tmp, "staged")
	f.write(staged, "greeter.json", `{"staged": true}`, 0o644)
	if err := os.Symlink("/etc/hostname", filepath.Join(staged, "theme.json")); err != nil {
		t.Fatal(err)
	}
	f.ok(rules.ActionInstall, rules.SourceGit, rules.ChannelTags, func(r *rules.Request) { r.Staged = staged })
	if f.copied("fallback/greeter.json") != `{"staged": true}` || f.exists("usr/share/axiom-greeter/fallback/theme.json") {
		t.Error("the snapshot isn't the staged bundle's files")
	}
}

func TestGitTagsTakesTheNewestReleaseOnly(t *testing.T) {
	t.Parallel()
	f := newInstallFixture(t)
	f.publish("greeter.qml", "unreleased", "")
	f.ok(rules.ActionInstall, rules.SourceGit, rules.ChannelTags)
	if f.copied("greeter.qml") != "greeter.qml" {
		t.Error("took an unreleased commit")
	}
	f.publish("greeter.qml", "v1.10", "v1.10")
	f.publish("shell.qml", "v1.9", "v1.9")
	s := f.status(rules.SourceGit, rules.ChannelTags)
	if s.CurrentHash != f.git(f.repo, "rev-parse", "v1.10^{commit}") || s.InstalledHash == s.CurrentHash {
		t.Errorf("status %+v", s)
	}
	f.ok(rules.ActionUpdate, rules.SourceGit, rules.ChannelTags)
	if f.copied("greeter.qml") != "v1.10" || f.copied(".greeter-hash") != s.CurrentHash+"\n" {
		t.Error("didn't take v1.10")
	}
}

// The main channel takes the commit main's newest build was made from,
// with that build's binary, even when main has moved on since
func TestGitMainTakesTheEdgeBuild(t *testing.T) {
	t.Parallel()
	f := newInstallFixture(t)
	f.ok(rules.ActionInstall, rules.SourceGit, rules.ChannelTags)
	f.publish("greeter.qml", "on main", "")
	built := f.git(f.repo, "rev-parse", "main")
	f.setEdge(built)
	f.publish("greeter.qml", "not built yet", "")
	if s := f.status(rules.SourceGit, rules.ChannelMain); s.CurrentHash != built {
		t.Errorf("main's current hash %q, want the edge build's %q", s.CurrentHash, built)
	}
	f.ok(rules.ActionUpdate, rules.SourceGit, rules.ChannelMain)
	if f.copied("greeter.qml") != "on main" || f.copied(".greeter-hash") != built+"\n" ||
		f.copied(".greeter-source") != "git main "+f.upstream+"\n" || f.copied("bin/axiom") != released {
		t.Errorf("didn't take the edge build's commit: %q %q", f.copied("greeter.qml"), f.copied(".greeter-hash"))
	}
	if s := f.status(rules.SourceGit, rules.ChannelMain); s.InstalledHash != s.CurrentHash {
		t.Errorf("status %+v", s)
	}
}

// An edge build of a commit that isn't on the official main, or none at
// all, is refused, the copy left as it was
func TestGitMainWithoutAnEdgeBuildOnMain(t *testing.T) {
	t.Parallel()
	f := newInstallFixture(t)
	f.ok(rules.ActionInstall, rules.SourceGit, rules.ChannelTags)
	f.refused("nothing to fetch", rules.ActionUpdate, rules.SourceGit, rules.ChannelMain)
	f.git(f.repo, "checkout", "-q", "-b", "fork")
	f.write(f.repo, "greeter.qml", "not on main", 0o644)
	f.git(f.repo, "commit", "-qam", "fork")
	f.git(f.repo, "push", "-q", "origin", "fork")
	f.setEdge(f.git(f.repo, "rev-parse", "fork"))
	f.refused("isn't on", rules.ActionUpdate, rules.SourceGit, rules.ChannelMain)
	if f.copied("greeter.qml") != "greeter.qml" || f.copied(".greeter-source") != "git tags "+f.upstream+"\n" {
		t.Error("a refused update changed the copy")
	}
}

// Uncommitted edits, local commits and a changed remote don't reach a git
// copy
func TestGitIgnoresTheClone(t *testing.T) {
	t.Parallel()
	f := newInstallFixture(t)
	f.ok(rules.ActionInstall, rules.SourceGit, rules.ChannelTags)
	f.write(f.repo, "greeter.qml", "edited", 0o644)
	f.git(f.repo, "commit", "-qam", "local only")
	other := filepath.Join(f.tmp, "other.git")
	f.git(f.tmp, "clone", "-q", "--bare", f.repo, other)
	f.git(f.repo, "tag", "-a", "v9.0", "-m", "v9.0")
	f.git(f.repo, "push", "-q", other, "v9.0")
	f.git(f.repo, "remote", "set-url", "origin", other)
	if s := f.status(rules.SourceGit, rules.ChannelTags); s.URL != f.upstream || s.InstalledHash != s.CurrentHash {
		t.Errorf("status %+v", s)
	}
	f.ok(rules.ActionUpdate, rules.SourceGit, rules.ChannelTags)
	if f.copied("greeter.qml") != "greeter.qml" {
		t.Error("took the clone's edit")
	}
}

// A copy recorded from a fork (before the pin) updates to the official
// repository's code, and records it
func TestGitUpdatesAForkToTheOfficial(t *testing.T) {
	t.Parallel()
	f := newInstallFixture(t)
	f.ok(rules.ActionInstall, rules.SourceGit, rules.ChannelTags)
	f.write(f.root, "usr/share/axiom-greeter/.greeter-source", "git tags https://github.com/me/fork.git\n", 0o644)
	f.ok(rules.ActionUpdate, rules.SourceGit, rules.ChannelTags)
	if got := f.copied(".greeter-source"); got != "git tags "+f.upstream+"\n" {
		t.Errorf(".greeter-source %q", got)
	}
}

func TestLocalCopiesTheWorkingTree(t *testing.T) {
	t.Parallel()
	f := newInstallFixture(t)
	f.git(f.repo, "checkout", "-q", "-b", "feature")
	f.write(f.repo, "greeter.qml", "uncommitted", 0o644)
	f.ok(rules.ActionInstall, rules.SourceLocal, rules.ChannelTags)
	if f.copied("greeter.qml") != "uncommitted" || f.exists("usr/share/axiom-greeter/docs") || f.copied("bin/axiom") != localBinary {
		t.Error("the copy isn't the working tree and the shell's binary")
	}
	s := f.status(rules.SourceLocal, rules.ChannelTags)
	if s.InstalledSource != "local" || s.InstalledHash != s.CurrentHash || !s.Binaries {
		t.Errorf("status %+v", s)
	}
	f.write(f.repo, "greeter.qml", "edited again", 0o644)
	if s := f.status(rules.SourceLocal, rules.ChannelTags); s.InstalledHash == s.CurrentHash {
		t.Error("an edit isn't an update")
	}
	f.ok(rules.ActionUpdate, rules.SourceLocal, rules.ChannelTags)
	f.write(f.repo, "docs/notes.md", "more", 0o644)
	if s := f.status(rules.SourceLocal, rules.ChannelTags); s.InstalledHash != s.CurrentHash {
		t.Error("a docs edit is an update")
	}
}

func TestLocalBinaryRefusals(t *testing.T) {
	t.Parallel()
	f := newInstallFixture(t)
	f.ok(rules.ActionInstall, rules.SourceLocal, rules.ChannelTags)
	f.refused("no axiom binary given", rules.ActionUpdate, rules.SourceLocal, rules.ChannelTags, func(r *rules.Request) { r.Binary = "" })
	script := filepath.Join(f.tmp, "not-a-program")
	f.write(f.tmp, "not-a-program", "#!/bin/sh\n", 0o755)
	f.refused("isn't a program", rules.ActionUpdate, rules.SourceLocal, rules.ChannelTags, func(r *rules.Request) { r.Binary = script })
	f.refused("reading", rules.ActionUpdate, rules.SourceLocal, rules.ChannelTags, func(r *rules.Request) { r.Binary = script + ".missing" })
	// A failed update leaves the copy as it was
	if f.copied("bin/axiom") != localBinary {
		t.Error("a refused update changed the copy")
	}
}

func TestGitTakesTheReleasesBinary(t *testing.T) {
	t.Parallel()
	f := newInstallFixture(t)
	f.ok(rules.ActionInstall, rules.SourceGit, rules.ChannelTags)
	if f.copied("bin/axiom") != released {
		t.Errorf("binary %q", f.copied("bin/axiom"))
	}
}

// releases serves every tag's release: data as the binary for this
// machine and sums as its SHA256SUMS line (data's own when ""; no binary
// when "-").
func releases(t *testing.T, data, sums string) string {
	return releasesWithEdge(t, data, sums, nil)
}

// releasesWithEdge is releases, with the edge prerelease's COMMIT naming
// what edge returns at the time it's asked (no COMMIT when nil or "").
func releasesWithEdge(t *testing.T, data, sums string, edge func() string) string {
	t.Helper()
	asset, ok := release.Asset(runtime.GOARCH)
	if !ok {
		t.Skip("no release binary for", runtime.GOARCH)
	}
	if sums == "" {
		sums = fmt.Sprintf("%x", sha256.Sum256([]byte(data)))
	}
	commit := func() string {
		if edge == nil {
			return ""
		}
		return edge()
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch tag := strings.Split(strings.TrimPrefix(r.URL.Path, "/"), "/")[0]; r.URL.Path {
		case "/" + tag + "/" + asset:
			if sums == "-" {
				http.NotFound(w, r)
				return
			}
			w.Write([]byte(data))
		case "/" + tag + "/SHA256SUMS":
			fmt.Fprintf(w, "%s  %s\n", sums, asset)
			if c := commit(); tag == release.Edge && c != "" {
				fmt.Fprintf(w, "%x  COMMIT\n", sha256.Sum256([]byte(c+"\n")))
			}
		case "/edge/COMMIT":
			if c := commit(); c != "" {
				fmt.Fprintln(w, c)
				return
			}
			http.NotFound(w, r)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)
	return srv.URL
}

func (f *fixture) withReleases(url string) *Installer {
	return New(Options{Root: f.root, Releases: url, Upstream: f.upstream, Environ: func() []string { return f.env }})
}

func TestGitRefusesABinaryItsSumsDontMatch(t *testing.T) {
	t.Parallel()
	f := newInstallFixture(t)
	r := f.runWith(f.withReleases(releases(t, released, strings.Repeat("0", 64))), rules.ActionInstall, rules.SourceGit, rules.ChannelTags)
	if r.OK || !strings.Contains(r.Error, "doesn't match its SHA256SUMS") || f.exists("usr/share/axiom-greeter") {
		t.Errorf("result %+v", r)
	}
}

// A release without a binary for this machine (one from before the
// release workflow) has
// nothing root may run: refused
func TestGitWithoutAReleaseBinary(t *testing.T) {
	t.Parallel()
	f := newInstallFixture(t)
	r := f.runWith(f.withReleases(releases(t, "", "-")), rules.ActionInstall, rules.SourceGit, rules.ChannelTags)
	if r.OK || !strings.Contains(r.Error, "no axiom binary for v1.0") || f.exists("usr/share/axiom-greeter") {
		t.Errorf("result %+v", r)
	}
}

func TestSwitchingSource(t *testing.T) {
	t.Parallel()
	f := newInstallFixture(t)
	f.ok(rules.ActionInstall, rules.SourceLocal, rules.ChannelTags)
	f.ok(rules.ActionUpdate, rules.SourceGit, rules.ChannelTags)
	if got := f.status(rules.SourceGit, rules.ChannelTags).InstalledSource; got != "git:tags" {
		t.Errorf("installed source %q", got)
	}
}

func TestRefusesAReleaseWithoutALoginScreen(t *testing.T) {
	t.Parallel()
	f := newInstallFixture(t)
	f.git(f.repo, "rm", "-q", "greeter.qml")
	f.git(f.repo, "commit", "-qm", "old")
	f.git(f.repo, "tag", "-a", "v2.0", "-m", "v2.0")
	f.git(f.repo, "push", "-q", "origin", "main", "--tags")
	f.refused("v2.0 has no login screen", rules.ActionInstall, rules.SourceGit, rules.ChannelTags)
	f.refused("has no login screen", rules.ActionInstall, rules.SourceLocal, rules.ChannelTags)
	if f.exists("usr/share/axiom-greeter") || f.exists("usr/share/axiom-greeter.new") {
		t.Error("a refused install left a copy")
	}
}

func TestGitUnreachable(t *testing.T) {
	t.Parallel()
	f := newInstallFixture(t)
	in := New(Options{Root: f.root, Releases: f.releases, Upstream: filepath.Join(f.tmp, "missing.git"), Environ: func() []string { return f.env }})
	if r := f.runWith(in, rules.ActionInstall, rules.SourceGit, rules.ChannelTags); r.OK || !strings.Contains(r.Error, "offline") {
		t.Errorf("result %+v", r)
	}
}

func TestPolicyNamesTheInstalledHelper(t *testing.T) {
	t.Parallel()
	f := newInstallFixture(t)
	f.ok(rules.ActionInstall, rules.SourceGit, rules.ChannelTags)
	policy := readText(filepath.Join(f.root, "usr/share/polkit-1/actions/org.axiom.greeter.policy"))
	if !strings.Contains(policy, `<annotate key="org.freedesktop.policykit.exec.path">`+HelperPath+`<`) {
		t.Errorf("policy:\n%s", policy)
	}
	f.ok(rules.ActionUninstall, "", "")
	if f.exists("usr/share/polkit-1/actions/org.axiom.greeter.policy") {
		t.Error("uninstall left the policy")
	}
}

func TestSectionWithoutACommandGetsOne(t *testing.T) {
	t.Parallel()
	f := newInstallFixture(t)
	f.write(f.root, "etc/greetd/config.toml", "[default_session]\nuser = \""+f.user+"\"\n\n[terminal]\nvt = 1\n", 0o644)
	f.ok(rules.ActionInstall, rules.SourceGit, rules.ChannelTags)
	if config := f.config(); rules.GreetdValue(config, "command") != rules.Session || rules.GreetdValue(config, "user") != f.user {
		t.Errorf("config:\n%s", config)
	}
}

func TestUninstallRestoresTheOriginal(t *testing.T) {
	t.Parallel()
	f := newInstallFixture(t)
	f.ok(rules.ActionInstall, rules.SourceGit, rules.ChannelTags)
	f.ok(rules.ActionUninstall, "", "")
	if f.config() != f.original || f.exists("usr/share/axiom-greeter") || f.exists("var/lib/axiom-greeter") ||
		f.exists("etc/greetd/config.toml.axiom-original") {
		t.Error("uninstall didn't put everything back")
	}
	// A later install backs up the config as it is then
	changed := strings.Replace(f.original, "vt = 1", "vt = 2", 1)
	f.write(f.root, "etc/greetd/config.toml", changed, 0o644)
	f.ok(rules.ActionInstall, rules.SourceGit, rules.ChannelTags)
	f.ok(rules.ActionUninstall, "", "")
	if f.config() != changed {
		t.Error("a reinstall's uninstall didn't restore the config of then")
	}
}

func TestRefusals(t *testing.T) {
	t.Parallel()
	f := newInstallFixture(t)
	f.refused("no such user", rules.ActionInstall, rules.SourceGit, rules.ChannelTags, func(r *rules.Request) { r.User = "no-such-user-here" })
	f.refused("no repo", rules.ActionInstall, rules.SourceGit, rules.ChannelTags, func(r *rules.Request) { r.Repo = filepath.Join(f.tmp, "missing") })
	os.RemoveAll(filepath.Join(f.repo, ".git"))
	f.refused("not a git clone", rules.ActionInstall, rules.SourceLocal, rules.ChannelTags)
	os.Remove(filepath.Join(f.root, "usr/bin/sway"))
	f.refused("neither sway nor Hyprland", rules.ActionInstall, rules.SourceGit, rules.ChannelTags)
	os.Remove(filepath.Join(f.root, "usr/bin/agreety"))
	f.refused("agreety", rules.ActionInstall, rules.SourceGit, rules.ChannelTags)
	os.Remove(filepath.Join(f.root, "etc/greetd/config.toml"))
	f.refused("greetd isn't installed", rules.ActionInstall, rules.SourceGit, rules.ChannelTags)
	if f.exists("usr/share/axiom-greeter") {
		t.Error("a refused install left a copy")
	}
}

// package lays a packaged axiom out at /usr/share/axiom, as its PKGBUILD
// does.
func (f *fixture) packageAxiom(version string) string {
	dir := filepath.Join(f.root, "usr/share/axiom")
	for _, name := range []string{"greeter.qml", "shell.qml", "scripts/greeter/greeter-session.sh", "scripts/greeter/hyprland.lua",
		"scripts/greeter/greeter_install.sh", "scripts/greeter/org.axiom.greeter.policy"} {
		f.write(dir, name, name, 0o644)
	}
	f.write(dir, ".packaged", version+"\n", 0o644)
	return dir
}

// A packaged axiom: the greeter runs the package's code, so the install
// folder gets only scripts/greeter/ and the snapshot, and the package's
// version is its hash
func TestPackageSource(t *testing.T) {
	t.Parallel()
	f := newInstallFixture(t)
	f.refused(".packaged is missing", rules.ActionInstall, rules.SourcePackage, rules.ChannelTags)
	dir := f.packageAxiom("1.2.0-1")
	f.write(f.root, "var/lib/axiom-greeter/config/greeter.json", "{}", 0o644)
	f.ok(rules.ActionInstall, rules.SourcePackage, rules.ChannelTags)
	entries, _ := os.ReadDir(filepath.Join(f.root, "usr/share/axiom-greeter"))
	var names []string
	for _, e := range entries {
		names = append(names, e.Name())
	}
	if !slices.Equal(names, []string{".greeter-hash", ".greeter-source", "fallback", "scripts"}) {
		t.Errorf("the copy holds %v", names)
	}
	if f.copied(".greeter-source") != "package /usr/share/axiom\n" || f.copied("fallback/greeter.json") != "{}" ||
		f.copied("scripts/greeter/greeter_install.sh") != "scripts/greeter/greeter_install.sh" || rules.GreetdValue(f.config(), "command") != rules.Session {
		t.Error("the package's install isn't set up")
	}
	s := f.status(rules.SourcePackage, rules.ChannelTags)
	if s.InstalledSource != "package" || s.InstalledHash != "1.2.0-1" || s.CurrentHash != "1.2.0-1" || s.URL != "" {
		t.Errorf("status %+v", s)
	}
	// The package manager updated it: behind until Update
	f.write(dir, ".packaged", "1.3.0-1\n", 0o644)
	f.ok(rules.ActionUpdate, rules.SourcePackage, rules.ChannelTags)
	if f.copied(".greeter-hash") != "1.3.0-1\n" {
		t.Error("the update didn't take the package's version")
	}
}

func TestBackupsAreDated(t *testing.T) {
	t.Parallel()
	f := newInstallFixture(t)
	at := time.Date(2026, 10, 27, 9, 8, 7, 0, time.Local)
	in := New(Options{Root: f.root, Releases: f.releases, Upstream: f.upstream, Now: func() time.Time { return at }, Environ: func() []string { return f.env }})
	r := f.runWith(in, rules.ActionInstall, rules.SourceGit, rules.ChannelTags)
	if !strings.HasSuffix(r.Backup, "config.toml.axiom-bak-20261027-090807") {
		t.Errorf("backup %q", r.Backup)
	}
}

// A hostile archive (the user's clone, a fetched tree) lands nothing
// outside the copy and no link: escaping names, absolute ones, links,
// and a file under a link's name are each kept out or made plain
func TestExtractTakesNoEscapesOrLinks(t *testing.T) {
	t.Parallel()
	tmp := t.TempDir()
	outside := filepath.Join(tmp, "outside")
	if err := os.MkdirAll(outside, 0o755); err != nil {
		t.Fatal(err)
	}
	var archive bytes.Buffer
	tw := tar.NewWriter(&archive)
	for _, h := range []tar.Header{
		{Name: "../outside/escaped", Typeflag: tar.TypeReg},
		{Name: "a/../../outside/climbed", Typeflag: tar.TypeReg},
		{Name: outside + "/absolute", Typeflag: tar.TypeReg},
		{Name: "link", Typeflag: tar.TypeSymlink, Linkname: outside},
		{Name: "link/through", Typeflag: tar.TypeReg},
		{Name: "hard", Typeflag: tar.TypeLink, Linkname: "/etc/hostname"},
		{Name: "./kept/file", Typeflag: tar.TypeReg},
	} {
		h.Mode, h.Size = 0o644, 1
		if h.Typeflag != tar.TypeReg {
			h.Size = 0
		}
		if err := tw.WriteHeader(&h); err != nil {
			t.Fatal(err)
		}
		if h.Size > 0 {
			tw.Write([]byte("x"))
		}
	}
	tw.Close()
	stage := filepath.Join(tmp, "stage")
	n, err := extract(&archive, stage, func(string, []byte) bool { return true })
	if err != nil {
		t.Fatal(err)
	}
	if entries, _ := os.ReadDir(outside); len(entries) != 0 {
		t.Errorf("wrote outside the copy: %v", entries)
	}
	var got []string
	filepath.WalkDir(stage, func(p string, d os.DirEntry, _ error) error {
		if d.Type()&os.ModeSymlink != 0 {
			t.Errorf("made a link: %s", p)
		}
		if d.Type().IsRegular() {
			rel, _ := filepath.Rel(stage, p)
			got = append(got, rel)
		}
		return nil
	})
	if want := []string{"kept/file", "link/through"}; n != 2 || !slices.Equal(got, want) {
		t.Errorf("extracted %d: %v, want %v", n, got, want)
	}
}
