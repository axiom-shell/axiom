package wire

import (
	"bytes"
	"context"
	"encoding/binary"
	"fmt"
	"net"
	"sync"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// Conn is a long-lived connection to the compositor: the objects made on
// it, and the events for them, dispatched to each object's handler on
// the goroutine running Run. Requests may be sent from any goroutine,
// handlers included.
type Conn struct {
	nc net.Conn

	mu       sync.Mutex
	next     uint32
	free     []uint32 // ids the compositor confirmed deleted, to reuse
	handlers map[uint32]Handler
}

// Handler gets the events of one object: the opcode and its arguments.
type Handler func(opcode uint16, args *Args)

// Dial connects to the compositor at socket.
func Dial(socket string) (*Conn, error) {
	nc, err := net.Dial("unix", socket)
	if err != nil {
		return nil, axerr.Wrap(axerr.Unavailable, err, "connecting to the compositor")
	}
	return &Conn{nc: nc, next: displayID + 1, handlers: map[uint32]Handler{}}, nil
}

// PeerPID is the compositor's process id, by the socket's credentials
// (0 when the kernel can't say).
func (c *Conn) PeerPID() int {
	uc, ok := c.nc.(*net.UnixConn)
	if !ok {
		return 0
	}
	raw, err := uc.SyscallConn()
	if err != nil {
		return 0
	}
	pid := 0
	raw.Control(func(fd uintptr) {
		if cred, err := unix.GetsockoptUcred(int(fd), unix.SOL_SOCKET, unix.SO_PEERCRED); err == nil {
			pid = int(cred.Pid)
		}
	})
	return pid
}

// Close ends the connection; Run returns.
func (c *Conn) Close() error { return c.nc.Close() }

// NewObject takes an id for an object the next request creates, its
// events going to h (nil: dropped).
func (c *Conn) NewObject(h Handler) uint32 {
	c.mu.Lock()
	defer c.mu.Unlock()
	var id uint32
	if n := len(c.free); n > 0 {
		id, c.free = c.free[n-1], c.free[:n-1]
	} else {
		id = c.next
		c.next++
	}
	if h == nil {
		h = func(uint16, *Args) {}
	}
	c.handlers[id] = h
	return id
}

// Forget stops dispatching id's events, once its destructor was sent
// (its id is reused after the compositor's delete_id).
func (c *Conn) Forget(id uint32) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if _, ok := c.handlers[id]; ok {
		c.handlers[id] = func(uint16, *Args) {}
	}
}

// Send sends a request on obj.
func (c *Conn) Send(obj uint32, opcode uint16, args ...Arg) error {
	var b bytes.Buffer
	raw := make([][]byte, len(args))
	for i, a := range args {
		raw[i] = a
	}
	writeMessage(&b, obj, opcode, raw...)
	c.mu.Lock()
	defer c.mu.Unlock()
	_, err := c.nc.Write(b.Bytes())
	return err
}

// Registry asks for the registry, whose events (global, global_remove)
// go to h.
func (c *Conn) Registry(h Handler) (uint32, error) {
	id := c.NewObject(h)
	return id, c.Send(displayID, opGetRegistry, Uint(id))
}

// Bind binds the global name (announced as iface) at version, its
// events going to h.
func (c *Conn) Bind(registry, name uint32, iface string, version uint32, h Handler) (uint32, error) {
	id := c.NewObject(h)
	return id, c.Send(registry, opRegistryBind, Uint(name), String(iface), Uint(version), Uint(id))
}

// Sync calls done once the compositor has handled every request sent
// before it (and sent their events).
func (c *Conn) Sync(done func()) error {
	var id uint32
	id = c.NewObject(func(op uint16, _ *Args) {
		if op == evCallbackDone {
			// A callback is destroyed by its done
			c.Forget(id)
			done()
		}
	})
	return c.Send(displayID, opSync, Uint(id))
}

// Run reads and dispatches events until the connection ends: ErrGone
// when the compositor closed it, nil when ctx ended (it closes the
// connection), an error for a protocol error the compositor reported.
func (c *Conn) Run(ctx context.Context) error {
	done := make(chan struct{})
	defer close(done)
	go func() {
		select {
		case <-ctx.Done():
			c.nc.Close()
		case <-done:
		}
	}()
	for {
		obj, op, body, err := readMessage(c.nc)
		if ctx.Err() != nil {
			return nil
		}
		if err != nil {
			return fmt.Errorf("%w: %v", ErrGone, err)
		}
		args := &Args{b: body}
		if obj == displayID {
			switch op {
			case evDisplayError:
				object, code, msg := args.Uint(), args.Uint(), args.String()
				c.nc.Close()
				return axerr.New(axerr.Internal, "the compositor reported error %d on object %d: %s", code, object, msg)
			case evDeleteID:
				id := args.Uint()
				c.mu.Lock()
				if _, ok := c.handlers[id]; ok {
					delete(c.handlers, id)
					c.free = append(c.free, id)
				}
				c.mu.Unlock()
			}
			continue
		}
		c.mu.Lock()
		h := c.handlers[obj]
		c.mu.Unlock()
		if h != nil {
			h(op, args)
		}
	}
}

// Arg is one request argument, encoded.
type Arg []byte

// Uint is a uint, an object or a new_id argument.
func Uint(v uint32) Arg { return uint32Arg(v) }

// Int is an int argument.
func Int(v int32) Arg { return uint32Arg(uint32(v)) }

// String is a string argument: its length with the NUL, then the bytes
// padded to 4.
func String(s string) Arg {
	n := len(s) + 1
	b := make([]byte, 4+(n+3)&^3)
	binary.LittleEndian.PutUint32(b, uint32(n))
	copy(b[4:], s)
	return b
}

// Args reads an event's arguments in order; past the end, each reads as
// zero.
type Args struct{ b []byte }

// Uint reads a uint (or an object id).
func (a *Args) Uint() uint32 {
	v := readUint(a.b)
	a.skip(4)
	return v
}

// Int reads an int.
func (a *Args) Int() int32 { return int32(a.Uint()) }

// String reads a string.
func (a *Args) String() string {
	s, rest := readStringRest(a.b)
	a.b = rest
	return s
}

func (a *Args) skip(n int) {
	if len(a.b) < n {
		a.b = nil
		return
	}
	a.b = a.b[n:]
}

// ParseArgs reads arguments from a message's body (for fakes).
func ParseArgs(body []byte) *Args { return &Args{b: body} }
