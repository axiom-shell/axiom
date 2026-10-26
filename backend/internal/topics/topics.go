// Package topics runs the daemon's polled topics: a source the shell
// subscribes to (`<name>.subscribe` with an interval and whatever else
// its request carries) is fetched once for every subscriber, at the
// shortest interval asked, and not at all without subscribers; its state
// is pushed as `<name>.state` whenever it changes, latest-wins. A request
// asking for something no subscriber asked for yet (more than another
// interval) is fetched at once rather than at the next interval. The Go side of the
// shell's ConsumerRegistry contract.
package topics

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"reflect"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// Source is one polled topic. Its Name is a literal where it's built
// (`topics.Source{Name: "x", …}`): scripts/gen_docs.py reads it for the
// methods and push it defines.
type Source struct {
	Name string
	// Floor is the shortest interval anyone gets (MinInterval for a
	// source whose interval comes from a setting); Default the one a
	// request without an interval asks for
	Floor, Default time.Duration
	// Fetch returns the state for the subscribers' requests (each as it
	// was sent); it's marshalled as JSON and pushed when it changed
	Fetch func(ctx context.Context, requests []json.RawMessage) (any, error)
	// Request is the Go type a request decodes into, besides the hub's
	// interval; State the type Fetch returns (rpc.ShapeOf reports them)
	Request, State reflect.Type
	// OnRefresh, when set, is told of `<name>.refresh` before the fetch
	// it starts, for a source whose Fetch does more when asked to (it
	// mustn't block: the hub's lock is held)
	OnRefresh func()
}

// MinInterval is the floor of every source whose interval comes from a
// setting. No interval setting's schema minimum is below it
// (TestIntervalSettingsMeetMinInterval), so every value the settings
// offer is polled at, never silently raised to a floor.
const MinInterval = 250 * time.Millisecond

// Subscriber is where states go: an *rpc.Conn.
type Subscriber interface {
	NotifyLatest(method string, params any) error
}

// Options configure a Hub; the zero Now and After are the real clock.
type Options struct {
	Log *slog.Logger
	// Context bounds every loop (the daemon's); Go runs one on a
	// goroutine its owner waits for (the daemon's tasks)
	Context context.Context
	Go      func(func(ctx context.Context))
	Now     func() time.Time
	After   func(time.Duration) <-chan time.Time
}

// Hub holds every source and who subscribes to it.
type Hub struct {
	o       Options
	mu      sync.Mutex
	sources map[string]*topic
}

type topic struct {
	src  Source
	subs map[Subscriber]subscription
	// While anyone subscribes: the loop's context, and its generation (a
	// loop stopped and started again never publishes for the new one)
	cancel context.CancelFunc
	gen    int
	// changed is signalled when the intervals change, refresh to fetch now
	changed, refresh chan struct{}
	last             json.RawMessage // the state last pushed
	lastErr          string
}

type subscription struct {
	request  json.RawMessage
	interval time.Duration
	// what is the request without its interval: what a fetch is for
	what string
}

// New returns an empty hub.
func New(o Options) *Hub {
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	if o.Context == nil {
		o.Context = context.Background()
	}
	if o.Go == nil {
		o.Go = func(fn func(context.Context)) { go fn(o.Context) }
	}
	if o.Now == nil {
		o.Now = time.Now
	}
	if o.After == nil {
		o.After = time.After
	}
	return &Hub{o: o, sources: map[string]*topic{}}
}

// Register adds src to the hub and its methods to reg:
// `<name>.subscribe` (params: `{interval}` in ms, plus the source's own),
// `<name>.unsubscribe` and `<name>.refresh` (fetch now).
func Register(reg *rpc.Registry, h *Hub, src Source) {
	h.add(src)
	name := src.Name
	rpc.Handle(reg, name+".subscribe", func(ctx context.Context, c *rpc.Conn, p json.RawMessage) (struct{}, error) {
		return struct{}{}, h.Subscribe(c, name, p)
	})
	rpc.Handle(reg, name+".unsubscribe", func(ctx context.Context, c *rpc.Conn, p struct{}) (struct{}, error) {
		h.Unsubscribe(c, name)
		return struct{}{}, nil
	})
	rpc.Handle(reg, name+".refresh", func(ctx context.Context, c *rpc.Conn, p struct{}) (struct{}, error) {
		return struct{}{}, h.Refresh(name)
	})
}

func (h *Hub) add(src Source) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.sources[src.Name] = &topic{src: src, subs: map[Subscriber]subscription{}}
}

func (h *Hub) find(name string) (*topic, error) {
	t := h.sources[name]
	if t == nil {
		return nil, axerr.New(axerr.NotFound, "no topic %q", name)
	}
	return t, nil
}

// Subscribe sets s's request for a topic (replacing its last one) and
// starts the topic's loop if s is its first subscriber. A state already
// fetched is pushed to s at once.
func (h *Hub) Subscribe(s Subscriber, name string, request json.RawMessage) error {
	var p struct {
		Interval *float64 `json:"interval"`
	}
	if len(request) > 0 && string(request) != "null" {
		if err := json.Unmarshal(request, &p); err != nil {
			return axerr.Wrap(axerr.BadRequest, err, "%s.subscribe: bad params", name)
		}
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	t, err := h.find(name)
	if err != nil {
		return err
	}
	if err := checkRequest(t.src.Request, request); err != nil {
		return axerr.Wrap(axerr.BadRequest, err, "%s.subscribe: bad params", name)
	}
	interval := t.src.Default
	if p.Interval != nil {
		interval = time.Duration(*p.Interval * float64(time.Millisecond))
	}
	sub := subscription{request: request, interval: max(interval, t.src.Floor), what: what(request)}
	// Something no subscriber asked for yet is fetched now; the same
	// again, at another interval, only moves the next fetch
	asked := false
	for _, o := range t.subs {
		asked = asked || o.what == sub.what
	}
	t.subs[s] = sub
	if t.cancel == nil {
		h.start(t)
	} else {
		if !asked {
			signal(t.refresh)
		} else {
			signal(t.changed)
		}
		if t.last != nil {
			s.NotifyLatest(name+".state", t.last)
		}
	}
	return nil
}

// checkRequest fails on a key of request that neither the hub's interval
// nor the source's Request type takes (rpc.DecodeStrict), as a method's
// params do.
func checkRequest(typ reflect.Type, request json.RawMessage) error {
	if typ == nil || len(request) == 0 || string(request) == "null" {
		return nil
	}
	var keys map[string]json.RawMessage
	if err := json.Unmarshal(request, &keys); err != nil {
		return err
	}
	delete(keys, "interval")
	rest, err := json.Marshal(keys)
	if err != nil {
		return err
	}
	return rpc.DecodeStrict(rest, reflect.New(typ).Interface())
}

// Unsubscribe drops s's request; the topic stops with its last subscriber.
func (h *Hub) Unsubscribe(s Subscriber, name string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if t := h.sources[name]; t != nil {
		h.drop(t, s)
	}
}

// Forget drops every request of s (a connection that closed).
func (h *Hub) Forget(s Subscriber) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for _, t := range h.sources {
		h.drop(t, s)
	}
}

// Refresh fetches a topic now, if anyone subscribes to it.
func (h *Hub) Refresh(name string) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	t, err := h.find(name)
	if err != nil {
		return err
	}
	if t.cancel != nil {
		if t.src.OnRefresh != nil {
			t.src.OnRefresh()
		}
		signal(t.refresh)
	}
	return nil
}

func (h *Hub) drop(t *topic, s Subscriber) {
	if _, ok := t.subs[s]; !ok {
		return
	}
	delete(t.subs, s)
	if len(t.subs) > 0 {
		signal(t.changed)
		return
	}
	t.cancel()
	// A state fetched before is stale by the next subscriber
	t.cancel, t.last, t.lastErr = nil, nil, ""
}

// start runs t's loop; h.mu is held.
func (h *Hub) start(t *topic) {
	t.gen++
	gen := t.gen
	t.changed, t.refresh = make(chan struct{}, 1), make(chan struct{}, 1)
	changed, refresh := t.changed, t.refresh
	ctx, cancel := context.WithCancel(h.o.Context)
	t.cancel = cancel
	h.o.Go(func(context.Context) {
		defer cancel()
		h.loop(ctx, t, gen, changed, refresh)
	})
}

// loop fetches, then waits for the shortest interval asked since that
// fetch (again whenever the intervals change), or a refresh (a request
// asking for something new too).
func (h *Hub) loop(ctx context.Context, t *topic, gen int, changed, refresh <-chan struct{}) {
	for ctx.Err() == nil {
		requests, _ := h.requests(t)
		fetched := h.o.Now()
		state, err := t.src.Fetch(ctx, requests)
		if ctx.Err() != nil {
			return
		}
		h.publish(t, gen, state, err)
	wait:
		for {
			_, interval := h.requests(t)
			d := fetched.Add(interval).Sub(h.o.Now())
			if d <= 0 {
				break
			}
			select {
			case <-ctx.Done():
				return
			case <-refresh:
				break wait
			case <-changed:
			case <-h.o.After(d):
				break wait
			}
		}
	}
}

// requests is every subscriber's request and the shortest interval asked.
func (h *Hub) requests(t *topic) ([]json.RawMessage, time.Duration) {
	h.mu.Lock()
	defer h.mu.Unlock()
	var out []json.RawMessage
	interval := time.Duration(-1)
	for _, s := range t.subs {
		out = append(out, s.request)
		if interval < 0 || s.interval < interval {
			interval = s.interval
		}
	}
	return out, max(interval, t.src.Floor)
}

// publish pushes state to every subscriber when it differs from the last.
func (h *Hub) publish(t *topic, gen int, state any, err error) {
	var data []byte
	if err == nil {
		data, err = json.Marshal(state)
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	if gen != t.gen || t.cancel == nil {
		return
	}
	if err != nil {
		// Once per distinct error, not every interval
		if msg := err.Error(); msg != t.lastErr {
			t.lastErr = msg
			h.o.Log.Warn("fetching a topic", "topic", t.src.Name, "err", err)
		}
		return
	}
	t.lastErr = ""
	if bytes.Equal(data, t.last) {
		return
	}
	t.last = data
	for s := range t.subs {
		s.NotifyLatest(t.src.Name+".state", json.RawMessage(data))
	}
}

// what is request without its interval (keys sorted), or as sent when
// it isn't an object.
func what(request json.RawMessage) string {
	var m map[string]json.RawMessage
	if json.Unmarshal(request, &m) != nil || m == nil {
		return string(request)
	}
	delete(m, "interval")
	data, _ := json.Marshal(m)
	return string(data)
}

func signal(ch chan struct{}) {
	select {
	case ch <- struct{}{}:
	default:
	}
}
