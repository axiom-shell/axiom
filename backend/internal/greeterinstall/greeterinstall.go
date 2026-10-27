// Package greeterinstall sets axiom up as greetd's login screen, and
// reports how it's set up (GreeterManager, through the daemon's
// greeter.status and greeter.apply). The greeter runs as greetd's user,
// who can't read the user's home, so it gets a copy of axiom of its own,
// owned by root, and a folder the user's axiom exports its config to;
// installing, updating and removing that copy runs as root through pkexec,
// by root's own copy of scripts/greeter/greeter_install.sh once one is
// installed (org.axiom.greeter.policy names it). What to take and from
// where is decided by package rules; this package runs git, reads and
// writes the files. Every system path is under Options.Root, for tests.
package greeterinstall

import (
	"bytes"
	"context"
	"crypto/sha256"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/greeterinstall/rules"
)

// HelperPath is root's copy of the installer, which the installed polkit
// action names: update and uninstall run it.
const HelperPath = "/usr/share/axiom-greeter/scripts/greeter/greeter_install.sh"

// binariesMarker starts a line of every helper that installs the axiom
// binary too: an older one doesn't, and is never run (Report.Binaries).
const binariesMarker = "# (This helper installs the axiom binary too"

// lsRemoteTimeout bounds asking a remote for its refs.
const lsRemoteTimeout = time.Minute

// Options configure an Installer.
type Options struct {
	// Root prefixes every system path ("" or "/" for the real one)
	Root string
	// Environ is the environment of what runs as this process (default
	// os.Environ())
	Environ func() []string
	// Pkexec runs a program as root (default "pkexec")
	Pkexec string
	// Getenv reads this process's variables (default os.Getenv): pkexec's
	// PKEXEC_UID
	Getenv func(string) string
	// Releases replaces the GitHub releases' download url (tests)
	Releases string
	// Now dates the backups (default time.Now)
	Now func() time.Time
}

// Installer sets the greeter up under one root.
type Installer struct {
	opts Options
	root string
}

// New returns an Installer for opts.Root.
func New(opts Options) *Installer {
	if opts.Environ == nil {
		opts.Environ = os.Environ
	}
	if opts.Pkexec == "" {
		opts.Pkexec = "pkexec"
	}
	if opts.Getenv == nil {
		opts.Getenv = os.Getenv
	}
	if opts.Now == nil {
		opts.Now = time.Now
	}
	return &Installer{opts: opts, root: strings.TrimSuffix(opts.Root, "/")}
}

// path is a system path under the root.
func (in *Installer) path(p string) string { return in.root + p }

func (in *Installer) installDir() string   { return in.path("/usr/share/axiom-greeter") }
func (in *Installer) varDir() string       { return in.path("/var/lib/axiom-greeter") }
func (in *Installer) greetdConfig() string { return in.path("/etc/greetd/config.toml") }
func (in *Installer) policy() string {
	return in.path("/usr/share/polkit-1/actions/org.axiom.greeter.policy")
}
func (in *Installer) packageDir() string { return in.path(rules.PackagePath) }

// Report is how the greeter is set up, and what its source stands at.
type Report struct {
	// greetd and its text login (the login screen's fallback) installed
	Greetd  bool `json:"greetd"`
	Agreety bool `json:"agreety"`
	// What the login screen runs in, as greeter-session.sh picks it:
	// "sway" | "hyprland" | "" for neither
	Compositor string `json:"compositor"`
	// display-manager.service's unit ("sddm"), "" for none
	DisplayManager string `json:"displayManager"`
	// A copy is installed, and greetd starts it
	Installed  bool `json:"installed"`
	Configured bool `json:"configured"`
	// Root's helper and its polkit action are installed, and the helper
	// installs the axiom binary too
	Helper   bool `json:"helper"`
	Binaries bool `json:"binaries"`
	// What the copy came from: "git:tags" | "git:main" | "local" |
	// "package" | ""
	InstalledSource string `json:"installedSource"`
	// The url git takes ("" for the other sources)
	URL string `json:"url"`
	// The copy's version, and its source's now ("" when a remote can't be
	// reached). A git hash is the commit, a local one the files' content,
	// a package's its version
	InstalledHash string `json:"installedHash"`
	CurrentHash   string `json:"currentHash"`
	// greetd's default_session user
	GreeterUser string `json:"greeterUser"`
	// The bundle's folder is the user's to write
	BundleWritable bool `json:"bundleWritable"`
	// The tree is a git clone: git and local take their code from one, so
	// a tree with no .git (a release's source unpacked by hand) has
	// neither, only a package
	Clone bool `json:"clone"`
}

// Status describes the setup for the tree at repo, the copy's code to come
// from source (on channel, for git). It runs as the user: nothing here
// needs root.
func (in *Installer) Status(ctx context.Context, repo, source, channel string) (Report, error) {
	if info, err := os.Stat(repo); err != nil || !info.IsDir() {
		return Report{}, axerr.New(axerr.NotFound, "no repo: %s", repo)
	}
	config := readText(in.greetdConfig())
	r := Report{
		Greetd:         executable(in.path("/usr/bin/greetd")) || executable(in.path("/usr/sbin/greetd")),
		Agreety:        executable(in.path("/usr/bin/agreety")),
		Compositor:     in.compositor(),
		Configured:     rules.GreetdValue(config, "command") == rules.Session,
		GreeterUser:    rules.GreetdValue(config, "user"),
		BundleWritable: unix.Access(filepath.Join(in.varDir(), "config"), unix.W_OK) == nil,
	}
	if link, err := os.Readlink(in.path("/etc/systemd/system/display-manager.service")); err == nil {
		r.DisplayManager = strings.TrimSuffix(filepath.Base(link), ".service")
	}
	if hash, err := os.ReadFile(filepath.Join(in.installDir(), ".greeter-hash")); err == nil {
		r.Installed, r.InstalledHash = true, strings.TrimRight(string(hash), "\n")
	}
	r.Helper, r.Binaries = in.helper()
	r.InstalledSource = in.origin().Label()
	_, err := os.Lstat(filepath.Join(repo, ".git"))
	r.Clone = err == nil
	if !r.Clone && source != rules.SourcePackage {
		return r, nil // no git to run, nothing to compare with
	}
	g := in.git(repo, nil)
	if source == rules.SourceGit {
		r.URL = g.upstreamURL(ctx, in.origin())
	}
	r.CurrentHash = in.currentHash(ctx, g, source, channel)
	return r, nil
}

// helper says whether root's helper and its polkit action are installed,
// and whether that helper installs the binary too.
func (in *Installer) helper() (installed, binaries bool) {
	helper := in.path(HelperPath)
	if !executable(helper) || !regular(in.policy()) {
		return false, false
	}
	for line := range strings.Lines(readText(helper)) {
		if strings.HasPrefix(line, binariesMarker) {
			return true, true
		}
	}
	return true, false
}

// origin is what the installed copy was made from.
func (in *Installer) origin() rules.Origin {
	return rules.ParseOrigin(readText(filepath.Join(in.installDir(), ".greeter-source")))
}

// compositor is what greeter-session.sh starts the login screen in: sway,
// else Hyprland (start-hyprland), where greetd's user finds them.
func (in *Installer) compositor() string {
	for _, c := range []struct{ name, program string }{{"sway", "sway"}, {"hyprland", "start-hyprland"}} {
		for _, dir := range []string{"/usr/local/bin/", "/usr/bin/"} {
			if executable(in.path(dir + c.program)) {
				return c.name
			}
		}
	}
	return ""
}

// currentHash is source's version now: the package's, the local files',
// or the commit git's channel stands at ("" when it can't be told).
func (in *Installer) currentHash(ctx context.Context, g gitRunner, source, channel string) string {
	switch source {
	case rules.SourcePackage:
		return firstLine(readText(filepath.Join(in.packageDir(), ".packaged")))
	case rules.SourceLocal:
		hash, _ := g.localHash(ctx)
		return hash
	}
	url := g.upstreamURL(ctx, in.origin())
	if url == "" {
		return ""
	}
	target, _ := in.remoteTarget(ctx, url, channel)
	return target.Commit
}

// remoteTarget asks url for the channel's newest commit (ok false when it
// can't be reached or has none).
func (in *Installer) remoteTarget(ctx context.Context, url, channel string) (rules.Target, bool) {
	ctx, cancel := context.WithTimeout(ctx, lsRemoteTimeout)
	defer cancel()
	out, err := in.git("", nil).run(ctx, nil, "ls-remote", "--sort=-v:refname", url)
	if err != nil {
		return rules.Target{}, false
	}
	return rules.Newest(string(out), channel)
}

// gitRunner runs git in one repository (dir, "" for none), as an account
// (nil: as this process).
type gitRunner struct {
	in  *Installer
	dir string
	as  *account
}

func (in *Installer) git(dir string, as *account) gitRunner {
	return gitRunner{in: in, dir: dir, as: as}
}

// run runs git: never prompting, never running a transport's commands.
func (g gitRunner) run(ctx context.Context, stdout io.Writer, args ...string) ([]byte, error) {
	full := []string{"-c", "protocol.ext.allow=never"}
	if g.dir != "" {
		full = append(full, "-C", g.dir)
	}
	return g.in.command(ctx, cmd{as: g.as, stdout: stdout}, "git", append(full, args...)...)
}

func (g gitRunner) output(ctx context.Context, args ...string) string {
	out, err := g.run(ctx, nil, args...)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

// upstreamURL is the url git takes: the one the installed copy's git
// install recorded (nothing that writes to the clone redirects it later),
// else the clone's remote (its branch's, else origin), as https.
func (g gitRunner) upstreamURL(ctx context.Context, recorded rules.Origin) string {
	if recorded.Source == rules.SourceGit {
		return recorded.URL
	}
	remote := "origin"
	if branch := g.output(ctx, "symbolic-ref", "--quiet", "--short", "HEAD"); branch != "" {
		if r := g.output(ctx, "config", "branch."+branch+".remote"); r != "" {
			remote = r
		}
	}
	url := g.output(ctx, "remote", "get-url", remote)
	if url == "" {
		return ""
	}
	return rules.HTTPSURL(url)
}

// localHash is the hash of the clone's tracked files as they are in the
// working tree (rules.LocalHash), read as the runner's account.
func (g gitRunner) localHash(ctx context.Context) (string, error) {
	out, err := g.run(ctx, nil, "ls-files", "-z", "--cached")
	if err != nil {
		return "", err
	}
	var sums []rules.FileSum
	for _, name := range strings.Split(strings.TrimSuffix(string(out), "\x00"), "\x00") {
		if name == "" || !rules.Hashes(name) {
			continue
		}
		data, err := os.ReadFile(filepath.Join(g.dir, name))
		if err != nil {
			continue // deleted, or unreadable: not part of the copy either
		}
		sums = append(sums, rules.FileSum{Path: name, Sum: sha256.Sum256(data)})
	}
	return rules.LocalHash(sums), nil
}

// account is a user whose commands run as them (when this process is
// root).
type account struct {
	uid, gid uint32
	groups   []uint32
	home     string
}

// cmd is how a command runs.
type cmd struct {
	as     *account  // as this user (nil: as this process)
	dir    string    // in this folder ("" for this process's)
	stdin  io.Reader // from this
	stdout io.Writer // its output to this, else returned
}

// command runs a program. Its error carries the program's first line of
// stderr.
func (in *Installer) command(ctx context.Context, c cmd, name string, args ...string) ([]byte, error) {
	env := in.opts.Environ()
	path := lookupEnv(env, "PATH")
	run := exec.CommandContext(ctx, lookPath(name, path), args...)
	run.Dir, run.Stdin = c.dir, c.stdin
	run.Env = append(env, "GIT_TERMINAL_PROMPT=0", "LC_ALL=C")
	if c.as != nil {
		run.Env = append(run.Env, "HOME="+c.as.home)
		run.SysProcAttr = &syscall.SysProcAttr{Credential: &syscall.Credential{Uid: c.as.uid, Gid: c.as.gid, Groups: c.as.groups}}
	}
	var out, errOut bytes.Buffer
	run.Stdout, run.Stderr = &out, &errOut
	if c.stdout != nil {
		run.Stdout = c.stdout
	}
	if err := run.Run(); err != nil {
		if line := firstLine(strings.TrimSpace(errOut.String())); line != "" {
			return nil, errors.New(line)
		}
		return nil, err
	}
	return out.Bytes(), nil
}

// lookPath finds a program in the environment's PATH (its own, not this
// process's: tests stand fakes in); as it is when it isn't there.
func lookPath(name, path string) string {
	if strings.Contains(name, "/") {
		return name
	}
	for _, dir := range filepath.SplitList(path) {
		if p := filepath.Join(dir, name); dir != "" && executable(p) && regular(p) {
			return p
		}
	}
	return name
}

// lookupEnv is a variable's value in an environment.
func lookupEnv(env []string, key string) string {
	for i := len(env) - 1; i >= 0; i-- {
		if value, ok := strings.CutPrefix(env[i], key+"="); ok {
			return value
		}
	}
	return ""
}

// readText is a file's text ("" when it can't be read).
func readText(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return string(data)
}

func firstLine(s string) string {
	line, _, _ := strings.Cut(s, "\n")
	return line
}

func executable(path string) bool { return unix.Access(path, unix.X_OK) == nil }

func regular(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}
