// Package gamma sets each output's gamma ramps over
// zwlr_gamma_control_manager_v1, for the night light where the
// compositor has no color transform (sway). A control is held per output
// only while the ramps are set: destroying it gives the output its own
// back. Only one client may hold an output's gamma: another one holding
// it fails ours (Blocked).
package gamma

import (
	"encoding/binary"
	"sync"

	"github.com/axiom-shell/axiom/backend/internal/wayland/client"
	"github.com/axiom-shell/axiom/backend/internal/wayland/outputs"
	"github.com/axiom-shell/axiom/backend/internal/wayland/wire"
)

// The interfaces and their opcodes (wlr-gamma-control-unstable-v1.xml)
const (
	ifaceManager = "zwlr_gamma_control_manager_v1"

	opGetGammaControl = 0 // (id, output)
	opManagerDestroy  = 1
	opSetGamma        = 0 // (fd): 3 × gamma_size uint16, red then green then blue
	opControlDestroy  = 1
	evGammaSize       = 0
	evFailed          = 1
)

// Ramps makes the ramps for one output's gamma size.
type Ramps func(size int) []uint16

// Options configure the control.
type Options struct {
	Outputs *outputs.Tracker
	// OnChange is told when the manager is offered or withdrawn, or an
	// output's gamma is taken by another client (Blocked)
	OnChange func()
}

// Control sets the ramps; it is a client.Client.
type Control struct {
	opts Options

	mu       sync.Mutex
	s        *client.Session
	manager  uint32
	global   uint32
	ramps    Ramps               // nil: off
	controls map[uint32]*control // by wl_output object
}

type control struct {
	obj    uint32
	size   int
	failed bool
}

// New returns a control.
func New(opts Options) *Control {
	c := &Control{opts: opts, controls: map[uint32]*control{}}
	opts.Outputs.OnChange(func() {
		c.mu.Lock()
		c.apply()
		c.mu.Unlock()
	})
	return c
}

// Available reports whether the compositor offers the protocol.
func (c *Control) Available() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.manager != 0
}

// Blocked reports whether another client holds an output's gamma.
func (c *Control) Blocked() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	for _, ctl := range c.controls {
		if ctl.failed {
			return true
		}
	}
	return false
}

// Set sets ramps on every output; nil gives each its own back.
func (c *Control) Set(ramps Ramps) {
	c.mu.Lock()
	c.ramps = ramps
	c.apply()
	c.mu.Unlock()
}

// apply sends the state; c.mu is held.
func (c *Control) apply() {
	bound := map[uint32]bool{}
	if c.ramps != nil && c.manager != 0 {
		for _, o := range c.opts.Outputs.Bound() {
			bound[o.ID] = true
		}
	}
	// Controls for outputs gone, or all of them when off
	for out, ctl := range c.controls {
		if !bound[out] {
			c.destroy(ctl)
			delete(c.controls, out)
		}
	}
	for out := range bound {
		ctl := c.controls[out]
		if ctl == nil {
			ctl = &control{}
			c.controls[out] = ctl
			ctl.obj = c.s.Conn.NewObject(func(op uint16, a *wire.Args) { c.event(ctl, op, a) })
			c.s.Conn.Send(c.manager, opGetGammaControl, wire.Uint(ctl.obj), wire.Uint(out))
			continue // its ramps go once its size is known
		}
		c.send(ctl)
	}
}

func (c *Control) event(ctl *control, op uint16, a *wire.Args) {
	c.mu.Lock()
	switch op {
	case evGammaSize:
		ctl.size = int(a.Uint())
		if c.ramps != nil {
			c.send(ctl)
		}
		c.mu.Unlock()
	case evFailed:
		ctl.failed = true
		c.mu.Unlock()
		c.changed()
	default:
		c.mu.Unlock()
	}
}

// send sets ctl's ramps; c.mu is held.
func (c *Control) send(ctl *control) {
	if ctl.size <= 0 || ctl.failed || c.ramps == nil {
		return
	}
	ramps := c.ramps(ctl.size)
	data := make([]byte, 2*len(ramps))
	for i, v := range ramps {
		binary.LittleEndian.PutUint16(data[2*i:], v)
	}
	f, err := wire.SealedFile("axiom-gamma", data)
	if err != nil {
		return
	}
	defer f.Close()
	c.s.Conn.Send(ctl.obj, opSetGamma, wire.Fd(f))
}

func (c *Control) destroy(ctl *control) {
	c.s.Conn.Send(ctl.obj, opControlDestroy)
	c.s.Conn.Forget(ctl.obj)
}

// Interfaces (client.Client)
func (c *Control) Interfaces() []string { return []string{ifaceManager} }

// Start (client.Client)
func (c *Control) Start(s *client.Session) {
	c.mu.Lock()
	c.s, c.manager, c.global, c.controls = s, 0, 0, map[uint32]*control{}
	c.mu.Unlock()
}

// Global binds the manager: binding it takes no output's gamma
// (client.Client).
func (c *Control) Global(g client.Global) {
	c.mu.Lock()
	if c.manager != 0 {
		c.mu.Unlock()
		return
	}
	c.manager, _, _ = c.s.Bind(g, 1, nil)
	c.global = g.Name
	c.apply()
	c.mu.Unlock()
	c.changed()
}

// Removed drops the manager and its controls (client.Client).
func (c *Control) Removed(name uint32) {
	c.mu.Lock()
	if name != c.global {
		c.mu.Unlock()
		return
	}
	for out, ctl := range c.controls {
		c.destroy(ctl)
		delete(c.controls, out)
	}
	c.s.Conn.Send(c.manager, opManagerDestroy)
	c.s.Conn.Forget(c.manager)
	c.manager, c.global = 0, 0
	c.mu.Unlock()
	c.changed()
}

// Ready (client.Client)
func (c *Control) Ready() {}

func (c *Control) changed() {
	if c.opts.OnChange != nil {
		c.opts.OnChange()
	}
}
