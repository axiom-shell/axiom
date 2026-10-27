package selfupdate

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// repos is an upstream with release v1.0.0 and a clone of it.
type repos struct {
	t        *testing.T
	upstream string
	clone    string
	env      []string
}

func newRepos(t *testing.T) *repos {
	t.Helper()
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git isn't installed")
	}
	dir := t.TempDir()
	r := &repos{t: t, upstream: filepath.Join(dir, "upstream"), clone: filepath.Join(dir, "clone")}
	// A scratch HOME: no user git config reaches the tests
	r.env = append(os.Environ(), "HOME="+dir, "XDG_CONFIG_HOME="+dir, "GIT_CONFIG_NOSYSTEM=1",
		"GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@t", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@t")
	r.git(dir, "init", "-q", "-b", "main", r.upstream)
	r.commit(r.upstream, "one")
	r.git(r.upstream, "tag", "-a", "v1.0.0", "-m", "first")
	r.git(dir, "clone", "-q", r.upstream, r.clone)
	return r
}

func (r *repos) git(dir string, args ...string) {
	r.t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir, cmd.Env = dir, r.env
	if out, err := cmd.CombinedOutput(); err != nil {
		r.t.Fatalf("git %v: %v\n%s", args, err, out)
	}
}

func (r *repos) commit(repo, name string) {
	r.t.Helper()
	if err := os.WriteFile(filepath.Join(repo, name+".txt"), []byte(name), 0o644); err != nil {
		r.t.Fatal(err)
	}
	r.git(repo, "add", ".")
	r.git(repo, "commit", "-q", "-m", name)
}

func (r *repos) release(tag, notes string) {
	r.t.Helper()
	r.commit(r.upstream, tag)
	r.git(r.upstream, "tag", "-a", tag, "-m", notes)
}

func (r *repos) updater() *Updater {
	return New(Options{Dir: r.clone, Environ: func() []string { return r.env }})
}

func (r *repos) check(channel string) Report {
	r.t.Helper()
	rep, err := r.updater().Check(context.Background(), channel)
	if err != nil {
		r.t.Fatal(err)
	}
	return rep
}

func (r *repos) apply(channel, target string) Report {
	r.t.Helper()
	rep, err := r.updater().Apply(context.Background(), channel, target)
	if err != nil {
		r.t.Fatal(err)
	}
	return rep
}

func (r *repos) exists(name string) bool {
	_, err := os.Stat(filepath.Join(r.clone, name))
	return err == nil
}

func TestUpToDate(t *testing.T) {
	t.Parallel()
	r := newRepos(t)
	rep := r.check(ChannelTags)
	if rep.State != "uptodate" || rep.Current != "v1.0.0" || rep.Blocked != "" || rep.Error != "" {
		t.Fatalf("%+v", rep)
	}
}

func TestAvailableThenApplied(t *testing.T) {
	t.Parallel()
	r := newRepos(t)
	r.release("v1.1.0", "Better things")
	rep := r.check(ChannelTags)
	if rep.State != "available" || rep.Latest != "v1.1.0" || rep.Behind != 1 || !strings.Contains(rep.Notes, "Better things") {
		t.Fatalf("check: %+v", rep)
	}
	applied := r.apply(ChannelTags, "v1.1.0")
	if applied.State != "uptodate" || applied.Current != "v1.1.0" || applied.Error != "" || !r.exists("v1.1.0.txt") {
		t.Fatalf("apply: %+v", applied)
	}
}

func TestStatusDoesNotFetch(t *testing.T) {
	t.Parallel()
	r := newRepos(t)
	r.release("v1.1.0", "notes")
	rep, err := r.updater().Status(context.Background(), ChannelTags)
	if err != nil || rep.State != "uptodate" || rep.Latest != "v1.0.0" {
		t.Fatalf("%+v %v", rep, err)
	}
}

func TestBlocked(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name    string
		setup   func(r *repos)
		state   string
		blocked string
	}{
		{"dirty", func(r *repos) { os.WriteFile(filepath.Join(r.clone, "one.txt"), []byte("local edit"), 0o644) }, "available", "dirty"},
		{"untracked files don't block", func(r *repos) { os.WriteFile(filepath.Join(r.clone, "new.txt"), nil, 0o644) }, "available", ""},
		{"diverged", func(r *repos) { r.commit(r.clone, "mine") }, "diverged", "diverged"},
		{"branch", func(r *repos) { r.git(r.clone, "checkout", "-q", "-b", "feature") }, "available", "branch"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			r := newRepos(t)
			r.release("v1.1.0", "notes")
			before := r.check(ChannelTags) // fetched before the clone changes
			tc.setup(r)
			rep := r.check(ChannelTags)
			if rep.State != tc.state || rep.Blocked != tc.blocked {
				t.Fatalf("check: %+v (before %+v)", rep, before)
			}
			if tc.blocked == "" {
				return
			}
			applied := r.apply(ChannelTags, "v1.1.0")
			if applied.Error == "" || r.exists("v1.1.0.txt") {
				t.Fatalf("a blocked clone updated: %+v", applied)
			}
			if tc.name == "dirty" {
				if data, _ := os.ReadFile(filepath.Join(r.clone, "one.txt")); string(data) != "local edit" {
					t.Fatalf("the local edit is gone: %q", data)
				}
			}
		})
	}
}

func TestOnlyTheLatestTagApplies(t *testing.T) {
	t.Parallel()
	r := newRepos(t)
	r.release("v1.1.0", "notes")
	r.release("v1.2.0", "notes")
	r.check(ChannelTags)
	if rep := r.apply(ChannelTags, "v1.1.0"); !strings.Contains(rep.Error, "not an available update") {
		t.Fatalf("%+v", rep)
	}
}

func TestVersionOrder(t *testing.T) {
	t.Parallel()
	r := newRepos(t)
	r.release("v1.9.0", "nine")
	r.release("v1.10.0", "ten")
	if rep := r.check(ChannelTags); rep.Latest != "v1.10.0" || rep.Behind != 2 {
		t.Fatalf("%+v", rep)
	}
}

func TestNotAClone(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	u := New(Options{Dir: dir})
	rep, err := u.Check(context.Background(), ChannelTags)
	if err != nil || rep.Blocked != "nogit" || rep.Error != "" {
		t.Fatalf("check: %+v %v", rep, err)
	}
	if rep, _ := u.Apply(context.Background(), ChannelTags, "v1.0.0"); rep.Error == "" {
		t.Fatalf("apply: %+v", rep)
	}
}

func TestBadRequests(t *testing.T) {
	t.Parallel()
	u := New(Options{Dir: t.TempDir()})
	if _, err := u.Check(context.Background(), "nightly"); err == nil {
		t.Fatal("an unknown channel was accepted")
	}
	if _, err := u.Apply(context.Background(), ChannelTags, ""); err == nil {
		t.Fatal("an apply without a target was accepted")
	}
}

func TestMainChannelFollowsCommits(t *testing.T) {
	t.Parallel()
	r := newRepos(t)
	r.commit(r.upstream, "two")
	if rep := r.check(ChannelTags); rep.State != "uptodate" {
		t.Fatalf("tags: %+v", rep)
	}
	rep := r.check(ChannelMain)
	if rep.Channel != "main" || rep.State != "available" || rep.Behind != 1 || rep.Current != "v1.0.0" || !strings.Contains(rep.Notes, "- two") {
		t.Fatalf("main: %+v", rep)
	}
	applied := r.apply(ChannelMain, rep.Latest)
	if applied.State != "uptodate" || applied.Ahead || applied.Error != "" || !r.exists("two.txt") {
		t.Fatalf("apply: %+v", applied)
	}
	// Back on tags, being past the newest release isn't a downgrade
	if rep := r.check(ChannelTags); rep.State != "uptodate" || !rep.Ahead {
		t.Fatalf("back on tags: %+v", rep)
	}
}

// With an edge build, main aims at the commit it was made from, not the
// head, and keeps aiming there without fetching (a status, an apply, a
// restarted daemon)
func TestMainChannelFollowsTheEdgeBuild(t *testing.T) {
	t.Parallel()
	r := newRepos(t)
	r.commit(r.upstream, "two")
	built := r.head(r.upstream)
	r.commit(r.upstream, "three")
	edge := func(context.Context) (string, error) { return built, nil }
	u := New(Options{Dir: r.clone, Environ: func() []string { return r.env }, EdgeCommit: edge})
	rep, err := u.Check(context.Background(), ChannelMain)
	if err != nil || rep.State != "available" || rep.Behind != 1 || rep.Latest != built[:len(rep.Latest)] || strings.Contains(rep.Notes, "three") {
		t.Fatalf("check: %+v %v", rep, err)
	}
	if status := r.status(ChannelMain); status.Latest != rep.Latest {
		t.Fatalf("a status without fetching aims at %q, not %q", status.Latest, rep.Latest)
	}
	applied := r.apply(ChannelMain, rep.Latest)
	if applied.Error != "" || !r.exists("two.txt") || r.exists("three.txt") || r.updater().Head(context.Background()) != built {
		t.Fatalf("apply: %+v", applied)
	}
	// No build any more: main's head again
	none := func(context.Context) (string, error) { return "", errors.New("no edge build") }
	u = New(Options{Dir: r.clone, Environ: func() []string { return r.env }, EdgeCommit: none})
	if rep, err := u.Check(context.Background(), ChannelMain); err != nil || rep.Behind != 1 || !strings.Contains(rep.Notes, "three") {
		t.Fatalf("without a build: %+v %v", rep, err)
	}
	// A build of a commit this clone can't fetch isn't followed
	unknown := func(context.Context) (string, error) { return strings.Repeat("a", 40), nil }
	u = New(Options{Dir: r.clone, Environ: func() []string { return r.env }, EdgeCommit: unknown})
	if rep, err := u.Check(context.Background(), ChannelMain); err != nil || rep.Behind != 1 {
		t.Fatalf("an unknown build: %+v %v", rep, err)
	}
}

func (r *repos) head(repo string) string {
	r.t.Helper()
	cmd := exec.Command("git", "-C", repo, "rev-parse", "HEAD")
	cmd.Env = r.env
	out, err := cmd.Output()
	if err != nil {
		r.t.Fatal(err)
	}
	return strings.TrimSpace(string(out))
}

func (r *repos) status(channel string) Report {
	r.t.Helper()
	rep, err := r.updater().Status(context.Background(), channel)
	if err != nil {
		r.t.Fatal(err)
	}
	return rep
}

func TestMainChannelFallsBackToMaster(t *testing.T) {
	t.Parallel()
	r := newRepos(t)
	r.git(r.upstream, "branch", "-m", "main", "master")
	r.commit(r.upstream, "two")
	if rep := r.check(ChannelMain); rep.State != "available" || rep.Error != "" {
		t.Fatalf("%+v", rep)
	}
}

func TestMainChannelDetachedClone(t *testing.T) {
	t.Parallel()
	r := newRepos(t)
	r.git(r.clone, "checkout", "-q", "v1.0.0")
	r.commit(r.upstream, "two")
	rep := r.check(ChannelMain)
	if rep.State != "available" || rep.Blocked != "" {
		t.Fatalf("%+v", rep)
	}
	if applied := r.apply(ChannelMain, rep.Latest); applied.Error != "" || !r.exists("two.txt") {
		t.Fatalf("apply: %+v", applied)
	}
}

func TestOfflineKeepsTheInstalledVersion(t *testing.T) {
	t.Parallel()
	r := newRepos(t)
	r.git(r.clone, "remote", "set-url", "origin", filepath.Join(t.TempDir(), "gone"))
	rep := r.check(ChannelTags)
	if rep.Error == "" || rep.Current != "v1.0.0" || rep.State != "uptodate" {
		t.Fatalf("%+v", rep)
	}
}

func TestAssess(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		f       facts
		state   string
		ahead   bool
		blocked string
	}{
		{facts{contains: true}, "uptodate", false, ""},
		{facts{contains: true, past: true, dirty: true, branch: "feature"}, "uptodate", true, ""},
		{facts{}, "diverged", false, "diverged"},
		{facts{behind: true, branch: "main"}, "available", false, ""},
		{facts{behind: true, branch: "master", dirty: true}, "available", false, "dirty"},
		{facts{behind: true, branch: "feature", dirty: true}, "available", false, "branch"},
		{facts{behind: true}, "available", false, ""},
	} {
		state, ahead, blocked := assess(tc.f)
		if state != tc.state || ahead != tc.ahead || blocked != tc.blocked {
			t.Errorf("assess(%+v) = %q %v %q", tc.f, state, ahead, blocked)
		}
	}
}

func TestFirstError(t *testing.T) {
	t.Parallel()
	for in, want := range map[string]string{
		"hint: something\nfatal: couldn't find remote ref main\nhint: more": "couldn't find remote ref main",
		"error: Your local changes would be overwritten\nAborting":          "Your local changes would be overwritten",
		"Not possible to fast-forward, aborting.\n":                         "Not possible to fast-forward, aborting.",
		"": "git failed",
	} {
		if got := firstError(in); got != want {
			t.Errorf("firstError(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestTagNotes(t *testing.T) {
	t.Parallel()
	in := "Release notes\n\n- one\n-----BEGIN PGP SIGNATURE-----\nabc\n-----END PGP SIGNATURE-----\n"
	if got := tagNotes(in); got != "Release notes\n\n- one" {
		t.Fatalf("%q", got)
	}
}
