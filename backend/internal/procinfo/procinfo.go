// Package procinfo is what the window rules engine knows of a window's process: its name, the names of the processes above it, and the game signals of its process tree (game.go). It reads only the user's own processes under /proc, keeps facts per process (pid and start time, so a reused pid reads afresh), and never keeps or returns an environment value or an argument: only signal names.
package procinfo

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
)

const (
	maxRead    = 256 << 10 // environ and cmdline are read at most this far
	maxEntries = 512       // cache size before it is pruned
	maxWalk    = 64        // processes above a window followed at most
)

// Options are where the reader looks; zero values are the real ones.
type Options struct {
	Proc string // "/proc"
	// Mine: the process whose /proc folder this is runs as our user
	// (default: the folder's owner is os.Getuid()). Tests fake it.
	Mine func(dir string) bool
}

// Process is what a window's process tells the rules (never its
// environment or arguments).
type Process struct {
	PID       int      `json:"pid"`
	Start     uint64   `json:"-"`         // field 22 of stat: with PID, which process this is
	Name      string   `json:"name"`      // the `process` condition; "" for a bridge
	Ancestors []string `json:"ancestors"` // the `startedFrom` condition: nearest first, our own processes only, never nil
	Signals   []Signal `json:"signals"`   // the process tree's game signals, table order, never nil
	Bridge    bool     `json:"bridge"`    // an X11 bridge (xwayland-satellite, Xwayland): it stands for many windows, so nothing above is known
}

// node is one process as the walk needs it.
type node struct {
	start       uint64
	ppid        int
	name        string
	exe         string // basename of the exe link
	steamLaunch bool   // named reaper, with an argument exactly SteamLaunch
}

// Reader looks windows' processes up, for the daemon's lifetime.
type Reader struct {
	o     Options
	mu    sync.Mutex
	procs map[int]Process
	nodes map[int]node
}

// New fills Options' zero values.
func New(o Options) *Reader {
	if o.Proc == "" {
		o.Proc = "/proc"
	}
	if o.Mine == nil {
		o.Mine = mineByOwner
	}
	return &Reader{o: o, procs: map[int]Process{}, nodes: map[int]node{}}
}

func mineByOwner(dir string) bool {
	info, err := os.Stat(dir)
	if err != nil {
		return false
	}
	st, ok := info.Sys().(*syscall.Stat_t)
	return ok && st.Uid == uint32(os.Getuid())
}

// Lookup is pid's process. False when pid is 0 or less, gone, or not
// ours. Cached by pid and start time.
func (r *Reader) Lookup(pid int) (Process, bool) {
	if pid <= 0 {
		return Process{}, false
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	dir := r.dir(pid)
	comm, ppid, start, ok := r.stat(pid)
	if !ok {
		return Process{}, false
	}
	if p, ok := r.procs[pid]; ok && p.Start == start {
		return p, true
	}
	if !r.o.Mine(dir) {
		return Process{}, false
	}
	self := r.nodeFor(pid, comm, ppid, start)
	p := Process{PID: pid, Start: start, Ancestors: []string{}, Signals: []Signal{}}
	if bridgeNames[self.name] {
		p.Bridge = true
		r.store(pid, p)
		return p, true
	}
	p.Name = self.name
	var above []node
	seen := map[int]bool{pid: true}
	child := self
	for next := self.ppid; next > 0 && len(above) < maxWalk && !seen[next]; {
		seen[next] = true
		if !r.o.Mine(r.dir(next)) {
			break
		}
		c, pp, st, ok := r.stat(next)
		if !ok || st > child.start {
			break
		}
		n := r.nodeFor(next, c, pp, st)
		above = append(above, n)
		p.Ancestors = append(p.Ancestors, n.name)
		child, next = n, n.ppid
	}
	env := readCapped(filepath.Join(dir, "environ"), maxRead)
	p.Signals = signalsOf(self, above, env)
	r.store(pid, p)
	return p, true
}

func (r *Reader) dir(pid int) string { return filepath.Join(r.o.Proc, strconv.Itoa(pid)) }

// stat reads pid's stat.
func (r *Reader) stat(pid int) (comm string, ppid int, start uint64, ok bool) {
	data, err := os.ReadFile(filepath.Join(r.dir(pid), "stat"))
	if err != nil {
		return "", 0, 0, false
	}
	return parseStat(data)
}

// nodeFor is pid's node, read afresh when its start time is not the cached one.
func (r *Reader) nodeFor(pid int, comm string, ppid int, start uint64) node {
	if n, ok := r.nodes[pid]; ok && n.start == start {
		return n
	}
	dir := r.dir(pid)
	argv := bytes.Split(bytes.TrimSuffix(readCapped(filepath.Join(dir, "cmdline"), maxRead), []byte{0}), []byte{0})
	argv0 := string(argv[0])
	exe, _ := os.Readlink(filepath.Join(dir, "exe"))
	exe = filepath.Base(strings.TrimSuffix(exe, " (deleted)"))
	if exe == "." || exe == "/" {
		exe = ""
	}
	n := node{start: start, ppid: ppid, name: name(comm, argv0, exe), exe: exe}
	if n.name == "reaper" {
		for _, a := range argv[1:] {
			if string(a) == "SteamLaunch" {
				n.steamLaunch = true
			}
		}
	}
	r.nodes[pid] = n
	return n
}

// store caches p, pruning first when the caches are full: entries whose
// process is gone or restarted go, and if that is not enough, all.
func (r *Reader) store(pid int, p Process) {
	if len(r.procs) >= maxEntries || len(r.nodes) >= maxEntries {
		for id, q := range r.procs {
			if _, _, st, ok := r.stat(id); !ok || st != q.Start {
				delete(r.procs, id)
			}
		}
		for id, n := range r.nodes {
			if _, _, st, ok := r.stat(id); !ok || st != n.start {
				delete(r.nodes, id)
			}
		}
		if len(r.procs) >= maxEntries {
			clear(r.procs)
		}
		if len(r.nodes) >= maxEntries {
			clear(r.nodes)
		}
	}
	r.procs[pid] = p
}

// parseStat reads a stat line: comm sits between the first "(" and the
// last ")" (it may hold spaces and parentheses), the rest counts from there.
func parseStat(data []byte) (comm string, ppid int, start uint64, ok bool) {
	i, j := bytes.IndexByte(data, '('), bytes.LastIndexByte(data, ')')
	if i < 0 || j < i {
		return "", 0, 0, false
	}
	fields := strings.Fields(string(data[j+1:]))
	// fields[0] is field 3
	if len(fields) < 20 {
		return "", 0, 0, false
	}
	pp, err := strconv.Atoi(fields[1])
	if err != nil {
		return "", 0, 0, false
	}
	st, err := strconv.ParseUint(fields[19], 10, 64)
	if err != nil {
		return "", 0, 0, false
	}
	return string(data[i+1 : j]), pp, st, true
}

// name is what a process is called: comm, unless the kernel cut it at 15
// bytes and argv[0] or the exe link holds the longer name.
func name(comm, argv0, exe string) string {
	if len(comm) != 15 {
		return comm
	}
	for _, c := range []string{filepath.Base(argv0), exe} {
		if len(c) > len(comm) && strings.HasPrefix(c, comm) {
			return c
		}
	}
	return comm
}

// readCapped reads path to EOF or max bytes (files under /proc report
// size 0); an error is no data.
func readCapped(path string, max int64) []byte {
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()
	data, _ := io.ReadAll(io.LimitReader(f, max))
	return data
}
