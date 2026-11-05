package daemon

import (
	"context"
	"sync"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/nightlight"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/wayland/client"
	"github.com/axiom-shell/axiom/backend/internal/wayland/ctm"
	"github.com/axiom-shell/axiom/backend/internal/wayland/gamma"
)

// waylandState is what the daemon's Wayland connection can do for the
// shell (wayland.state): the services gate on it, not on a compositor.
type waylandState struct {
	// Ready: the connection's globals are bound, so the rest is what the
	// compositor offers (all off before), or the connection failed since
	// (all off: nothing on it works)
	Ready bool `json:"ready"`
	// Typing: virtual keyboards (input.type)
	Typing bool `json:"typing"`
	// NightLight: how the night light warms the screens, "ctm", "gamma"
	// or "" (nightlight.set)
	NightLight string `json:"nightLight"`
	// Clipboard: the clipboard control bound, "ext", "wlr" or ""
	// (clipboard.*)
	Clipboard string `json:"clipboard"`
	// InputMethod: the compositor offers input methods (an IME's global,
	// zwp_input_method_manager_v2), so fcitx5 or ibus can type in its
	// windows (supports.inputMethod; inputMethod.*)
	InputMethod bool `json:"inputMethod"`
}

func (d *Daemon) waylandNow() waylandState {
	d.wayland.mu.Lock()
	ready, failed := d.wayland.ready, d.wayland.failed
	d.wayland.mu.Unlock()
	if !ready || failed {
		return waylandState{Ready: ready}
	}
	return waylandState{Ready: ready, Typing: d.keyboard.Available(), NightLight: d.nightLight.Mode(), Clipboard: d.clip.Protocol(), InputMethod: d.wayland.inputMethod()}
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
		pushWaylandState.Send(d.server, st, subscribedTo(topicWayland))
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
	rpc.Handle(reg, "nightlight.get", func(ctx context.Context, c *rpc.Conn, _ struct{}) (nightlight.State, error) {
		return d.nightLight.State(), nil
	})
	rpc.Handle(reg, "nightlight.set", func(ctx context.Context, c *rpc.Conn, p nightlight.Settings) (struct{}, error) {
		if !fromShell(c) {
			return struct{}{}, axerr.New(axerr.Refused, "only the shell drives the night light")
		}
		if p.On && (p.Temperature < 1000 || p.Temperature > 40000 || p.Gamma < 0 || p.Gamma > 100) {
			return struct{}{}, axerr.New(axerr.BadRequest, "a temperature of 1000-40000 K and a gamma of 0-100%%")
		}
		d.nightLight.Set(p)
		return struct{}{}, nil
	})
}

// newNightLight is the night light on the connection's color transform
// or gamma ramps, whichever the compositor offers.
func (d *Daemon) newNightLight() {
	changed := func() {
		if d.nightLight != nil {
			d.nightLight.Changed()
		}
		d.pushWayland()
	}
	d.ctm = ctm.New(ctm.Options{Outputs: d.outputs, OnChange: changed})
	d.gamma = gamma.New(gamma.Options{Outputs: d.outputs, OnChange: changed})
	d.nightLight = nightlight.New(nightlight.Options{
		CTM:   d.ctm,
		Gamma: d.gamma,
		OnState: func(st nightlight.State) {
			if d.server != nil {
				pushNightLightState.Send(d.server, st, subscribedTo(topicWayland))
			}
		},
	})
}

// The input method protocol's global: the daemon binds nothing of it (the
// IME does), it only reports that the compositor offers it
const inputMethodGlobal = "zwp_input_method_manager_v2"

// waylandSession remembers the daemon's Wayland connection for what asks
// about the compositor behind it, and whether it's ready; a client.Client
// binding nothing, last on the connection so its Ready follows the others'.
// It also watches the globals only reported, never bound.
type waylandSession struct {
	mu    sync.Mutex
	s     *client.Session
	ready bool
	// imGlobals are the input method globals offered, by name
	imGlobals map[uint32]bool
	// failed: the connection failed after Start (a protocol error)
	failed bool
	pushed *waylandState
	// onChange is told when ready changes
	onChange func()
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

func (w *waylandSession) Interfaces() []string { return []string{inputMethodGlobal} }
func (w *waylandSession) Start(s *client.Session) {
	w.mu.Lock()
	w.s, w.ready, w.failed = s, false, false
	w.imGlobals = map[uint32]bool{}
	w.mu.Unlock()
	w.onChange()
}

// Global and Removed see only the input method's global (Interfaces):
// told once ready, so a compositor adding it later is heard.
func (w *waylandSession) Global(g client.Global) {
	w.mu.Lock()
	w.imGlobals[g.Name] = true
	ready := w.ready
	w.mu.Unlock()
	if ready {
		w.onChange()
	}
}

func (w *waylandSession) Removed(name uint32) {
	w.mu.Lock()
	delete(w.imGlobals, name)
	ready := w.ready
	w.mu.Unlock()
	if ready {
		w.onChange()
	}
}

// inputMethod: the compositor offers the input method protocol.
func (w *waylandSession) inputMethod() bool {
	w.mu.Lock()
	defer w.mu.Unlock()
	return len(w.imGlobals) > 0
}
func (w *waylandSession) Ready() {
	w.mu.Lock()
	w.ready = true
	w.mu.Unlock()
	w.onChange()
}

// Failed: the connection failed (followCompositor), so the shell falls
// back from everything it offered.
func (w *waylandSession) Failed() {
	w.mu.Lock()
	w.ready, w.failed = true, true
	w.mu.Unlock()
	w.onChange()
}
