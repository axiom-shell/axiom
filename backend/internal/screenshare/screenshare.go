// Package screenshare is axiom's screen-share picker: the portal backends
// ask it what to share (xdg-desktop-portal-hyprland through its custom
// picker, xdg-desktop-portal-wlr through its chooser command, both
// `axiom screenshare-pick`; niri through axiom's own ScreenCast portal,
// Portal), and the Broker asks the shell, which shows the picker and
// answers.
//
// Apps such as Discord ask several times for one share. A request that
// comes within ReuseSeconds of the last answer, from the same app (or one
// that didn't say), gets that answer again without the picker; requests
// wait their turn, so repeats sent at once are answered by the first.
package screenshare

import (
	"context"
	"log/slog"
	"strconv"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// Backends: who asks, which decides what a choice can be
const (
	BackendXDPH = "xdph" // regions too; windows by xdph's handle
	BackendXDPW = "xdpw" // windows by their ext-foreign-toplevel identifier
	BackendNiri = "niri" // windows by niri's id
)

// Kinds of choice
const (
	KindScreen = "screen"
	KindWindow = "window"
	KindRegion = "region"
)

// Output is a monitor that can be shared.
type Output struct {
	Name string `json:"name"`
	// Label is the backend's description of it ("" when it has none)
	Label string `json:"label,omitempty"`
}

// Window is a window that can be shared.
type Window struct {
	// Token is what the backend names it by in a choice
	Token string `json:"token"`
	// ID is the compositor's window id as CompositorManager has it
	// ("0x…" on Hyprland, niri's id), "" when the backend doesn't say
	ID    string `json:"id,omitempty"`
	Title string `json:"title"`
	AppID string `json:"appId,omitempty"`
}

// Request is what a backend offers to share, pushed to the shell as
// screenshare.request.
type Request struct {
	ID      string `json:"id"`
	Backend string `json:"backend"`
	// AppID is the app asking ("" when the backend doesn't know)
	AppID   string   `json:"appId,omitempty"`
	Outputs []Output `json:"outputs"`
	Windows []Window `json:"windows"`
	// Region: a rectangle of a monitor can be shared
	Region bool `json:"region"`
}

// Rect is a region of an output, in its logical pixels from its top left.
type Rect struct {
	X int `json:"x"`
	Y int `json:"y"`
	W int `json:"w"`
	H int `json:"h"`
}

// Choice is what the user picked.
type Choice struct {
	Kind   string `json:"kind"`
	Output string `json:"output,omitempty"` // a screen's, or a region's
	Window string `json:"window,omitempty"` // the window's Token
	Rect   *Rect  `json:"rect,omitempty"`   // a region's
}

// Settings are the ScreenSharing section.
type Settings struct {
	// Enabled: axiom's picker answers; off, the backends' own pickers do
	Enabled bool
	// ReuseSeconds: a request within this long of the last answer gets
	// it again (0: never)
	ReuseSeconds int
	// Remember: apps may keep a choice to share it again later without
	// asking (restore tokens)
	Remember bool
}

// valid reports whether c can be given for r.
func (c Choice) valid(r Request) bool {
	hasOutput := func(name string) bool {
		for _, o := range r.Outputs {
			if o.Name == name {
				return true
			}
		}
		return false
	}
	switch c.Kind {
	case KindScreen:
		return hasOutput(c.Output)
	case KindWindow:
		for _, w := range r.Windows {
			if w.Token == c.Window {
				return true
			}
		}
	case KindRegion:
		return r.Region && c.Rect != nil && c.Rect.W > 0 && c.Rect.H > 0 && c.Rect.X >= 0 && c.Rect.Y >= 0 && hasOutput(c.Output)
	}
	return false
}

// Options configure a Broker.
type Options struct {
	// OnRequest shows a request to the shell; false when there's no shell
	// to ask
	OnRequest func(Request) bool
	// OnDone tells the shell a request it shows is over (its asker gave
	// up, or the shell is told again)
	OnDone func(id string)
	// Now is the clock (time.Now when nil)
	Now func() time.Time
	Log *slog.Logger
}

// Broker hands requests to the shell, one at a time, and their answers
// back.
type Broker struct {
	o    Options
	turn chan struct{}

	mu       sync.Mutex
	settings Settings
	next     int
	pending  map[string]chan answer
	last     *last
}

type answer struct {
	choice *Choice
	err    error
}

// last is the last answer given, for repeats.
type last struct {
	at      time.Time
	backend string
	appID   string
	choice  Choice
}

// New returns a broker.
func New(o Options) *Broker {
	if o.Now == nil {
		o.Now = time.Now
	}
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	return &Broker{o: o, turn: make(chan struct{}, 1), pending: map[string]chan answer{}}
}

// Configure sets the settings.
func (b *Broker) Configure(s Settings) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.settings = s
}

// Settings are the settings set.
func (b *Broker) Settings() Settings {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.settings
}

// Ask asks the user what to share of r (its ID is set here): the choice,
// or nil when they cancelled. With no shell to ask it fails Unavailable;
// when ctx ends first, the shell is told to close the picker.
func (b *Broker) Ask(ctx context.Context, r Request) (*Choice, error) {
	select {
	case b.turn <- struct{}{}:
	case <-ctx.Done():
		return nil, axerr.Wrap(axerr.Unavailable, ctx.Err(), "waiting for the picker")
	}
	defer func() { <-b.turn }()

	b.mu.Lock()
	if c := b.repeat(r); c != nil {
		b.mu.Unlock()
		b.o.Log.Info("screen share: a repeat request, answered again", "backend", r.Backend, "app", r.AppID, "kind", c.Kind)
		return c, nil
	}
	b.next++
	r.ID = strconv.Itoa(b.next)
	ch := make(chan answer, 1)
	b.pending[r.ID] = ch
	b.mu.Unlock()

	if b.o.OnRequest == nil || !b.o.OnRequest(r) {
		b.take(r.ID)
		return nil, axerr.New(axerr.Unavailable, "no shell to show the picker")
	}
	select {
	case a := <-ch:
		if a.err == nil && a.choice != nil {
			b.mu.Lock()
			b.last = &last{at: b.o.Now(), backend: r.Backend, appID: r.AppID, choice: *a.choice}
			b.mu.Unlock()
		}
		return a.choice, a.err
	case <-ctx.Done():
		if b.take(r.ID) != nil && b.o.OnDone != nil {
			b.o.OnDone(r.ID)
		}
		return nil, axerr.Wrap(axerr.Unavailable, ctx.Err(), "the picker's asker went away")
	}
}

// repeat is the last answer when r repeats it; b.mu is held.
func (b *Broker) repeat(r Request) *Choice {
	l := b.last
	if l == nil || b.settings.ReuseSeconds <= 0 || l.backend != r.Backend {
		return nil
	}
	if l.appID != "" && r.AppID != "" && l.appID != r.AppID {
		return nil
	}
	if b.o.Now().Sub(l.at) >= time.Duration(b.settings.ReuseSeconds)*time.Second || !l.choice.valid(r) {
		return nil
	}
	c := l.choice
	return &c
}

func (b *Broker) take(id string) chan answer {
	b.mu.Lock()
	defer b.mu.Unlock()
	ch := b.pending[id]
	delete(b.pending, id)
	return ch
}

// Answer answers request id: choice, or with cancel, the user declined.
func (b *Broker) Answer(id string, choice *Choice, cancel bool) error {
	b.mu.Lock()
	ch := b.pending[id]
	b.mu.Unlock()
	if ch == nil {
		return axerr.New(axerr.NotFound, "no screen share request %s waits", id)
	}
	if !cancel {
		if choice == nil {
			return axerr.New(axerr.BadRequest, "no choice and no cancel")
		}
		// The request's own sources aren't kept: the backend checks the
		// choice against them (an unknown one shares nothing)
		if choice.Kind != KindScreen && choice.Kind != KindWindow && choice.Kind != KindRegion {
			return axerr.New(axerr.BadRequest, "no such kind of share: %q", choice.Kind)
		}
	}
	if b.take(id) == nil {
		return axerr.New(axerr.NotFound, "no screen share request %s waits", id)
	}
	if cancel {
		choice = nil
	}
	ch <- answer{choice: choice}
	return nil
}

// Forget fails every request the shell shows: it went away. Their askers
// fall back to the backends' own pickers.
func (b *Broker) Forget() {
	b.mu.Lock()
	pending := b.pending
	b.pending = map[string]chan answer{}
	b.mu.Unlock()
	for _, ch := range pending {
		ch <- answer{err: axerr.New(axerr.Unavailable, "the shell went away")}
	}
}
