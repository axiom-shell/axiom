package fileindex

import (
	"bufio"
	"bytes"
	"encoding/json"
	"os/exec"
	"strings"
	"syscall"
	"time"

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
	// folders are crawled next, where a crawl reads them itself)
	build, stat bool
}

type childMsg struct {
	kind  byte
	path  string
	mtime int64
	kids  []filesearch.Child
	done  bool
	err   error
}

// stderrTail keeps the start of what the child said on stderr.
type stderrTail struct{ buf bytes.Buffer }

func (s *stderrTail) Write(p []byte) (int, error) {
	if room := 4096 - s.buf.Len(); room > 0 {
		s.buf.Write(p[:min(room, len(p))])
	}
	return len(p), nil
}

// startChild runs `axiom index-crawl` on req: in a process group of its
// own (killed whole), with nothing of the daemon's environment, one P and
// a small heap (it lowers its own priority before it reads anything).
func (l *loop) startChild(req CrawlRequest) {
	data, err := json.Marshal(req)
	if err != nil {
		return
	}
	cmd := exec.Command(l.s.o.Exe, ChildCommand)
	cmd.Env = []string{"GOMAXPROCS=1", "GOGC=20"}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Stdin = bytes.NewReader(data)
	stderr := &stderrTail{}
	cmd.Stderr = stderr
	stdout, err := cmd.StdoutPipe()
	if err == nil {
		err = cmd.Start()
	}
	if err != nil {
		l.errText = "the crawl couldn't start: " + err.Error()
		l.s.o.Log.Warn("file search: the crawl couldn't start", "err", err)
		if l.phase == PhaseCrawling {
			l.phase = PhaseReady
		}
		l.publish(true)
		return
	}
	c := &child{cmd: cmd, msgs: make(chan childMsg, 64), stop: make(chan struct{}), build: l.phase == PhaseCrawling, stat: len(req.Stat) > 0}
	l.child = c
	l.wg.Go(func() {
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
		l.wg.Go(func() {
			buf := make([]byte, 32<<10)
			for {
				if _, err := stdout.Read(buf); err != nil {
					return
				}
			}
		})
		err := cmd.Wait()
		if readErr != nil && err == nil {
			err = readErr
		}
		if err != nil {
			if first, _, _ := strings.Cut(strings.TrimSpace(stderr.buf.String()), "\n"); first != "" {
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
	case msgUnreadable, msgTruncated, msgEnd:
	default:
		return m, false
	}
	return m, !c.bad
}

func (l *loop) childC() <-chan childMsg {
	if l.child == nil {
		return nil
	}
	return l.child.msgs
}

// stopChild kills the child's process group and lets its reader go.
func (l *loop) stopChild() {
	if l.child == nil {
		return
	}
	if p := l.child.cmd.Process; p != nil {
		unix.Kill(-p.Pid, unix.SIGKILL)
	}
	close(l.child.stop)
	l.child = nil
}

// childMsg applies one of the child's messages.
func (l *loop) childMsg(m childMsg) {
	if l.child == nil {
		return
	}
	ix := l.ix()
	switch {
	case m.done:
		build := l.child.build
		l.child = nil
		if m.err != nil {
			l.errText = "the crawl failed: " + m.err.Error()
			l.s.o.Log.Warn("file search: the crawl failed", "err", m.err)
		} else {
			l.errText = ""
		}
		if build {
			l.s.o.Log.Info("file search: indexed", "entries", ix.Len(), "unreadable", l.unreadable, "truncated", l.truncated)
		}
		if l.phase == PhaseCrawling && len(l.pendingStart) == 0 {
			l.phase = PhaseReady
		}
		l.compact()
		l.publish(true)
		l.next()
		return
	case m.kind == msgDir:
		l.applyDir(m.path, m.mtime, m.kids, l.child.stat)
	case m.kind == msgGone:
		if l.f.rootOf(m.path) == m.path {
			l.applyDir(m.path, 0, nil, false)
		} else {
			l.changedDir(parentOf(m.path))
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
			l.statAll = true
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
				l.changedDir(parentOf(dir))
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
	st := State{Phase: l.phase, Unreadable: l.unreadable, Truncated: l.truncated, Error: l.errText}
	if ix := l.ix(); ix != nil {
		st.Entries = ix.Len()
		if l.w != nil {
			st.Watched = len(l.w.byPath)
		}
		st.Unwatched = max(0, ix.Folders()-st.Watched)
	}
	l.s.stateMu.Lock()
	changed := st != l.s.state
	l.s.state = st
	l.s.stateMu.Unlock()
	if !changed {
		return
	}
	now := l.s.o.Now()
	if urgent || now.Sub(l.lastPush) >= l.s.o.PushEvery {
		if l.pushTimer != nil {
			l.pushTimer.Stop()
			l.pushTimer = nil
		}
		l.lastPush = now
		l.s.o.OnState(st)
		return
	}
	if l.pushTimer == nil {
		l.pushTimer = time.NewTimer(l.s.o.PushEvery - now.Sub(l.lastPush))
	}
}
