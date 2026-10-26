// Package dbustest is a small in-process message bus for tests of D-Bus
// clients: it authenticates (EXTERNAL, descriptors agreed), names each
// connection, owns well-known names (RequestName, ReleaseName,
// GetNameOwner, NameOwnerChanged), routes calls and replies by
// destination, and hands every signal to every other connection (each
// client filters by its own match rules). Services a test needs (a fake
// logind) are a second dbus.Conn on it that exports them.
package dbustest

import (
	"bufio"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/unixmsg"
)

// Bus is the fake bus.
type Bus struct {
	// Address is what dbus.Dial connects to.
	Address string

	mu     sync.Mutex
	next   int
	conns  map[string]*conn // by unique name
	owners map[string]string
	serial uint32
}

type conn struct {
	name string
	uc   *unixmsg.Conn
}

// New starts a bus on a socket in a temp dir; it stops with the test.
func New(t *testing.T) *Bus {
	t.Helper()
	path := filepath.Join(t.TempDir(), "bus")
	ln, err := net.ListenUnix("unix", &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	b := &Bus{Address: "unix:path=" + path, conns: map[string]*conn{}, owners: map[string]string{}}
	var wg sync.WaitGroup
	t.Cleanup(func() {
		ln.Close()
		b.mu.Lock()
		for _, c := range b.conns {
			c.uc.Close()
		}
		b.mu.Unlock()
		wg.Wait()
	})
	wg.Add(1)
	go func() {
		defer wg.Done()
		for {
			uc, err := ln.AcceptUnix()
			if err != nil {
				return
			}
			wg.Add(1)
			go func() {
				defer wg.Done()
				b.serve(unixmsg.New(uc))
			}()
		}
	}()
	return b
}

// Owner is the unique name owning a well-known name, "" for none.
func (b *Bus) Owner(name string) string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.owners[name]
}

func (b *Bus) serve(uc *unixmsg.Conn) {
	defer uc.Close()
	br := bufio.NewReader(uc)
	if err := authenticate(br, uc); err != nil {
		return
	}
	b.mu.Lock()
	b.next++
	c := &conn{name: fmt.Sprintf(":1.%d", b.next), uc: uc}
	b.conns[c.name] = c
	b.mu.Unlock()
	defer b.drop(c)
	for {
		m, err := dbus.ReadMessage(br, uc.TakeFD)
		if err != nil {
			return
		}
		m.Sender = c.name
		if m.Destination == dbus.BusName {
			b.busCall(c, m)
		} else {
			b.route(m)
		}
		m.Close()
	}
}

// authenticate is the bus side of EXTERNAL, then descriptors, then BEGIN.
func authenticate(br *bufio.Reader, w io.Writer) error {
	nul, err := br.ReadByte()
	if err != nil || nul != 0 {
		return fmt.Errorf("no NUL byte")
	}
	for {
		line, err := br.ReadString('\n')
		if err != nil {
			return err
		}
		line = strings.TrimRight(line, "\r\n")
		switch {
		case strings.HasPrefix(line, "AUTH EXTERNAL"):
			io.WriteString(w, "OK 0123456789abcdef0123456789abcdef\r\n")
		case line == "NEGOTIATE_UNIX_FD":
			io.WriteString(w, "AGREE_UNIX_FD\r\n")
		case line == "BEGIN":
			return nil
		default:
			io.WriteString(w, "ERROR\r\n")
		}
	}
}

func (b *Bus) drop(c *conn) {
	b.mu.Lock()
	delete(b.conns, c.name)
	var lost []string
	for name, owner := range b.owners {
		if owner == c.name {
			delete(b.owners, name)
			lost = append(lost, name)
		}
	}
	b.mu.Unlock()
	for _, name := range lost {
		b.ownerChanged(name, c.name, "")
	}
	b.ownerChanged(c.name, c.name, "")
}

// send writes m to c, its UnixFD values turned from indexes into the
// descriptors they index.
func (b *Bus) send(c *conn, m *dbus.Message) {
	body := make([]any, len(m.Body))
	for i, v := range m.Body {
		body[i] = fdsOf(v, m.Files)
	}
	out := *m
	out.Body = body
	b.mu.Lock()
	b.serial++
	serial := b.serial
	b.mu.Unlock()
	if out.Type == dbus.TypeMethodCall || out.Type == dbus.TypeSignal {
		// Forwarded calls keep their serial: replies name it
		serial = m.Serial
	}
	data, fds, err := out.Marshal(serial)
	if err != nil {
		return
	}
	c.uc.WriteMsg(data, fds)
}

func fdsOf(v any, files []*os.File) any {
	switch x := v.(type) {
	case dbus.UnixFD:
		if int(x) < len(files) && files[x] != nil {
			return dbus.UnixFD(files[x].Fd())
		}
	case dbus.Variant:
		return dbus.Variant{Sig: x.Sig, Value: fdsOf(x.Value, files)}
	case []any:
		out := make([]any, len(x))
		for i, e := range x {
			out[i] = fdsOf(e, files)
		}
		return out
	}
	return v
}

func (b *Bus) route(m *dbus.Message) {
	b.mu.Lock()
	dest := m.Destination
	if owner, ok := b.owners[dest]; ok {
		dest = owner
	}
	target := b.conns[dest]
	var all []*conn
	if m.Type == dbus.TypeSignal && m.Destination == "" {
		for _, c := range b.conns {
			if c.name != m.Sender {
				all = append(all, c)
			}
		}
	}
	b.mu.Unlock()
	if m.Type == dbus.TypeSignal && m.Destination == "" {
		for _, c := range all {
			b.send(c, m)
		}
		return
	}
	if target == nil {
		if m.Type == dbus.TypeMethodCall {
			b.replyError(m, dbus.ErrServiceUnknown, "no owner for "+m.Destination)
		}
		return
	}
	b.send(target, m)
}

func (b *Bus) reply(call *dbus.Message, sig string, body ...any) {
	b.mu.Lock()
	c := b.conns[call.Sender]
	b.mu.Unlock()
	if c != nil {
		b.send(c, &dbus.Message{Type: dbus.TypeMethodReturn, Sender: dbus.BusName, ReplySerial: call.Serial, Destination: call.Sender, Signature: dbus.Signature(sig), Body: body})
	}
}

func (b *Bus) replyError(call *dbus.Message, name, text string) {
	b.mu.Lock()
	c := b.conns[call.Sender]
	b.mu.Unlock()
	if c != nil {
		b.send(c, &dbus.Message{Type: dbus.TypeError, Sender: dbus.BusName, ReplySerial: call.Serial, Destination: call.Sender, ErrorName: name, Signature: "s", Body: []any{text}})
	}
}

func (b *Bus) ownerChanged(name, old, new string) {
	b.route(&dbus.Message{
		Type: dbus.TypeSignal, Sender: dbus.BusName, Path: dbus.BusPath, Interface: dbus.BusInterface, Member: "NameOwnerChanged",
		Signature: "sss", Body: []any{name, old, new},
	})
}

func (b *Bus) busCall(c *conn, m *dbus.Message) {
	arg := func() string {
		if len(m.Body) > 0 {
			s, _ := m.Body[0].(string)
			return s
		}
		return ""
	}
	switch m.Member {
	case "Hello":
		b.reply(m, "s", c.name)
		b.ownerChanged(c.name, "", c.name)
	case "AddMatch", "RemoveMatch":
		b.reply(m, "")
	case "RequestName":
		name := arg()
		var flags uint32
		if len(m.Body) > 1 {
			flags, _ = m.Body[1].(uint32)
		}
		b.mu.Lock()
		owner, taken := b.owners[name]
		switch {
		case taken && owner == c.name:
			b.mu.Unlock()
			b.reply(m, "u", dbus.NameAlreadyOwner)
		case taken:
			b.mu.Unlock()
			if flags&dbus.NameDoNotQueue != 0 {
				b.reply(m, "u", dbus.NameExists)
			} else {
				b.reply(m, "u", dbus.NameInQueue)
			}
		default:
			b.owners[name] = c.name
			b.mu.Unlock()
			b.reply(m, "u", dbus.NamePrimaryOwner)
			b.ownerChanged(name, "", c.name)
		}
	case "ReleaseName":
		name := arg()
		b.mu.Lock()
		owned := b.owners[name] == c.name
		if owned {
			delete(b.owners, name)
		}
		b.mu.Unlock()
		if owned {
			b.reply(m, "u", uint32(1))
			b.ownerChanged(name, c.name, "")
		} else {
			b.reply(m, "u", uint32(3))
		}
	case "GetNameOwner":
		name := arg()
		b.mu.Lock()
		owner, ok := b.owners[name]
		_, isConn := b.conns[name]
		b.mu.Unlock()
		switch {
		case ok:
			b.reply(m, "s", owner)
		case isConn:
			b.reply(m, "s", name)
		default:
			b.replyError(m, dbus.ErrNameHasNoOwner, "no owner for "+name)
		}
	case "GetConnectionUnixProcessID":
		b.reply(m, "u", uint32(os.Getpid()))
	default:
		b.replyError(m, dbus.ErrUnknownMethod, m.Member)
	}
}
