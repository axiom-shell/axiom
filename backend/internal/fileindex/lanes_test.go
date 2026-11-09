package fileindex

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"slices"
	"strings"
	"sync/atomic"
	"syscall"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"golang.org/x/sys/unix"
)

// has: a query for text lists path (whatever the phase)
func (r *running) has(text, path string) bool {
	return slices.ContainsFunc(r.Query(Query{Text: text, Limit: 50}).Items, func(it Item) bool { return it.Path == path })
}

// A network root's child that sends nothing is killed only when its
// threads say it's stuck in the kernel (none runnable, none woken since
// the last check, in either kind of sleep: FUSE's S, NFS's D), never
// when it's starved or reading a slow server; the local lane goes on
// meanwhile either way
func TestStuckNetworkChild(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		name   string
		states string
		// woken: its context switches grow between checks
		woken  bool
		killed bool
	}{
		{"stuck on FUSE", "SS", false, true},
		{"stuck on NFS", "SD", false, true},
		{"starved", "RS", false, false},
		{"reading a slow server", "SS", true, false},
	} {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			base := tree(t, "local/alpha.txt", "share/beta.txt", "share.hang")
			local, share := base+"/local", base+"/share"
			var checks atomic.Int32
			var pid atomic.Int64
			r := start(t, Options{
				Mountinfo:  fakeMounts(t, true, share),
				StuckAfter: 50 * time.Millisecond,
				RetryAfter: time.Hour,
				Threads: func(p int) Threads {
					pid.Store(int64(p))
					n := checks.Add(1)
					if !c.woken {
						n = 0
					}
					return Threads{States: c.states, Switches: uint64(n)}
				},
			}, Settings{Enabled: true, Roots: []string{local, share}})
			if !testkit.Eventually(func() bool { return r.has("alpha", local+"/alpha.txt") }) {
				t.Fatalf("the local lane waits for the network one (state %+v)", r.State())
			}
			if c.killed {
				ok := testkit.Eventually(func() bool {
					st := r.State()
					return st.Unreachable == 1 && st.Phase == PhaseReady
				})
				if !ok {
					t.Fatalf("not set aside: %+v", r.State())
				}
				// Killed and reaped
				if !testkit.Eventually(func() bool { return unix.Kill(int(pid.Load()), 0) == unix.ESRCH }) {
					t.Error("the stuck child lives on")
				}
				return
			}
			if !testkit.Eventually(func() bool { return checks.Load() >= 4 }) {
				t.Fatal("never checked")
			}
			if st := r.State(); st.Unreachable != 0 || st.Phase != PhaseCrawling || unix.Kill(int(pid.Load()), 0) != nil {
				t.Errorf("a child that isn't stuck was killed: %+v", st)
			}
		})
	}
}

// An unreachable root is tried again after the backoff; a pass that
// ends clears it, and its files are found (from the index: the disk
// isn't looked at for them)
func TestUnreachableRootRecovers(t *testing.T) {
	t.Parallel()
	base := tree(t, "local/alpha.txt", "share/beta.txt", "share.hang")
	local, share := base+"/local", base+"/share"
	r := start(t, Options{
		Mountinfo:  fakeMounts(t, true, share),
		StuckAfter: 50 * time.Millisecond,
		RetryAfter: 50 * time.Millisecond,
		// Blocked while the server is gone; once back, a slow start
		// (a race build's) is only starved
		Threads: func(int) Threads {
			if _, err := os.Stat(share + ".hang"); err == nil {
				return Threads{States: "D"}
			}
			return Threads{States: "R"}
		},
	}, Settings{Enabled: true, Roots: []string{local, share}})
	r.Query(Query{Text: "x"})
	if !testkit.Eventually(func() bool { return r.State().Unreachable == 1 }) {
		t.Fatalf("not set aside: %+v", r.State())
	}
	os.Remove(share + ".hang")
	ok := testkit.Eventually(func() bool { return r.State().Unreachable == 0 && r.has("beta", share+"/beta.txt") })
	if !ok {
		t.Fatalf("never answered again: %+v", r.State())
	}
	items := r.Query(Query{Text: "beta", Limit: 5}).Items
	if len(items) != 1 || items[0].Name != "beta.txt" || items[0].Mtime == 0 {
		t.Errorf("a network root's item: %+v", items)
	}
}

// hungChild runs the test binary as a child that hangs on root (its
// "<root>.hang" made), reaped when the test ends
func hungChild(t *testing.T, root string) *child {
	t.Helper()
	os.WriteFile(root+".hang", nil, 0o600)
	data, _ := json.Marshal(CrawlRequest{Roots: []string{root}})
	cmd := exec.Command(os.Args[0], ChildCommand)
	cmd.Stdin = bytes.NewReader(data)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cmd.Process.Kill()
		cmd.Wait()
	})
	return &child{cmd: cmd, msgs: make(chan childMsg), stop: make(chan struct{}), lane: root, exited: make(chan struct{})}
}

// The backoff doubles from RetryAfter up to an hour; a root whose killed
// child is still alive starts no other, even when its retry is due
func TestBackoffAndOneChildPerRoot(t *testing.T) {
	t.Parallel()
	now := time.Now()
	root := t.TempDir()
	l := loopOn(t, root, &now)
	l.s.o.Mountinfo = fakeMounts(t, true, root)
	l.s.o.Threads = func(int) Threads { return Threads{States: "S"} }
	l.refreshMounts()
	for _, want := range []time.Duration{time.Minute, 2 * time.Minute, 4 * time.Minute} {
		c := hungChild(t, root)
		l.netChild = c
		now = now.Add(2 * l.s.o.StuckAfter)
		l.checkStuck() // samples it
		l.checkStuck()
		nl := l.net[root]
		if l.netChild != nil || !nl.unreachable || nl.backoff != want || !nl.retryAt.Equal(now.Add(want)) || l.reaping[root] != c || !nl.statAll {
			t.Fatalf("after a kill: backoff %v (want %v), %+v", nl.backoff, want, nl)
		}
		close(c.exited)
	}
	l.net[root].backoff = 45 * time.Minute
	l.netChild = hungChild(t, root)
	now = now.Add(2 * l.s.o.StuckAfter)
	l.checkStuck()
	l.checkStuck()
	if b := l.net[root].backoff; b != time.Hour {
		t.Errorf("the backoff isn't capped: %v", b)
	}

	// Due, but the last child lives on (unreaped): no other
	now = now.Add(2 * time.Hour)
	l.nextNet()
	if l.netChild != nil {
		t.Fatal("a second child for a root whose last is alive")
	}
	close(l.reaping[root].exited)
	l.nextNet()
	if l.netChild == nil || l.netChild.lane != root {
		t.Fatal("no child once the last was reaped")
	}
	c := l.netChild
	l.stopNet()
	if !testkit.Eventually(func() bool { return exited(c) }) {
		t.Error("never reaped")
	}
}

// A listing of a network root's folder answers "can't be read" after its
// deadline; while it's stuck, the root's other listings answer so at once
func TestBrowseNetworkDeadline(t *testing.T) {
	t.Parallel()
	root := tree(t, "a/x")
	blocked := root + "/blocks"
	const deadline = 100 * time.Millisecond
	s := New(Options{BrowseDeadline: deadline})
	s.setNetworkRoots([]string{root})
	// A listing of one folder blocks, as a read of a dead share does
	unblock := make(chan struct{})
	s.readDir = func(path string) ([]os.DirEntry, error) {
		if path == blocked {
			<-unblock
		}
		return os.ReadDir(path)
	}
	if _, err := s.Browse(blocked, "", 10, false); axerr.KindOf(err) != axerr.Failed {
		t.Fatalf("past the deadline: %v", err)
	}
	began := time.Now()
	if _, err := s.Browse(root+"/a", "", 10, false); axerr.KindOf(err) != axerr.Failed || time.Since(began) >= deadline/2 {
		t.Fatalf("while one is stuck: %v after %v", err, time.Since(began))
	}
	// The stuck one ends: listings work again
	close(unblock)
	ok := testkit.Eventually(func() bool {
		res, err := s.Browse(root+"/a", "", 10, false)
		return err == nil && len(res.Items) == 1
	})
	if !ok {
		t.Error("listings never came back")
	}
	if _, err := s.Browse(root+"/gone", "", 10, false); axerr.KindOf(err) != axerr.NotFound {
		t.Errorf("a missing folder: %v", err)
	}
}

// The network lane's timer is never armed in the past: a retry due
// while another root's child runs waits for its end, and an unreachable
// root with nothing to do sets none (either would fire the timer at
// once, again and again)
func TestNetTimerNeverDue(t *testing.T) {
	t.Parallel()
	now := time.Now()
	root := t.TempDir()
	l := loopOn(t, root, &now)
	l.s.o.Mountinfo = fakeMounts(t, true, root)
	l.refreshMounts()
	nl := l.netLane(root)
	nl.unreachable, nl.retryAt, nl.statAll = true, now.Add(-time.Second), true
	l.netChild = hungChild(t, root)
	l.armNet()
	if want := now.Add(l.s.o.StuckAfter / 4); !l.netAt.Equal(want) {
		t.Errorf("with a child running: armed for %v, want %v", l.netAt.Sub(now), want.Sub(now))
	}
	l.stopNet()
	close(l.reaping[root].exited)
	delete(l.reaping, root)
	l.netTimer.Stop()
	l.netTimer, nl.statAll = nil, false
	l.armNet()
	if l.netTimer != nil {
		t.Errorf("armed for %v with nothing to do", l.netAt.Sub(now))
	}
}

// A refill asked of both lanes reads the folders never read in each:
// the first lane's pass doesn't clear truncated (their only sign) before
// the other's ran
func TestRefillInBothLanes(t *testing.T) {
	t.Parallel()
	base := tree(t, "local/l1/x", "share/s1/y")
	local, share := base+"/local", base+"/share"
	now := time.Now()
	l := loopOn(t, local, &now)
	l.cur.Roots = []string{local, share}
	l.f = newFilter(l.cur.Roots, nil, nil, false)
	l.ix().AddRoot(share)
	l.readDir(t, share)
	l.s.o.Mountinfo = fakeMounts(t, true, share)
	l.refreshMounts()
	l.truncated = true
	l.askAll(func(w *work) { w.refill = true })
	var req, netReq CrawlRequest
	if !l.refillPass(&req, "") || !slices.Equal(req.Stat, []StatDir{{Path: local + "/l1"}}) {
		t.Fatalf("the local lane's refill: %+v", req.Stat)
	}
	if !l.refillPass(&netReq, share) || !slices.Equal(netReq.Stat, []StatDir{{Path: share + "/s1"}}) {
		t.Fatalf("the network lane's refill: %+v", netReq.Stat)
	}
	if l.truncated {
		t.Error("truncated once both lanes had their pass")
	}
}

// readThreads reads a live process's threads: this one runs (R) and has
// switched before
func TestReadThreads(t *testing.T) {
	t.Parallel()
	th := readThreads(os.Getpid())
	if !strings.ContainsRune(th.States, 'R') || th.Switches == 0 {
		t.Errorf("this process read as %+v", th)
	}
	if th := readThreads(-1); th.blocked() {
		t.Errorf("no process reads as blocked: %+v", th)
	}
}
