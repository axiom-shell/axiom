// Package session is what axiom leaves in the user's session while it runs
// and takes out again when it stops, however it stops (docs/dev/backend/
// session-teardown.md): the compositor's runtime layer, the polkit agents
// and units it stopped, a user's wlsunset, the niri portal line. Two
// versioned records say what to undo (a runtime one in the display's
// runtime folder, a state one beside the other state), Teardown undoes it,
// and the guard (a process of its own) runs Teardown when the daemon dies
// without having done so.
package session

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"time"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/fsx"
)

// Version is the records' format: a record of another version is read as
// absent, and never acted on.
const Version = 1

// Logf logs a line (nil: silent).
type Logf func(format string, args ...any)

func (l Logf) log(format string, args ...any) {
	if l != nil {
		l(format, args...)
	}
}

// Runtime is $XDG_RUNTIME_DIR/axiom/<display>/session.json: this daemon's
// part of the session, gone with the session itself.
type Runtime struct {
	Version   int    `json:"version"`
	Instance  string `json:"instance"` // the compositor instance (manager's runtime state)
	DaemonPID int    `json:"daemonPid"`
	GuardPID  int    `json:"guardPid,omitempty"`
	// Clean: the daemon finished its teardown
	Clean      bool       `json:"clean"`
	Compositor Compositor `json:"compositor"`
	// Stopped are the processes of the user's axiom stopped (polkit
	// agents, wlsunset), to start again
	Stopped []Process `json:"stopped"`
}

// Compositor is what undoes the runtime layer, and the environment to
// reach the compositor with.
type Compositor struct {
	Kind  string            `json:"kind"`
	Env   map[string]string `json:"env"` // HYPRLAND_INSTANCE_SIGNATURE / SWAYSOCK / NIRI_SOCKET, XDG_RUNTIME_DIR, WAYLAND_DISPLAY
	Steps []Step            `json:"steps"`
}

// Step is one thing to ask the compositor, by Op: "reload" (hyprland,
// sway), "load" (niri: Path), "commands" (sway: Lines), "eval" (hyprland:
// Lines, joined), "setcursor" (hyprland: Theme, Size).
type Step struct {
	Op    string   `json:"op"`
	Path  string   `json:"path,omitempty"`
	Lines []string `json:"lines,omitempty"`
	Theme string   `json:"theme,omitempty"`
	Size  int      `json:"size,omitempty"`
}

// Process is one the user's axiom stopped: what starts it again. Kind is
// "polkit" or "wlsunset"; Start (the process's start time, field 22 of its
// stat) guards against a reused pid.
type Process struct {
	Kind  string   `json:"kind"`
	Argv  []string `json:"argv"`
	Env   []string `json:"env"`
	Cwd   string   `json:"cwd"`
	PID   int      `json:"pid"`
	Start uint64   `json:"start"`
}

// State is $XDG_STATE_HOME/axiom/session.json: what outlives a session
// (a unit stopped, a line in a file), healed by the next start. Every
// read-modify-write holds a flock on session.lock beside it.
type State struct {
	Version int          `json:"version"`
	Units   []Unit       `json:"units"`
	Lines   []PortalLine `json:"lines"`
}

// Unit is a systemd user unit axiom stopped, on a display.
type Unit struct {
	Name    string `json:"name"`
	Display string `json:"display"`
}

// PortalLine is a line axiom put in a portal config for a display, with
// exactly what it changed, so taking it out leaves the file as it was.
type PortalLine struct {
	Display string `json:"display"`
	Path    string `json:"path"`
	Line    string `json:"line"`
	// Commented are the original texts of lines now prefixed "# axiom: "
	Commented      []string `json:"commented,omitempty"`
	CreatedSection bool     `json:"createdSection,omitempty"`
	CreatedFile    bool     `json:"createdFile,omitempty"`
	// BlankAdded: a blank line went in before the new section
	BlankAdded bool `json:"blankAdded,omitempty"`
	// NoFinalNewline: the file didn't end in a newline before
	NoFinalNewline bool `json:"noFinalNewline,omitempty"`
	// Adopted: the line was there already, from an earlier persistent hookup
	Adopted bool `json:"adopted,omitempty"`
}

// ReadRuntime reads the runtime record: nil when it isn't there, isn't
// readable, or is of another version (logged, never acted on).
func ReadRuntime(path string, log Logf) *Runtime {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var r Runtime
	if err := json.Unmarshal(data, &r); err != nil {
		log.log("session: %s isn't readable: %v", path, err)
		return nil
	}
	if r.Version != Version {
		log.log("session: %s is version %d, not %d: leaving it alone", path, r.Version, Version)
		return nil
	}
	return &r
}

// Write saves the record atomically.
func (r *Runtime) Write(path string) error {
	r.Version = Version
	data, err := json.Marshal(r)
	if err != nil {
		return err
	}
	return fsx.WriteFile(path, data, 0o600)
}

// Store is the state record and its lock.
type Store struct {
	Path string
	Log  Logf
}

func (s Store) lockPath() string { return filepath.Join(filepath.Dir(s.Path), "session.lock") }

// lockWait bounds the wait for session.lock
const lockWait = 5 * time.Second

// lock takes session.lock, waiting for another process's.
func (s Store) lock() (release func(), err error) {
	if err := os.MkdirAll(filepath.Dir(s.Path), 0o700); err != nil {
		return nil, err
	}
	f, err := os.OpenFile(s.lockPath(), os.O_RDWR|os.O_CREATE|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0o600)
	if err != nil {
		return nil, err
	}
	deadline := time.Now().Add(lockWait)
	for {
		err := unix.Flock(int(f.Fd()), unix.LOCK_EX|unix.LOCK_NB)
		if err == nil {
			return func() { unix.Flock(int(f.Fd()), unix.LOCK_UN); f.Close() }, nil
		}
		if !errors.Is(err, unix.EWOULDBLOCK) || time.Now().After(deadline) {
			f.Close()
			return nil, err
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func (s Store) read() *State {
	data, err := os.ReadFile(s.Path)
	if err != nil {
		return &State{Version: Version}
	}
	var st State
	if err := json.Unmarshal(data, &st); err != nil {
		s.Log.log("session: %s isn't readable: %v", s.Path, err)
		return &State{Version: Version}
	}
	if st.Version != Version {
		s.Log.log("session: %s is version %d, not %d: leaving it alone", s.Path, st.Version, Version)
		return nil
	}
	return &st
}

// Read is the state record (empty when there is none; nil for one of
// another version).
func (s Store) Read() *State {
	release, err := s.lock()
	if err != nil {
		return s.read()
	}
	defer release()
	return s.read()
}

// Update reads the record, lets fn change it, and writes it, all under
// session.lock. A record of another version is left as it is (an error).
func (s Store) Update(fn func(*State) error) error {
	release, err := s.lock()
	if err != nil {
		return err
	}
	defer release()
	st := s.read()
	if st == nil {
		return errors.New("the session record is of another version")
	}
	if err := fn(st); err != nil {
		return err
	}
	st.Version = Version
	data, err := json.Marshal(st)
	if err != nil {
		return err
	}
	return fsx.WriteFile(s.Path, data, 0o600)
}
