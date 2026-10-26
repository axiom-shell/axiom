package daemon

import (
	"context"
	"sync"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/wayland/client"
)

// waylandState is what the daemon's Wayland connection can do for the
// shell (wayland.state): the services gate on it, not on a compositor.
type waylandState struct {
	// Typing: virtual keyboards (input.type)
	Typing bool `json:"typing"`
}

func (d *Daemon) waylandNow() waylandState {
	return waylandState{Typing: d.keyboard.Available()}
}

// pushWayland pushes the connection's state when it changed (its clients
// tell when a global comes or goes).
func (d *Daemon) pushWayland() {
	st := d.waylandNow()
	d.wayland.mu.Lock()
	same := d.wayland.pushed != nil && *d.wayland.pushed == st
	d.wayland.pushed = &st
	d.wayland.mu.Unlock()
	if !same && d.server != nil {
		d.server.BroadcastLatest("wayland.state", st, subscribedTo(topicWayland))
	}
}

// waylandPart: what the shell asks of the Wayland connection.
func (d *Daemon) waylandPart() part {
	return part{name: "wayland", methods: d.waylandMethods}
}

func (d *Daemon) waylandMethods(reg *rpc.Registry) {
	rpc.Handle(reg, "wayland.get", func(ctx context.Context, c *rpc.Conn, _ struct{}) (waylandState, error) {
		return d.waylandNow(), nil
	})
	type typeParams struct {
		Text string `json:"text"`
	}
	rpc.Handle(reg, "input.type", func(ctx context.Context, c *rpc.Conn, p typeParams) (struct{}, error) {
		// What's typed goes to the focused window: only the shell asks
		if !fromShell(c) {
			return struct{}{}, axerr.New(axerr.Refused, "only the shell types")
		}
		return struct{}{}, d.keyboard.Type(ctx, p.Text)
	})
}

// waylandSession remembers the daemon's Wayland connection for what asks
// about the compositor behind it; a client.Client binding nothing.
type waylandSession struct {
	mu     sync.Mutex
	s      *client.Session
	pushed *waylandState
}

// CompositorPID is the compositor's process id (0 before the connection).
func (w *waylandSession) CompositorPID() int {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.s == nil {
		return 0
	}
	return w.s.Conn.PeerPID()
}

func (w *waylandSession) Interfaces() []string { return nil }
func (w *waylandSession) Start(s *client.Session) {
	w.mu.Lock()
	w.s = s
	w.mu.Unlock()
}
func (w *waylandSession) Global(client.Global) {}
func (w *waylandSession) Removed(uint32)       {}
func (w *waylandSession) Ready()               {}
