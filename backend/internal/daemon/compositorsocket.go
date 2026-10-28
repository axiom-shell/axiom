package daemon

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
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
	h, n, s := ipc.HyprFromEnv(getenv), ipc.NiriFromEnv(getenv), ipc.SwayFromEnv(getenv)
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
		return struct{}{}, applyOutputs(ctx, h, n, s, rules, details)
	})
	// One at a time, in the order sent: a revert lands after the Apply it
	// undoes
	reg.InOrder("outputs.apply")
}

// applyOutputs sends the rules to the first of Hyprland, niri and sway
// running (as the config layer picks), in their own terms
func applyOutputs(ctx context.Context, h *ipc.Hypr, n *ipc.Niri, s *ipc.Sway, rules, details any) error {
	switch {
	case h != nil:
		reply, err := h.Eval(ctx, strings.Join(render.MonitorCalls(rules, render.MirrorNames(details)), "\n"))
		if err != nil {
			return axerr.Wrap(axerr.Unavailable, err, "no reply from Hyprland")
		}
		if reply != "" {
			return axerr.New(axerr.Refused, "Hyprland refused the monitor rules: %s", reply)
		}
	case n != nil:
		// Each request on its own: one niri refuses doesn't stop the rest
		var refused error
		for _, request := range render.NiriOutputRequests(rules, details).Items {
			if _, err := n.Request(ctx, json.RawMessage(jsonx.MarshalCompact(request))); errors.Is(err, ipc.ErrRefused) {
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
	case s != nil:
		results, err := s.Run(ctx, render.SwayOutputCommands(rules))
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
