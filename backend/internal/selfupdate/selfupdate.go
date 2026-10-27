// Package selfupdate brings axiom's own git clone up to date from its
// remote (SelfUpdateManager, through the daemon's selfupdate.* methods),
// following one of two channels: "tags" (releases, `v*` tags, to the
// newest) or "main" (the remote's main branch, else master). An update
// only fast-forwards; a clone with changed tracked files, commits of its
// own or another branch checked out is reported as blocked and never
// touched (nothing is stashed, reset or forced). A tree with no .git is
// updated by whatever installed it: it is reported as "nogit" without
// running git at all.
//
// git does the work (the clone may use any remote, transport or
// credential helper the user set up); what its answers mean is decided by
// the pure functions at the bottom (assess, firstError, tagNotes).
package selfupdate

import (
	"bytes"
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// The channels
const (
	ChannelTags = "tags"
	ChannelMain = "main"
)

// Report is the clone as a check or an update left it.
type Report struct {
	Channel string `json:"channel"`
	// The newest release tag at or below HEAD ("" before the first), and
	// HEAD's short commit
	Current string `json:"current"`
	Commit  string `json:"commit"`
	// The newest release, or main's short commit ("" when there is none)
	Latest string `json:"latest"`
	// "uptodate" | "available" | "diverged" | "" (nothing to compare with)
	State string `json:"state"`
	// Ahead: past Latest (a development clone); Behind: commits to Latest
	Ahead  bool `json:"ahead"`
	Behind int  `json:"behind"`
	// Why it can't update: "dirty" | "diverged" | "branch" | "nogit" | ""
	Blocked string `json:"blocked"`
	// The release's tag message, or main's new commit subjects
	Notes string `json:"notes"`
	// After an update: whether the axiom binary was rebuilt from the
	// updated tree, or why that failed (the update itself stays in)
	Rebuilt    bool   `json:"rebuilt"`
	BuildError string `json:"buildError"`
	// Error is git's reason a fetch or an update failed, or why an update
	// was refused; the rest still describes the clone
	Error string `json:"error"`
}

// Options configure an Updater.
type Options struct {
	Dir string // the clone
	// Environ is git's environment (default os.Environ()): the user's
	// ssh agent and credential helpers come from it
	Environ func() []string
	// FetchTimeout bounds a fetch (default a minute)
	FetchTimeout time.Duration
}

// Updater checks and updates one clone, one call at a time (git's index
// and refs aren't shared safely between concurrent runs).
type Updater struct {
	opts Options
	mu   sync.Mutex
}

// New returns an Updater for opts.Dir.
func New(opts Options) *Updater {
	if opts.Environ == nil {
		opts.Environ = os.Environ
	}
	if opts.FetchTimeout == 0 {
		opts.FetchTimeout = time.Minute
	}
	return &Updater{opts: opts}
}

// IsClone reports whether dir is a git checkout (a .git folder, or the
// file a worktree has).
func IsClone(dir string) bool {
	_, err := os.Stat(filepath.Join(dir, ".git"))
	return err == nil
}

// Status describes the clone from the refs it has, without fetching.
func (u *Updater) Status(ctx context.Context, channel string) (Report, error) {
	u.mu.Lock()
	defer u.mu.Unlock()
	r, s, err := u.begin(ctx, channel)
	if err != nil || s == nil {
		return r, err
	}
	return s.inspect(ctx, "")
}

// Check fetches the channel's refs and describes the clone. Offline (or
// any failed fetch), it still describes it from the refs it has, with
// git's reason as the report's Error.
func (u *Updater) Check(ctx context.Context, channel string) (Report, error) {
	u.mu.Lock()
	defer u.mu.Unlock()
	r, s, err := u.begin(ctx, channel)
	if err != nil || s == nil {
		return r, err
	}
	fetched, fetchErr := s.fetch(ctx)
	r, err = s.inspect(ctx, fetched)
	if err == nil && fetchErr != "" {
		r.Error = fetchErr
	}
	return r, err
}

// Apply moves the clone to target, which must be the Latest a check
// reported, still available and not blocked: a fast-forward of the branch
// checked out (main or master), or a detached checkout when HEAD is
// detached. The report is the clone after it; a refusal or a failed
// merge is its Error. It runs to the end once started, whatever ctx does.
func (u *Updater) Apply(ctx context.Context, channel, target string) (Report, error) {
	ctx = context.WithoutCancel(ctx)
	u.mu.Lock()
	defer u.mu.Unlock()
	if target == "" {
		return Report{}, axerr.New(axerr.BadRequest, "no target given")
	}
	r, s, err := u.begin(ctx, channel)
	if err != nil || s == nil {
		if err == nil {
			r.Error = "not a git clone"
		}
		return r, err
	}
	if r, err = s.inspect(ctx, ""); err != nil {
		return r, err
	}
	switch {
	case r.State != "available" || r.Latest != target:
		r.Error = target + " is not an available update"
		return r, nil
	case r.Blocked != "":
		r.Error = "blocked: " + r.Blocked
		return r, nil
	}
	var out []byte
	if s.branch != "" {
		out, err = s.git(ctx, "merge", "--ff-only", "--quiet", s.ref)
	} else {
		out, err = s.git(ctx, "checkout", "--quiet", "--detach", s.ref)
	}
	after, inspectErr := s.inspect(ctx, "")
	if err != nil {
		after.Error = firstError(string(out))
	}
	return after, inspectErr
}

// begin checks the channel and opens a session on the clone (nil, with
// the report saying so, when the tree isn't one).
func (u *Updater) begin(ctx context.Context, channel string) (Report, *session, error) {
	if channel != ChannelTags && channel != ChannelMain {
		return Report{}, nil, axerr.New(axerr.BadRequest, "unknown channel %q", channel)
	}
	r := Report{Channel: channel}
	if !IsClone(u.opts.Dir) {
		r.Blocked = "nogit"
		return r, nil, nil
	}
	s := &session{u: u, channel: channel}
	if _, err := exec.LookPath("git"); err != nil {
		return r, nil, axerr.Wrap(axerr.Unavailable, err, "git isn't installed")
	}
	if out, err := s.git(ctx, "symbolic-ref", "--quiet", "--short", "HEAD"); err == nil {
		s.branch = strings.TrimSpace(string(out))
	}
	s.remote = "origin"
	if s.branch != "" {
		if out, err := s.git(ctx, "config", "branch."+s.branch+".remote"); err == nil && strings.TrimSpace(string(out)) != "" {
			s.remote = strings.TrimSpace(string(out))
		}
	}
	return r, s, nil
}

// session is one call's view of the clone.
type session struct {
	u       *Updater
	channel string
	branch  string // "" when HEAD is detached
	remote  string
	ref     string // what an update moves to (inspect sets it)
}

// git runs git in the clone: never waiting on a password or host-key
// prompt, in the C locale so its messages read the same everywhere.
// The output is stdout and stderr together.
func (s *session) git(ctx context.Context, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, "git", append([]string{"-C", s.u.opts.Dir}, args...)...)
	env := s.u.opts.Environ()
	ssh := "ssh"
	for _, kv := range env {
		if v, ok := strings.CutPrefix(kv, "GIT_SSH_COMMAND="); ok && v != "" {
			ssh = v
		}
	}
	cmd.Env = append(env, "GIT_TERMINAL_PROMPT=0", "GIT_SSH_COMMAND="+ssh+" -o BatchMode=yes", "LC_ALL=C")
	var out bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &out
	err := cmd.Run()
	return out.Bytes(), err
}

// line is a git command's first line of output, "" when it failed.
func (s *session) line(ctx context.Context, args ...string) string {
	out, err := s.git(ctx, args...)
	if err != nil {
		return ""
	}
	first, _, _ := strings.Cut(strings.TrimSpace(string(out)), "\n")
	return first
}

// ancestor reports whether a is an ancestor of b (or b itself).
func (s *session) ancestor(ctx context.Context, a, b string) (bool, error) {
	_, err := s.git(ctx, "merge-base", "--is-ancestor", a, b)
	var exit *exec.ExitError
	switch {
	case err == nil:
		return true, nil
	case errors.As(err, &exit) && exit.ExitCode() == 1:
		return false, nil
	}
	return false, axerr.Wrap(axerr.Internal, err, "comparing %s with %s", a, b)
}

// fetch brings the channel's refs from the remote (on main the release
// tags too, so the installed version still reads as one). It returns the
// branch main found, and git's reason when it failed.
func (s *session) fetch(ctx context.Context) (fetched, failed string) {
	ctx, cancel := context.WithTimeout(ctx, s.u.opts.FetchTimeout)
	defer cancel()
	tags := "refs/tags/v*:refs/tags/v*"
	try := func(refspecs ...string) (string, bool) {
		out, err := s.git(ctx, append([]string{"fetch", "--quiet", "--force", "--no-tags", s.remote}, refspecs...)...)
		if ctx.Err() != nil {
			return "fetch from " + s.remote + " timed out", false
		}
		return string(out), err == nil
	}
	if s.channel == ChannelTags {
		if out, ok := try(tags); !ok {
			return "", firstError(out)
		}
		return "", ""
	}
	var out string
	for _, b := range []string{"main", "master"} {
		var ok bool
		if out, ok = try(tags, "+refs/heads/"+b+":refs/remotes/"+s.remote+"/"+b); ok {
			return b, ""
		}
		if !strings.Contains(out, "couldn't find remote ref") {
			break
		}
	}
	return "", firstError(out)
}

// inspect describes the clone against the channel's newest ref, setting
// s.ref. fetched is the branch a fetch found on main, preferred over a
// stale remote-tracking one.
func (s *session) inspect(ctx context.Context, fetched string) (Report, error) {
	r := Report{Channel: s.channel}
	r.Current = s.line(ctx, "describe", "--tags", "--abbrev=0", "--match", "v*", "HEAD")
	if r.Commit = s.line(ctx, "rev-parse", "--short", "HEAD"); r.Commit == "" {
		return r, axerr.New(axerr.Unavailable, "the clone has no commit checked out")
	}
	s.ref = ""
	if s.channel == ChannelTags {
		if r.Latest = s.line(ctx, "tag", "-l", "v*", "--sort=-v:refname"); r.Latest == "" {
			return r, nil
		}
		s.ref = "refs/tags/" + r.Latest
		if out, err := s.git(ctx, "tag", "-l", "--format=%(contents)", r.Latest); err == nil {
			r.Notes = tagNotes(string(out))
		}
	} else {
		for _, b := range []string{fetched, "main", "master"} {
			ref := "refs/remotes/" + s.remote + "/" + b
			if b != "" && s.line(ctx, "rev-parse", "--quiet", "--verify", ref) != "" {
				s.ref = ref
				break
			}
		}
		if s.ref == "" {
			return r, nil
		}
		r.Latest = s.line(ctx, "rev-parse", "--short", s.ref)
	}
	var f facts
	var err error
	if f.contains, err = s.ancestor(ctx, s.ref, "HEAD"); err != nil {
		return r, err
	}
	if f.contains {
		f.past = s.line(ctx, "rev-parse", "HEAD") != s.line(ctx, "rev-parse", s.ref+"^{commit}")
	} else if f.behind, err = s.ancestor(ctx, "HEAD", s.ref); err != nil {
		return r, err
	}
	if f.behind {
		f.branch = s.branch
		out, err := s.git(ctx, "status", "--porcelain", "--untracked-files=no")
		if err != nil {
			return r, axerr.Wrap(axerr.Internal, err, "reading the clone's status")
		}
		f.dirty = strings.TrimSpace(string(out)) != ""
		r.Behind, _ = strconv.Atoi(s.line(ctx, "rev-list", "--count", "HEAD.."+s.ref))
		if s.channel == ChannelMain {
			if out, err := s.git(ctx, "log", "--no-merges", "--format=- %s", "-n", "30", "HEAD.."+s.ref); err == nil {
				r.Notes = strings.TrimRight(string(out), "\n")
			}
		}
	}
	r.State, r.Ahead, r.Blocked = assess(f)
	return r, nil
}

// facts are what git said about HEAD and the newest ref.
type facts struct {
	contains bool // the ref is HEAD or an ancestor of it
	past     bool // ... and HEAD isn't it
	behind   bool // HEAD is an ancestor of the ref
	branch   string
	dirty    bool // tracked files changed
}

// assess is the state they make, and what blocks an update. Being past
// the newest release is up to date, so switching from main back to tags
// never downgrades.
func assess(f facts) (state string, ahead bool, blocked string) {
	switch {
	case f.contains:
		return "uptodate", f.past, ""
	case !f.behind:
		return "diverged", false, "diverged"
	case f.branch != "" && f.branch != "main" && f.branch != "master":
		return "available", false, "branch"
	case f.dirty:
		return "available", false, "dirty"
	}
	return "available", false, ""
}

// firstError is git's reason rather than its closing advice: the first
// "fatal:" or "error:" line, else the last line.
func firstError(out string) string {
	lines := strings.Split(strings.TrimSpace(out), "\n")
	for _, l := range lines {
		for _, p := range []string{"fatal: ", "error: "} {
			if rest, ok := strings.CutPrefix(l, p); ok {
				return rest
			}
		}
	}
	if last := strings.TrimSpace(lines[len(lines)-1]); last != "" {
		return last
	}
	return "git failed"
}

// tagNotes is a tag's message without its signature.
func tagNotes(contents string) string {
	for _, sig := range []string{"-----BEGIN PGP SIGNATURE-----", "-----BEGIN SSH SIGNATURE-----"} {
		if i := strings.Index(contents, sig); i >= 0 {
			contents = contents[:i]
		}
	}
	return strings.TrimRight(contents, "\n")
}
