package session

import (
	"context"
	"fmt"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/command"
	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
)

// What bounds a teardown, and each request in it
const (
	TeardownBound = 5 * time.Second
	ipcBound      = 2 * time.Second
)

// Marker is the environment entry marking axiom's own wlsunset, per
// display (NightLight).
func Marker(display string) string { return "AXIOM_SPAWNED=nightlight:" + display }

// SystemctlFunc runs `systemctl --user args…`, returning its output.
type SystemctlFunc func(ctx context.Context, args ...string) (string, error)

// SignalFunc signals a process.
type SignalFunc func(pid int, sig syscall.Signal) error

// SpawnFunc starts a program detached.
type SpawnFunc func(ctx context.Context, argv, env []string, cwd string) error

// Seams are the effects a teardown has, replaced in tests (the defaults
// are real: systemctl, kill, setsid).
type Seams struct {
	Systemctl SystemctlFunc
	Spawn     SpawnFunc
	Signal    SignalFunc
}

func (s Seams) withDefaults() Seams {
	if s.Systemctl == nil {
		s.Systemctl = func(ctx context.Context, args ...string) (string, error) {
			out, err := exec.CommandContext(ctx, "systemctl", append([]string{"--user"}, args...)...).Output()
			return string(out), err
		}
	}
	if s.Spawn == nil {
		s.Spawn = func(ctx context.Context, argv, env []string, cwd string) error {
			return command.Spawn(ctx, command.Options{Env: env}, argv, cwd)
		}
	}
	if s.Signal == nil {
		s.Signal = func(pid int, sig syscall.Signal) error { return syscall.Kill(pid, sig) }
	}
	return s
}

// SystemctlOrDefault, SignalOrDefault and SpawnOrDefault are the seam, or
// the real effect.
func (s Seams) SystemctlOrDefault() SystemctlFunc { return s.withDefaults().Systemctl }
func (s Seams) SignalOrDefault() SignalFunc       { return s.withDefaults().Signal }
func (s Seams) SpawnOrDefault() SpawnFunc         { return s.withDefaults().Spawn }

// TeardownOptions say what to undo and how.
type TeardownOptions struct {
	// Runtime is the record in memory (changed, and saved to RuntimePath)
	Runtime     *Runtime
	RuntimePath string
	// State is the state record's file (read and changed under its lock)
	State Store
	Scope Scope
	// CompositorAlive: the compositor still answers; SameInstance: the
	// record is of the compositor running now; Compositor: run the
	// compositor's steps (the guard does; a daemon asked its manager to)
	CompositorAlive, SameInstance, Compositor bool
	// Bus is the session bus (nil: none, so no units, no portal restart)
	Bus Bus
	Seams
	// RestartPortal restarts the portal once a line of its config changed
	RestartPortal func(ctx context.Context) error
	// PortalEnv edits the portal's config
	Portal PortalEnv
	Log    Logf
}

// Teardown gives the session back what axiom took, in this order, within
// TeardownBound: the compositor's steps; axiom's own wlsunset, and the
// processes the user's axiom stopped (when the compositor and instance are
// the same); the units it stopped; the portal lines. Each part logs its
// failure and the rest goes on. It sets Clean and saves the records.
func Teardown(ctx context.Context, o TeardownOptions) error {
	o.Seams = o.Seams.withDefaults()
	ctx, cancel := context.WithTimeout(ctx, TeardownBound)
	defer cancel()
	display := o.Scope.WaylandDisplay
	rt := o.Runtime
	if rt == nil {
		rt = &Runtime{}
	}

	// 1. the compositor
	if o.Compositor && o.CompositorAlive {
		RunSteps(ctx, rt.Compositor.Kind, rt.Compositor.Env, rt.Compositor.Steps, o.Log)
	}
	rt.Compositor.Steps = nil

	// 2. processes
	for _, f := range o.Scope.FindEnv(Marker(display)) {
		if err := o.Signal(f.PID, syscall.SIGTERM); err != nil {
			o.Log.log("session: stopping wlsunset %d: %v", f.PID, err)
		}
	}
	if o.CompositorAlive && o.SameInstance {
		o.respawn(ctx, rt, "")
	}
	rt.Stopped = nil

	// 3. units
	o.startUnits(ctx)

	// 4. portal lines
	changed := o.undoLines(display)
	if changed && o.CompositorAlive && o.RestartPortal != nil {
		if err := o.RestartPortal(ctx); err != nil {
			o.Log.log("session: restarting the portal: %v", err)
		}
	}

	// 5.
	rt.Clean = true
	if o.RuntimePath != "" {
		if err := rt.Write(o.RuntimePath); err != nil {
			o.Log.log("session: saving the record: %v", err)
			return err
		}
	}
	return nil
}

// respawn starts again the processes of rt.Stopped (of kind, "": all) that
// no in-scope process runs already, and drops them from the record.
func (o TeardownOptions) respawn(ctx context.Context, rt *Runtime, kind string) {
	var kept []Process
	for _, p := range rt.Stopped {
		if kind != "" && p.Kind != kind {
			kept = append(kept, p)
			continue
		}
		if len(p.Argv) == 0 || o.Scope.Running(filepath.Base(p.Argv[0])) {
			continue
		}
		if err := o.Spawn(ctx, p.Argv, p.Env, p.Cwd); err != nil {
			o.Log.log("session: starting %s again: %v", p.Argv[0], err)
		}
	}
	rt.Stopped = kept
}

// StartUnits starts this display's units that axiom stopped, and drops
// them from the record: only when the user manager is this session's.
func (o TeardownOptions) StartUnits(ctx context.Context) {
	o.Seams = o.Seams.withDefaults()
	o.startUnits(ctx)
}

// Respawn is the polkit hand-back's: the polkit entries start again.
func (o TeardownOptions) Respawn(ctx context.Context, kind string) {
	o.Seams = o.Seams.withDefaults()
	o.respawn(ctx, o.Runtime, kind)
}

func (o TeardownOptions) startUnits(ctx context.Context) {
	display := o.Scope.WaylandDisplay
	if !o.CompositorAlive || !UnitsAllowed(ctx, o.Bus) {
		if st := o.State.Read(); st != nil && len(st.Units) > 0 {
			o.Log.log("session: left units alone: this daemon's bus isn't the user manager's")
		}
		return
	}
	var names []string
	err := o.State.Update(func(st *State) error {
		var kept []Unit
		for _, u := range st.Units {
			if u.Display == display {
				names = append(names, u.Name)
			} else {
				kept = append(kept, u)
			}
		}
		if len(names) == 0 {
			return nil
		}
		if _, err := o.Systemctl(ctx, append([]string{"start"}, names...)...); err != nil {
			o.Log.log("session: starting %s: %v", strings.Join(names, ", "), err)
			return fmt.Errorf("start failed")
		}
		st.Units = kept
		return nil
	})
	if err != nil && len(names) == 0 {
		o.Log.log("session: the units: %v", err)
	}
}

// undoLines takes out this display's portal lines, true when a file changed.
func (o TeardownOptions) undoLines(display string) bool {
	changed := false
	err := o.State.Update(func(st *State) error {
		var kept []PortalLine
		for _, l := range st.Lines {
			if l.Display != display {
				kept = append(kept, l)
				continue
			}
			c, err := o.Portal.Remove(l)
			if err != nil {
				o.Log.log("session: taking the line out of %s: %v", l.Path, err)
				kept = append(kept, l)
				continue
			}
			changed = changed || c
		}
		st.Lines = kept
		return nil
	})
	if err != nil {
		o.Log.log("session: the portal lines: %v", err)
	}
	return changed
}

// RunSteps asks the compositor each step (reached through env: its
// socket variables); a failed one is logged and the rest go on, each
// within ipcBound.
func RunSteps(ctx context.Context, kind string, env map[string]string, steps []Step, log Logf) {
	getenv := func(k string) string { return env[k] }
	do := func(fn func(ctx context.Context) error, what string) {
		c, cancel := context.WithTimeout(ctx, ipcBound)
		defer cancel()
		if err := fn(c); err != nil {
			log.log("session: %s: %v", what, err)
		}
	}
	for _, s := range steps {
		switch kind {
		case "hyprland":
			h := ipc.HyprFromEnv(getenv)
			if h == nil {
				log.log("session: no Hyprland to reach")
				return
			}
			switch s.Op {
			case "reload":
				do(func(c context.Context) error { _, err := h.Request(c, "reload"); return err }, "reload")
			case "eval":
				do(func(c context.Context) error {
					reply, err := h.Eval(c, strings.Join(s.Lines, "\n"))
					if err == nil && reply != "" {
						err = fmt.Errorf("%s", reply)
					}
					return err
				}, "eval")
			case "setcursor":
				do(func(c context.Context) error {
					_, err := h.Request(c, fmt.Sprintf("setcursor %s %d", s.Theme, s.Size))
					return err
				}, "setcursor")
			}
		case "sway":
			sw := ipc.SwayFromEnv(getenv)
			if sw == nil {
				log.log("session: no sway to reach")
				return
			}
			run := func(cmd string) {
				do(func(c context.Context) error {
					results, err := sw.Run(c, cmd)
					for _, r := range results {
						if !r.Success && r.Error != "No matching node." && err == nil {
							err = fmt.Errorf("%s", r.Error)
						}
					}
					return err
				}, "sway "+clip(cmd))
			}
			switch s.Op {
			case "reload":
				run("reload")
			case "commands":
				for _, l := range s.Lines {
					if l != "" {
						run(l)
					}
				}
			}
		case "niri":
			n := ipc.NiriFromEnv(getenv)
			if n == nil {
				log.log("session: no niri to reach")
				return
			}
			if s.Op == "load" {
				var path any = s.Path
				if s.Path == "" {
					path = nil // niri's own default path
				}
				do(func(c context.Context) error {
					return n.Action(c, map[string]any{"LoadConfigFile": map[string]any{"path": path}})
				}, "load "+s.Path)
			}
		}
	}
}

func clip(s string) string {
	if len(s) > 80 {
		return s[:80]
	}
	return s
}

// PatternFor is a regexp matching a program's command line by its base
// name, as pgrep -f would with an anchored pattern.
func PatternFor(name string) *regexp.Regexp {
	return regexp.MustCompile(`^([^ ]*/)?` + regexp.QuoteMeta(name) + `( |$)`)
}
