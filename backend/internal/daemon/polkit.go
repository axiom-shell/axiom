package daemon

import (
	"context"
	"regexp"
	"slices"
	"syscall"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	sessx "github.com/axiom-shell/axiom/backend/internal/session"
)

// polkitMethods: polkit.probe, polkit.stopOthers and polkit.handBack, the
// shell's way of taking the session's polkit agent (PolkitManager): the
// daemon looks and stops in this session only, and records what it stops.
func (d *Daemon) polkitMethods(reg *rpc.Registry) {
	type patternParams struct {
		Pattern string `json:"pattern"`
	}
	type namesResult struct {
		Names []string `json:"names"`
	}
	rpc.Handle(reg, "polkit.probe", func(ctx context.Context, c *rpc.Conn, p patternParams) (namesResult, error) {
		if err := shellOnly(c); err != nil {
			return namesResult{}, err
		}
		re, err := regexp.Compile(p.Pattern)
		if err != nil {
			return namesResult{}, axerr.Wrap(axerr.BadRequest, err, "the pattern")
		}
		return namesResult{Names: namesOf(d.sessionScope().Find(re))}, nil
	})
	type stopParams struct {
		Pattern string   `json:"pattern"`
		Units   []string `json:"units"`
	}
	rpc.Handle(reg, "polkit.stopOthers", func(ctx context.Context, c *rpc.Conn, p stopParams) (stopOthersResult, error) {
		if err := shellOnly(c); err != nil {
			return stopOthersResult{}, err
		}
		re, err := regexp.Compile(p.Pattern)
		if err != nil {
			return stopOthersResult{}, axerr.Wrap(axerr.BadRequest, err, "the pattern")
		}
		return d.stopOthers(ctx, re, p.Units), nil
	})
	rpc.Handle(reg, "polkit.handBack", func(ctx context.Context, c *rpc.Conn, _ struct{}) (struct{}, error) {
		if err := shellOnly(c); err != nil {
			return struct{}{}, err
		}
		d.handBack(ctx)
		return struct{}{}, nil
	})
}

func namesOf(found []sessx.Found) []string {
	names := []string{}
	for _, f := range found {
		if n := f.Basename(); !slices.Contains(names, n) {
			names = append(names, n)
		}
	}
	return names
}

// stopOthers stops the polkit agents of this session (their units when the
// user manager is ours, then their processes), each recorded before it is
// stopped; matches outside the session are logged and left alone.
func (d *Daemon) stopOthers(ctx context.Context, re *regexp.Regexp, units []string) stopOthersResult {
	scope := d.sessionScope()
	o, closeBus := d.teardownOptions(ctx, &sessx.Runtime{})
	defer closeBus()
	seams := o.Seams
	res := stopOthersResult{Units: []string{}, Names: []string{}}
	if sessx.UnitsAllowed(ctx, o.Bus, scope) {
		for _, unit := range units {
			if _, err := seams.Systemctl(ctx, "-q", "is-active", unit); err != nil {
				continue
			}
			// Written ahead: a unit that can't be recorded isn't stopped
			err := d.sessionStore().Update(func(st *sessx.State) error {
				for _, u := range st.Units {
					if u.Name == unit && u.Display == scope.WaylandDisplay {
						return nil
					}
				}
				st.Units = append(st.Units, sessx.Unit{Name: unit, Display: scope.WaylandDisplay})
				return nil
			})
			if err != nil {
				d.sessionLog("not stopping %s: it couldn't be recorded: %v", unit, err)
				continue
			}
			if _, err := seams.Systemctl(ctx, "stop", unit); err != nil {
				d.sessionLog("stopping %s: %v", unit, err)
				continue
			}
			res.Units = append(res.Units, unit)
		}
	} else if len(units) > 0 {
		d.sessionLog("left units alone: this daemon's bus isn't the user manager's")
	}
	for _, f := range scope.Find(re) {
		err := d.sess.with(func(rt *sessx.Runtime) {
			rt.Stopped = append(rt.Stopped, sessx.Process{Kind: "polkit", Argv: f.Argv, Env: f.Env, Cwd: f.Cwd, PID: f.PID, Start: f.Start})
		})
		if err != nil {
			d.sessionLog("not stopping %s: it couldn't be recorded: %v", f.Basename(), err)
			continue
		}
		if err := seams.Signal(f.PID, syscall.SIGTERM); err != nil {
			d.sessionLog("stopping %s: %v", f.Basename(), err)
			continue
		}
		waitGone(scope, f)
		res.Names = append(res.Names, f.Basename())
	}
	for _, pid := range scope.Elsewhere(re) {
		d.sessionLog("a polkit agent (pid %d) runs in another session: left alone", pid)
	}
	return res
}

type stopOthersResult struct {
	Units []string `json:"units"`
	Names []string `json:"names"`
}

// waitGone waits up to a second for f to exit
func waitGone(scope sessx.Scope, f sessx.Found) {
	for range 20 {
		if !scope.Same(f.PID, f.Start) {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
}

// handBack starts the units axiom stopped and the agents again (polkit
// off).
func (d *Daemon) handBack(ctx context.Context) {
	d.sess.mu.Lock()
	defer d.sess.mu.Unlock()
	o, closeBus := d.teardownOptions(ctx, &d.sess.rec)
	defer closeBus()
	o.CompositorAlive = true
	o.StartUnits(ctx)
	o.Respawn(ctx, "polkit")
	d.sess.saveLocked()
}
