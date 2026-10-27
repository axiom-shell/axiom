package command

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"
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

// fakeSub records the outputs pushed to it.
type fakeSub struct{ pushes chan Outputs }

func newSub() *fakeSub { return &fakeSub{pushes: make(chan Outputs, 64)} }

func (s *fakeSub) NotifyLatest(method string, params any) error {
	s.pushes <- params.(Outputs)
	return nil
}

func (s *fakeSub) next(t *testing.T) Outputs {
	t.Helper()
	select {
	case p := <-s.pushes:
		return p
	case <-time.After(5 * time.Second):
		t.Fatal("nothing pushed")
		return Outputs{}
	}
}

type harness struct {
	w     *Watches
	clock *fakeClock
	runs  chan string // each command run (its sh -c argument)
	mu    sync.Mutex
	out   map[string]string // what each command prints (default: a count)
	n     int
}

func newHarness(t *testing.T) *harness {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	h := &harness{clock: &fakeClock{now: time.Unix(1000, 0)}, runs: make(chan string, 64), out: map[string]string{}}
	h.w = NewWatches(WatchOptions{
		Method: "exec.outputs", Context: ctx, Now: h.clock.Now, After: h.clock.After,
		Run: func(ctx context.Context, argv []string) (Result, error) {
			h.mu.Lock()
			h.n++
			out, ok := h.out[argv[2]]
			if !ok {
				out = string(rune('a'+h.n%26)) + "\n"
			}
			h.mu.Unlock()
			h.runs <- argv[2]
			if out == "!fail" {
				return Result{}, errors.New("sh isn't installed")
			}
			return Result{Stdout: out}, nil
		},
	})
	return h
}

func (h *harness) ran(t *testing.T, want string) {
	t.Helper()
	select {
	case got := <-h.runs:
		if got != want {
			t.Fatalf("ran %q, want %q", got, want)
		}
	case <-time.After(5 * time.Second):
		t.Fatalf("%q didn't run", want)
	}
}

func (h *harness) idle(t *testing.T) {
	t.Helper()
	select {
	case got := <-h.runs:
		t.Fatalf("%q ran", got)
	case <-time.After(50 * time.Millisecond):
	}
}

func ms(n float64) *float64 { return &n }

// Each command runs at the shortest interval its watchers ask, and
// follows them as they come and go.
func TestWatchIntervalUnionPerCommand(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	a, b := newSub(), newSub()
	if err := h.w.Watch(a, WatchRequest{Command: "x", Interval: ms(3000)}); err != nil {
		t.Fatal(err)
	}
	h.ran(t, "x")
	a.next(t)
	h.w.Watch(b, WatchRequest{Command: "x", Interval: ms(1000)})
	b.next(t) // the output there is pushed at once, without a run
	h.idle(t)
	h.clock.Advance(time.Second)
	h.ran(t, "x")
	// Another command keeps its own interval
	h.w.Watch(a, WatchRequest{Command: "y", Interval: ms(10000)})
	h.ran(t, "y")
	h.w.Unwatch(b, "x")
	h.idle(t)
	h.clock.Advance(time.Second)
	h.idle(t)
	h.clock.Advance(2 * time.Second)
	h.ran(t, "x")
	// Below the floor is the floor
	h.w.Watch(b, WatchRequest{Command: "x", Interval: ms(1)})
	b.next(t)
	h.clock.Advance(MinPollInterval)
	h.ran(t, "x")
}

// A command watched once runs once, then only when refreshed; a poll
// watching it too makes it poll.
func TestWatchOnce(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	s := newSub()
	h.w.Watch(s, WatchRequest{Command: "x", Mode: ModeOnce})
	h.ran(t, "x")
	s.next(t)
	h.clock.Advance(time.Hour)
	h.idle(t)
	h.w.Refresh("x")
	h.ran(t, "x")
	h.w.Watch(newSub(), WatchRequest{Command: "x", Interval: ms(1000)})
	h.clock.Advance(time.Second)
	h.ran(t, "x")
}

// With json, the output is parsed: a value, or an error with the raw
// text kept; with text alone it isn't. One push carries every command.
func TestWatchFormats(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name, out, format string
		value, err        string
	}{
		{name: "json", out: `{"text": "5"}` + "\n", format: FormatJSON, value: `{"text": "5"}`},
		{name: "bad json", out: "{oops\n", format: FormatJSON, err: "the output isn't JSON"},
		{name: "empty json", out: "\n", format: FormatJSON},
		{name: "text", out: `{"text": "5"}`, format: FormatText},
		{name: "doesn't start", out: "!fail", format: FormatText, err: "sh isn't installed"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			h := newHarness(t)
			h.out["x"], h.out["y"] = c.out, "other\n"
			s := newSub()
			h.w.Watch(s, WatchRequest{Command: "y", Mode: ModeOnce})
			h.ran(t, "y")
			s.next(t)
			h.w.Watch(s, WatchRequest{Command: "x", Format: c.format})
			h.ran(t, "x")
			p := s.next(t)
			if p.Outputs["y"].Text != "other" {
				t.Errorf("the push lost y: %+v", p)
			}
			e := p.Outputs["x"]
			if string(e.Value) != c.value || e.Error != c.err {
				t.Errorf("entry %+v, want value %s error %q", e, c.value, c.err)
			}
			if c.out != "!fail" && e.Text != strings.TrimSpace(c.out) {
				t.Errorf("text %q", e.Text)
			}
			if c.out == "!fail" && e.ExitCode != -1 {
				t.Errorf("exit code %d", e.ExitCode)
			}
			if e.At != h.clock.Now().UnixMilli() {
				t.Errorf("at %d", e.At)
			}
			if _, err := json.Marshal(p); err != nil {
				t.Error(err)
			}
		})
	}
}

// An unchanged output isn't pushed again; a text watcher asking for json
// gets it parsed at once.
func TestWatchPushesChanges(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	h.out["x"] = "[1]"
	s := newSub()
	h.w.Watch(s, WatchRequest{Command: "x", Interval: ms(1000)})
	h.ran(t, "x")
	if e := s.next(t).Outputs["x"]; e.Value != nil {
		t.Errorf("text parsed: %+v", e)
	}
	h.clock.Advance(time.Second)
	h.ran(t, "x")
	select {
	case p := <-s.pushes:
		t.Errorf("unchanged output pushed: %+v", p)
	case <-time.After(50 * time.Millisecond):
	}
	h.w.Watch(s, WatchRequest{Command: "x", Interval: ms(1000), Format: FormatJSON})
	h.ran(t, "x")
	if e := s.next(t).Outputs["x"]; string(e.Value) != "[1]" {
		t.Errorf("json not parsed: %+v", e)
	}
}

// A command stops with its last watcher, whether it unwatched or its
// connection closed (Forget); bad requests are refused.
func TestWatchStops(t *testing.T) {
	t.Parallel()
	for _, forget := range []bool{false, true} {
		h := newHarness(t)
		s := newSub()
		h.w.Watch(s, WatchRequest{Command: "x", Interval: ms(1000)})
		h.w.Watch(s, WatchRequest{Command: "y", Interval: ms(1000)})
		<-h.runs
		<-h.runs
		if forget {
			h.w.Forget(s)
		} else {
			h.w.Unwatch(s, "x")
			h.w.Unwatch(s, "y")
		}
		h.clock.Advance(time.Hour)
		h.idle(t)
		h.w.Refresh("x")
		h.idle(t)
		h.w.mu.Lock()
		if len(h.w.runs) != 0 || len(h.w.subs) != 0 {
			t.Errorf("forget %v: left %v %v", forget, h.w.runs, h.w.subs)
		}
		h.w.mu.Unlock()
	}
	h := newHarness(t)
	for _, r := range []WatchRequest{{}, {Command: "x", Mode: "tail"}, {Command: "x", Format: "xml"}} {
		if err := h.w.Watch(newSub(), r); err == nil {
			t.Errorf("%+v accepted", r)
		}
	}
}

// A second watcher gets the output already there at once, even when its
// asking for json reruns the command to an unchanged (empty) output.
func TestWatchNewWatcherGetsOutput(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	h.out["x"] = "\n"
	a, b := newSub(), newSub()
	h.w.Watch(a, WatchRequest{Command: "x", Mode: ModeOnce})
	h.ran(t, "x")
	a.next(t)
	h.w.Watch(b, WatchRequest{Command: "x", Mode: ModeOnce, Format: FormatJSON})
	if _, ok := b.next(t).Outputs["x"]; !ok {
		t.Error("b got no output")
	}
	h.ran(t, "x")
	h.idle(t)
	select {
	case p := <-a.pushes:
		t.Errorf("unchanged output pushed: %+v", p)
	default:
	}
}
