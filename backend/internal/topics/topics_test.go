package topics

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/assets"
)

// fakeClock moves only when told; After fires once Advance passes it.
type fakeClock struct {
	mu    sync.Mutex
	now   time.Time
	waits []fakeWait
}

type fakeWait struct {
	at time.Time
	ch chan time.Time
}

func (c *fakeClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

func (c *fakeClock) After(d time.Duration) <-chan time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	ch := make(chan time.Time, 1)
	c.waits = append(c.waits, fakeWait{c.now.Add(d), ch})
	return ch
}

func (c *fakeClock) Advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.now = c.now.Add(d)
	kept := c.waits[:0]
	for _, w := range c.waits {
		if w.at.After(c.now) {
			kept = append(kept, w)
		} else {
			w.ch <- c.now
		}
	}
	c.waits = kept
}

// fakeSub records the states pushed to it.
type fakeSub struct{ states chan string }

func newSub() *fakeSub { return &fakeSub{states: make(chan string, 64)} }

func (s *fakeSub) NotifyLatest(method string, params any) error {
	s.states <- method + " " + string(params.(json.RawMessage))
	return nil
}

type harness struct {
	hub     *Hub
	clock   *fakeClock
	fetches chan []json.RawMessage
	mu      sync.Mutex
	value   int
}

// newHarness is a hub with one source, "t" (floor 1s, default 10s),
// whose state is the harness's value; with changes to it from each opt.
func newHarness(t *testing.T, opts ...func(*Source)) *harness {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	var wg sync.WaitGroup
	t.Cleanup(func() { cancel(); wg.Wait() })
	h := &harness{clock: &fakeClock{now: time.Unix(1000, 0)}, fetches: make(chan []json.RawMessage, 64)}
	h.hub = New(Options{
		Context: ctx,
		Go: func(fn func(context.Context)) {
			wg.Add(1)
			go func() { defer wg.Done(); fn(ctx) }()
		},
		Now:   h.clock.Now,
		After: h.clock.After,
	})
	src := Source{Name: "t", Floor: time.Second, Default: 10 * time.Second,
		Fetch: func(ctx context.Context, requests []json.RawMessage) (any, error) {
			h.fetches <- requests
			h.mu.Lock()
			defer h.mu.Unlock()
			return map[string]int{"v": h.value}, nil
		}}
	for _, o := range opts {
		o(&src)
	}
	h.hub.add(src)
	return h
}

func (h *harness) set(v int) {
	h.mu.Lock()
	h.value = v
	h.mu.Unlock()
}

func fetched(t *testing.T, h *harness) []json.RawMessage {
	t.Helper()
	select {
	case r := <-h.fetches:
		return r
	case <-time.After(5 * time.Second):
		t.Fatal("no fetch")
		return nil
	}
}

func notFetched(t *testing.T, h *harness) {
	t.Helper()
	select {
	case <-h.fetches:
		t.Fatal("fetched")
	case <-time.After(50 * time.Millisecond):
	}
}

func state(t *testing.T, s *fakeSub) string {
	t.Helper()
	select {
	case st := <-s.states:
		return st
	case <-time.After(5 * time.Second):
		t.Fatal("no state")
		return ""
	}
}

func noState(t *testing.T, s *fakeSub) {
	t.Helper()
	select {
	case st := <-s.states:
		t.Fatalf("pushed %s", st)
	case <-time.After(50 * time.Millisecond):
	}
}

func subscribe(t *testing.T, h *harness, s Subscriber, request string) {
	t.Helper()
	if err := h.hub.Subscribe(s, "t", json.RawMessage(request)); err != nil {
		t.Fatal(err)
	}
}

// settle waits for the loop to be waiting again after a fetch (its
// state pushed), so the next Advance is measured from that fetch.
func settle(t *testing.T, h *harness) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		h.clock.mu.Lock()
		n := len(h.clock.waits)
		h.clock.mu.Unlock()
		if n > 0 {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("the loop never waited")
}

func TestFetchesOnlyWithSubscribers(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	notFetched(t, h)
	s := newSub()
	subscribe(t, h, s, `{"interval":3000}`)
	if r := fetched(t, h); len(r) != 1 || string(r[0]) != `{"interval":3000}` {
		t.Errorf("requests %s", r)
	}
	if got := state(t, s); got != `t.state {"v":0}` {
		t.Errorf("state %q", got)
	}
	settle(t, h)
	h.clock.Advance(3 * time.Second)
	fetched(t, h)
	h.hub.Unsubscribe(s, "t")
	h.clock.Advance(time.Hour)
	notFetched(t, h)
}

func TestShortestIntervalAndFloor(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name      string
		requests  []string
		short, at time.Duration // no fetch after short, one by at
	}{
		{"default", []string{`{}`}, 9 * time.Second, 10 * time.Second},
		{"shortest wins", []string{`{"interval":10000}`, `{"interval":3000}`}, 2 * time.Second, 3 * time.Second},
		{"floor", []string{`{"interval":100}`}, 500 * time.Millisecond, time.Second},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			h := newHarness(t)
			for _, r := range tc.requests {
				subscribe(t, h, newSub(), r)
			}
			fetched(t, h)
			settle(t, h)
			h.clock.Advance(tc.short)
			notFetched(t, h)
			h.clock.Advance(tc.at - tc.short)
			fetched(t, h)
		})
	}
}

func TestPushesOnlyChanges(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	s := newSub()
	subscribe(t, h, s, `{"interval":1000}`)
	fetched(t, h)
	state(t, s)
	settle(t, h)
	h.clock.Advance(time.Second)
	fetched(t, h)
	noState(t, s)
	h.set(2)
	settle(t, h)
	h.clock.Advance(time.Second)
	fetched(t, h)
	if got := state(t, s); got != `t.state {"v":2}` {
		t.Errorf("state %q", got)
	}
}

func TestLateSubscriberGetsTheState(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	a := newSub()
	subscribe(t, h, a, `{}`)
	fetched(t, h)
	state(t, a)
	b := newSub()
	subscribe(t, h, b, `{}`)
	if got := state(t, b); got != `t.state {"v":0}` {
		t.Errorf("state %q", got)
	}
	notFetched(t, h)
}

func TestForgetAndRefresh(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	s := newSub()
	subscribe(t, h, s, `{}`)
	fetched(t, h)
	if err := h.hub.Refresh("t"); err != nil {
		t.Fatal(err)
	}
	fetched(t, h)
	h.hub.Forget(s)
	if err := h.hub.Refresh("t"); err != nil {
		t.Fatal(err)
	}
	h.clock.Advance(time.Hour)
	notFetched(t, h)
	// Subscribing again starts afresh: no stale state, a new fetch
	h.set(5)
	subscribe(t, h, s, `{}`)
	fetched(t, h)
	for st := state(t, s); st != `t.state {"v":5}`; st = state(t, s) {
	}
}

func TestRefusesUnknownTopicsAndBadParams(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	if err := h.hub.Subscribe(newSub(), "nope", nil); err == nil {
		t.Error("subscribed to an unknown topic")
	}
	if err := h.hub.Subscribe(newSub(), "t", json.RawMessage(`{"interval":"x"}`)); err == nil {
		t.Error("took a string interval")
	}
}

// A request asking for something new is fetched at once; another
// interval only moves the next fetch
func TestFetchesANewRequestAtOnce(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	s := newSub()
	subscribe(t, h, s, `{"interval":60000}`)
	fetched(t, h)
	settle(t, h)
	subscribe(t, h, s, `{"interval":30000}`)
	notFetched(t, h)
	subscribe(t, h, s, `{"interval":30000, "more": true}`)
	if r := fetched(t, h); string(r[0]) != `{"interval":30000, "more": true}` {
		t.Errorf("fetched for %s", r)
	}
	settle(t, h)
	// The same request again, keys in another order: nothing new
	subscribe(t, h, s, `{"more": true, "interval":30000}`)
	notFetched(t, h)
	// A second subscriber asking for the same gets the state it has
	other := newSub()
	subscribe(t, h, other, `{"interval":60000, "more": true}`)
	notFetched(t, h)
	// and asking for its own, fetches
	subscribe(t, h, other, `{"interval":60000}`)
	fetched(t, h)
}

func TestOnRefresh(t *testing.T) {
	t.Parallel()
	refreshed := 0
	h := newHarness(t, func(s *Source) { s.OnRefresh = func() { refreshed++ } })
	// Nothing to refresh without subscribers
	h.hub.Refresh("t")
	s := newSub()
	subscribe(t, h, s, `{}`)
	fetched(t, h)
	h.hub.Refresh("t")
	fetched(t, h)
	h.hub.mu.Lock()
	defer h.hub.mu.Unlock()
	if refreshed != 1 {
		t.Errorf("told of %d refreshes, want 1", refreshed)
	}
}

// Every interval setting (a number named *interval*, *refresh* or *poll*,
// stored in ms whatever its x-unit) offers nothing below MinInterval, the
// floor of the topics fed by a setting, so no value a topic's setting
// offers is silently raised. Settings polled in QML are held to it too,
// which keeps the check from depending on knowing which ones feed a topic;
// those known to must be among them, so renaming one can't slip it past.
func TestIntervalSettingsMeetMinInterval(t *testing.T) {
	t.Parallel()
	data, err := assets.Read("config/json/config.schema.json")
	if err != nil {
		t.Skip("no built schema:", err)
	}
	var root any
	if err := json.Unmarshal(data, &root); err != nil {
		t.Fatal(err)
	}
	feeds := map[string]bool{
		"/definitions/TailscaleWidget/properties/properties.interval":      false, // tailscale
		"/definitions/SystemStatsWidget/properties/properties.interval":    false, // system
		"/definitions/UpdatesWidget/properties/properties.interval":        false, // updates
		"/definitions/UpdatesOverlayModule/properties/properties.interval": false, // updates
		"/properties/ClaudeUsage.interval":                                 false, // claudeUsage's every
	}
	var walk func(node any, path string)
	walk = func(node any, path string) {
		switch n := node.(type) {
		case []any:
			for i, v := range n {
				walk(v, fmt.Sprintf("%s[%d]", path, i))
			}
		case map[string]any:
			if props, ok := n["properties"].(map[string]any); ok {
				for key, v := range props {
					p, ok := v.(map[string]any)
					name := strings.ToLower(key)
					if !ok || (p["type"] != "integer" && p["type"] != "number") ||
						!strings.Contains(name, "interval") && !strings.Contains(name, "refresh") && !strings.Contains(name, "poll") {
						continue
					}
					if _, known := feeds[path+"."+key]; known {
						feeds[path+"."+key] = true
					}
					if minimum, ok := p["minimum"].(float64); !ok || time.Duration(minimum)*time.Millisecond < MinInterval {
						t.Errorf("%s.%s: minimum %v is below topics.MinInterval (%v)", path, key, p["minimum"], MinInterval)
					}
				}
			}
			for k, v := range n {
				walk(v, path+"/"+k)
			}
		}
	}
	walk(root, "")
	for path, seen := range feeds {
		if !seen {
			t.Errorf("%s: not found as an interval setting: was it renamed or moved?", path)
		}
	}
}
