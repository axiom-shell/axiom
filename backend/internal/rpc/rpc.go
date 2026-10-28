// Package rpc is how the shell, the CLI and the daemon talk: JSON-RPC 2.0,
// one message per line (NDJSON) over a unix socket, in both directions
// (the daemon also calls the shell, for IPC). Every message of a
// connection goes out through one queue in order, so a notification sent
// while handling a request reaches the peer before that request's reply:
// `config.changed` always arrives before the reply to the `config.set`
// that caused it. A state push (NotifyLatest) holds one place in that
// queue and carries the newest state when it's written, so a peer that
// reads slowly gets fewer states rather than a queue that fills.
//
// Security (docs/dev/backend/README.md › Security): a server only accepts
// peers of its own user (SO_PEERCRED), and bounds line length, nesting,
// connections and requests in flight.
package rpc

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"reflect"
	"sync"
	"sync/atomic"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// Limits bound what one peer can make the other hold.
type Limits struct {
	MaxLine     int // bytes in one message
	MaxDepth    int // nesting of one message
	MaxInFlight int // requests being handled at once, per connection
	QueueSize   int // messages waiting to be written; a peer that falls this far behind is dropped
}

// DefaultLimits suit the shell: a whole config is tens of KB.
func DefaultLimits() Limits {
	return Limits{MaxLine: 16 << 20, MaxDepth: 64, MaxInFlight: 256, QueueSize: 4096}
}

// Handler handles one method; its result is marshalled as JSON
// (json.RawMessage passes through as is).
type Handler func(ctx context.Context, c *Conn, params json.RawMessage) (any, error)

// Registry maps methods to handlers. Before, when set, runs ahead of
// every call, a method it has no handler for too, and can refuse it (the
// daemon refuses everything but daemon.hello until a connection said
// hello; the greeter's answers what it doesn't serve as unavailable).
type Registry struct {
	handlers map[string]entry
	Before   func(c *Conn, method string) error
}

// entry is one method: its handler, the Go types of what it takes and
// returns (ShapeOf turns them into what goes on the wire), and whether
// its calls run in the order they arrived (InOrder).
type entry struct {
	handler        Handler
	params, result reflect.Type
	inOrder        bool
}

// NewRegistry returns an empty registry.
func NewRegistry() *Registry { return &Registry{handlers: map[string]entry{}} }

// Handle registers a typed handler: params are decoded into P strictly
// (DecodeStrict), the result R encoded. P and R are kept for Types.
func Handle[P, R any](r *Registry, method string, fn func(ctx context.Context, c *Conn, p P) (R, error)) {
	h := func(ctx context.Context, c *Conn, raw json.RawMessage) (any, error) {
		var p P
		if len(raw) > 0 && !bytes.Equal(raw, []byte("null")) {
			if err := DecodeStrict(raw, &p); err != nil {
				return nil, axerr.New(axerr.BadRequest, "%s: bad params: %v", method, err)
			}
		}
		return fn(ctx, c, p)
	}
	r.handlers[method] = entry{handler: h, params: reflect.TypeFor[P](), result: reflect.TypeFor[R]()}
}

// DecodeStrict decodes params into v, failing on a key v has no field
// for, at any depth: a typo or a renamed field is an error the caller
// sees, never a method run on its zero value. Every caller (the shell,
// the CLI) sends only the keys the method takes (docs/dev/backend/
// protocol.md › Changing the protocol); params typed json.RawMessage, a
// map or any take every key.
func DecodeStrict(raw json.RawMessage, v any) error {
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		return err
	}
	if _, err := dec.Token(); !errors.Is(err, io.EOF) {
		return errors.New("data after the params")
	}
	return nil
}

// InOrder makes a connection's calls of these methods (registered ones)
// run one at a time, in the order they arrived: the shell sends saves
// without waiting for the last, so two quick ones must not land in the
// order their goroutines happen to run. Other methods still run alongside.
func (r *Registry) InOrder(methods ...string) {
	for _, m := range methods {
		e, ok := r.handlers[m]
		if !ok {
			panic("rpc: InOrder of unregistered method " + m)
		}
		e.inOrder = true
		r.handlers[m] = e
	}
}

// Types is what method takes and returns, as Go types (false: no such
// method).
func (r *Registry) Types(method string) (params, result reflect.Type, ok bool) {
	e, ok := r.handlers[method]
	return e.params, e.result, ok
}

// Methods lists the registered methods.
func (r *Registry) Methods() []string {
	out := make([]string, 0, len(r.handlers))
	for m := range r.handlers {
		out = append(out, m)
	}
	return out
}

// JSON-RPC's own error codes
const (
	codeParse          = -32700
	codeInvalidRequest = -32600
	codeMethodNotFound = -32601
)

type message struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method,omitempty"`
	Params  json.RawMessage `json:"params,omitempty"`
	Result  json.RawMessage `json:"result,omitempty"`
	Error   *wireError      `json:"error,omitempty"`
}

type wireError struct {
	Code    int        `json:"code"`
	Message string     `json:"message"`
	Data    *errorData `json:"data,omitempty"`
}

type errorData struct {
	Kind   axerr.Kind    `json:"kind"`
	Issues []axerr.Issue `json:"issues,omitempty"`
}

func toWire(err error) *wireError {
	kind := axerr.KindOf(err)
	return &wireError{Code: axerr.RPCCode(kind), Message: err.Error(), Data: &errorData{Kind: kind, Issues: axerr.IssuesOf(err)}}
}

func (w *wireError) toError() error {
	e := &axerr.Error{Kind: axerr.Internal, Message: w.Message}
	if w.Data != nil {
		e.Kind, e.Issues = w.Data.Kind, w.Data.Issues
	} else if w.Code == codeMethodNotFound {
		e.Kind = axerr.NotFound
	} else if w.Code == codeInvalidRequest || w.Code == -32602 {
		e.Kind = axerr.BadRequest
	}
	return e
}

// Conn is one connection, either end: it handles the peer's requests with
// its registry and sends its own.
type Conn struct {
	nc     net.Conn
	reg    *Registry
	limits Limits
	log    *slog.Logger

	out       chan queued
	closeOnce sync.Once
	done      chan struct{}
	inFlight  chan struct{}

	mu      sync.Mutex
	pending map[string]chan message
	nextID  atomic.Int64

	latestMu sync.Mutex
	latest   map[string][]byte // NotifyLatest's newest unsent message, by method, while its place is queued

	handling sync.WaitGroup // the read loop and the handlers it started

	values sync.Map // per-connection state a server keeps (hello, client kind)
}

// NewConn wraps nc and starts reading and writing; it ends when either
// side closes. reg may be nil for a peer that only calls.
func NewConn(nc net.Conn, reg *Registry, limits Limits, log *slog.Logger) *Conn {
	if reg == nil {
		reg = NewRegistry()
	}
	if log == nil {
		log = slog.New(slog.DiscardHandler)
	}
	c := &Conn{
		nc: nc, reg: reg, limits: limits, log: log,
		out:      make(chan queued, limits.QueueSize),
		done:     make(chan struct{}),
		inFlight: make(chan struct{}, limits.MaxInFlight),
		pending:  map[string]chan message{},
		latest:   map[string][]byte{},
	}
	go c.writeLoop()
	c.handling.Add(1)
	go c.readLoop()
	return c
}

// Done is closed when the connection has ended.
func (c *Conn) Done() <-chan struct{} { return c.done }

// Close ends the connection.
func (c *Conn) Close() error {
	c.closeOnce.Do(func() {
		// Pending calls see done; their channels stay open, so a reply
		// read while closing has somewhere to go
		close(c.done)
		c.nc.Close()
	})
	return nil
}

// Wait waits, once the connection has ended, for the handlers still
// running its requests (their context is cancelled): nothing they touch
// may be closed under them.
func (c *Conn) Wait() { c.handling.Wait() }

// PeerPID is the pid of the process at the other end (-1 when it can't be
// told: not a unix socket).
func (c *Conn) PeerPID() int {
	pid, err := PeerPID(c.nc)
	if err != nil {
		return -1
	}
	return pid
}

// Value and SetValue hold per-connection state for handlers.
func (c *Conn) Value(key any) (any, bool) { return c.values.Load(key) }
func (c *Conn) SetValue(key, v any)       { c.values.Store(key, v) }

// Call sends a request and waits for its reply, decoding it into result
// (nil to drop it).
func (c *Conn) Call(ctx context.Context, method string, params any, result any) error {
	id := fmt.Sprint(c.nextID.Add(1))
	ch := make(chan message, 1)
	c.mu.Lock()
	select {
	case <-c.done:
		c.mu.Unlock()
		return axerr.New(axerr.Unavailable, "connection closed")
	default:
	}
	c.pending[id] = ch
	c.mu.Unlock()
	defer func() {
		c.mu.Lock()
		delete(c.pending, id)
		c.mu.Unlock()
	}()
	raw, err := marshalParams(params)
	if err != nil {
		return err
	}
	if err := c.send(message{JSONRPC: "2.0", ID: json.RawMessage(id), Method: method, Params: raw}); err != nil {
		return err
	}
	select {
	case reply := <-ch:
		if reply.Error != nil {
			return reply.Error.toError()
		}
		if result != nil && len(reply.Result) > 0 {
			if err := json.Unmarshal(reply.Result, result); err != nil {
				return axerr.Wrap(axerr.Internal, err, "%s: bad reply", method)
			}
		}
		return nil
	case <-ctx.Done():
		return ctx.Err()
	case <-c.done:
		return axerr.New(axerr.Unavailable, "connection closed before %s replied", method)
	}
}

// Notify sends a notification (no reply).
func (c *Conn) Notify(method string, params any) error {
	raw, err := marshalParams(params)
	if err != nil {
		return err
	}
	return c.send(message{JSONRPC: "2.0", Method: method, Params: raw})
}

// NotifyLatest sends a state notification that a newer one of the same
// method replaces while it waits: the method holds one place in the queue
// (where the first unsent state was sent, so order with replies holds),
// and what is written there is the newest state.
func (c *Conn) NotifyLatest(method string, params any) error {
	raw, err := marshalParams(params)
	if err != nil {
		return err
	}
	data, err := json.Marshal(message{JSONRPC: "2.0", Method: method, Params: raw})
	if err != nil {
		return axerr.Wrap(axerr.Internal, err, "encoding a message")
	}
	c.latestMu.Lock()
	_, waiting := c.latest[method]
	c.latest[method] = data
	c.latestMu.Unlock()
	if waiting {
		return nil
	}
	if err := c.enqueue(queued{latest: method}); err != nil {
		c.latestMu.Lock()
		delete(c.latest, method)
		c.latestMu.Unlock()
		return err
	}
	return nil
}

// queued is one place in the write queue: a message, or the place a
// NotifyLatest method holds (its data is taken when it's written).
type queued struct {
	data   []byte
	latest string
}

// takeLatest is the newest state queued for method, freeing its place.
func (c *Conn) takeLatest(method string) []byte {
	c.latestMu.Lock()
	defer c.latestMu.Unlock()
	data := c.latest[method]
	delete(c.latest, method)
	return data
}

func marshalParams(params any) (json.RawMessage, error) {
	if params == nil {
		return nil, nil
	}
	if raw, ok := params.(json.RawMessage); ok {
		return raw, nil
	}
	raw, err := json.Marshal(params)
	if err != nil {
		return nil, axerr.Wrap(axerr.Internal, err, "encoding params")
	}
	return raw, nil
}

func (c *Conn) send(m message) error {
	data, err := json.Marshal(m)
	if err != nil {
		return axerr.Wrap(axerr.Internal, err, "encoding a message")
	}
	return c.enqueue(queued{data: data})
}

func (c *Conn) enqueue(q queued) error {
	select {
	case <-c.done:
		return axerr.New(axerr.Unavailable, "connection closed")
	default:
	}
	select {
	case c.out <- q:
		return nil
	case <-c.done:
		return axerr.New(axerr.Unavailable, "connection closed")
	default:
		// The peer stopped reading: holding more for it only grows memory
		c.log.Warn("dropping a peer that stopped reading")
		c.Close()
		return axerr.New(axerr.Unavailable, "peer too slow")
	}
}

func (c *Conn) writeLoop() {
	w := bufio.NewWriter(c.nc)
	write := func(q queued) {
		data := q.data
		if q.latest != "" {
			data = c.takeLatest(q.latest)
		}
		w.Write(data)
		w.WriteByte('\n')
	}
	for {
		select {
		case q := <-c.out:
			write(q)
			// Batch what's already queued into one write
			for more := true; more; {
				select {
				case q := <-c.out:
					write(q)
				default:
					more = false
				}
			}
			if err := w.Flush(); err != nil {
				c.Close()
				return
			}
		case <-c.done:
			return
		}
	}
}

func (c *Conn) readLoop() {
	defer c.handling.Done()
	defer c.Close()
	sc := bufio.NewScanner(c.nc)
	// The scanner allows tokens up to the larger of its max and the first
	// buffer's capacity, so that buffer must not exceed the limit
	sc.Buffer(make([]byte, 0, min(64<<10, c.limits.MaxLine)), c.limits.MaxLine)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	// Closed once the last in-order call (InOrder) is handled: the next
	// one waits for it
	var lastInOrder chan struct{}
	for sc.Scan() {
		line := sc.Bytes()
		if len(bytes.TrimSpace(line)) == 0 {
			continue
		}
		if depth(line) > c.limits.MaxDepth {
			c.replyError(nil, &wireError{Code: codeInvalidRequest, Message: fmt.Sprintf("nested deeper than %d", c.limits.MaxDepth)})
			continue
		}
		var m message
		if err := json.Unmarshal(line, &m); err != nil {
			c.replyError(nil, &wireError{Code: codeParse, Message: "not JSON: " + err.Error()})
			continue
		}
		if m.Method == "" {
			c.deliver(m)
			continue
		}
		// Notifications are handled here, in order: one that arrived
		// before a reply is seen before the call returns
		if m.ID == nil {
			c.dispatch(ctx, m)
			continue
		}
		select {
		case c.inFlight <- struct{}{}:
		default:
			if m.ID != nil {
				c.replyError(m.ID, toWire(axerr.New(axerr.Unavailable, "too many requests in flight")))
			}
			continue
		}
		var after, done chan struct{}
		if c.reg.handlers[m.Method].inOrder {
			after, done = lastInOrder, make(chan struct{})
			lastInOrder = done
		}
		c.handling.Add(1)
		go func(m message) {
			defer c.handling.Done()
			defer func() { <-c.inFlight }()
			if done != nil {
				defer close(done)
			}
			if after != nil {
				<-after
			}
			c.dispatch(ctx, m)
		}(m)
	}
	if err := sc.Err(); errors.Is(err, bufio.ErrTooLong) {
		c.log.Warn("dropping a peer that sent a message over the size limit")
	}
}

// deliver hands a reply to its call. The first reply for an id is taken
// and a repeat or unknown one dropped: blocking on it would stop the read
// loop.
func (c *Conn) deliver(m message) {
	c.mu.Lock()
	defer c.mu.Unlock()
	ch, ok := c.pending[string(m.ID)]
	if !ok {
		return
	}
	delete(c.pending, string(m.ID))
	select {
	case ch <- m:
	default:
	}
}

func (c *Conn) dispatch(ctx context.Context, m message) {
	if c.reg.Before != nil {
		if err := c.reg.Before(c, m.Method); err != nil {
			if m.ID != nil {
				c.replyError(m.ID, toWire(err))
			}
			return
		}
	}
	e, ok := c.reg.handlers[m.Method]
	if !ok {
		if m.ID != nil {
			c.replyError(m.ID, &wireError{Code: codeMethodNotFound, Message: "no method " + m.Method})
		}
		return
	}
	result, err := safeCall(ctx, e.handler, c, m.Params)
	if m.ID == nil {
		if err != nil {
			c.log.Warn("notification failed", "method", m.Method, "err", err)
		}
		return
	}
	if err != nil {
		c.replyError(m.ID, toWire(err))
		return
	}
	raw, ok := result.(json.RawMessage)
	if !ok {
		var merr error
		raw, merr = json.Marshal(result)
		if merr != nil {
			c.replyError(m.ID, toWire(axerr.Wrap(axerr.Internal, merr, "encoding the reply")))
			return
		}
	}
	if len(raw) == 0 {
		raw = json.RawMessage("null")
	}
	c.send(message{JSONRPC: "2.0", ID: m.ID, Result: raw})
}

// safeCall turns a handler's panic into an internal error: one bad request
// never takes the daemon down.
func safeCall(ctx context.Context, h Handler, c *Conn, params json.RawMessage) (result any, err error) {
	defer func() {
		if r := recover(); r != nil {
			c.log.Error("handler panicked", "panic", r)
			err = axerr.New(axerr.Internal, "internal error")
		}
	}()
	return h(ctx, c, params)
}

func (c *Conn) replyError(id json.RawMessage, e *wireError) {
	if id == nil {
		id = json.RawMessage("null")
	}
	c.send(message{JSONRPC: "2.0", ID: id, Error: e})
}

// depth is how deeply a JSON text nests (outside strings).
func depth(data []byte) int {
	max, cur := 0, 0
	inString, escaped := false, false
	for _, b := range data {
		if inString {
			switch {
			case escaped:
				escaped = false
			case b == '\\':
				escaped = true
			case b == '"':
				inString = false
			}
			continue
		}
		switch b {
		case '"':
			inString = true
		case '{', '[':
			cur++
			if cur > max {
				max = cur
			}
		case '}', ']':
			cur--
		}
	}
	return max
}
