// Package seat binds the compositor's seat (wl_seat), which idle
// notifications, data control and the virtual keyboard are made for. It
// takes the first seat offered: the compositors axiom runs on have one.
package seat

import (
	"sync"

	"github.com/axiom-shell/axiom/backend/internal/wayland/client"
)

const ifaceSeat = "wl_seat"

// Tracker holds the seat bound; it is a client.Client.
type Tracker struct {
	mu   sync.Mutex
	s    *client.Session
	id   uint32 // the bound wl_seat, 0 without
	name uint32 // its global
	subs []func(seat uint32)
}

// New returns a tracker without a seat.
func New() *Tracker { return &Tracker{} }

// ID is the bound seat's object id, 0 without one.
func (t *Tracker) ID() uint32 {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.id
}

// OnChange calls fn with the seat's object id whenever it changes (0:
// gone), on the connection's goroutine.
func (t *Tracker) OnChange(fn func(seat uint32)) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.subs = append(t.subs, fn)
}

func (t *Tracker) set(id, name uint32) {
	t.mu.Lock()
	t.id, t.name = id, name
	subs := append([]func(uint32){}, t.subs...)
	t.mu.Unlock()
	for _, fn := range subs {
		fn(id)
	}
}

// Interfaces (client.Client)
func (t *Tracker) Interfaces() []string { return []string{ifaceSeat} }

// Start (client.Client)
func (t *Tracker) Start(s *client.Session) {
	t.mu.Lock()
	t.s = s
	t.mu.Unlock()
	t.set(0, 0)
}

// Global binds the first seat (client.Client). Version 1: nothing here
// reads its events.
func (t *Tracker) Global(g client.Global) {
	if t.ID() != 0 {
		return
	}
	id, _, err := t.s.Bind(g, 1, nil)
	if err == nil {
		t.set(id, g.Name)
	}
}

// Removed lets the seat go (client.Client).
func (t *Tracker) Removed(name uint32) {
	t.mu.Lock()
	id, ours := t.id, t.name == name
	t.mu.Unlock()
	if !ours {
		return
	}
	t.s.Conn.Forget(id)
	t.set(0, 0)
}

// Ready (client.Client)
func (t *Tracker) Ready() {}
