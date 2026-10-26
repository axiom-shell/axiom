// Package dbus is a small D-Bus client, pure Go: one connection to a bus
// (the session's or the system's), method calls with their replies,
// signals by match rule, objects exported for others to call, bus names
// and properties, with descriptor passing (logind's inhibitor is one).
// What it doesn't do: anything but unix sockets and EXTERNAL auth (a
// local bus needs nothing else), and exported properties (the first
// service exporting them adds them). Docs: docs/dev/backend/dbus.md.
package dbus

import (
	"bufio"
	"context"
	"errors"
	"log/slog"
	"os"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/unixmsg"
)

// The bus itself
const (
	BusName      = "org.freedesktop.DBus"
	BusPath      = ObjectPath("/org/freedesktop/DBus")
	BusInterface = "org.freedesktop.DBus"
)

// How many incoming method calls and signals wait for their handler or
// subscriber before more are refused or dropped: a peer flooding the
// connection can't grow it without bound
const (
	callQueue   = 64
	signalQueue = 64
)

// Options configure a connection.
type Options struct {
	Log *slog.Logger
	// UID is the uid EXTERNAL auth claims (default: this process's)
	UID int
}

// Conn is a connection to a bus. Calls may come from any goroutine; its
// own goroutines (reading, running exported methods) end with it.
type Conn struct {
	uc     *unixmsg.Conn
	log    *slog.Logger
	unique string
	fds    bool // the bus agreed to descriptor passing

	ctx    context.Context // ends with the connection: handlers get it
	cancel context.CancelFunc

	mu      sync.Mutex
	serial  uint32
	pending map[uint32]chan *Message
	subs    map[*Subscription]struct{}
	objects map[ObjectPath]map[string]*Interface

	calls     chan *Message
	done      chan struct{}
	err       error
	closeOnce sync.Once
	wg        sync.WaitGroup
}

// Dial connects to the bus at address (SessionAddress, SystemAddress),
// authenticates and says Hello.
func Dial(ctx context.Context, address string, opts Options) (*Conn, error) {
	if opts.Log == nil {
		opts.Log = slog.New(slog.DiscardHandler)
	}
	if opts.UID == 0 {
		opts.UID = os.Getuid()
	}
	paths, err := socketPaths(address)
	if err != nil {
		return nil, axerr.Wrap(axerr.Unavailable, err, "the bus address")
	}
	var uc *unixmsg.Conn
	for _, p := range paths {
		if uc, err = unixmsg.Dial(p); err == nil {
			break
		}
	}
	if err != nil {
		return nil, axerr.Wrap(axerr.Unavailable, err, "connecting to the bus")
	}
	deadline, ok := ctx.Deadline()
	if !ok {
		deadline = time.Now().Add(10 * time.Second)
	}
	uc.UnixConn().SetDeadline(deadline)
	fds, err := authenticate(uc, uc, opts.UID)
	if err != nil {
		uc.Close()
		return nil, axerr.Wrap(axerr.Unavailable, err, "authenticating to the bus")
	}
	uc.UnixConn().SetDeadline(time.Time{})

	c := &Conn{
		uc:      uc,
		log:     opts.Log,
		fds:     fds,
		pending: map[uint32]chan *Message{},
		subs:    map[*Subscription]struct{}{},
		objects: map[ObjectPath]map[string]*Interface{},
		calls:   make(chan *Message, callQueue),
		done:    make(chan struct{}),
	}
	c.ctx, c.cancel = context.WithCancel(context.Background())
	c.wg.Add(2)
	go c.read()
	go c.dispatch()
	reply, err := c.Call(ctx, BusName, BusPath, BusInterface, "Hello", "")
	if err == nil {
		err = reply.Store(&c.unique)
	}
	if err != nil {
		c.Close()
		return nil, axerr.Wrap(axerr.Unavailable, err, "saying hello to the bus")
	}
	return c, nil
}

// UniqueName is the connection's name on the bus (":1.42").
func (c *Conn) UniqueName() string { return c.unique }

// Done is closed when the connection ended (Close, or the bus closing
// it); Err then says why.
func (c *Conn) Done() <-chan struct{} { return c.done }

// Err is why the connection ended, nil while it runs and after Close.
func (c *Conn) Err() error {
	select {
	case <-c.done:
		return c.err
	default:
		return nil
	}
}

// Close ends the connection and waits for its goroutines. Not from a
// method handler: Close waits for the handler to return.
func (c *Conn) Close() error {
	c.closeOnce.Do(func() {
		c.cancel()
		c.uc.Close()
	})
	c.wg.Wait()
	return nil
}

// read reads messages until the connection ends.
func (c *Conn) read() {
	defer c.wg.Done()
	br := bufio.NewReaderSize(c.uc, 64<<10)
	var err error
	for {
		var m *Message
		if m, err = ReadMessage(br, c.uc.TakeFD); err != nil {
			break
		}
		c.route(m)
	}
	if c.ctx.Err() != nil {
		err = nil // closed on purpose
	} else {
		c.log.Warn("the bus connection ended", "err", err)
	}
	c.mu.Lock()
	c.err = err
	c.pending = map[uint32]chan *Message{}
	subs := c.subs
	c.subs = map[*Subscription]struct{}{}
	c.mu.Unlock()
	close(c.done)
	c.cancel()
	for s := range subs {
		s.end()
	}
}

func (c *Conn) route(m *Message) {
	switch m.Type {
	case TypeMethodReturn, TypeError:
		c.mu.Lock()
		ch := c.pending[m.ReplySerial]
		delete(c.pending, m.ReplySerial)
		c.mu.Unlock()
		if ch == nil {
			m.Close()
			return
		}
		ch <- m
	case TypeSignal:
		// Sent under the lock (never blocking), so a subscription closed
		// meanwhile gets nothing on its closed channel
		c.mu.Lock()
		var to []*Subscription
		for s := range c.subs {
			if s.match.matches(m) {
				to = append(to, s)
			}
		}
		if len(to) != 1 {
			// Descriptors go to one owner only
			m.Close()
		}
		for _, s := range to {
			select {
			case s.ch <- m:
			default:
				c.log.Warn("dropped a D-Bus signal: its subscriber is behind", "member", m.Member, "interface", m.Interface)
			}
		}
		c.mu.Unlock()
	case TypeMethodCall:
		select {
		case c.calls <- m:
		default:
			m.Close()
			c.replyError(m, NewError(ErrLimitsExceeded, "too many calls waiting"))
		}
	default:
		m.Close()
	}
}

// send writes m with the next serial; registers a reply channel first
// when reply isn't nil.
func (c *Conn) send(m *Message, reply chan *Message) (uint32, error) {
	c.mu.Lock()
	c.serial++
	if c.serial == 0 {
		c.serial = 1
	}
	serial := c.serial
	b, fds, err := m.Marshal(serial)
	if err == nil && len(fds) > 0 && !c.fds {
		err = errors.New("dbus: the bus doesn't pass file descriptors")
	}
	if err == nil && reply != nil {
		c.pending[serial] = reply
	}
	c.mu.Unlock()
	if err != nil {
		return 0, axerr.Wrap(axerr.BadRequest, err, "encoding a message")
	}
	select {
	case <-c.done:
		return 0, axerr.New(axerr.Unavailable, "the bus connection ended")
	default:
	}
	if err := c.uc.WriteMsg(b, fds); err != nil {
		c.forget(serial)
		return 0, axerr.Wrap(axerr.Unavailable, err, "writing to the bus")
	}
	return serial, nil
}

func (c *Conn) forget(serial uint32) {
	c.mu.Lock()
	delete(c.pending, serial)
	c.mu.Unlock()
}

// Call calls a method and waits for its reply; an error reply is an
// error wrapping *Error. A reply carrying descriptors is the caller's to
// Close.
func (c *Conn) Call(ctx context.Context, dest string, path ObjectPath, iface, member, sig string, args ...any) (*Message, error) {
	ch := make(chan *Message, 1)
	serial, err := c.send(&Message{
		Type: TypeMethodCall, Destination: dest, Path: path, Interface: iface, Member: member,
		Signature: Signature(sig), Body: args,
	}, ch)
	if err != nil {
		return nil, err
	}
	select {
	case m := <-ch:
		if m.Type == TypeError {
			e := &Error{Name: m.ErrorName}
			if len(m.Body) > 0 {
				e.Message, _ = m.Body[0].(string)
			}
			m.Close()
			return nil, axerr.Wrap(kindOf(e.Name), e, "%s.%s", iface, member)
		}
		return m, nil
	case <-ctx.Done():
		c.forget(serial)
		return nil, axerr.Wrap(axerr.Unavailable, ctx.Err(), "%s.%s", iface, member)
	case <-c.done:
		return nil, axerr.New(axerr.Unavailable, "the bus connection ended during %s.%s", iface, member)
	}
}

// Emit sends a signal.
func (c *Conn) Emit(path ObjectPath, iface, member, sig string, args ...any) error {
	_, err := c.send(&Message{Type: TypeSignal, Path: path, Interface: iface, Member: member, Signature: Signature(sig), Body: args}, nil)
	return err
}

func (c *Conn) reply(call *Message, sig string, body []any) {
	if call.Flags&FlagNoReplyExpected != 0 {
		return
	}
	_, err := c.send(&Message{Type: TypeMethodReturn, Destination: call.Sender, ReplySerial: call.Serial, Signature: Signature(sig), Body: body}, nil)
	if err != nil {
		c.log.Warn("replying on the bus", "member", call.Member, "err", err)
		c.replyError(call, NewError(ErrFailed, "%v", err))
	}
}

func (c *Conn) replyError(call *Message, e *Error) {
	if call.Flags&FlagNoReplyExpected != 0 {
		return
	}
	c.send(&Message{Type: TypeError, Destination: call.Sender, ReplySerial: call.Serial, ErrorName: e.Name, Signature: "s", Body: []any{e.Message}}, nil)
}

// Match selects signals: every field set must equal the signal's. A
// well-known Sender is matched by the bus only (signals carry the
// sender's unique name).
type Match struct {
	Sender    string
	Path      ObjectPath
	Interface string
	Member    string
	// Arg0 matches the first argument, a string (NameOwnerChanged's name)
	Arg0 string
}

func (m Match) rule() string {
	rule := "type='signal'"
	add := func(k, v string) {
		if v != "" {
			rule += "," + k + "='" + v + "'"
		}
	}
	add("sender", m.Sender)
	add("path", string(m.Path))
	add("interface", m.Interface)
	add("member", m.Member)
	add("arg0", m.Arg0)
	return rule
}

func (m Match) matches(msg *Message) bool {
	if m.Sender != "" && m.Sender[0] == ':' && msg.Sender != m.Sender {
		return false
	}
	if m.Path != "" && msg.Path != m.Path || m.Interface != "" && msg.Interface != m.Interface || m.Member != "" && msg.Member != m.Member {
		return false
	}
	if m.Arg0 != "" {
		if len(msg.Body) == 0 {
			return false
		}
		if s, _ := msg.Body[0].(string); s != m.Arg0 {
			return false
		}
	}
	return true
}

// Subscription is a stream of the signals a Match selects.
type Subscription struct {
	// C gets the signals; it is closed when the connection ends.
	C <-chan *Message

	c       *Conn
	ch      chan *Message
	match   Match
	endOnce sync.Once
}

// Subscribe asks the bus for the signals m selects (AddMatch). A
// subscriber that falls more than 64 signals behind loses the newest.
func (c *Conn) Subscribe(ctx context.Context, m Match) (*Subscription, error) {
	ch := make(chan *Message, signalQueue)
	s := &Subscription{C: ch, c: c, ch: ch, match: m}
	c.mu.Lock()
	c.subs[s] = struct{}{}
	c.mu.Unlock()
	if _, err := c.Call(ctx, BusName, BusPath, BusInterface, "AddMatch", "s", m.rule()); err != nil {
		c.mu.Lock()
		delete(c.subs, s)
		c.mu.Unlock()
		return nil, err
	}
	return s, nil
}

// Close stops the subscription (RemoveMatch).
func (s *Subscription) Close() {
	s.c.mu.Lock()
	_, ok := s.c.subs[s]
	delete(s.c.subs, s)
	s.c.mu.Unlock()
	if !ok {
		return
	}
	ctx, cancel := context.WithTimeout(s.c.ctx, time.Second)
	defer cancel()
	s.c.Call(ctx, BusName, BusPath, BusInterface, "RemoveMatch", "s", s.match.rule())
	s.end()
}

func (s *Subscription) end() { s.endOnce.Do(func() { close(s.ch) }) }
