package fileindex

import (
	"bufio"
	"bytes"
	"encoding/json"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/command"
	"github.com/axiom-shell/axiom/backend/internal/filesearch"
	"golang.org/x/sys/unix"
)

// child is a running crawl child: its messages come on msgs, the last one
// with done set.
type child struct {
	cmd  *exec.Cmd
	msgs chan childMsg
	stop chan struct{}
	// build: the index's first crawl; stat: a stat pass (whose new
	// folders are crawled next, where a crawl reads them itself); refill:
	// a stat pass of what the index left out (loop.refillPass)
	build, stat, refill bool
	// lane: "" the local lane's, else the network root it reads
	lane string
	// lastFrame: when its last message came; switches: its threads'
	// context switches at the last stuck check (sampled once there was
	// one)
	lastFrame time.Time
	switches  uint64
	sampled   bool
	// exited is closed once it's reaped
	exited chan struct{}
}

type childMsg struct {
	kind  byte
	path  string
	mtime int64
	kids  []filesearch.Child
	done  bool
	err   error
}

// startChild runs `axiom index-crawl` on req in a lane: in a process
// group of its own (killed whole), with nothing of the daemon's
// environment, one P and a small heap (it lowers its own priority before
// it reads anything). A network root's child is read and reaped by
// goroutines nothing waits on: blocked on a dead server, it may never
// end, and neither a reset nor the daemon's shutdown may wait for it.
func (l *loop) startChild(req CrawlRequest, lane string, refill bool) {
	data, err := json.Marshal(req)
	if err != nil {
		return
	}
	cmd := exec.Command(l.s.o.Exe, ChildCommand)
	cmd.Env = []string{"GOMAXPROCS=1", "GOGC=20"}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Stdin = bytes.NewReader(data)
	// The start of what it says
	stderr := &command.Capped{Max: 4096}
	cmd.Stderr = stderr
	stdout, err := cmd.StdoutPipe()
	if err == nil {
		err = cmd.Start()
	}
	if err != nil {
		l.s.o.Log.Warn("file search: the crawl couldn't start", "err", err)
		if l.phase == PhaseCrawling {
			l.errText = "the crawl couldn't start: " + err.Error()
			l.phase = PhaseReady
		}
		l.publish(true)
		return
	}
	c := &child{cmd: cmd, msgs: make(chan childMsg, 64), stop: make(chan struct{}), build: l.phase == PhaseCrawling,
		stat: len(req.Stat) > 0, refill: refill, lane: lane, lastFrame: l.s.o.Now(), exited: make(chan struct{})}
	goFn, reaped := l.wg.Go, l.reaped
	if lane == "" {
		l.child = c
	} else {
		l.netChild = c
		goFn = func(f func()) { go f() }
	}
	goFn(func() {
		r := &frameReader{r: bufio.NewReaderSize(stdout, 64<<10)}
		send := func(m childMsg) bool {
			select {
			case c.msgs <- m:
				return true
			case <-c.stop:
				return false
			}
		}
		var readErr error
		for {
			kind, payload, err := r.next()
			if err != nil {
				readErr = err
				break
			}
			m, ok := decodeMsg(kind, payload)
			if !ok {
				readErr = errFrame
				break
			}
			if !send(m) {
				break
			}
			if kind == msgEnd {
				readErr = nil
				break
			}
		}
		// Drain, so the child never blocks on a full pipe before the
		// kill or its exit
		goFn(func() {
			buf := make([]byte, 32<<10)
			for {
				if _, err := stdout.Read(buf); err != nil {
					return
				}
			}
		})
		err := cmd.Wait()
		close(c.exited)
		signal(reaped)
		if readErr != nil && err == nil {
			err = readErr
		}
		if err != nil {
			if first, _, _ := strings.Cut(strings.TrimSpace(stderr.String()), "\n"); first != "" {
				err = &childError{err: err, said: first}
			}
		}
		send(childMsg{done: true, err: err})
	})
}

type childError struct {
	err  error
	said string
}

func (e *childError) Error() string { return e.err.Error() + ": " + e.said }

// decodeMsg reads one frame. A folder's names point into the frame's own
// bytes (one allocation per folder, none per name).
func decodeMsg(kind byte, payload []byte) (childMsg, bool) {
	m := childMsg{kind: kind}
	c := &cursor{b: bytes.Clone(payload)}
	switch kind {
	case msgDir:
		m.path = string(c.bytes())
		m.mtime = c.varint()
		n := c.uvarint()
		if c.bad || n > uint64(len(c.b)) {
			return m, false
		}
		m.kids = make([]filesearch.Child, 0, n)
		for range n {
			name := c.bytes()
			k := c.byte()
			mt := c.varint()
			if c.bad || len(name) == 0 {
				return m, false
			}
			m.kids = append(m.kids, filesearch.Child{Name: name, Dir: k == kindDir, Link: k == kindLink, Mtime: mt})
		}
	case msgGone:
		m.path = string(c.bytes())
	case msgUnreadable, msgTruncated, msgEnd, msgProgress:
	default:
		return m, false
	}
	return m, !c.bad
}

func (l *loop) childC(c *child) <-chan childMsg {
	if c == nil {
		return nil
	}
	return c.msgs
}

// stopChild stops both lanes' children.
func (l *loop) stopChild() {
	if l.child != nil {
		l.kill(l.child)
		l.child = nil
	}
	l.stopNet()
}

// childMsg applies one of a child's messages.
func (l *loop) childMsg(c *child, m childMsg) {
	if c == nil {
		return
	}
	c.lastFrame = l.s.o.Now()
	ix := l.ix()
	switch {
	case m.done:
		build := c.build
		if c == l.child {
			l.child = nil
		} else {
			l.netChild = nil
			if nl := l.net[c.lane]; nl != nil && m.err == nil {
				// It answers again
				nl.unreachable, nl.backoff = false, 0
			}
		}
		if m.err != nil {
			// The state's error is a build's (the shell says the index
			// couldn't be built); a later run's only logged
			if build {
				l.errText = "the crawl failed: " + m.err.Error()
			}
			l.s.o.Log.Warn("file search: the crawl failed", "err", m.err)
		} else {
			l.errText = ""
		}
		if build {
			l.s.o.Log.Info("file search: indexed", "entries", ix.Len(), "unreadable", l.unreadable, "truncated", l.truncated)
		}
		l.built()
		l.compact()
		l.publish(true)
		l.next()
		return
	case m.kind == msgDir:
		if c.refill && ix.Len() >= l.s.o.MaxEntries {
			// Full again: the rest stays left out (still marked, or
			// never read), not replaced under the lock for nothing
			l.truncated = true
			break
		}
		watched := false
		if d, ok := ix.Lookup(m.path); ok {
			watched = ix.Watched(d)
		}
		l.applyDir(m.path, m.mtime, m.kids, c.stat)
		if watched && c.stat {
			// A stat pass's read of a watched folder (after a lost queue)
			// may land after a newer one the watch made: read it again
			l.recheck(m.path, m.mtime)
		}
	case m.kind == msgGone:
		if l.f.rootOf(m.path) == m.path {
			l.applyDir(m.path, 0, nil, false)
		} else {
			// Gone (its folder drops it) or unreadable: no longer asked
			// for by a refill
			if d, ok := ix.Lookup(m.path); ok {
				l.s.mu.Lock()
				ix.ClearLeftOut(d)
				l.s.mu.Unlock()
			}
			l.changedDir(filepath.Dir(m.path))
		}
	case m.kind == msgUnreadable:
		l.unreadable++
	case m.kind == msgTruncated:
		l.truncated = true
	}
	l.publish(false)
}

// watchEvents takes a read's inotify events.
func (l *loop) watchEvents(evs []event) {
	ix := l.ix()
	if ix == nil {
		return
	}
	for _, ev := range evs {
		if ev.mask&unix.IN_Q_OVERFLOW != 0 {
			// Events were lost: every folder is checked
			l.askAll(func(w *work) { w.statAll = true })
			l.arm()
			continue
		}
		dir, ok := l.w.byWd[ev.wd]
		if !ok {
			continue
		}
		switch {
		case ev.mask&unix.IN_IGNORED != 0:
			// The kernel dropped it (the folder's gone, its disk
			// unmounted): left to the stat pass
			l.w.forget(ev.wd)
			if d, ok := ix.Lookup(dir); ok {
				l.s.mu.Lock()
				ix.SetWatched(d, false)
				l.s.mu.Unlock()
			}
		case ev.mask&(unix.IN_DELETE_SELF|unix.IN_MOVE_SELF) != 0:
			l.w.remove(dir)
			if d, ok := ix.Lookup(dir); ok {
				l.s.mu.Lock()
				ix.SetWatched(d, false)
				l.s.mu.Unlock()
			}
			if l.f.rootOf(dir) == dir {
				l.changedDir(dir)
			} else {
				l.changedDir(filepath.Dir(dir))
			}
		case ev.mask&unix.IN_CLOSE_WRITE != 0:
			if ev.name != "" {
				l.written[join(dir, ev.name)] = true
				l.arm()
			}
		default:
			l.changedDir(dir)
		}
	}
}

// publish sets the state; pushed at once when urgent (a phase changed),
// else at most every PushEvery.
func (l *loop) publish(urgent bool) {
	st := State{Phase: l.phase, Unreadable: l.unreadable, Truncated: l.truncated, Unreachable: l.unreachable(), Error: l.errText}
	if ix := l.ix(); ix != nil {
		st.Entries = ix.Len()
		if l.w != nil {
			st.Watched = len(l.w.byPath)
		}
		st.Unwatched = max(0, ix.Folders()-st.Watched)
	}
	l.s.stateMu.Lock()
	l.s.state = st
	l.s.stateMu.Unlock()
	// Against the last pushed: a change held for the timer is pushed then
	if st == l.pushed {
		return
	}
	now := l.s.o.Now()
	if urgent || now.Sub(l.lastPush) >= l.s.o.PushEvery {
		if l.pushTimer != nil {
			l.pushTimer.Stop()
			l.pushTimer = nil
		}
		l.lastPush, l.pushed = now, st
		l.s.o.OnState(st)
		return
	}
	if l.pushTimer == nil {
		l.pushTimer = time.NewTimer(l.s.o.PushEvery - now.Sub(l.lastPush))
	}
}
