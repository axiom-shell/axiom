// Package wiretest is a scripted fake compositor for tests of Wayland
// clients (wire.Conn and what runs on it): it answers get_registry with
// its globals, sync with done, and hands every other request to the
// test, which answers with events.
package wiretest

import (
	"bytes"
	"encoding/binary"
	"io"
	"net"
	"path/filepath"
	"sync"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/wayland/wire"
)

// Global is one global the fake offers.
type Global struct {
	Name      uint32
	Interface string
	Version   uint32
}

// Request is one request the client sent, past the registry and sync:
// a bind is reported with Global, Interface and Version set (Args then
// hold the new id only).
type Request struct {
	Object    uint32
	Opcode    uint16
	Global    uint32 // for a bind: the global's name, its interface and the version asked
	Interface string
	Version   uint32
	Args      *wire.Args
}

// Compositor is the fake. OnRequest runs on its read goroutine.
type Compositor struct {
	Socket    string
	OnRequest func(c *Compositor, r Request)

	mu       sync.Mutex
	conn     net.Conn
	globals  []Global
	registry uint32
	ready    chan struct{}
}

// New listens on a socket in a temp dir and serves one client.
func New(t *testing.T, globals []Global, onRequest func(c *Compositor, r Request)) *Compositor {
	t.Helper()
	c := &Compositor{Socket: filepath.Join(t.TempDir(), "wayland-0"), OnRequest: onRequest, globals: globals, ready: make(chan struct{})}
	ln, err := net.Listen("unix", c.Socket)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close(); c.Close() })
	go func() {
		nc, err := ln.Accept()
		if err != nil {
			return
		}
		c.mu.Lock()
		c.conn = nc
		c.mu.Unlock()
		close(c.ready)
		c.serve(nc)
	}()
	return c
}

// Close closes the client's connection: the compositor is gone.
func (c *Compositor) Close() {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.conn != nil {
		c.conn.Close()
	}
}

// Send sends an event.
func (c *Compositor) Send(obj uint32, opcode uint16, args ...wire.Arg) {
	<-c.ready
	var b bytes.Buffer
	size := 8
	for _, a := range args {
		size += len(a)
	}
	var head [8]byte
	binary.LittleEndian.PutUint32(head[:4], obj)
	binary.LittleEndian.PutUint32(head[4:], uint32(size)<<16|uint32(opcode))
	b.Write(head[:])
	for _, a := range args {
		b.Write(a)
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.conn.Write(b.Bytes())
}

// AddGlobal announces a global (a hotplugged output).
func (c *Compositor) AddGlobal(g Global) {
	c.mu.Lock()
	c.globals = append(c.globals, g)
	registry := c.registry
	c.mu.Unlock()
	if registry != 0 {
		c.Send(registry, wire.EvGlobal, wire.Uint(g.Name), wire.String(g.Interface), wire.Uint(g.Version))
	}
}

// RemoveGlobal withdraws a global.
func (c *Compositor) RemoveGlobal(name uint32) {
	c.mu.Lock()
	registry := c.registry
	c.mu.Unlock()
	c.Send(registry, wire.EvGlobalRemove, wire.Uint(name))
}

func (c *Compositor) serve(r io.Reader) {
	for {
		var head [8]byte
		if _, err := io.ReadFull(r, head[:]); err != nil {
			return
		}
		obj := binary.LittleEndian.Uint32(head[:4])
		word := binary.LittleEndian.Uint32(head[4:])
		body := make([]byte, int(word>>16)-8)
		if _, err := io.ReadFull(r, body); err != nil {
			return
		}
		op := uint16(word & 0xffff)
		args := wire.ParseArgs(body)
		c.mu.Lock()
		registry := c.registry
		c.mu.Unlock()
		switch {
		case obj == 1 && op == 0: // sync
			c.Send(args.Uint(), 0, wire.Uint(0))
			c.Send(1, 1, wire.Uint(binary.LittleEndian.Uint32(body))) // delete_id
		case obj == 1 && op == 1: // get_registry
			id := args.Uint()
			c.mu.Lock()
			c.registry = id
			globals := append([]Global{}, c.globals...)
			c.mu.Unlock()
			for _, g := range globals {
				c.Send(id, wire.EvGlobal, wire.Uint(g.Name), wire.String(g.Interface), wire.Uint(g.Version))
			}
		case obj == registry && op == 0: // bind
			name, iface, version := args.Uint(), args.String(), args.Uint()
			c.request(Request{Object: obj, Global: name, Interface: iface, Version: version, Args: args})
		default:
			c.request(Request{Object: obj, Opcode: op, Args: args})
		}
	}
}

func (c *Compositor) request(r Request) {
	if c.OnRequest != nil {
		c.OnRequest(c, r)
	}
}
