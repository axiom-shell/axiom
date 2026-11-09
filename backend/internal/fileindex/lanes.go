package fileindex

import (
	"bytes"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"time"

	"golang.org/x/sys/unix"
)

// The children run in two lanes, so a network root whose server is gone
// (its child blocked in the kernel for good) stalls only itself: the
// local lane, one child for every root not on the network, as with no
// network roots at all; and the network lane, one child per network root,
// one at a time. A network child that sent nothing for StuckAfter while
// none of its threads can run and none woke since the last check is
// stuck (one merely starved of CPU at SCHED_IDLE has a runnable thread;
// one reading a slow server wakes on each reply): it's killed, its root
// marked unreachable and tried again with a backoff.

// work is what waits for a lane's child: folders to crawl, stat passes,
// a refill of what the cap left out (refillPass).
type work struct {
	start         []string
	statAll       bool
	statUnwatched bool
	refill        bool
}

// netLane is one network root's work and whether it answers.
type netLane struct {
	work
	// unreachable: its last child got stuck; tried again at retryAt,
	// after a backoff doubling from RetryAfter up to maxRetry
	unreachable bool
	backoff     time.Duration
	retryAt     time.Time
}

// maxRetry caps the backoff of an unreachable root
const maxRetry = time.Hour

// lane is the work of a lane: "" the local one, else a network root's.
func (l *loop) lane(root string) *work {
	if root == "" {
		return &l.work
	}
	return &l.netLane(root).work
}

func (l *loop) netLane(root string) *netLane {
	if l.net == nil {
		l.net = map[string]*netLane{}
	}
	nl := l.net[root]
	if nl == nil {
		nl = &netLane{}
		l.net[root] = nl
	}
	return nl
}

// laneOf is the lane path's work goes to.
func (l *loop) laneOf(path string) string {
	if r := l.f.rootOf(path); l.f.netRoots[r] {
		return r
	}
	return ""
}

// inLane says whether path is lane's (with no network roots, every
// path is the local lane's).
func (l *loop) inLane(path, lane string) bool {
	if lane == "" && len(l.f.netRoots) == 0 {
		return true
	}
	return l.laneOf(path) == lane
}

// localRoots are the roots not on the network.
func (l *loop) localRoots() []string {
	if len(l.f.netRoots) == 0 {
		return l.cur.Roots
	}
	var out []string
	for _, r := range l.cur.Roots {
		if !l.f.netRoots[r] {
			out = append(out, r)
		}
	}
	return out
}

// askAll asks every lane for something (a stat pass, a refill).
func (l *loop) askAll(ask func(*work)) {
	ask(&l.work)
	for r := range l.f.netRoots {
		ask(l.lane(r))
	}
}

// sortLanes moves work to the lane its root is in now: a root moves
// between them when a share is mounted over it or unmounted.
func (l *loop) sortLanes() {
	if len(l.f.netRoots) > 0 && len(l.start) > 0 {
		kept := l.start[:0]
		for _, p := range l.start {
			if lane := l.laneOf(p); lane != "" {
				w := l.lane(lane)
				w.start = append(w.start, p)
			} else {
				kept = append(kept, p)
			}
		}
		l.start = kept
	}
	for r, nl := range l.net {
		if l.f.netRoots[r] {
			continue
		}
		l.start = append(l.start, nl.start...)
		l.statAll = l.statAll || nl.statAll
		l.statUnwatched = l.statUnwatched || nl.statUnwatched
		l.refill = l.refill || nl.refill
		delete(l.net, r)
	}
}

// refillWaits: a lane still waits for its refill pass.
func (l *loop) refillWaits() bool {
	if l.refill {
		return true
	}
	for r, nl := range l.net {
		if nl.refill && l.f.netRoots[r] {
			return true
		}
	}
	return false
}

// anyStart: a lane has folders to crawl.
func (l *loop) anyStart() bool {
	if len(l.start) > 0 {
		return true
	}
	for _, nl := range l.net {
		if len(nl.start) > 0 {
			return true
		}
	}
	return false
}

// built ends the crawling phase once no lane crawls the first build or
// has folders to crawl (but an unreachable root's, crawled when it
// answers again).
func (l *loop) built() {
	if l.phase != PhaseCrawling || len(l.start) > 0 {
		return
	}
	for _, c := range []*child{l.child, l.netChild} {
		if c != nil && c.build {
			return
		}
	}
	for _, nl := range l.net {
		if len(nl.start) > 0 && !nl.unreachable {
			return
		}
	}
	l.phase = PhaseReady
	l.publish(true)
}

// nextNet starts the first network root's job that has one, answers
// (or is due to be tried again) and has no killed child still alive.
func (l *loop) nextNet() {
	now := l.s.o.Now()
	for _, r := range l.cur.Roots {
		nl := l.net[r]
		if nl == nil || !l.f.netRoots[r] {
			continue
		}
		if c := l.reaping[r]; c != nil {
			if !exited(c) {
				if !nl.unreachable && nl.pending() {
					nl.unreachable = true
					l.publish(false)
				}
				continue
			}
			delete(l.reaping, r)
		}
		if nl.unreachable && now.Before(nl.retryAt) {
			continue
		}
		req := l.request([]string{r})
		if start, refill, _ := l.take(&nl.work, &req, r); start {
			l.startChild(req, r, refill)
			if l.netChild != nil {
				return
			}
		}
	}
}

func exited(c *child) bool {
	select {
	case <-c.exited:
		return true
	default:
		return false
	}
}

// pending: the work has something for a child.
func (w *work) pending() bool {
	return len(w.start) > 0 || w.statAll || w.statUnwatched || w.refill
}

// armNet sets the network lane's timer: while a child runs, its stuck
// check every quarter of StuckAfter (a retry due meanwhile waits for the
// child's end, which starts the next job); else the soonest retry of a
// root with work waiting (a retry already due, or one with nothing to
// do, would fire the timer at once, again and again).
func (l *loop) armNet() {
	now := l.s.o.Now()
	var want time.Time
	if l.netChild != nil {
		want = now.Add(l.s.o.StuckAfter / 4)
	} else {
		for r, nl := range l.net {
			if nl.unreachable && nl.pending() && l.f.netRoots[r] && l.reaping[r] == nil && (want.IsZero() || nl.retryAt.Before(want)) {
				want = nl.retryAt
			}
		}
	}
	if want.IsZero() {
		if l.netTimer != nil {
			l.netTimer.Stop()
			l.netTimer = nil
		}
		return
	}
	// An armed timer that fires sooner stays (re-armed only when it
	// fires: arming it again on every call would put a check off forever)
	if l.netTimer != nil && !want.Before(l.netAt) {
		return
	}
	if l.netTimer != nil {
		l.netTimer.Stop()
	}
	l.netAt = want
	l.netTimer = time.NewTimer(max(0, want.Sub(now)))
}

// checkStuck kills the network child when it's stuck: nothing sent for
// StuckAfter, no thread runnable, and not one context switch since the
// last check (never on silence alone: at SCHED_IDLE a busy CPU starves
// it for minutes, and one large folder on a slow server is read in one
// long call). The sleep's kind isn't asked: FUSE (sshfs) waits for its
// server interruptibly (S), NFS and SMB uninterruptibly (D).
// Its root is marked unreachable and asked a stat pass of every folder
// (which also reads those its crawl never reached), after the backoff.
func (l *loop) checkStuck() {
	c := l.netChild
	if c == nil {
		return
	}
	th := l.s.o.Threads(c.cmd.Process.Pid)
	woke := !c.sampled || th.Switches != c.switches
	c.sampled, c.switches = true, th.Switches
	if l.s.o.Now().Sub(c.lastFrame) < l.s.o.StuckAfter || woke || !th.blocked() {
		return
	}
	l.s.o.Log.Warn("file search: a network root doesn't answer: its crawl is stopped and tried again later")
	l.stopNet()
	nl := l.netLane(c.lane)
	nl.unreachable = true
	nl.backoff = min(max(l.s.o.RetryAfter, 2*nl.backoff), maxRetry)
	nl.retryAt = l.s.o.Now().Add(nl.backoff)
	nl.statAll = true
	nl.refill = nl.refill || c.refill
	nl.start = nil
	l.built()
	l.publish(true)
}

// Threads is a process's threads as /proc shows them: their states (a
// letter each) and their context switches, summed.
type Threads struct {
	States   string
	Switches uint64
}

// blocked: it has threads, none runnable (R): all asleep, whatever kind
// of sleep.
func (t Threads) blocked() bool {
	return t.States != "" && !strings.ContainsRune(t.States, 'R')
}

// readThreads reads pid's threads from /proc/<pid>/task/*/stat and
// status (none when it can't: gone, it isn't stuck).
func readThreads(pid int) Threads {
	task := filepath.Join("/proc", strconv.Itoa(pid), "task")
	ents, err := os.ReadDir(task)
	if err != nil {
		return Threads{}
	}
	var out Threads
	var states []byte
	for _, e := range ents {
		data, err := os.ReadFile(filepath.Join(task, e.Name(), "stat"))
		// "pid (comm) S …": the comm may hold anything but the last ')'
		if i := bytes.LastIndexByte(data, ')'); err == nil && i >= 0 && i+2 < len(data) {
			states = append(states, data[i+2])
		}
		status, _ := os.ReadFile(filepath.Join(task, e.Name(), "status"))
		for line := range strings.SplitSeq(string(status), "\n") {
			if k, v, ok := strings.Cut(line, ":"); ok && (k == "voluntary_ctxt_switches" || k == "nonvoluntary_ctxt_switches") {
				n, _ := strconv.ParseUint(strings.TrimSpace(v), 10, 64)
				out.Switches += n
			}
		}
	}
	out.States = string(states)
	return out
}

// stopNet kills the network child; it's reaped in a goroutine nothing
// waits on (one blocked on a dead server may outlive SIGKILL), kept in
// reaping until it is, so its root starts no other meanwhile.
func (l *loop) stopNet() {
	c := l.netChild
	if c == nil {
		return
	}
	l.kill(c)
	if l.reaping == nil {
		l.reaping = map[string]*child{}
	}
	l.reaping[c.lane] = c
	l.netChild = nil
}

// kill kills a child's process group and lets its reader go.
func (l *loop) kill(c *child) {
	if p := c.cmd.Process; p != nil {
		unix.Kill(-p.Pid, unix.SIGKILL)
	}
	close(c.stop)
}

// unreachable counts the network roots marked unreachable.
func (l *loop) unreachable() int {
	n := 0
	if !l.active {
		return 0
	}
	for r, nl := range l.net {
		if nl.unreachable && l.f.netRoots[r] {
			n++
		}
	}
	return n
}

// setNetworkRoots sets the network roots the RPCs leave the disk alone
// for.
func (s *Service) setNetworkRoots(roots []string) {
	s.netMu.Lock()
	defer s.netMu.Unlock()
	if !slices.Equal(roots, s.netRoots) {
		s.netRoots = roots
	}
}
