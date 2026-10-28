package manager

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// Outputs are the connected outputs of the first of Hyprland, niri and
// sway running (as the config layer picks): read, and set by monitor
// rules (MonitorRule) in the compositor's own terms.
type Outputs struct {
	Hypr *ipc.Hypr
	Niri *ipc.Niri
	Sway *ipc.Sway
}

// OutputsFromEnv are the outputs of the compositor the environment names.
func OutputsFromEnv(getenv func(string) string) Outputs {
	return Outputs{Hypr: ipc.HyprFromEnv(getenv), Niri: ipc.NiriFromEnv(getenv), Sway: ipc.SwayFromEnv(getenv)}
}

// Read lists the outputs connected, disabled ones too.
func (o Outputs) Read(ctx context.Context) ([]render.Output, error) {
	switch {
	case o.Hypr != nil:
		return o.Hypr.Outputs(ctx)
	case o.Niri != nil:
		return o.Niri.Outputs(ctx)
	case o.Sway != nil:
		return o.Sway.Outputs(ctx)
	}
	return nil, axerr.New(axerr.Unavailable, "no compositor to read the outputs of")
}

// Apply sets the rules now. details are the outputs connected (Read's, or
// CompositorManager.withOutputDetails), which a rule naming its output or
// mirror by description is resolved in.
func (o Outputs) Apply(ctx context.Context, rules, details any) error {
	switch {
	case o.Hypr != nil:
		reply, err := o.Hypr.Eval(ctx, strings.Join(render.MonitorCalls(rules, render.MirrorNames(details)), "\n"))
		if err != nil {
			return axerr.Wrap(axerr.Unavailable, err, "no reply from Hyprland")
		}
		if reply != "" {
			return axerr.New(axerr.Refused, "Hyprland refused the monitor rules: %s", reply)
		}
	case o.Niri != nil:
		// Each request on its own: one niri refuses doesn't stop the rest
		var refused error
		for _, request := range render.NiriOutputRequests(rules, details).Items {
			if _, err := o.Niri.Request(ctx, json.RawMessage(jsonx.MarshalCompact(request))); errors.Is(err, ipc.ErrRefused) {
				if refused == nil {
					refused = axerr.Wrap(axerr.Refused, err, "")
				}
			} else if err != nil {
				return axerr.Wrap(axerr.Unavailable, err, "no reply from niri")
			}
		}
		if refused != nil {
			return refused
		}
	case o.Sway != nil:
		results, err := o.Sway.Run(ctx, render.SwayOutputCommands(rules))
		if err != nil {
			return axerr.Wrap(axerr.Unavailable, err, "no reply from sway")
		}
		for _, r := range results {
			if !r.Success {
				return axerr.New(axerr.Refused, "sway refused an output command: %s", r.Error)
			}
		}
	default:
		return axerr.New(axerr.Unavailable, "no compositor to set the outputs on")
	}
	return nil
}

// outputsIO reads and sets the outputs (Outputs; a fake in tests).
type outputsIO interface {
	Read(ctx context.Context) ([]render.Output, error)
	Apply(ctx context.Context, rules, details any) error
}

// profileRules are profiles' rules for outputs: render.HyprlandRules on
// Hyprland, render.SavedRules elsewhere.
func profileRules(hyprland bool, profiles any, outputs []render.Output) []any {
	if hyprland {
		return render.HyprlandRules(profiles, outputs)
	}
	return render.SavedRules(profiles, outputs)
}

// profileSwitch keeps the saved monitor profile (Monitors.items) for
// what's connected applied: read again on each hotplug, applied once per
// set of outputs and rules.
type profileSwitch struct {
	io       outputsIO
	hyprland bool
	// outputs as last read, nil until then
	outputs []render.Output
	// applied: the outputs and rules applied last ("" after a reload,
	// which sets the outputs as the compositor's config says)
	applied string
}

// read reads the outputs again.
func (p *profileSwitch) read(ctx context.Context) error {
	outputs, err := p.io.Read(ctx)
	if err != nil {
		return err
	}
	if outputs == nil {
		outputs = []render.Output{}
	}
	p.outputs = outputs
	return nil
}

// rules are profiles' rules for the outputs read ([] for none), nil until
// they're read.
func (p *profileSwitch) rules(profiles any) *jsonx.Array {
	if p.outputs == nil {
		return nil
	}
	return jsonx.Arr(profileRules(p.hyprland, profiles, p.outputs)...)
}

// matched is the name of the saved profile for the outputs read
// (compositor.state's monitorProfile), "" for none or before they're read
func (p *profileSwitch) matched(profiles any) string {
	if p.outputs == nil {
		return ""
	}
	i := render.MatchProfile(profiles, p.outputs)
	if i < 0 {
		return ""
	}
	name, _ := getAny(itemsOf(profiles)[i], "name").(string)
	return name
}

// apply applies profiles' rules for the outputs read, unless they're
// what was applied last for the same outputs or no profile matches.
func (p *profileSwitch) apply(ctx context.Context, profiles any) error {
	rules := p.rules(profiles)
	if rules == nil || len(rules.Items) == 0 {
		return nil
	}
	names := make([]string, len(p.outputs))
	for i, o := range p.outputs {
		names[i] = o.Name + " " + o.Description
	}
	slices.Sort(names)
	key := strings.Join(names, "\n") + string(jsonx.MarshalCompact(rules))
	if key == p.applied {
		return nil
	}
	p.applied = key
	return p.io.Apply(ctx, rules, tree(p.outputs))
}

// ProfileWatch keeps a saved monitor profile applied where no config
// layer runs (the greeter's Hyprland or sway), as the session's Manager
// does: after each hotplug (Changed), once the outputs have settled (at
// once on Hyprland), it reads them again and applies the profile for them,
// until ctx ends.
type ProfileWatch struct {
	ctx      context.Context
	log      *slog.Logger
	mu       sync.Mutex
	sw       profileSwitch
	profiles any
	timer    *time.Timer
	delay    time.Duration
}

// NewProfileWatch watches the outputs of o's compositor.
func NewProfileWatch(ctx context.Context, o Outputs, log *slog.Logger) *ProfileWatch {
	w := newProfileWatch(ctx, o, log)
	if o.Hypr != nil {
		w.sw.hyprland, w.delay = true, 0
	}
	return w
}

func newProfileWatch(ctx context.Context, io outputsIO, log *slog.Logger) *ProfileWatch {
	w := &ProfileWatch{ctx: ctx, log: log, sw: profileSwitch{io: io}, delay: 500 * time.Millisecond}
	w.timer = time.AfterFunc(time.Hour, w.apply)
	w.timer.Stop()
	context.AfterFunc(ctx, func() { w.timer.Stop() })
	return w
}

// SetProfiles takes the profiles (Monitors.items) and applies the one
// for what's connected.
func (w *ProfileWatch) SetProfiles(profiles any) {
	w.mu.Lock()
	w.profiles = profiles
	w.mu.Unlock()
	w.Changed()
}

// Changed tells of an output connected or gone.
func (w *ProfileWatch) Changed() {
	if w.ctx.Err() == nil {
		w.timer.Reset(w.delay)
	}
}

func (w *ProfileWatch) apply() {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.ctx.Err() != nil {
		return
	}
	if err := w.sw.read(w.ctx); err != nil {
		w.log.Warn("could not read the outputs", "err", err)
		return
	}
	if err := w.sw.apply(w.ctx, w.profiles); err != nil {
		w.log.Warn("could not apply the monitor profile", "err", err)
	}
}
