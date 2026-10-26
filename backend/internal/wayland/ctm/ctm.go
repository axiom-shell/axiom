// Package ctm sets a color transform per output over Hyprland's
// hyprland_ctm_control_manager_v1 (the protocol hyprsunset uses), for the
// night light on Hyprland: gamma tables stay untouched. The manager is
// bound only while a transform is set, since holding it keeps every
// other client (hyprsunset) out; letting it go puts the identity back.
package ctm

import (
	"sync"

	"github.com/axiom-shell/axiom/backend/internal/wayland/client"
	"github.com/axiom-shell/axiom/backend/internal/wayland/outputs"
	"github.com/axiom-shell/axiom/backend/internal/wayland/wire"
)

// The interface and its opcodes (hyprland-ctm-control-v1.xml)
const (
	ifaceManager = "hyprland_ctm_control_manager_v1"
	maxVersion   = 2 // blocked

	opSetCtmForOutput = 0 // (output, mat0 … mat8 as fixed)
	opCommit          = 1
	opDestroy         = 2
	evBlocked         = 0 // another client took control (v2)
)

var identity = [9]float64{1, 0, 0, 0, 1, 0, 0, 0, 1}

// Options configure the control.
type Options struct {
	Outputs *outputs.Tracker
	// OnChange is told when the manager is offered or withdrawn, or
	// another client takes control (Blocked)
	OnChange func()
}

// Control sets the transform; it is a client.Client.
type Control struct {
	opts Options

	mu      sync.Mutex
	s       *client.Session
	global  *client.Global
	manager uint32
	blocked bool
	on      bool
	matrix  [9]float64
}

// New returns a control; it binds nothing until a transform is set.
func New(opts Options) *Control {
	c := &Control{opts: opts}
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
	return c.global != nil
}

// Blocked reports whether another client holds the transforms.
func (c *Control) Blocked() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.blocked
}

// Set sets matrix (row major) on every output, or with on false puts the
// identity back and lets the manager go.
func (c *Control) Set(on bool, matrix [9]float64) {
	c.mu.Lock()
	c.on, c.matrix = on, matrix
	c.apply()
	c.mu.Unlock()
}

// apply sends the state; c.mu is held.
func (c *Control) apply() {
	if !c.on {
		if c.manager != 0 {
			c.setAll(identity)
			c.s.Conn.Send(c.manager, opDestroy)
			c.s.Conn.Forget(c.manager)
			c.manager, c.blocked = 0, false
		}
		return
	}
	if c.global == nil {
		return
	}
	if c.manager == 0 {
		c.manager, _, _ = c.s.Bind(*c.global, maxVersion, func(op uint16, _ *wire.Args) {
			if op == evBlocked {
				c.mu.Lock()
				c.blocked = true
				c.mu.Unlock()
				c.changed()
			}
		})
	}
	if !c.blocked {
		c.setAll(c.matrix)
	}
}

func (c *Control) setAll(m [9]float64) {
	for _, o := range c.opts.Outputs.Bound() {
		args := []wire.Arg{wire.Uint(o.ID)}
		for _, v := range m {
			args = append(args, wire.Fixed(v))
		}
		c.s.Conn.Send(c.manager, opSetCtmForOutput, args...)
	}
	c.s.Conn.Send(c.manager, opCommit)
}

// Interfaces (client.Client)
func (c *Control) Interfaces() []string { return []string{ifaceManager} }

// Start (client.Client)
func (c *Control) Start(s *client.Session) {
	c.mu.Lock()
	c.s, c.global, c.manager, c.blocked = s, nil, 0, false
	c.mu.Unlock()
}

// Global notes the manager offered, binding it if a transform waits
// (client.Client).
func (c *Control) Global(g client.Global) {
	c.mu.Lock()
	c.global = &g
	c.apply()
	c.mu.Unlock()
	c.changed()
}

// Removed forgets the manager (client.Client).
func (c *Control) Removed(name uint32) {
	c.mu.Lock()
	if c.global == nil || c.global.Name != name {
		c.mu.Unlock()
		return
	}
	if c.manager != 0 {
		c.s.Conn.Forget(c.manager)
	}
	c.global, c.manager, c.blocked = nil, 0, false
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
