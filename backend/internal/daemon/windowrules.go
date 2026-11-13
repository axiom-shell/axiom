package daemon

import (
	"context"
	"encoding/json"

	"github.com/axiom-shell/axiom/backend/internal/compositor/place"
	"github.com/axiom-shell/axiom/backend/internal/compositor/windows"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/mimeapps"
	"github.com/axiom-shell/axiom/backend/internal/procinfo"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/store"
	"github.com/axiom-shell/axiom/backend/internal/windowrules/engine"
)

// newWindowRules is the window rules engine: the open windows (the
// compositor's, through windows.Watcher) matched against the saved rules,
// and the while-effects they hold (WindowRulesManager).
func (d *Daemon) newWindowRules() {
	o := engine.Options{
		// One reader for the daemon's life: it caches what it read of a process
		Lookup:   procinfo.New(procinfo.Options{}).Lookup,
		OnChange: d.windowRulesChanged,
		Log:      d.opts.Log.With("part", "windowrules"),
	}
	env := mimeapps.FromEnv(d.opts.Getenv)
	o.AppIDs = func(id string) []string { return mimeapps.WindowAppIDs(env, id) }
	if w := windows.New(windows.Options{Getenv: d.opts.Getenv, Log: d.opts.Log.With("part", "windows")}); w != nil {
		o.Events = w.Run
	}
	// The compositor's placement: the engine decides, this sends (a nil one
	// places nothing)
	if p := place.New(place.Options{Getenv: d.opts.Getenv}); p != nil {
		o.Place = p.Run
	}
	d.windowRules = engine.New(o)
}

// windowRulesReport hands the engine what the compositor's config does with
// each rule (compositor.state's windowRules), from the compositor's pushes.
func (d *Daemon) windowRulesReport(method string, params any) {
	if method != pushCompositorState.Method || d.windowRules == nil {
		return
	}
	if o, ok := jsonx.AsObject(params); ok {
		d.windowRules.SetReport(o.Value("windowRules"))
	}
}

// windowRulesChanged pushes the engine's state; the daemon's effect owners
// (keep awake, power profile, pause binds) take st.Holds here too (PRs 10 and 12).
func (d *Daemon) windowRulesChanged(st engine.State) {
	if d.server != nil {
		pushWindowRulesState.Send(d.server, st, subscribedTo(topicWindowRules))
	}
}

// windowRulesConfig hands the engine the saved rules and the binds' ids.
func (d *Daemon) windowRulesConfig() {
	cfg, _ := d.store.Config()
	// reads: WindowRules, Keybinds.binds
	rules, _ := config.Lookup(cfg, config.Keys("WindowRules"))
	binds, _ := config.Lookup(cfg, config.Keys("Keybinds"))
	d.windowRules.SetConfig(rules, binds)
}

// windowRulesPart: the engine, following the saved rules.
func (d *Daemon) windowRulesPart() part {
	d.windowRulesConfig()
	return part{
		name:     "windowrules",
		methods:  d.windowRulesMethods,
		run:      d.windowRules.Run,
		onConfig: func(store.Event) { d.windowRulesConfig() },
	}
}

func (d *Daemon) windowRulesMethods(reg *rpc.Registry) {
	rpc.Handle(reg, "windowRules.get", func(ctx context.Context, c *rpc.Conn, _ struct{}) (engine.State, error) {
		return d.windowRules.State(), nil
	})
	rpc.Handle(reg, "windowRules.windows", func(ctx context.Context, c *rpc.Conn, _ struct{}) (struct {
		Windows []engine.WindowInfo `json:"windows"`
	}, error) {
		return struct {
			Windows []engine.WindowInfo `json:"windows"`
		}{d.windowRules.Windows()}, nil
	})
	// Apply to open windows: the saved rules, now, on every open window
	rpc.Handle(reg, "windowRules.applyNow", func(ctx context.Context, c *rpc.Conn, _ struct{}) (struct {
		Windows int `json:"windows"`
	}, error) {
		n, err := d.windowRules.Apply(ctx)
		return struct {
			Windows int `json:"windows"`
		}{n}, err
	})
	type matchParams struct {
		Section json.RawMessage `json:"section"`
	}
	type matchResult struct {
		Rules []engine.RuleWindows `json:"rules"`
	}
	// The editor's draft: how many open windows each rule would match
	rpc.Handle(reg, "windowRules.match", func(ctx context.Context, c *rpc.Conn, p matchParams) (matchResult, error) {
		filled, err := fillWindowRules(d.store.Pipeline().Schema(), p.Section)
		if err != nil {
			return matchResult{}, err
		}
		return matchResult{d.windowRules.Match(filled)}, nil
	})
}
