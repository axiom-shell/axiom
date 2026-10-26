// Package client shares the daemon's one Wayland connection between the
// protocol clients that run on it (outputs, the seat, idle, …): it asks
// for the registry once, hands each client the globals of the interfaces
// it named, and their removal, and tells every client when the first
// globals are bound and have described themselves (two roundtrips).
// Clients' handlers run on the connection's goroutine and never block:
// slow work (a pipe to read, an action to run) goes elsewhere.
package client

import (
	"context"

	"github.com/axiom-shell/axiom/backend/internal/wayland/wire"
)

// Global is one global the compositor offers.
type Global = wire.Global

// Client is one protocol client on the connection. Its methods run on
// the connection's goroutine, in this order: Start, the globals present
// (Global), Ready, then hotplug (Global, Removed) until the connection
// ends.
type Client interface {
	// Interfaces are the globals it wants
	Interfaces() []string
	// Start is a new connection: state from an earlier one is gone
	Start(s *Session)
	Global(g Global)
	Removed(name uint32)
	// Ready: the globals present at the start are bound and their first
	// events are in
	Ready()
}

// Session is the connection as the clients see it.
type Session struct {
	Conn     *wire.Conn
	registry uint32
}

// Bind binds g at the lower of version and the version offered, its
// events going to h; it returns the object and the version bound.
func (s *Session) Bind(g Global, version uint32, h wire.Handler) (uint32, uint32, error) {
	v := min(version, g.Version)
	id, err := s.Conn.Bind(s.registry, g.Name, g.Interface, v, h)
	return id, v, err
}

// Run connects to the compositor at socket and runs the clients on it
// until ctx ends (nil) or the connection does (wire.ErrGone when the
// compositor closed it).
func Run(ctx context.Context, socket string, clients ...Client) error {
	c, err := wire.Dial(socket)
	if err != nil {
		return err
	}
	defer c.Close()
	s := &Session{Conn: c}
	byIface := map[string][]Client{}
	for _, cl := range clients {
		cl.Start(s)
		for _, iface := range cl.Interfaces() {
			byIface[iface] = append(byIface[iface], cl)
		}
	}
	// A global's interface by name, for its removal
	owners := map[uint32][]Client{}
	s.registry, err = c.Registry(func(op uint16, a *wire.Args) {
		switch op {
		case wire.EvGlobal:
			g := Global{Name: a.Uint(), Interface: a.String(), Version: a.Uint()}
			for _, cl := range byIface[g.Interface] {
				owners[g.Name] = append(owners[g.Name], cl)
				cl.Global(g)
			}
		case wire.EvGlobalRemove:
			name := a.Uint()
			for _, cl := range owners[name] {
				cl.Removed(name)
			}
			delete(owners, name)
		}
	})
	if err != nil {
		return err
	}
	// The first sync answers once the globals are listed (and bound); the
	// second once the bound objects have described themselves
	err = c.Sync(func() {
		c.Sync(func() {
			for _, cl := range clients {
				cl.Ready()
			}
		})
	})
	if err != nil {
		return err
	}
	return c.Run(ctx)
}
