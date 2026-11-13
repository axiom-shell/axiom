package daemon

import (
	"context"
	"encoding/json"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/compositor/place"
	"github.com/axiom-shell/axiom/backend/internal/compositor/windows"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/mimeapps"
	"github.com/axiom-shell/axiom/backend/internal/powerprofiles"
	"github.com/axiom-shell/axiom/backend/internal/procinfo"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/store"
	"github.com/axiom-shell/axiom/backend/internal/windowrules"
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

// ruleEffects reads the holds the daemon's effect owners act on: the names of
// the rules holding keep awake, and the power profile (PPD's name, "" for none
// or while the user overrode it) with the rule's name for its reason.
func ruleEffects(st engine.State) (awake []string, profile, reason string) {
	names := map[string]string{}
	for _, r := range st.Rules {
		names[r.Rule] = r.Name
	}
	name := func(id string) string {
		if n := names[id]; n != "" {
			return n
		}
		return id
	}
	awake = []string{}
	for _, id := range st.Holds.KeepAwake {
		awake = append(awake, name(id))
	}
	if h := st.Holds.PowerProfile; h.Rule != "" && !st.Overrides.PowerProfile {
		profile, reason = powerprofiles.Name(h.Profile), name(h.Rule)
	}
	return awake, profile, reason
}

// windowRulesChanged pushes the engine's state and gives the daemon's effect
// owners their holds (keep awake, the power profile, the paused shortcuts).
func (d *Daemon) windowRulesChanged(st engine.State) {
	awake, profile, reason := ruleEffects(st)
	if d.idle != nil {
		d.idle.SetKeepAwake(awake)
	}
	if d.power != nil {
		d.power.Hold(profile, reason)
	}
	if d.compositor != nil {
		d.compositor.SetPause(st.Holds.PauseBinds)
	}
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
	type overrideParams struct {
		Effect string `json:"effect"`
	}
	// The user's own say over a hold (the shell's DND switch turned off by
	// hand): it wins until the rule's hold ends. A profile is overridden by
	// picking one, which PPD reports.
	rpc.Handle(reg, "windowRules.override", func(ctx context.Context, c *rpc.Conn, p overrideParams) (struct{}, error) {
		if !fromShell(c) {
			return struct{}{}, axerr.New(axerr.Refused, "only the shell overrides a window rule's hold")
		}
		if p.Effect != "dnd" {
			return struct{}{}, axerr.New(axerr.BadRequest, "only dnd is overridden this way")
		}
		return struct{}{}, d.windowRules.Override(p.Effect)
	})
	type fromParams struct {
		ID string `json:"id"`
	}
	type fromResult struct {
		Window engine.WindowInfo `json:"window"`
		Kind   windowrules.Kind  `json:"kind"`
	}
	// What a rule made from a window starts with (id "": the focused window)
	rpc.Handle(reg, "windowRules.fromWindow", func(ctx context.Context, c *rpc.Conn, p fromParams) (fromResult, error) {
		w, facts, ok := d.windowRules.Window(p.ID)
		switch {
		case ok:
			return fromResult{w, windowrules.KindFor(facts)}, nil
		case p.ID == "":
			return fromResult{}, axerr.New(axerr.NotFound, "no focused window")
		}
		return fromResult{}, axerr.New(axerr.NotFound, "no such window")
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
