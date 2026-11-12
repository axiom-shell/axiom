package uninstall

import (
	"context"
	"fmt"
	"path/filepath"
	"slices"

	"github.com/axiom-shell/axiom/backend/internal/session"
)

// leftoverDisplays are the displays an earlier axiom left something of in
// the session: a runtime record that didn't end clean, or units and portal
// lines the state record still has.
func (o Options) leftoverDisplays() []string {
	var out []string
	for _, d := range o.displays() {
		if rec := session.ReadRuntime(filepath.Join(o.runtimeRoot(), d, session.RuntimeFile), nil); rec != nil && !rec.Clean {
			out = append(out, d)
		}
	}
	if st := session.StoreFrom(o.Getenv, nil).Peek(); st != nil {
		for _, u := range st.Units {
			out = append(out, u.Display)
		}
		for _, l := range st.Lines {
			out = append(out, l.Display)
		}
	}
	slices.Sort(out)
	return slices.DeleteFunc(slices.Compact(out), func(d string) bool { return d == "" })
}

// sessionLeftovers are the plan's actions for those.
func (o Options) sessionLeftovers() []Action {
	var out []Action
	for _, d := range o.leftoverDisplays() {
		out = append(out, Action{Step: "session", What: "Undo what an unclean stop of axiom left (units, portal lines, processes)", Path: d})
	}
	return out
}

// stateLines counts the portal lines the state record holds.
func (o Options) stateLines() int {
	if st := session.StoreFrom(o.Getenv, nil).Peek(); st != nil {
		return len(st.Lines)
	}
	return 0
}

// 5. the session leftovers: the teardown of each display's records, without
// the compositor's own steps (nothing of axiom's is running), and without
// starting the agents again across instances
func (r *run) sessionLeft(ctx context.Context) {
	logf := func(format string, args ...any) { r.Log.Info(fmt.Sprintf(format, args...), "part", "uninstall") }
	mine := session.ScopeFrom(r.Getenv)
	var bus session.Bus
	if r.DialBus != nil {
		var closeBus func()
		if bus, closeBus = r.DialBus(ctx); closeBus != nil {
			defer closeBus()
		}
	}
	for _, d := range r.leftoverDisplays() {
		scope := mine
		scope.WaylandDisplay = d
		rec := session.ReadRuntime(filepath.Join(r.runtimeRoot(), d, session.RuntimeFile), logf)
		if rec == nil {
			rec = &session.Runtime{Clean: true}
		}
		lines := r.stateLines()
		err := session.Teardown(ctx, session.TeardownOptions{
			Runtime: rec, State: session.StoreFrom(r.Getenv, logf), Scope: scope,
			Compositor: false, SameInstance: false,
			CompositorAlive: d == mine.WaylandDisplay && session.DisplayAlive(scope.RuntimeDir, d),
			Bus:             bus, Seams: r.Session, Portal: session.PortalEnvFrom(r.Getenv), Log: logf,
		})
		if err != nil {
			r.left("session", "Undo what an unclean stop of axiom left", d, err.Error())
			continue
		}
		if r.stateLines() < lines {
			r.portal = true
		}
		r.done("session", "Undid what an unclean stop of axiom left", d, "")
	}
}
