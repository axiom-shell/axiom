package wire

import (
	"bufio"
	"bytes"
	"context"
	"encoding/binary"
	"fmt"
	"math"
	"os"
	"sync"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/unixmsg"
)

// Conn is a long-lived connection to the compositor: the objects made on
// it, and the events for them, dispatched to each object's handler on
// the goroutine running Run. Requests may be sent from any goroutine,
// handlers included. File descriptors go both ways (Fd, Args.Fd).
type Conn struct {
	nc *unixmsg.Conn

	mu       sync.Mutex
	next     uint32
	free     []uint32 // ids the compositor confirmed deleted, to reuse
	handlers map[uint32]Handler
}

// Handler gets the events of one object: the opcode and its arguments.
type Handler func(opcode uint16, args *Args)

// Dial connects to the compositor at socket.
func Dial(socket string) (*Conn, error) {
	nc, err := unixmsg.Dial(socket)
	if err != nil {
		return nil, axerr.Wrap(axerr.Unavailable, err, "connecting to the compositor")
	}
	return &Conn{nc: nc, next: displayID + 1, handlers: map[uint32]Handler{}}, nil
}

// PeerPID is the compositor's process id, by the socket's credentials
// (0 when the kernel can't say).
func (c *Conn) PeerPID() int {
	raw, err := c.nc.UnixConn().SyscallConn()
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

// serverIDs are where the compositor numbers the objects it makes (a
// data_offer event's new object)
const serverIDs = 0xff000000

// Adopt takes an object the compositor made (an event's new_id), its
// events going to h.
func (c *Conn) Adopt(id uint32, h Handler) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if h == nil {
		h = func(uint16, *Args) {}
	}
	c.handlers[id] = h
}

// Forget stops dispatching id's events, once its destructor was sent
// (its id is reused after the compositor's delete_id; one the compositor
// made gets none, and goes at once).
func (c *Conn) Forget(id uint32) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if id >= serverIDs {
		delete(c.handlers, id)
		return
	}
	if _, ok := c.handlers[id]; ok {
		c.handlers[id] = func(uint16, *Args) {}
	}
}

// Send sends a request on obj; its Fd arguments go with it, still the
// caller's to close.
func (c *Conn) Send(obj uint32, opcode uint16, args ...Arg) error {
	var b bytes.Buffer
	raw, fds := Frame(args)
	writeMessage(&b, obj, opcode, raw...)
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.nc.WriteMsg(b.Bytes(), fds)
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
	r := bufio.NewReaderSize(c.nc, maxMessageBytes)
	for {
		obj, op, body, err := readMessage(r)
		if ctx.Err() != nil {
			return nil
		}
		if err != nil {
			return fmt.Errorf("%w: %v", ErrGone, err)
		}
		args := &Args{b: body, takeFD: c.nc.TakeFD}
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

// Arg is one request argument, encoded, or a file descriptor (which
// takes no bytes: it goes beside the message).
type Arg struct {
	b  []byte
	fd *os.File
}

// Frame splits arguments into their bytes and their descriptors (for
// fakes writing messages of their own).
func Frame(args []Arg) ([][]byte, []int) {
	raw := make([][]byte, 0, len(args))
	var fds []int
	for _, a := range args {
		if a.fd != nil {
			fds = append(fds, int(a.fd.Fd()))
			continue
		}
		raw = append(raw, a.b)
	}
	return raw, fds
}

// Uint is a uint, an object or a new_id argument.
func Uint(v uint32) Arg { return Arg{b: uint32Arg(v)} }

// Int is an int argument.
func Int(v int32) Arg { return Arg{b: uint32Arg(uint32(v))} }

// Fixed is a fixed argument: a signed 24.8 number.
func Fixed(v float64) Arg { return Int(int32(math.Round(v * 256))) }

// String is a string argument: its length with the NUL, then the bytes
// padded to 4.
func String(s string) Arg {
	n := len(s) + 1
	b := make([]byte, 4+(n+3)&^3)
	binary.LittleEndian.PutUint32(b, uint32(n))
	copy(b[4:], s)
	return Arg{b: b}
}

// Array is an array argument: its length, then the bytes padded to 4.
func Array(data []byte) Arg {
	b := make([]byte, 4+(len(data)+3)&^3)
	binary.LittleEndian.PutUint32(b, uint32(len(data)))
	copy(b[4:], data)
	return Arg{b: b}
}

// NewID is a new_id argument of an interface the request doesn't name
// (wl_registry.bind's): the interface, its version, then the id.
func NewID(iface string, version, id uint32) Arg {
	return Arg{b: append(append(String(iface).b, uint32Arg(version)...), uint32Arg(id)...)}
}

// Fd is a file descriptor argument. The descriptor is duplicated into
// the message: f stays the caller's.
func Fd(f *os.File) Arg { return Arg{fd: f} }

// Args reads an event's arguments in order; past the end, each reads as
// zero.
type Args struct {
	b      []byte
	takeFD func() (*os.File, error)
}

// Uint reads a uint (or an object id).
func (a *Args) Uint() uint32 {
	v := readUint(a.b)
	a.skip(4)
	return v
}

// Int reads an int.
func (a *Args) Int() int32 { return int32(a.Uint()) }

// Fixed reads a fixed (24.8).
func (a *Args) Fixed() float64 { return float64(a.Int()) / 256 }

// String reads a string.
func (a *Args) String() string {
	s, rest := readStringRest(a.b)
	a.b = rest
	return s
}

// Array reads an array's bytes.
func (a *Args) Array() []byte {
	n := int(readUint(a.b))
	if n < 0 || 4+n > len(a.b) {
		a.b = nil
		return nil
	}
	out := append([]byte(nil), a.b[4:4+n]...)
	a.skip(4 + (n+3)&^3)
	return out
}

// Fd takes the event's next file descriptor: the caller owns it. Every
// fd argument must be taken, in order, or the ones after it go to the
// wrong events.
func (a *Args) Fd() (*os.File, error) {
	if a.takeFD == nil {
		return nil, unixmsg.ErrNoFD
	}
	return a.takeFD()
}

func (a *Args) skip(n int) {
	if len(a.b) < n {
		a.b = nil
		return
	}
	a.b = a.b[n:]
}

// ParseArgs reads arguments from a message's body (for fakes); takeFD
// gives its descriptors (nil: none came).
func ParseArgs(body []byte, takeFD func() (*os.File, error)) *Args {
	return &Args{b: body, takeFD: takeFD}
}
