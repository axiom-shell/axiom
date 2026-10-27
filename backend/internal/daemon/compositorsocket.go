package daemon

import (
	"context"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// compositorSocketPart: the running compositor's own socket, for the
// shell's Hyprland backend: what HyprlandManager asks Hyprland's request socket
// (hyprctl's requests, without a process each).
func (d *Daemon) compositorSocketPart() part {
	return part{name: "compositor socket", methods: d.compositorSocketMethods}
}

func (d *Daemon) compositorSocketMethods(reg *rpc.Registry) {
	hyprHandlers(reg, ipc.HyprFromEnv(d.opts.Getenv))
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
