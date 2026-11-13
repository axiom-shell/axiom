// Package ipc talks to the running compositor: Hyprland's request and
// event sockets, sway's i3 IPC and niri's JSON socket. Each is a small
// client: requests with a reply, and an event stream telling axiom's config
// layer when the compositor reloaded its config
// (docs/dev/compositor/config-modes.md). The shell's Hyprland and niri
// backends send their requests through it too (hypr.request, niri.request),
// and niri's backend reads niri's event stream from it (niri.watch).
package ipc

import (
	"context"
	"errors"
	"net"
	"os"
	"strings"
	"time"
)

// timeout bounds one request
const timeout = 5 * time.Second

// ErrNoCompositor: the environment names no socket of that compositor.
var ErrNoCompositor = errors.New("no compositor socket")

// ctxConn is a connection a done ctx cuts off: a read or write blocked on
// a compositor that never answers returns at once (callers answer with
// ctxErr). Close releases the watch.
type ctxConn struct {
	net.Conn
	stop func() bool
}

func (c *ctxConn) Close() error {
	c.stop()
	return c.Conn.Close()
}

// ctxErr is ctx's error when ctx ended (what cut the request short), else err.
func ctxErr(ctx context.Context, err error) error {
	if err == nil {
		return nil
	}
	if ctx.Err() != nil {
		return ctx.Err()
	}
	// The connection's deadline is ctx's and may fire just before ctx notices
	if dl, ok := ctx.Deadline(); ok && errors.Is(err, os.ErrDeadlineExceeded) && time.Until(dl) < 50*time.Millisecond {
		return context.DeadlineExceeded
	}
	return err
}

// dial connects to path; the connection has a deadline (timeout, or ctx's
// when sooner) and is cut off when ctx is done.
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
	return &ctxConn{Conn: conn, stop: context.AfterFunc(ctx, func() { conn.SetDeadline(time.Unix(1, 0)) })}, nil
}

// Reloads is a compositor's event stream as what the layer needs from it:
// one value per config reload (Failed when it couldn't load the config).
// Initial is niri's state as the stream starts (whether the config it
// runs loaded), not a reload.
type Reload struct {
	Failed, Initial bool
}

// describe is an output's description as the shell builds it from the
// compositor's make, model and serial: the parts it knows, "Unknown" ones
// dropped (SwayState, NiriState)
func describe(parts ...string) string {
	known := parts[:0]
	for _, part := range parts {
		if part != "" && part != "Unknown" {
			known = append(known, part)
		}
	}
	return strings.Join(known, " ")
}
