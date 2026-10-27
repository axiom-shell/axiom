package greeterinstall

import (
	"archive/tar"
	"bytes"
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"os/user"
	"path/filepath"
	"runtime"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"time"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/greeterinstall/rules"
)

// The time limits of what an install waits on.
const (
	fetchTimeout    = 5 * time.Minute
	sumsTimeout     = time.Minute
	downloadTimeout = 5 * time.Minute
)

// loginScreen is what a copy can't do without: a release from before the
// login screen existed has nothing to run.
var loginScreen = []string{"greeter.qml", "scripts/greeter/greeter-session.sh", "scripts/greeter/org.axiom.greeter.policy"}

// failure is why a run as root stopped: its message is the reply's error.
type failure string

func (f failure) Error() string { return string(f) }

func failf(format string, args ...any) error { return failure(fmt.Sprintf(format, args...)) }

// run is one install, update or uninstall: what it changed so far, for
// the reply.
type run struct {
	in      *Installer
	req     rules.Request
	changed []string
	backup  string
	// The user's and greetd's user's accounts; nil while this process
	// isn't root (a test), where their commands run as it
	user, greeter *account
}

// Run carries req out as root: install or update the copy (its code from
// req.Source, its snapshot, greetd's command and the polkit action), or
// uninstall it. The result is the reply root's helper prints.
func (in *Installer) Run(ctx context.Context, req rules.Request) rules.Result {
	r := &run{in: in, req: req}
	var err error
	if req.Action == rules.ActionUninstall {
		err = r.uninstall()
	} else {
		err = r.install(ctx)
	}
	result := rules.Result{OK: err == nil, Changed: r.changed, Backup: r.backup}
	if result.Changed == nil {
		result.Changed = []string{}
	}
	if err != nil {
		var f failure
		if !errors.As(err, &f) {
			err = failf("%v", err)
		}
		result.Error = err.Error()
	}
	return result
}

// isRoot says whether this process is root, which then runs the user's
// commands as them and greetd's user's as that user.
func (in *Installer) isRoot() bool { return os.Geteuid() == 0 }

// lookup is a user's account, for running commands as them.
func lookup(name string) (*account, *user.User, error) {
	u, err := user.Lookup(name)
	if err != nil {
		return nil, nil, err
	}
	uid, _ := strconv.ParseUint(u.Uid, 10, 32)
	gid, _ := strconv.ParseUint(u.Gid, 10, 32)
	a := &account{uid: uint32(uid), gid: uint32(gid), home: u.HomeDir}
	ids, _ := u.GroupIds()
	for _, id := range ids {
		if g, err := strconv.ParseUint(id, 10, 32); err == nil {
			a.groups = append(a.groups, uint32(g))
		}
	}
	return a, u, nil
}

func (r *run) install(ctx context.Context) error {
	in, req := r.in, r.req
	if info, err := os.Stat(req.Repo); err != nil || !info.IsDir() {
		return failf("no repo: %s", req.Repo)
	}
	userAccount, _, err := lookup(req.User)
	if req.User == "" || err != nil {
		return failf("no such user: %s", req.User)
	}
	// Through pkexec, the bundle's folder goes only to whoever authenticated
	if uid := in.opts.Getenv("PKEXEC_UID"); uid != "" {
		if caller, err := user.LookupId(uid); err != nil || caller.Username != req.User {
			return failf("%s isn't the user who ran pkexec", req.User)
		}
	}
	config, err := os.ReadFile(in.greetdConfig())
	if err != nil {
		return failf("greetd isn't installed (%s is missing)", in.greetdConfig())
	}
	if !executable(in.path("/usr/bin/agreety")) {
		// The login screen's fallback: without it a broken greeter locks
		// everyone out
		return failf("agreety (greetd's text login, the login screen's fallback) isn't installed")
	}
	if in.compositor() == "" {
		return failf("neither sway nor Hyprland is installed: the login screen runs in one of them")
	}
	if in.isRoot() && req.User != "root" {
		r.user = userAccount
	}
	if req.Source == rules.SourcePackage {
		if err := in.checkPackage(); err != nil {
			return err
		}
	} else if _, err := in.git(req.Repo, r.user).run(ctx, nil, "rev-parse", "--git-dir"); err != nil {
		return failf("not a git clone: %s", req.Repo)
	}
	greeterName := rules.GreetdValue(string(config), "user")
	if greeterName == "" {
		greeterName = "greeter"
	}
	greeterAccount, _, err := lookup(greeterName)
	if err != nil {
		return failf("greetd's user %s doesn't exist", greeterName)
	}
	if in.isRoot() {
		r.greeter = greeterAccount
	}

	// The greeter's folder: config/ the user's (the bundle), state/
	// greetd's user's (the last user and sessions)
	if err := in.makeVarDir(userAccount, greeterAccount); err != nil {
		return failf("can't make %s", in.varDir())
	}
	r.changed = append(r.changed, in.varDir())

	if err := r.replaceCopy(ctx); err != nil {
		return err
	}
	r.changed = append(r.changed, in.installDir())

	// The polkit action naming the copy's own helper: update and uninstall
	// ask for it by name, and run root's file rather than the user's
	policy, err := os.ReadFile(filepath.Join(in.installDir(), "scripts/greeter/org.axiom.greeter.policy"))
	if err == nil {
		err = writeFile(in.policy(), policy, 0o644)
	}
	if err != nil {
		return failf("can't write %s", in.policy())
	}
	r.changed = append(r.changed, in.policy())
	return r.pointGreetd(string(config))
}

// checkPackage refuses a package root doesn't own: the greeter runs its
// code, and its helper becomes the one polkit runs as root.
func (in *Installer) checkPackage() error {
	dir := in.packageDir()
	if !regular(filepath.Join(dir, ".packaged")) {
		return failf("axiom isn't installed as a package (%s/.packaged is missing)", dir)
	}
	// (on a test root, the user running the tests)
	owner := 0
	if in.root != "" {
		owner = os.Getuid()
	}
	for _, p := range []string{dir, filepath.Join(dir, "scripts/greeter")} {
		if uid, ok := ownerOf(p); !ok || uid != owner {
			return failf("%s isn't root's", dir)
		}
	}
	return nil
}

// makeVarDir makes the greeter's folder and hands its parts over.
func (in *Installer) makeVarDir(u, greeter *account) error {
	config, state := filepath.Join(in.varDir(), "config"), filepath.Join(in.varDir(), "state")
	for _, d := range []struct {
		path  string
		mode  os.FileMode
		owner *account
	}{{in.varDir(), 0o755, nil}, {config, 0o755, u}, {state, 0o700, greeter}} {
		if err := os.MkdirAll(d.path, d.mode); err != nil {
			return err
		}
		if err := os.Chmod(d.path, d.mode); err != nil {
			return err
		}
		if d.owner != nil {
			if err := os.Chown(d.path, int(d.owner.uid), int(d.owner.gid)); err != nil {
				return err
			}
		}
	}
	return nil
}

// replaceCopy builds the new copy beside the old one and swaps it in.
func (r *run) replaceCopy(ctx context.Context) error {
	in := r.in
	stage := in.installDir() + ".new"
	if os.RemoveAll(stage) != nil || os.MkdirAll(stage, 0o755) != nil {
		return failf("can't write %s", stage)
	}
	err := r.fillCopy(ctx, stage)
	if err == nil {
		err = r.snapshot(stage)
	}
	if err == nil {
		err = settle(stage)
	}
	if err != nil {
		os.RemoveAll(stage)
		return err
	}
	old := in.installDir() + ".old"
	os.RemoveAll(old)
	if _, err := os.Lstat(in.installDir()); err == nil {
		if err := os.Rename(in.installDir(), old); err != nil {
			os.RemoveAll(stage)
			return failf("can't replace %s", in.installDir())
		}
	}
	if err := os.Rename(stage, in.installDir()); err != nil {
		os.Rename(old, in.installDir())
		os.RemoveAll(stage)
		return failf("can't replace %s", in.installDir())
	}
	os.RemoveAll(old)
	return nil
}

// fillCopy puts the source's code and binary in stage, and what names
// them (.greeter-hash, .greeter-source).
func (r *run) fillCopy(ctx context.Context, stage string) error {
	in, req := r.in, r.req
	var hash, label string
	var origin rules.Origin
	code := stage
	var target rules.Target
	switch req.Source {
	case rules.SourcePackage:
		// Only what greetd and polkit name by path; the session script runs
		// the package's code (.greeter-source)
		if err := copyTree(filepath.Join(in.packageDir(), "scripts/greeter"), filepath.Join(stage, "scripts/greeter")); err != nil {
			return failf("copying %s/scripts/greeter failed", in.packageDir())
		}
		hash = firstLine(readText(filepath.Join(in.packageDir(), ".packaged")))
		origin = rules.Origin{Source: rules.SourcePackage, Dir: rules.PackagePath}
		label, code = "the package in "+in.packageDir(), in.packageDir()
	case rules.SourceLocal:
		h, n, err := r.localArchive(ctx, stage)
		if err != nil || n == 0 {
			return failf("copying %s failed", req.Repo)
		}
		hash, origin, label = h, rules.Origin{Source: rules.SourceLocal}, req.Repo
	default:
		var err error
		if target, hash, origin, err = r.fetch(ctx, stage); err != nil {
			return err
		}
		label = target.Name()
	}
	for _, file := range loginScreen {
		if !regular(filepath.Join(code, file)) {
			return failf("%s has no login screen (no %s): follow main, or use local", label, file)
		}
	}
	// The binary (a package's is its own, on PATH)
	binary := filepath.Join(stage, "bin/axiom")
	switch req.Source {
	case rules.SourceLocal:
		if err := r.userBinary(ctx, binary); err != nil {
			return err
		}
	case rules.SourceGit:
		// Only a release's, checked against its SHA256SUMS: root runs it at
		// the next update
		data, _, err := in.releaseBinary(ctx, target)
		if err == nil && data != nil {
			err = writeFile(binary, data, 0o755)
		}
		if err != nil {
			return err
		}
		if data == nil {
			return failf("no axiom binary for %s: only a release's prebuilt one, checked against its SHA256SUMS, is installed (follow releases, or use Local)", label)
		}
	}
	if writeFile(filepath.Join(stage, ".greeter-hash"), []byte(hash+"\n"), 0o644) != nil ||
		writeFile(filepath.Join(stage, ".greeter-source"), []byte(origin.String()+"\n"), 0o644) != nil {
		return failf("can't write %s", stage)
	}
	return nil
}

// localArchive copies the clone's tracked files as they are in the working
// tree, uncommitted changes included, read as the user (their git config
// and filters stay theirs, and root follows none of their links): its
// hash (rules.LocalHash) and how many files it copied.
func (r *run) localArchive(ctx context.Context, stage string) (string, int, error) {
	g := r.in.git(r.req.Repo, r.user)
	list, err := g.run(ctx, nil, "ls-files", "-z", "--cached")
	if err != nil {
		return "", 0, err
	}
	pr, pw := io.Pipe()
	done := make(chan error, 1)
	go func() {
		_, err := r.in.command(ctx, cmd{as: r.user, dir: r.req.Repo, stdin: bytes.NewReader(list), stdout: pw},
			"tar", "--null", "--ignore-failed-read", "-T", "-", "-cf", "-")
		pw.CloseWithError(err)
		done <- err
	}()
	var sums []rules.FileSum
	n, err := extract(pr, stage, func(name string, data []byte) bool {
		if rules.Hashes(name) {
			sums = append(sums, rules.FileSum{Path: name, Sum: sha256.Sum256(data)})
		}
		return rules.Ships(name)
	})
	if err == nil {
		_, err = io.Copy(io.Discard, pr) // the archive's padding
	}
	pr.CloseWithError(err)
	if terr := <-done; err == nil {
		err = terr
	}
	return rules.LocalHash(sums), n, err
}

// fetch takes git's channel from the official repository into root's own
// mirror, and its tree into stage.
func (r *run) fetch(ctx context.Context, stage string) (rules.Target, string, rules.Origin, error) {
	in, req := r.in, r.req
	url := in.upstream()
	target, ok := in.remoteTarget(ctx, url, req.Channel)
	if !ok {
		return target, "", rules.Origin{}, failf("nothing to fetch from %s on the %s channel (offline?)", url, req.Channel)
	}
	mirror := filepath.Join(in.varDir(), "upstream.git")
	if _, err := os.Stat(mirror); err != nil {
		if _, err := in.git("", nil).run(ctx, nil, "init", "-q", "--bare", mirror); err != nil {
			return target, "", rules.Origin{}, failf("can't make %s", mirror)
		}
	}
	m := in.git(mirror, nil)
	fetchCtx, cancel := context.WithTimeout(ctx, fetchTimeout)
	defer cancel()
	if _, err := m.run(fetchCtx, nil, "fetch", "-q", "--no-tags", url, "+"+target.Ref+":refs/axiom/target"); err != nil {
		return target, "", rules.Origin{}, failf("fetching %s from %s failed", target.Ref, url)
	}
	hash := m.output(ctx, "rev-parse", "refs/axiom/target^{commit}")
	if hash == "" {
		return target, "", rules.Origin{}, failf("fetched nothing from %s", url)
	}
	var archive bytes.Buffer
	if _, err := m.run(ctx, &archive, "archive", "--format=tar", "refs/axiom/target^{tree}"); err != nil {
		return target, "", rules.Origin{}, failf("archiving %s failed", target.Ref)
	}
	if _, err := extract(&archive, stage, func(name string, _ []byte) bool { return rules.Ships(name) }); err != nil {
		return target, "", rules.Origin{}, failf("unpacking the copy failed")
	}
	return target, hash, rules.Origin{Source: rules.SourceGit, Channel: req.Channel, URL: url}, nil
}

// userBinary copies the binary the user's shell runs, read as the user
// (root follows no link of theirs), refusing anything but a program.
func (r *run) userBinary(ctx context.Context, dest string) error {
	binary := r.req.Binary
	if binary == "" {
		return failf("no axiom binary given (the one the shell runs)")
	}
	var data bytes.Buffer
	if _, err := r.in.command(ctx, cmd{as: r.user, stdout: &data}, "cat", "--", binary); err != nil {
		return failf("reading %s failed", binary)
	}
	if !bytes.HasPrefix(data.Bytes(), []byte("\x7fELF")) {
		return failf("%s isn't a program (axiom's binary)", binary)
	}
	return writeFile(dest, data.Bytes(), 0o755)
}

// releaseBinary downloads the target tag's prebuilt binary for this
// machine from the official repository's GitHub release (rules.Releases,
// never the copy's remote), checked against the release's SHA256SUMS: its
// bytes and that listing's url. nil: there's none (not a tag, no such
// release or asset); a download that doesn't match fails the install.
func (in *Installer) releaseBinary(ctx context.Context, target rules.Target) ([]byte, string, error) {
	asset, ok := rules.ReleaseAsset(runtime.GOARCH)
	if !ok {
		return nil, "", nil
	}
	base := in.opts.Releases
	if base == "" {
		base = rules.Releases
	}
	sumsURL, ok := rules.ReleaseURL(base, target.Tag(), "SHA256SUMS")
	assetURL, _ := rules.ReleaseURL(base, target.Tag(), asset)
	if !ok {
		return nil, "", nil
	}
	sums, err := in.download(ctx, sumsURL, sumsTimeout)
	if err != nil {
		return nil, "", nil
	}
	data, err := in.download(ctx, assetURL, downloadTimeout)
	if err != nil {
		return nil, "", nil
	}
	sum := fmt.Sprintf("%x", sha256.Sum256(data))
	if want := rules.SumFor(string(sums), asset); want == "" || !strings.EqualFold(want, sum) {
		return nil, "", failf("the %s release's %s doesn't match its SHA256SUMS", target.Tag(), asset)
	}
	return data, sumsURL, nil
}

// download is a url's body.
func (in *Installer) download(ctx context.Context, url string, timeout time.Duration) ([]byte, error) {
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("%s: %s", url, resp.Status)
	}
	return io.ReadAll(resp.Body)
}

// snapshot copies what the user's axiom exported into the copy's
// fallback/: the bundle staged for this install (a first install has no
// bundle yet), else the greeter's config/. Either folder is the user's:
// a link there is never followed.
func (r *run) snapshot(stage string) error {
	bundle := filepath.Join(r.in.varDir(), "config")
	if info, err := os.Lstat(r.req.Staged); r.req.Staged != "" && err == nil && info.IsDir() {
		bundle = r.req.Staged
	}
	fallback := filepath.Join(stage, "fallback")
	if err := os.MkdirAll(fallback, 0o755); err != nil {
		return failf("can't write %s", fallback)
	}
	for _, name := range []string{"greeter.json", "theme.json"} {
		if data, err := readUsers(filepath.Join(bundle, name)); err == nil {
			if err := writeFile(filepath.Join(fallback, name), data, 0o644); err != nil {
				return failf("can't write %s", fallback)
			}
		}
	}
	return nil
}

// settle makes the copy root's and readable to everyone, writable only
// by root.
func settle(stage string) error {
	return filepath.WalkDir(stage, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		os.Lchown(p, 0, 0) // (fails, harmlessly, on a test root)
		if d.Type()&fs.ModeSymlink != 0 {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return err
		}
		mode := os.FileMode(0o644)
		if d.IsDir() || info.Mode()&0o100 != 0 {
			mode = 0o755
		}
		return os.Chmod(p, mode)
	})
}

// pointGreetd points greetd's default_session at the session script,
// backing its config up first: the original once, and each change.
func (r *run) pointGreetd(config string) error {
	in := r.in
	path := in.greetdConfig()
	if rules.GreetdValue(config, "command") == rules.Session {
		return nil
	}
	info, err := os.Stat(path)
	if err != nil {
		return failf("can't back up %s", path)
	}
	if _, err := os.Stat(path + ".axiom-original"); err != nil {
		if copyFile(path, path+".axiom-original") != nil {
			return failf("can't back up %s", path)
		}
	}
	r.backup = path + ".axiom-bak-" + in.opts.Now().Format("20060102-150405")
	if copyFile(path, r.backup) != nil {
		return failf("can't back up %s", path)
	}
	if writeFile(path, []byte(rules.PointGreetd(config, rules.Session)), info.Mode().Perm()) != nil {
		return failf("can't write %s", path)
	}
	r.changed = append(r.changed, path)
	return nil
}

// uninstall puts greetd's config back from its backup and removes the
// copy, the greeter's folder (the mirror with it) and the polkit action.
func (r *run) uninstall() error {
	in := r.in
	path := in.greetdConfig()
	if rules.GreetdValue(readText(path), "command") == rules.Session {
		// The config from before axiom's first install, else the latest
		// backup
		original := path + ".axiom-original"
		if !regular(original) {
			backups, _ := filepath.Glob(path + ".axiom-bak-*")
			slices.Sort(backups)
			original = ""
			if len(backups) > 0 {
				original = backups[len(backups)-1]
			}
		}
		if original == "" {
			return failf("no backup of %s to put back", path)
		}
		r.backup = path + ".axiom-bak-" + in.opts.Now().Format("20060102-150405")
		if copyFile(path, r.backup) != nil || copyFile(original, path) != nil {
			return failf("can't restore %s", path)
		}
		// Spent: a later install takes greetd's config as it is then
		os.Remove(path + ".axiom-original")
		r.changed = append(r.changed, path)
	}
	for _, p := range []string{in.installDir(), in.varDir(), in.policy()} {
		if _, err := os.Lstat(p); err != nil {
			continue
		}
		if os.RemoveAll(p) != nil {
			return failf("can't remove %s", p)
		}
		r.changed = append(r.changed, p)
	}
	return nil
}

// extract unpacks a tar's regular files into dir, those keep takes (it
// sees each file's content first), confined to dir: a name leaving it, a
// link or anything else is refused or skipped. It returns how many files
// it wrote.
func extract(r io.Reader, dir string, keep func(name string, data []byte) bool) (int, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return 0, err
	}
	root, err := os.OpenRoot(dir)
	if err != nil {
		return 0, err
	}
	defer root.Close()
	tr := tar.NewReader(r)
	n := 0
	for {
		h, err := tr.Next()
		if errors.Is(err, io.EOF) {
			return n, nil
		}
		if err != nil {
			return n, err
		}
		name := strings.TrimPrefix(filepath.Clean(h.Name), "./")
		if h.Typeflag != tar.TypeReg || !filepath.IsLocal(name) {
			continue // directories come from the files' paths; no links
		}
		data, err := io.ReadAll(tr)
		if err != nil {
			return n, err
		}
		if !keep(name, data) {
			continue
		}
		mode := os.FileMode(0o644)
		if h.Mode&0o100 != 0 {
			mode = 0o755
		}
		if err := root.MkdirAll(filepath.Dir(name), 0o755); err != nil {
			return n, err
		}
		if err := root.WriteFile(name, data, mode); err != nil {
			return n, err
		}
		n++
	}
}

// copyTree copies a folder of root's regular files.
func copyTree(src, dest string) error {
	return filepath.WalkDir(src, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(src, p)
		target := filepath.Join(dest, rel)
		switch {
		case d.IsDir():
			return os.MkdirAll(target, 0o755)
		case d.Type().IsRegular():
			info, err := d.Info()
			if err != nil {
				return err
			}
			data, err := os.ReadFile(p)
			if err != nil {
				return err
			}
			return os.WriteFile(target, data, info.Mode().Perm())
		}
		return nil
	})
}

// copyFile copies a file with its mode, through a temporary file.
func copyFile(src, dest string) error {
	info, err := os.Stat(src)
	if err != nil {
		return err
	}
	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	return writeFile(dest, data, info.Mode().Perm())
}

// writeFile writes a file of root's whole (fsx.ReplaceLink: through a
// temporary file, never through a link), its folder made first.
func writeFile(path string, data []byte, mode os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return fsx.ReplaceLink(path, data, mode)
}

// readUsers reads a file in a folder of the user's, following no link on
// the way (a link there could name a file only root may read).
func readUsers(path string) ([]byte, error) {
	fd, err := unix.Openat2(unix.AT_FDCWD, path, &unix.OpenHow{
		Flags: unix.O_RDONLY | unix.O_CLOEXEC | unix.O_NONBLOCK, Resolve: unix.RESOLVE_NO_SYMLINKS})
	if err != nil {
		return nil, err
	}
	f := os.NewFile(uintptr(fd), path)
	defer f.Close()
	if info, err := f.Stat(); err != nil || !info.Mode().IsRegular() {
		return nil, fmt.Errorf("%s isn't a file", path)
	}
	return io.ReadAll(f)
}

// ownerOf is a file's owner's uid.
func ownerOf(path string) (int, bool) {
	info, err := os.Stat(path)
	if err != nil {
		return 0, false
	}
	st, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return 0, false
	}
	return int(st.Uid), true
}
