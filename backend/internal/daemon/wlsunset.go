package daemon

import (
	"context"
	"os"
	"path/filepath"
	"syscall"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	sessx "github.com/axiom-shell/axiom/backend/internal/session"
)

// wlsunsetMethods: nightlight.wlsunset and nightlight.wlsunsetState, the
// night light where the compositor offers neither a color transform nor
// gamma ramps (NightLightManager).
func (d *Daemon) wlsunsetMethods(reg *rpc.Registry) {
	type wlsunsetParams struct {
		On   bool     `json:"on"`
		Argv []string `json:"argv"`
	}
	rpc.Handle(reg, "nightlight.wlsunset", func(ctx context.Context, c *rpc.Conn, p wlsunsetParams) (struct{}, error) {
		if err := shellOnly(c); err != nil {
			return struct{}{}, err
		}
		if p.On && (len(p.Argv) == 0 || filepath.Base(p.Argv[0]) != "wlsunset") {
			return struct{}{}, axerr.New(axerr.BadRequest, "not wlsunset: %v", p.Argv)
		}
		return struct{}{}, d.wlsunset(ctx, p.On, p.Argv)
	})
	rpc.Handle(reg, "nightlight.wlsunsetState", func(ctx context.Context, c *rpc.Conn, _ struct{}) (map[string]bool, error) {
		return map[string]bool{"running": len(d.sessionScope().FindEnv(sessx.Marker(d.sessionScope().WaylandDisplay))) > 0}, nil
	})
}

// wlsunset turns axiom's own wlsunset on or off. On: a user's wlsunset of
// this session is recorded and stopped first (teardown starts it again);
// axiom's, marked in its environment, is replaced.
func (d *Daemon) wlsunset(ctx context.Context, on bool, argv []string) error {
	// One at a time: two calls in flight would each start one
	d.wlsunsetMu.Lock()
	defer d.wlsunsetMu.Unlock()
	scope := d.sessionScope()
	seams := d.sessionSeams()
	marker := sessx.Marker(scope.WaylandDisplay)
	signal := seams.Signal
	if on {
		ours := map[int]bool{}
		for _, f := range scope.FindEnv(marker) {
			ours[f.PID] = true
		}
		for _, f := range scope.Find(sessx.PatternFor("wlsunset")) {
			if ours[f.PID] {
				continue
			}
			err := d.sess.with(func(rt *sessx.Runtime) {
				rt.Stopped = append(rt.Stopped, sessx.Process{Kind: "wlsunset", Argv: f.Argv, Env: f.Env, Cwd: f.Cwd, PID: f.PID, Start: f.Start})
			})
			if err != nil {
				d.sessionLog("not stopping %s: it couldn't be recorded: %v", f.Basename(), err)
				continue
			}
			signal(f.PID, syscall.SIGTERM)
			waitGone(scope, f)
		}
	}
	for _, f := range scope.FindEnv(marker) {
		signal(f.PID, syscall.SIGTERM)
		waitGone(scope, f)
	}
	if !on {
		return nil
	}
	env := d.commandOptions().Env
	if env == nil {
		env = os.Environ()
	}
	return seams.Spawn(ctx, argv, append(append([]string{}, env...), marker), "")
}
