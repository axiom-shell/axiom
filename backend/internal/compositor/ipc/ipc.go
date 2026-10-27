// Package ipc talks to the running compositor: Hyprland's request and
// event sockets, sway's i3 IPC and niri's JSON socket. Each is a small
// client: requests with a reply, and an event stream telling axiom's config
// layer when the compositor reloaded its config
// (docs/dev/compositor/config-modes.md). The shell's Hyprland backend sends
// its requests through it too (hypr.request).
package ipc

import (
	"context"
	"errors"
	"net"
	"time"
)

// timeout bounds one request
const timeout = 5 * time.Second

// ErrNoCompositor: the environment names no socket of that compositor.
var ErrNoCompositor = errors.New("no compositor socket")

func dial(ctx context.Context, path string) (net.Conn, error) {
	if path == "" {
		return nil, ErrNoCompositor
	}
	d := net.Dialer{Timeout: timeout}
	conn, err := d.DialContext(ctx, "unix", path)
	if err != nil {
		return nil, err
	}
	deadline := time.Now().Add(timeout)
	if dl, ok := ctx.Deadline(); ok && dl.Before(deadline) {
		deadline = dl
	}
	conn.SetDeadline(deadline)
	return conn, nil
}

// Reloads is a compositor's event stream as what the layer needs from it:
// one value per config reload (Failed when it couldn't load the config).
type Reload struct {
	Failed bool
}
