// Package unixmsg is a unix stream socket that carries file descriptors
// beside its bytes (SCM_RIGHTS), for the protocols that pass them: D-Bus
// (logind's inhibitor) and Wayland (keymaps, gamma ramps, clipboard
// pipes). Received descriptors are close-on-exec from the moment they
// arrive (MSG_CMSG_CLOEXEC), queue in the order they came, and are closed
// with the connection when nobody took them.
package unixmsg

import (
	"errors"
	"io"
	"net"
	"os"
	"sync"
	"time"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// maxFDs is the kernel's limit on descriptors in one message
// (SCM_MAX_FD): a read's control buffer fits that many.
const maxFDs = 253

// ErrNoFD is TakeFD's answer when no descriptor arrived for a message
// that names one.
var ErrNoFD = errors.New("no file descriptor was received")

// Conn is a unix stream connection with descriptor passing. One goroutine
// reads; writes may come from any goroutine.
type Conn struct {
	uc  *net.UnixConn
	oob []byte

	wmu sync.Mutex

	mu     sync.Mutex
	fds    []int
	closed bool
}

// Dial connects to the unix socket at path.
func Dial(path string) (*Conn, error) {
	uc, err := net.DialUnix("unix", nil, &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		return nil, err
	}
	return New(uc), nil
}

// New wraps a connected unix socket.
func New(uc *net.UnixConn) *Conn {
	return &Conn{uc: uc, oob: make([]byte, unix.CmsgSpace(maxFDs*4))}
}

// UnixConn is the socket itself (peer credentials, deadlines).
func (c *Conn) UnixConn() *net.UnixConn { return c.uc }

// SetReadDeadline sets the read deadline (zero: none).
func (c *Conn) SetReadDeadline(t time.Time) error { return c.uc.SetReadDeadline(t) }

// Read reads bytes, queueing the descriptors that came with them; io.EOF
// when the peer closed the connection.
func (c *Conn) Read(p []byte) (int, error) {
	if len(p) == 0 {
		return 0, nil
	}
	raw, err := c.uc.SyscallConn()
	if err != nil {
		return 0, err
	}
	var n, oobn, flags int
	var rerr error
	err = raw.Read(func(fd uintptr) bool {
		n, oobn, flags, _, rerr = unix.Recvmsg(int(fd), p, c.oob, unix.MSG_CMSG_CLOEXEC)
		return rerr != unix.EAGAIN
	})
	if err == nil {
		err = rerr
	}
	if err != nil {
		return 0, err
	}
	if oobn > 0 {
		if err := c.queue(c.oob[:oobn]); err != nil {
			return 0, err
		}
	}
	if flags&unix.MSG_CTRUNC != 0 {
		return 0, axerr.New(axerr.Internal, "file descriptors were cut off: more than %d in one message", maxFDs)
	}
	if n == 0 {
		return 0, io.EOF
	}
	return n, nil
}

func (c *Conn) queue(oob []byte) error {
	msgs, err := unix.ParseSocketControlMessage(oob)
	if err != nil {
		return err
	}
	var fds []int
	for _, m := range msgs {
		got, err := unix.ParseUnixRights(&m)
		if err != nil {
			continue
		}
		fds = append(fds, got...)
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed {
		closeAll(fds)
		return net.ErrClosed
	}
	c.fds = append(c.fds, fds...)
	return nil
}

// TakeFD takes the oldest descriptor received and not yet taken: the
// caller owns the file it returns.
func (c *Conn) TakeFD() (*os.File, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if len(c.fds) == 0 {
		return nil, ErrNoFD
	}
	fd := c.fds[0]
	c.fds = c.fds[1:]
	return os.NewFile(uintptr(fd), "fd"), nil
}

// Pending is how many descriptors wait to be taken.
func (c *Conn) Pending() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return len(c.fds)
}

// Write writes b with no descriptors.
func (c *Conn) Write(b []byte) (int, error) {
	if err := c.WriteMsg(b, nil); err != nil {
		return 0, err
	}
	return len(b), nil
}

// WriteMsg writes b in full, sending fds with its first byte. The fds
// stay the caller's: the kernel duplicates them into the message.
func (c *Conn) WriteMsg(b []byte, fds []int) error {
	c.wmu.Lock()
	defer c.wmu.Unlock()
	if len(fds) > maxFDs {
		return axerr.New(axerr.BadRequest, "%d file descriptors in one message (at most %d)", len(fds), maxFDs)
	}
	var oob []byte
	if len(fds) > 0 {
		oob = unix.UnixRights(fds...)
	}
	n, _, err := c.uc.WriteMsgUnix(b, oob, nil)
	if err != nil {
		return err
	}
	// A stream socket may take part of it: the rest goes without the
	// descriptors, which went with the first part
	for n < len(b) {
		m, err := c.uc.Write(b[n:])
		if err != nil {
			return err
		}
		n += m
	}
	return nil
}

// Close closes the connection and every descriptor nobody took.
func (c *Conn) Close() error {
	c.mu.Lock()
	fds := c.fds
	c.fds, c.closed = nil, true
	c.mu.Unlock()
	closeAll(fds)
	return c.uc.Close()
}

func closeAll(fds []int) {
	for _, fd := range fds {
		unix.Close(fd)
	}
}
