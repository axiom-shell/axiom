package daemon

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"os"
	"path/filepath"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/compositor/manager"
	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/cursortheme"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// compositorSocketPart: the running compositor's own socket, for the
// shell's backends: what HyprlandManager asks Hyprland's request socket
// (hyprctl's requests, without a process each), and NiriManager's requests
// and event stream (Quickshell has no niri module).
func (d *Daemon) compositorSocketPart() part {
	return part{name: "compositor socket", methods: d.compositorSocketMethods}
}

func (d *Daemon) compositorSocketMethods(reg *rpc.Registry) {
	hyprHandlers(reg, ipc.HyprFromEnv(d.opts.Getenv))
	niriHandlers(reg, ipc.NiriFromEnv(d.opts.Getenv), d.niriStreams)
	outputHandlers(reg, d.opts.Getenv)
}

// outputHandlers is outputs.apply: monitor rules (MonitorRule) set now on
// the compositor the environment names, as the Monitors page's Apply and
// the greeter's saved profile do. details are the outputs connected
// (CompositorManager.withOutputDetails), which a rule naming its output or
// mirror by description is resolved in.
func outputHandlers(reg *rpc.Registry, getenv func(string) string) {
	type applyParams struct {
		Rules   json.RawMessage `json:"rules"`
		Details json.RawMessage `json:"details"`
	}
	outputs := manager.OutputsFromEnv(getenv)
	rpc.Handle(reg, "outputs.apply", func(ctx context.Context, c *rpc.Conn, p applyParams) (struct{}, error) {
		if !fromShell(c) {
			return struct{}{}, axerr.New(axerr.Refused, "only the shell sets the outputs")
		}
		rules, err := jsonx.Unmarshal(orNull(p.Rules))
		if err != nil {
			return struct{}{}, axerr.Wrap(axerr.BadRequest, err, "rules")
		}
		details, err := jsonx.Unmarshal(orNull(p.Details))
		if err != nil {
			return struct{}{}, axerr.Wrap(axerr.BadRequest, err, "details")
		}
		return struct{}{}, outputs.Apply(ctx, rules, details)
	})
	// One at a time, in the order sent: a revert lands after the Apply it
	// undoes
	reg.InOrder("outputs.apply")
}

// greeterHandlers is greeter.compositor, the greeter's axiom's alone: the
// greeter's compositor, loading no config of axiom's, set up from its
// bundle (the config's Monitors profiles and Input values). On Hyprland and
// sway the monitors are kept in the saved profile for what's connected by
// profiles (greeterProfiles). Hyprland evals the Input options marked
// x-greeter, then sets the cursor; sway gets its live input and seat
// commands, its cursor the theme's companion when XCURSOR_PATH holds the
// bundle's copy of it (greeter-session.sh); niri takes input from its
// config file alone. schema is the config's.
func greeterHandlers(reg *rpc.Registry, getenv func(string) string, schema func() any, profiles func(any)) {
	type applyParams struct {
		Profiles json.RawMessage `json:"profiles"`
		Input    json.RawMessage `json:"input"`
	}
	h, n, s := ipc.HyprFromEnv(getenv), ipc.NiriFromEnv(getenv), ipc.SwayFromEnv(getenv)
	rpc.Handle(reg, "greeter.compositor", func(ctx context.Context, c *rpc.Conn, p applyParams) (struct{}, error) {
		if !fromShell(c) {
			return struct{}{}, axerr.New(axerr.Refused, "only the shell sets up the greeter's compositor")
		}
		monitors, err := jsonx.Unmarshal(orNull(p.Profiles))
		if err != nil {
			return struct{}{}, axerr.Wrap(axerr.BadRequest, err, "profiles")
		}
		values, err := jsonx.Unmarshal(orNull(p.Input))
		if err != nil {
			return struct{}{}, axerr.Wrap(axerr.BadRequest, err, "input")
		}
		return struct{}{}, applyGreeter(ctx, h, n != nil, s, monitors, values, inputSchemaOf(schema()), getenv("XCURSOR_PATH"), profiles)
	})
}

// inputSchemaOf is schema's properties.Input, or nil
func inputSchemaOf(schema any) any {
	o, _ := schema.(*jsonx.Object)
	if o != nil {
		o, _ = o.Value("properties").(*jsonx.Object)
	}
	if o == nil {
		return nil
	}
	return o.Value("Input")
}

// applyGreeter sets up the first of Hyprland, niri and sway running from
// the greeter's profiles and input values (greeter.compositor).
// xcursorPath is the greeter's XCURSOR_PATH; watch keeps Hyprland's and
// sway's monitors in the profiles (greeterProfiles).
func applyGreeter(ctx context.Context, h *ipc.Hypr, niri bool, s *ipc.Sway, profiles, values, inputSchema any, xcursorPath string, watch func(any)) error {
	input := render.Input(values, nil)
	cursor, _ := input.Value("cursor").(*jsonx.Object)
	if cursor != nil {
		if name := companionIn(xcursorPath, jsonx.ToString(cursor.Value("theme"))); name != "" {
			cursor.Set("xcursor", name)
		}
	}
	switch {
	case h != nil:
		watch(profiles)
		// A refused Lua (the input) still gets the cursor
		var refused error
		if lua := render.GreeterLua(inputSchema, values); len(lua) > 0 {
			reply, err := h.Eval(ctx, strings.Join(lua, "\n"))
			if err != nil {
				return axerr.Wrap(axerr.Unavailable, err, "no reply from Hyprland")
			}
			if reply != "" {
				refused = axerr.New(axerr.Refused, "Hyprland refused the greeter's Lua: %s", reply)
			}
		}
		if cursor == nil {
			return refused
		}
		reply, err := h.Request(ctx, "setcursor "+jsonx.ToString(cursor.Value("theme"))+" "+jsonx.ToString(cursor.Value("size")))
		if err != nil {
			return axerr.Wrap(axerr.Unavailable, err, "no reply from Hyprland")
		}
		if reply != "ok" {
			return axerr.New(axerr.Refused, "Hyprland refused the cursor: %s", reply)
		}
		return refused
	case niri:
	case s != nil:
		watch(profiles)
		results, err := s.Run(ctx, strings.Join(render.SwayInputLines(input, inputSchema, true), "; "))
		if err != nil {
			return axerr.Wrap(axerr.Unavailable, err, "no reply from sway")
		}
		for _, r := range results {
			if !r.Success {
				return axerr.New(axerr.Refused, "sway refused an input command: %s", r.Error)
			}
		}
	default:
		return axerr.New(axerr.Unavailable, "no compositor to set up")
	}
	return nil
}

// companionIn is theme's companion (cursortheme) when a folder of path
// (an XCURSOR_PATH) holds it, else "": the user's own, in their
// $XDG_DATA_HOME, is out of greetd's user's reach, so the bundle carries a
// copy (GreeterManager)
func companionIn(path, theme string) string {
	name := cursortheme.CompanionName(theme)
	for _, dir := range filepath.SplitList(path) {
		if _, err := os.Stat(filepath.Join(dir, name, "index.theme")); err == nil {
			return name
		}
	}
	return ""
}

// orNull is data, or JSON's null when it's missing
func orNull(data json.RawMessage) []byte {
	if len(data) == 0 {
		return []byte("null")
	}
	return data
}

// hyprHandlers is hypr.request on h (nil: not under Hyprland).
func hyprHandlers(reg *rpc.Registry, h *ipc.Hypr) {
	type requestParams struct {
		// As hyprctl sends it: "j/clients", "[[BATCH]]j/a;j/b", "eval …"
		Command string `json:"command"`
	}
	type requestResult struct {
		Reply string `json:"reply"`
	}
	// Shell only: a request may change Hyprland (eval, reload, setcursor)
	rpc.Handle(reg, "hypr.request", func(ctx context.Context, c *rpc.Conn, p requestParams) (requestResult, error) {
		if !fromShell(c) {
			return requestResult{}, axerr.New(axerr.Refused, "only the shell sends Hyprland requests")
		}
		if h == nil {
			return requestResult{}, axerr.New(axerr.Unavailable, "not running under Hyprland")
		}
		reply, err := h.Request(ctx, p.Command)
		if err != nil {
			return requestResult{}, axerr.Wrap(axerr.Unavailable, err, "no reply from Hyprland")
		}
		return requestResult{Reply: reply}, nil
	})
}

// niriStreams are niri's event stream for each connection watching it
// (niri.watch, pushed as niri.started and niri.event), their goroutines on
// goFn until ctx ends; nil when not under niri.
func niriStreams(getenv func(string) string, log *slog.Logger, ctx context.Context, goFn func(func(context.Context))) *ipc.NiriStreams {
	n := ipc.NiriFromEnv(getenv)
	if n == nil {
		return nil
	}
	return ipc.NewNiriStreams(n, ipc.NiriStreamsOptions{
		Started: func(s ipc.Subscriber) { s.Notify(pushNiriStarted.Method, struct{}{}) },
		Event:   func(s ipc.Subscriber, event json.RawMessage) { s.Notify(pushNiriEvent.Method, event) },
		Log:     log.With("part", "niri"), Context: ctx, Go: goFn})
}

// niriHandlers are niri.request and niri.watch on n (nil:
// not under niri) and its streams.
func niriHandlers(reg *rpc.Registry, n *ipc.Niri, streams *ipc.NiriStreams) {
	type requestParams struct {
		// A niri request: "Outputs", {"Action": {…}}, {"Output": {…}}
		Request json.RawMessage `json:"request"`
	}
	available := func(c *rpc.Conn) error {
		if !fromShell(c) {
			return axerr.New(axerr.Refused, "only the shell talks to niri")
		}
		if n == nil || streams == nil {
			return axerr.New(axerr.Unavailable, "not running under niri")
		}
		return nil
	}
	// The reply's Ok value; refused when niri answered Err
	rpc.Handle(reg, "niri.request", func(ctx context.Context, c *rpc.Conn, p requestParams) (json.RawMessage, error) {
		if err := available(c); err != nil {
			return nil, err
		}
		ok, err := n.Request(ctx, p.Request)
		switch {
		case errors.Is(err, ipc.ErrRefused):
			return nil, axerr.Wrap(axerr.Refused, err, "")
		case err != nil:
			return nil, axerr.Wrap(axerr.Unavailable, err, "no reply from niri")
		}
		return ok, nil
	})
	// Events come as niri.started and niri.event pushes, to this
	// connection only, until it closes; watching again keeps its stream
	rpc.Handle(reg, "niri.watch", func(ctx context.Context, c *rpc.Conn, _ struct{}) (struct{}, error) {
		if err := available(c); err != nil {
			return struct{}{}, err
		}
		streams.Watch(c)
		return struct{}{}, nil
	})
}
