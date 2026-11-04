// Package inputmethod is the input method framework for the shell: fcitx5
// on the session bus, or the real ibus-daemon on its own private bus
// (fcitx5 also answers as org.freedesktop.IBus on the session bus, so
// that name never means ibus). It follows the framework's current input
// method, its list (fcitx5's current group, ibus's preloaded engines) and
// the engines installed, from their signals (nothing polls but the look
// for a framework that isn't running yet); switches the input method;
// pushes the list axiom owns (Input.sources) to the framework; and sets
// fcitx5's few options axiom has settings for.
package inputmethod

import (
	"context"
	"log/slog"
	"reflect"
	"slices"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
)

// The frameworks, as Options.Framework and State.Framework name them
const (
	FrameworkNone  = "none"
	FrameworkAuto  = "auto"
	FrameworkFcitx = "fcitx5"
	FrameworkIBus  = "ibus"
)

// Item is one entry of the framework's list: an input method and the xkb
// layout it types on ("" for the list's default layout).
type Item struct {
	Name   string `json:"name"`
	Layout string `json:"layout"`
}

// Engine is an input method the framework has installed.
type Engine struct {
	// Name is its id (fcitx5's unique name, "keyboard-us", "mozc"; an
	// ibus engine's name, "xkb:us::eng")
	Name string `json:"name"`
	// Label is the short text an indicator shows ("あ", "en")
	Label string `json:"label"`
	// DisplayName is its name for a person ("Mozc", "Keyboard - English (US)")
	DisplayName string `json:"displayName"`
	Icon        string `json:"icon"`
	// Lang is its language code ("ja"; "" for none)
	Lang string `json:"lang"`
}

// State is the framework as the shell sees it (the inputMethod topic).
type State struct {
	// Framework is the one followed, "fcitx5" or "ibus"; "" for none
	// (none running, or Options.Framework none)
	Framework string `json:"framework"`
	// Running: the framework answers (the rest is empty otherwise)
	Running bool `json:"running"`
	// Current is the input method in use: fcitx5's in the text field
	// focused last, ibus's global engine; "" while there is none (fcitx5
	// before any text field had focus: the list's first then types)
	Current string `json:"current"`
	// DefaultLayout is the list's default xkb layout (fcitx5's group's;
	// "" for ibus, whose engines carry their own)
	DefaultLayout string `json:"defaultLayout"`
	// Group is the framework's list, in its order
	Group []Item `json:"group"`
	// Available are the input methods installed
	Available []Engine `json:"available"`
	// OutsideEdit: the list is no longer the one axiom pushed last (it
	// was edited in fcitx5-configtool or ibus-setup); false until axiom
	// pushed one
	OutsideEdit bool `json:"outsideEdit"`
}

// Settings are the options axiom sets on the framework; a nil field is
// left as it is. Only fcitx5 takes all of them; ibus takes the font.
type Settings struct {
	// ShareState is fcitx5's ShareInputState: "No", "All" or "Program"
	ShareState *string `json:"shareState,omitempty"`
	// VerticalCandidates lays the candidates out in a column (classicui)
	VerticalCandidates *bool `json:"verticalCandidates,omitempty"`
	// CandidateFont is the candidate window's font ("Sans 10"; ibus's
	// custom-font)
	CandidateFont *string `json:"candidateFont,omitempty"`
	// ShowSwitchPopup is fcitx5's own popup on a switch
	// (ShowInputMethodInformation; off while axiom's OSD shows it)
	ShowSwitchPopup *bool `json:"showSwitchPopup,omitempty"`
}

// Options configure the service.
type Options struct {
	// SessionBus connects to the session bus (a new connection each call)
	SessionBus func(ctx context.Context) (*dbus.Conn, error)
	// IBusAddress finds the running ibus-daemon's private bus ("" when
	// none runs); default: $IBUS_ADDRESS, else its address file
	IBusAddress func() string
	// Getenv reads the environment, for the default IBusAddress
	Getenv func(string) string
	// GSettings runs gsettings with args and returns its output (ibus
	// keeps its engine list and font there); nil leaves them alone
	GSettings func(ctx context.Context, args ...string) (string, error)
	// OnChange is told of every new state
	OnChange func(State)
	// Retry is how often to look again for a framework that isn't running
	// (default 10 s: fcitx5 is also heard appearing at once)
	Retry time.Duration
	Log   *slog.Logger
}

// backend is the framework followed while it runs.
type backend interface {
	set(ctx context.Context, name string) error
	push(ctx context.Context, defaultLayout string, items []Item) error
	settings(ctx context.Context, s Settings) error
}

// pushed is the list axiom pushed last, to tell an outside edit apart.
type pushed struct {
	defaultLayout string
	items         []Item
}

// Service follows the input method framework; Run runs it.
type Service struct {
	o Options

	// kick wakes Run to look again (the framework setting changed);
	// refresh to read the framework again (after a switch or a push)
	kick, refresh chan struct{}

	mu        sync.Mutex
	framework string
	active    backend
	last      *pushed
	state     State
}

// New returns a service, following any framework running until told
// otherwise (SetFramework); Run runs it.
func New(o Options) *Service {
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	if o.Retry == 0 {
		o.Retry = 10 * time.Second
	}
	if o.Getenv == nil {
		o.Getenv = func(string) string { return "" }
	}
	if o.IBusAddress == nil {
		getenv := o.Getenv
		o.IBusAddress = func() string { return ibusAddress(getenv) }
	}
	return &Service{
		o: o, framework: FrameworkAuto, state: emptyState(""),
		kick: make(chan struct{}, 1), refresh: make(chan struct{}, 1),
	}
}

func emptyState(framework string) State {
	return State{Framework: framework, Group: []Item{}, Available: []Engine{}}
}

// State is the current state.
func (s *Service) State() State {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.state
}

// SetFramework picks the framework to follow: none, auto (fcitx5 when it
// runs, else ibus), fcitx5 or ibus.
func (s *Service) SetFramework(name string) error {
	switch name {
	case FrameworkNone, FrameworkAuto, FrameworkFcitx, FrameworkIBus:
	default:
		return axerr.New(axerr.BadRequest, "no framework %q (none, auto, fcitx5, ibus)", name)
	}
	s.mu.Lock()
	same := s.framework == name
	s.framework = name
	s.mu.Unlock()
	if !same {
		wake(s.kick)
	}
	return nil
}

func wake(c chan struct{}) {
	select {
	case c <- struct{}{}:
	default:
	}
}

// Set switches to the input method name.
func (s *Service) Set(ctx context.Context, name string) error {
	if name == "" {
		return axerr.New(axerr.BadRequest, "no input method named")
	}
	b, err := s.backend()
	if err != nil {
		return err
	}
	if err := b.set(ctx, name); err != nil {
		return err
	}
	wake(s.refresh)
	return nil
}

// Push makes items the framework's list (fcitx5's current group, with
// defaultLayout; ibus's preloaded engines), remembered as axiom's so an
// edit elsewhere shows as OutsideEdit.
func (s *Service) Push(ctx context.Context, defaultLayout string, items []Item) error {
	if len(items) == 0 {
		return axerr.New(axerr.BadRequest, "an empty list (the framework needs one input method)")
	}
	seen := map[string]bool{}
	for _, it := range items {
		if it.Name == "" {
			return axerr.New(axerr.BadRequest, "an item without a name")
		}
		if seen[it.Name] {
			return axerr.New(axerr.BadRequest, "%s is in the list twice", it.Name)
		}
		seen[it.Name] = true
	}
	b, err := s.backend()
	if err != nil {
		return err
	}
	// Remembered first: the framework's signal of the change may come
	// before the call's reply
	s.mu.Lock()
	prev := s.last
	s.last = &pushed{defaultLayout: defaultLayout, items: slices.Clone(items)}
	s.mu.Unlock()
	if err := b.push(ctx, defaultLayout, items); err != nil {
		s.mu.Lock()
		s.last = prev
		s.mu.Unlock()
		return err
	}
	wake(s.refresh)
	return nil
}

// Configure sets the framework's options.
func (s *Service) Configure(ctx context.Context, set Settings) error {
	if set.ShareState != nil {
		switch *set.ShareState {
		case "No", "All", "Program":
		default:
			return axerr.New(axerr.BadRequest, "shareState is No, All or Program, not %q", *set.ShareState)
		}
	}
	b, err := s.backend()
	if err != nil {
		return err
	}
	return b.settings(ctx, set)
}

func (s *Service) backend() (backend, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.active == nil {
		return nil, axerr.New(axerr.Unavailable, "no input method framework is running")
	}
	return s.active, nil
}

// Run follows the framework until ctx ends, looking again whenever it
// stops or appears, or the framework setting changes.
func (s *Service) Run(ctx context.Context) error {
	for {
		again, err := s.runOnce(ctx)
		s.setActive(nil)
		if ctx.Err() != nil {
			return nil
		}
		if again {
			continue
		}
		if err != nil {
			s.o.Log.Debug("input method: looking again", "in", s.o.Retry, "err", err)
		}
		select {
		case <-ctx.Done():
			return nil
		case <-s.kick:
		case <-time.After(s.o.Retry):
		}
	}
}

// runOnce finds the framework and follows it while it runs. again: look
// again at once (the setting changed, or a framework came or went).
func (s *Service) runOnce(ctx context.Context) (again bool, err error) {
	s.mu.Lock()
	fw := s.framework
	s.mu.Unlock()
	if fw == FrameworkNone {
		s.publish(emptyState(""))
		select {
		case <-ctx.Done():
		case <-s.kick:
		}
		return true, nil
	}
	var session *dbus.Conn
	var owners *dbus.Subscription
	if fw != FrameworkIBus {
		session, err = s.o.SessionBus(ctx)
		if err != nil {
			s.publish(emptyState(""))
			return false, err
		}
		defer session.Close()
		// Subscribed before asking, so fcitx5 starting in between is heard
		owners, err = session.Subscribe(ctx, dbus.NameOwnerChanged(fcitxName))
		if err != nil {
			return false, err
		}
		defer owners.Close()
		if owner, _ := session.NameOwner(ctx, fcitxName); owner != "" {
			return s.followFcitx(ctx, session, owners)
		}
	}
	if fw != FrameworkFcitx {
		if addr := s.o.IBusAddress(); addr != "" {
			return s.followIBus(ctx, addr, owners)
		}
	}
	// Nothing running: fcitx5 is heard starting, ibus looked for again
	empty := emptyState("")
	if fw != FrameworkAuto {
		empty.Framework = fw
	}
	s.publish(empty)
	var appeared <-chan *dbus.Message
	if owners != nil {
		appeared = owners.C
	}
	var gone <-chan struct{}
	if session != nil {
		gone = session.Done()
	}
	for {
		select {
		case <-ctx.Done():
			return false, nil
		case <-s.kick:
			return true, nil
		case <-gone:
			return false, session.Err()
		case <-time.After(s.o.Retry):
			return true, nil
		case m, ok := <-appeared:
			if !ok {
				return false, nil
			}
			if ownerOf(m) != "" {
				return true, nil
			}
		}
	}
}

// ownerOf is the new owner a NameOwnerChanged names ("" for none, or for
// another signal).
func ownerOf(m *dbus.Message) string {
	var name, old, owner string
	if m.Member != "NameOwnerChanged" || m.Store(&name, &old, &owner) != nil {
		return ""
	}
	return owner
}

func (s *Service) setActive(b backend) {
	s.mu.Lock()
	s.active = b
	s.mu.Unlock()
}

// publish makes next the state (OutsideEdit worked out here), telling
// OnChange when it changed.
func (s *Service) publish(next State) {
	s.mu.Lock()
	if next.Running && s.last != nil {
		next.OutsideEdit = !s.last.matches(next, next.Framework == FrameworkFcitx)
	}
	same := reflect.DeepEqual(s.state, next)
	s.state = next
	s.mu.Unlock()
	if !same && s.o.OnChange != nil {
		s.o.OnChange(next)
	}
}

// matches: the list read is the one pushed (its default layout too where
// the framework keeps one).
func (p *pushed) matches(st State, layouts bool) bool {
	if layouts && p.defaultLayout != st.DefaultLayout {
		return false
	}
	if len(p.items) != len(st.Group) {
		return false
	}
	for i, it := range p.items {
		got := st.Group[i]
		if it.Name != got.Name || layouts && it.Layout != got.Layout {
			return false
		}
	}
	return true
}

// mapError gives the framework's error replies the kind the shell tells
// apart: what the bus says (gone, bad arguments) keeps its kind, anything
// the framework itself answered is a failure, with its message.
func mapError(err error) error {
	if err == nil || dbus.ErrorName(err) == "" || axerr.KindOf(err) != axerr.Internal {
		return err
	}
	return axerr.Wrap(axerr.Failed, err, "the input method framework")
}

// merged is subscriptions' signals in one channel, each subscription's in
// the order sent.
type merged struct {
	C    chan *dbus.Message
	done chan struct{}
	wg   sync.WaitGroup
}

// merge forwards subs' signals (nil ones skipped) until stop, which
// leaves the subscriptions open: their owners close them.
func merge(subs ...*dbus.Subscription) *merged {
	m := &merged{C: make(chan *dbus.Message, 64), done: make(chan struct{})}
	for _, sub := range subs {
		if sub == nil {
			continue
		}
		m.wg.Add(1)
		go func() {
			defer m.wg.Done()
			// Not ranging over C: a subscription may outlive the merge
			for {
				select {
				case msg, ok := <-sub.C:
					if !ok {
						return
					}
					select {
					case m.C <- msg:
					case <-m.done:
						return
					}
				case <-m.done:
					return
				}
			}
		}()
	}
	return m
}

// stop ends the forwarding and waits for it.
func (m *merged) stop() {
	close(m.done)
	m.wg.Wait()
}
