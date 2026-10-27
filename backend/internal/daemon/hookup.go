package daemon

import (
	"context"
	"path/filepath"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/compositor/edit"
	"github.com/axiom-shell/axiom/backend/internal/hookup"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// hookupPart: IntegrationHookupManager's hookups, the lines that load
// axiom's files from the user's own configs (a theme integration's
// x-hookup, the compositor's include and autostart lines), checked and
// applied by compositor/edit.
func (d *Daemon) hookupPart() part {
	return part{name: "hookup", methods: d.hookupMethods}
}

// HookupRequest names a ThemeIntegrations key, whose schema x-hookup the
// targets are, or passes its targets (the compositor's: key then only
// names them).
type HookupRequest struct {
	Key     string          `json:"key"`
	Targets []hookup.Target `json:"targets,omitempty"`
}

// HookupStatus is what Apply would do to each target.
type HookupStatus struct {
	Key     string       `json:"key"`
	Targets []hookup.Row `json:"targets"`
}

// HookupApplied is how Apply went for each target.
type HookupApplied struct {
	Key     string              `json:"key"`
	Results []edit.HookupResult `json:"results"`
}

func (d *Daemon) hookupMethods(reg *rpc.Registry) {
	h := edit.NewHookups(edit.HookupOptions{Getenv: d.opts.Getenv, Scripts: filepath.Join(d.opts.Tree, "scripts"), Now: time.Now})
	// The targets asked for, and the profiles.ini files of a browser's
	targets := func(p HookupRequest) ([]hookup.Target, []string, error) {
		if p.Targets != nil {
			return p.Targets, nil, nil
		}
		entry, ok := d.integrationEntry(p.Key)
		if !ok {
			return nil, nil, axerr.New(axerr.BadRequest, "no theme integration %q", p.Key)
		}
		return entry.Hookup, entry.Profiles, nil
	}
	rpc.Handle(reg, "hookup.status", func(ctx context.Context, c *rpc.Conn, p HookupRequest) (HookupStatus, error) {
		ts, profiles, err := targets(p)
		if err != nil {
			return HookupStatus{}, err
		}
		rows, err := h.Status(ts, profiles)
		return HookupStatus{Key: p.Key, Targets: rows}, err
	})
	// Only the shell's Apply (a user's click) edits the user's configs
	rpc.Handle(reg, "hookup.apply", func(ctx context.Context, c *rpc.Conn, p HookupRequest) (HookupApplied, error) {
		if !fromShell(c) {
			return HookupApplied{}, axerr.New(axerr.Refused, "only the shell applies a hookup")
		}
		ts, profiles, err := targets(p)
		if err != nil {
			return HookupApplied{}, err
		}
		return HookupApplied{Key: p.Key, Results: h.Apply(ts, profiles)}, nil
	})
}
