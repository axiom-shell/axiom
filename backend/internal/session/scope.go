package session

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
)

// Bus is the session bus as far as this package asks: who owns a name, and
// which process (*dbus.Conn).
type Bus interface {
	NameOwner(ctx context.Context, name string) (string, error)
	ConnectionPID(ctx context.Context, name string) (uint32, error)
}

// systemd is the user manager's name on the session bus
const systemd = "org.freedesktop.systemd1"

// UnitsAllowed: the session bus has an owner of org.freedesktop.systemd1,
// so `systemctl --user` reaches the user manager of this bus's session.
// False under a bus of its own (dbus-run-session, a nested shell): its
// units aren't this session's.
func UnitsAllowed(ctx context.Context, bus Bus) bool {
	if bus == nil {
		return false
	}
	owner, err := bus.NameOwner(ctx, systemd)
	return err == nil && owner != ""
}

// Scope is this session: the processes axiom may stop, signal or restart
// are those that run on its Wayland display and its runtime dir (and its
// session bus, when they have one). Another session's agents, a nested
// shell's, a scratch daemon's are out of it.
type Scope struct {
	WaylandDisplay, RuntimeDir, Bus string
	// ProcRoot is "/proc" (tests: a fixture folder)
	ProcRoot string
}

// Found is a process in scope.
type Found struct {
	PID   int
	Argv  []string
	Env   []string
	Cwd   string
	Start uint64
}

// Basename is argv[0]'s file name.
func (f Found) Basename() string {
	if len(f.Argv) == 0 {
		return ""
	}
	return filepath.Base(f.Argv[0])
}

func (s Scope) root() string {
	if s.ProcRoot == "" {
		return "/proc"
	}
	return s.ProcRoot
}

// Owns: the process is this user's and runs in this session. One with no
// WAYLAND_DISPLAY is out of scope.
func (s Scope) Owns(pid int) bool {
	_, ok := s.inspect(pid)
	return ok
}

func environOf(data []byte) []string {
	var out []string
	for _, e := range bytes.Split(data, []byte{0}) {
		if len(e) > 0 {
			out = append(out, string(e))
		}
	}
	return out
}

func lookup(env []string, key string) (string, bool) {
	for _, e := range env {
		if v, ok := strings.CutPrefix(e, key+"="); ok {
			return v, true
		}
	}
	return "", false
}

// inspect reads pid's process, and says whether it is in scope.
func (s Scope) inspect(pid int) (Found, bool) {
	dir := filepath.Join(s.root(), strconv.Itoa(pid))
	info, err := os.Stat(dir)
	if err != nil {
		return Found{}, false
	}
	if st, ok := info.Sys().(*syscall.Stat_t); !ok || int(st.Uid) != os.Getuid() {
		return Found{}, false
	}
	environ, err := os.ReadFile(filepath.Join(dir, "environ"))
	if err != nil {
		return Found{}, false
	}
	env := environOf(environ)
	if wd, _ := lookup(env, "WAYLAND_DISPLAY"); wd == "" || wd != s.WaylandDisplay {
		return Found{}, false
	}
	if rt, ok := lookup(env, "XDG_RUNTIME_DIR"); ok && rt != s.RuntimeDir {
		return Found{}, false
	}
	if bus, ok := lookup(env, "DBUS_SESSION_BUS_ADDRESS"); ok && bus != s.Bus {
		return Found{}, false
	}
	cmdline, _ := os.ReadFile(filepath.Join(dir, "cmdline"))
	var argv []string
	for _, a := range bytes.Split(bytes.TrimSuffix(cmdline, []byte{0}), []byte{0}) {
		argv = append(argv, string(a))
	}
	if len(cmdline) == 0 {
		argv = nil
	}
	cwd, _ := os.Readlink(filepath.Join(dir, "cwd"))
	return Found{PID: pid, Argv: argv, Env: env, Cwd: cwd, Start: startTime(dir)}, true
}

// startTime is field 22 of dir/stat: when the process started, in ticks
// since boot (0: unknown). The command name (field 2) may hold spaces and
// parentheses: fields count from the last ")".
func startTime(dir string) uint64 {
	data, err := os.ReadFile(filepath.Join(dir, "stat"))
	if err != nil {
		return 0
	}
	i := bytes.LastIndexByte(data, ')')
	if i < 0 {
		return 0
	}
	fields := strings.Fields(string(data[i+1:]))
	// fields[0] is field 3
	if len(fields) < 20 {
		return 0
	}
	n, _ := strconv.ParseUint(fields[19], 10, 64)
	return n
}

// all are the processes in scope, but this one.
func (s Scope) all() []Found {
	entries, err := os.ReadDir(s.root())
	if err != nil {
		return nil
	}
	var out []Found
	for _, e := range entries {
		pid, err := strconv.Atoi(e.Name())
		if err != nil || pid == os.Getpid() {
			continue
		}
		if f, ok := s.inspect(pid); ok {
			out = append(out, f)
		}
	}
	return out
}

// Find is the in-scope processes whose command line (argv joined with
// spaces: what pgrep -f matches) matches re.
func (s Scope) Find(re *regexp.Regexp) []Found {
	var out []Found
	for _, f := range s.all() {
		if re.MatchString(strings.Join(f.Argv, " ")) {
			out = append(out, f)
		}
	}
	return out
}

// FindEnv is the in-scope processes whose environment holds entry
// (NAME=value).
func (s Scope) FindEnv(entry string) []Found {
	var out []Found
	for _, f := range s.all() {
		for _, e := range f.Env {
			if e == entry {
				out = append(out, f)
				break
			}
		}
	}
	return out
}

// Running: an in-scope process runs a program of that base name.
func (s Scope) Running(name string) bool {
	for _, f := range s.all() {
		if f.Basename() == name {
			return true
		}
	}
	return false
}

// Same: the process still is the one recorded (not a reused pid).
func (s Scope) Same(pid int, start uint64) bool {
	f, ok := s.inspect(pid)
	return ok && (start == 0 || f.Start == start)
}
