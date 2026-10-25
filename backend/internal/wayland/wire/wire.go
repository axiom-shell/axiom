// Package wire is a minimal Wayland client: the wire protocol (messages
// of 32-bit words on the compositor's unix socket), a long-lived
// connection with its objects and their events (Conn: the daemon's own,
// wayland/outputs on it; idle, gamma, clipboard come later, with file
// descriptor passing), the globals a compositor offers (`axiom debug
// wayland-globals`), and an idle connection that tells when the
// compositor is gone (Watch).
package wire

import (
	"bytes"
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"path/filepath"
	"sort"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// Global is one global the compositor offers.
type Global struct {
	Name      uint32 `json:"name"`
	Interface string `json:"interface"`
	Version   uint32 `json:"version"`
}

// SocketPath is the compositor's socket: $WAYLAND_DISPLAY (absolute, or
// relative to $XDG_RUNTIME_DIR).
func SocketPath(getenv func(string) string) (string, error) {
	display := getenv("WAYLAND_DISPLAY")
	if display == "" {
		return "", axerr.New(axerr.Unavailable, "no $WAYLAND_DISPLAY")
	}
	if filepath.IsAbs(display) {
		return display, nil
	}
	rt := getenv("XDG_RUNTIME_DIR")
	if rt == "" {
		return "", axerr.New(axerr.Unavailable, "no $XDG_RUNTIME_DIR")
	}
	return filepath.Join(rt, display), nil
}

// The core objects and opcodes used here (wayland.xml)
const (
	displayID       = 1
	opSync          = 0 // wl_display.sync(callback)
	opGetRegistry   = 1 // wl_display.get_registry(registry)
	opRegistryBind  = 0 // wl_registry.bind(name, interface, version, id)
	evDisplayError  = 0 // wl_display.error(object, code, message)
	evDeleteID      = 1 // wl_display.delete_id(id)
	evGlobal        = 0 // wl_registry.global(name, interface, version)
	evGlobalRemove  = 1 // wl_registry.global_remove(name)
	evCallbackDone  = 0
	maxMessageBytes = 1 << 16
)

// The registry's events, for a Registry handler
const (
	EvGlobal       = evGlobal       // name, interface, version
	EvGlobalRemove = evGlobalRemove // name
)

// Globals connects to the compositor and lists its globals (sorted by
// interface), then disconnects.
func Globals(socket string, timeout time.Duration) ([]Global, error) {
	conn, err := net.DialTimeout("unix", socket, timeout)
	if err != nil {
		return nil, axerr.Wrap(axerr.Unavailable, err, "connecting to the compositor")
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(timeout))

	const registryID, callbackID = 2, 3
	var out bytes.Buffer
	writeMessage(&out, displayID, opGetRegistry, uint32Arg(registryID))
	writeMessage(&out, displayID, opSync, uint32Arg(callbackID))
	if _, err := conn.Write(out.Bytes()); err != nil {
		return nil, err
	}

	var globals []Global
	for {
		obj, op, body, err := readMessage(conn)
		if err != nil {
			return nil, fmt.Errorf("reading from the compositor: %w", err)
		}
		// Args, not slices of body: a short message reads as zeros
		args := &Args{b: body}
		switch {
		case obj == displayID && op == evDisplayError:
			_, code, msg := args.Uint(), args.Uint(), args.String()
			return nil, axerr.New(axerr.Unavailable, "the compositor reported error %d: %s", code, msg)
		case obj == registryID && op == evGlobal:
			name, iface, version := args.Uint(), args.String(), args.Uint()
			globals = append(globals, Global{Name: name, Interface: iface, Version: version})
		case obj == callbackID && op == evCallbackDone:
			sort.Slice(globals, func(i, j int) bool { return globals[i].Interface < globals[j].Interface })
			return globals, nil
		}
	}
}

// ErrGone is Watch's answer when the compositor closed the connection.
var ErrGone = errors.New("the compositor closed the connection")

// Watch holds a connection to the compositor at socket open until it ends:
// ErrGone when the compositor quit, nil when ctx is done first. It sends
// nothing: a client without objects, which a compositor keeps until it
// exits.
func Watch(ctx context.Context, socket string) error {
	conn, err := net.Dial("unix", socket)
	if err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "connecting to the compositor")
	}
	done := make(chan struct{})
	defer close(done)
	go func() {
		select {
		case <-ctx.Done():
		case <-done:
		}
		conn.Close()
	}()
	_, err = io.Copy(io.Discard, conn)
	if ctx.Err() != nil {
		return nil
	}
	if err != nil {
		return fmt.Errorf("%w: %v", ErrGone, err)
	}
	return ErrGone
}

func uint32Arg(v uint32) []byte {
	b := make([]byte, 4)
	binary.LittleEndian.PutUint32(b, v)
	return b
}

// writeMessage frames a request: the object id, then size<<16 | opcode,
// then the arguments (native byte order: little-endian on every machine
// axiom runs on).
func writeMessage(w io.Writer, obj uint32, opcode uint16, args ...[]byte) {
	size := 8
	for _, a := range args {
		size += len(a)
	}
	var head [8]byte
	binary.LittleEndian.PutUint32(head[:4], obj)
	binary.LittleEndian.PutUint32(head[4:], uint32(size)<<16|uint32(opcode))
	w.Write(head[:])
	for _, a := range args {
		w.Write(a)
	}
}

func readMessage(r io.Reader) (obj uint32, opcode uint16, body []byte, err error) {
	var head [8]byte
	if _, err = io.ReadFull(r, head[:]); err != nil {
		return
	}
	obj = binary.LittleEndian.Uint32(head[:4])
	word := binary.LittleEndian.Uint32(head[4:])
	size, opcode := int(word>>16), uint16(word&0xffff)
	if size < 8 || size > maxMessageBytes || size%4 != 0 {
		err = errors.New("malformed message")
		return
	}
	body = make([]byte, size-8)
	_, err = io.ReadFull(r, body)
	return
}

func readUint(b []byte) uint32 {
	if len(b) < 4 {
		return 0
	}
	return binary.LittleEndian.Uint32(b)
}

// readStringRest reads a wire string (length with its NUL, the bytes,
// padding to 4) and returns what follows it.
func readStringRest(b []byte) (string, []byte) {
	n := int(readUint(b))
	if n == 0 || 4+n > len(b) {
		return "", nil
	}
	s := string(b[4 : 4+n-1])
	padded := (n + 3) &^ 3
	if 4+padded > len(b) {
		return s, nil
	}
	return s, b[4+padded:]
}
