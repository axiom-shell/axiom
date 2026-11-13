// Package windows reports the running compositor's windows as they open,
// change and close (Hyprland, sway, niri), for the window rules engine
// (docs/dev/features/window-rules.md › Watching windows).
package windows

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"slices"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
)

// Window is one mapped window as the rules see it.
type Window struct {
	ID         string `json:"id"`    // contract.md's: Hyprland "0x…", sway and niri decimal
	AppID      string `json:"appId"` // the Wayland app id, or an X11 window's class
	Class      string `json:"class"` // an X11 window's WM_CLASS class, else ""
	Title      string `json:"title"`
	PID        int    `json:"pid"`       // 0 when not known
	XWayland   bool   `json:"xwayland"`  // always false on niri (not known)
	Workspace  string `json:"workspace"` // the name a rule's workspace uses; "" for none (sway's scratchpad)
	Output     string `json:"output"`    // the output's name; "" for none
	Floating   bool   `json:"floating"`
	Fullscreen bool   `json:"fullscreen"`
	Focused    bool   `json:"focused"`
}

// Kind is what happened; it marshals as "reset", "opened", "changed" or
// "closed".
type Kind int

const (
	Reset   Kind = iota // the full list after a (re)connect: Windows; nothing in it opened
	Opened              // Window appeared after the Reset
	Changed             // a field of Window differs
	Closed              // Window is gone; its last known fields
)

var kindNames = []string{"reset", "opened", "changed", "closed"}

// MarshalText makes a Kind its name in JSON.
func (k Kind) MarshalText() ([]byte, error) {
	if k < 0 || int(k) >= len(kindNames) {
		return nil, errors.New("windows: unknown kind")
	}
	return []byte(kindNames[k]), nil
}

// Event is one change; Windows is set for Reset only, Window for the rest.
type Event struct {
	Kind    Kind     `json:"kind"`
	Window  Window   `json:"window,omitzero"`
	Windows []Window `json:"windows,omitempty"`
}

// Options configure a Watcher; zero Retry is 2 s, nil Log discards.
type Options struct {
	Getenv func(string) string
	Log    *slog.Logger
	Retry  time.Duration
}

// Watcher reads one compositor's windows.
type Watcher struct {
	src   source
	fetch fetch
	log   *slog.Logger
	retry time.Duration
}

// New watches the compositor ipc.Detect finds in o.Getenv, or is nil when
// none. The compositor's kind isn't part of the API: what the engine may
// do is the shell's capabilities.
func New(o Options) *Watcher {
	var w Watcher
	switch ipc.Detect(o.Getenv) {
	case "hyprland":
		h := ipc.HyprFromEnv(o.Getenv)
		if h == nil {
			return nil
		}
		w.src = &hyprSource{h: h}
		w.fetch = func(ctx context.Context, request string) ([]byte, error) {
			reply, err := h.Request(ctx, request)
			return []byte(reply), err
		}
	case "sway":
		s := ipc.SwayFromEnv(o.Getenv)
		if s == nil {
			return nil
		}
		w.src = &swaySource{s: s}
		w.fetch = func(ctx context.Context, _ string) ([]byte, error) { return s.Tree(ctx) }
	case "niri":
		n := ipc.NiriFromEnv(o.Getenv)
		if n == nil {
			return nil
		}
		w.src = &niriSource{n: n}
		w.fetch = func(ctx context.Context, request string) ([]byte, error) {
			ok, err := n.Request(ctx, request)
			if err != nil {
				return nil, err
			}
			// The reply is {"Outputs": {name: output}}; the source reads the map
			var reply struct {
				Outputs map[string]any
			}
			if err := json.Unmarshal(ok, &reply); err != nil {
				return nil, err
			}
			return json.Marshal(reply.Outputs)
		}
	default:
		return nil
	}
	w.log = o.Log
	if w.log == nil {
		w.log = slog.New(slog.NewTextHandler(io.Discard, nil))
	}
	w.retry = o.Retry
	if w.retry <= 0 {
		w.retry = 2 * time.Second
	}
	return &w
}

// fetch answers one read request: Hyprland "j/clients", "j/monitors",
// "j/activewindow"; sway "get_tree"; niri "Outputs" (the output map)
type fetch func(ctx context.Context, request string) ([]byte, error)

// source is one compositor's side of the watcher
type source interface {
	// connect reads the event stream until ctx ends or it drops (ipc's Events)
	connect(ctx context.Context, started func(), event func([]byte)) error
	// start forgets everything and reads the full state (niri: only Outputs;
	// its Reset waits for the stream's first WindowsChanged); ready reports
	// whether the table now holds the snapshot
	start(ctx context.Context, f fetch, t *table) (ready bool, err error)
	// batch applies events in order, then any refetch they asked for (D3);
	// ready as for start (niri: true once WindowsChanged was applied)
	batch(ctx context.Context, f fetch, t *table, events [][]byte) (ready bool, err error)
}

// table is the windows a source knows, in the compositor's order
type table struct {
	list []Window
}

func (t *table) find(id string) int {
	return slices.IndexFunc(t.list, func(w Window) bool { return w.ID == id })
}

// update changes the window with id (if known) through fn
func (t *table) update(id string, fn func(*Window)) {
	if i := t.find(id); i >= 0 {
		fn(&t.list[i])
	}
}

func (t *table) remove(id string) {
	if i := t.find(id); i >= 0 {
		t.list = slices.Delete(t.list, i, i+1)
	}
}

// focus makes id the one focused window ("" for none)
func (t *table) focus(id string) {
	for i := range t.list {
		t.list[i].Focused = t.list[i].ID == id
	}
}

// diff is what changed since before: Closed (the last known window, old
// order), Changed (new order), then Opened (new order)
func (t *table) diff(before []Window) []Event {
	old := make(map[string]Window, len(before))
	for _, w := range before {
		old[w.ID] = w
	}
	now := make(map[string]bool, len(t.list))
	for _, w := range t.list {
		now[w.ID] = true
	}
	var events []Event
	for _, w := range before {
		if !now[w.ID] {
			events = append(events, Event{Kind: Closed, Window: w})
		}
	}
	for _, w := range t.list {
		if o, ok := old[w.ID]; ok && o != w {
			events = append(events, Event{Kind: Changed, Window: w})
		}
	}
	for _, w := range t.list {
		if _, ok := old[w.ID]; !ok {
			events = append(events, Event{Kind: Opened, Window: w})
		}
	}
	return events
}

// settle is what a batch emits: nothing until the snapshot is ready, one
// Reset on the batch that makes it ready, then the diffs
func (t *table) settle(before []Window, ready, wasReady bool) []Event {
	switch {
	case !ready:
		return nil
	case !wasReady:
		return []Event{{Kind: Reset, Windows: slices.Clone(t.list)}}
	}
	return t.diff(before)
}

// item is what the reader hands the processor: a start marker or an event
type item struct {
	start bool
	line  []byte
}

// Run sends the windows' events to out until ctx ends (then nil),
// connecting again after a drop with a fresh Reset; every send waits on
// ctx too.
func (w *Watcher) Run(ctx context.Context, out chan<- Event) error {
	for ctx.Err() == nil {
		err := w.session(ctx, out)
		if ctx.Err() != nil {
			return nil
		}
		w.log.Debug("windows: event stream", "err", err)
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(w.retry):
		}
	}
	return nil
}

// session is one connection: a reader goroutine feeds events in, this
// goroutine applies them in batches and emits the difference. It returns
// when the connection or a request fails, or ctx ends; the reader has
// ended by then.
func (w *Watcher) session(ctx context.Context, out chan<- Event) error {
	ctx, cancel := context.WithCancel(ctx)
	items := make(chan item, 256)
	var readErr error
	done := make(chan struct{})
	send := func(it item) {
		select {
		case items <- it:
		case <-ctx.Done():
		}
	}
	go func() {
		defer close(done)
		defer close(items)
		readErr = w.src.connect(ctx, func() { send(item{start: true}) }, func(line []byte) {
			send(item{line: slices.Clone(line)})
		})
	}()
	err := w.process(ctx, out, items)
	cancel()
	<-done
	if err == nil {
		err = readErr
	}
	if err == nil {
		err = errors.New("event stream closed")
	}
	return err
}

// process applies what the reader sends until it ends (nil) or something fails
func (w *Watcher) process(ctx context.Context, out chan<- Event, items <-chan item) error {
	t := &table{}
	wasReady := false
	for {
		var group []item
		select {
		case <-ctx.Done():
			return ctx.Err()
		case it, ok := <-items:
			if !ok {
				return nil
			}
			group = append(group, it)
		}
		// Everything else that is ready belongs to the same batch
	drain:
		for {
			select {
			case it, ok := <-items:
				if !ok {
					break drain
				}
				group = append(group, it)
			default:
				break drain
			}
		}
		before := slices.Clone(t.list)
		ready := wasReady
		var lines [][]byte
		flush := func() error {
			if len(lines) == 0 {
				return nil
			}
			r, err := w.src.batch(ctx, w.fetch, t, lines)
			lines = nil
			ready = r
			return err
		}
		for _, it := range group {
			if !it.start {
				lines = append(lines, it.line)
				continue
			}
			if err := flush(); err != nil {
				return err
			}
			r, err := w.src.start(ctx, w.fetch, t)
			if err != nil {
				return err
			}
			ready, wasReady, before = r, false, nil
		}
		if err := flush(); err != nil {
			return err
		}
		events := t.settle(before, ready, wasReady)
		wasReady = wasReady || ready
		for _, e := range events {
			select {
			case out <- e:
			case <-ctx.Done():
				return ctx.Err()
			}
		}
	}
}
