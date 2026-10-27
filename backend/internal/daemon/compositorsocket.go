package daemon

import (
	"context"
	"encoding/json"
	"errors"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
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
	niriHandlers(reg, ipc.NiriFromEnv(d.opts.Getenv), func() *ipc.NiriStreams { return d.niriStreams })
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

// niriHandlers are niri.request, niri.watch and niri.unwatch on n (nil:
// not under niri) and its streams.
func niriHandlers(reg *rpc.Registry, n *ipc.Niri, streams func() *ipc.NiriStreams) {
	type requestParams struct {
		// A niri request: "Outputs", {"Action": {…}}, {"Output": {…}}
		Request json.RawMessage `json:"request"`
	}
	available := func(c *rpc.Conn) error {
		if !fromShell(c) {
			return axerr.New(axerr.Refused, "only the shell talks to niri")
		}
		if n == nil || streams() == nil {
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
	// connection only; watching again starts over from niri's full state
	rpc.Handle(reg, "niri.watch", func(ctx context.Context, c *rpc.Conn, _ struct{}) (struct{}, error) {
		if err := available(c); err != nil {
			return struct{}{}, err
		}
		streams().Watch(c)
		return struct{}{}, nil
	})
	rpc.Handle(reg, "niri.unwatch", func(ctx context.Context, c *rpc.Conn, _ struct{}) (struct{}, error) {
		if err := available(c); err != nil {
			return struct{}{}, err
		}
		streams().Unwatch(c)
		return struct{}{}, nil
	})
}
