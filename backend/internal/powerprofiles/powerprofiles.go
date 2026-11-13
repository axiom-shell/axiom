// Package powerprofiles holds a power profile in power-profiles-daemon for the window rules (docs/dev/features/window-rules.md › The effects): one hold at a time, taken again when the daemon restarts, given up when the user picks a profile.
package powerprofiles

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/dbus"
)

// power-profiles-daemon's names: the UPower ones, else the older net.hadess ones
type target struct {
	name  string
	path  dbus.ObjectPath
	iface string
}

var (
	upower = target{"org.freedesktop.UPower.PowerProfiles", "/org/freedesktop/UPower/PowerProfiles", "org.freedesktop.UPower.PowerProfiles"}
	hadess = target{"net.hadess.PowerProfiles", "/net/hadess/PowerProfiles", "net.hadess.PowerProfiles"}
)

// Options build a Holder.
type Options struct {
	SystemBus    func(ctx context.Context) (*dbus.Conn, error)
	OnOverridden func()        // the user picked a profile while a hold was in force
	Log          *slog.Logger  // nil discards
	Retry        time.Duration // a lost bus, default 30 s
}

// wish is what Hold asked for; gen counts the changes, so a wish asked again
// after being dropped is a new one.
type wish struct {
	profile, reason string
	gen             int
}

// Holder holds a profile in power-profiles-daemon; Run runs it.
type Holder struct {
	o    Options
	kick chan struct{} // capacity 1: the wish changed

	mu   sync.Mutex
	want wish
}

// New is a holder holding nothing.
func New(o Options) *Holder {
	if o.Log == nil {
		o.Log = slog.New(slog.NewTextHandler(io.Discard, nil))
	}
	if o.Retry <= 0 {
		o.Retry = 30 * time.Second
	}
	return &Holder{o: o, kick: make(chan struct{}, 1)}
}

// Name is PPD's name for a window rule's profile ("powerSaver" → "power-saver").
func Name(config string) string {
	switch config {
	case "performance":
		return "performance"
	case "powerSaver":
		return "power-saver"
	}
	return ""
}

// Hold asks for profile ("performance" | "power-saver"; "" none) with reason;
// it returns at once, Run does the rest.
func (h *Holder) Hold(profile, reason string) {
	if profile == "" {
		reason = ""
	}
	h.mu.Lock()
	if h.want.profile != profile || h.want.reason != reason {
		h.want = wish{profile, reason, h.want.gen + 1}
	}
	h.mu.Unlock()
	select {
	case h.kick <- struct{}{}:
	default:
	}
}

func (h *Holder) wanted() wish {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.want
}

// Run holds what Hold asked for until ctx ends (then it lets go and returns
// nil). It dials the system bus only while a profile is wanted.
func (h *Holder) Run(ctx context.Context) error {
	for {
		if h.wanted().profile == "" {
			select {
			case <-ctx.Done():
				return nil
			case <-h.kick:
				continue
			}
		}
		err := h.session(ctx)
		if ctx.Err() != nil {
			return nil
		}
		if err == nil {
			continue
		}
		h.o.Log.Warn("powerprofiles: the system bus is out of reach: retrying", "in", h.o.Retry, "err", err)
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(h.o.Retry):
		}
	}
}

// session is one connection's life: it ends, nil, once nothing is wanted.
func (h *Holder) session(ctx context.Context) error {
	conn, err := h.o.SystemBus(ctx)
	if err != nil {
		return err
	}
	defer conn.Close()
	released, err := conn.Subscribe(ctx, dbus.Match{Member: "ProfileReleased"})
	if err != nil {
		return err
	}
	defer released.Close()
	ownersU, err := conn.Subscribe(ctx, dbus.NameOwnerChanged(upower.name))
	if err != nil {
		return err
	}
	defer ownersU.Close()
	ownersH, err := conn.Subscribe(ctx, dbus.NameOwnerChanged(hadess.name))
	if err != nil {
		return err
	}
	defer ownersH.Close()

	s := &session{h: h, conn: conn}
	defer func() {
		if s.cookie != 0 {
			s.release(s.cookie)
		}
	}()
	for {
		w := h.wanted()
		if w.profile == "" {
			return nil
		}
		s.reconcile(ctx, w)
		select {
		case <-ctx.Done():
			return nil
		case <-conn.Done():
			return conn.Err()
		case <-h.kick:
		case m, ok := <-released.C:
			if !ok {
				return errors.New("connection closed")
			}
			s.released(m)
		case m, ok := <-ownersU.C:
			if !ok {
				return errors.New("connection closed")
			}
			s.ownerChanged(upower, m)
		case m, ok := <-ownersH.C:
			if !ok {
				return errors.New("connection closed")
			}
			s.ownerChanged(hadess, m)
		}
	}
}

// session is what one connection knows of its hold.
type session struct {
	h    *Holder
	conn *dbus.Conn

	cookie  uint32 // the hold taken now; 0: none
	held    wish   // what it holds (profile and reason)
	in      *target
	waiting bool // no daemon: wait for a name to get an owner
	done    int  // the gen given up on (overridden or refused); 0: none
}

// reconcile takes, changes or lets go of the hold so it is w.
func (s *session) reconcile(ctx context.Context, w wish) {
	if s.cookie != 0 && s.held.profile == w.profile && s.held.reason == w.reason {
		return
	}
	if s.done == w.gen || s.waiting {
		// Overridden or refused: nothing again until the wish changes
		return
	}
	old := s.cookie
	cookie, in, err := s.take(ctx, w)
	switch {
	case err == nil:
		s.cookie, s.held, s.in = cookie, w, in
	case errors.Is(err, errNoDaemon):
		s.h.o.Log.Info("powerprofiles: power-profiles-daemon isn't running: waiting for it")
		s.cookie, s.in, s.waiting = 0, nil, true
	case ctx.Err() != nil || s.conn.Err() != nil:
		return
	default:
		s.h.o.Log.Warn("powerprofiles: the profile was refused", "profile", w.profile, "reason", w.reason, "err", err)
		s.cookie, s.done = 0, w.gen
	}
	// The new hold is taken before the old goes, so PPD doesn't fall back
	// to the user's profile between them
	if old != 0 {
		s.release(old)
	}
}

var errNoDaemon = errors.New("no power-profiles-daemon")

// take holds w.profile on the daemon in use, else on whichever answers.
func (s *session) take(ctx context.Context, w wish) (uint32, *target, error) {
	candidates := []target{upower, hadess}
	if s.in != nil {
		candidates = []target{*s.in}
	}
	for _, t := range candidates {
		tctx, cancel := context.WithTimeout(ctx, 5*time.Second)
		m, err := s.conn.Call(tctx, t.name, t.path, t.iface, "HoldProfile", "sss", w.profile, w.reason, "axiom")
		cancel()
		if dbus.ErrorName(err) == dbus.ErrServiceUnknown || dbus.ErrorName(err) == dbus.ErrNameHasNoOwner {
			continue
		}
		if err != nil {
			return 0, nil, err
		}
		var cookie uint32
		if err := m.Store(&cookie); err != nil {
			return 0, nil, err
		}
		t := t
		return cookie, &t, nil
	}
	return 0, nil, errNoDaemon
}

// release gives a hold back; the cookie is no longer s.cookie, so PPD's
// ProfileReleased for it is never read as the user's.
func (s *session) release(cookie uint32) {
	t := s.in
	if t == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if cookie == s.cookie {
		s.cookie = 0
	}
	s.conn.Call(ctx, t.name, t.path, t.iface, "ReleaseProfile", "u", cookie)
}

// released reads PPD's ProfileReleased: for the hold in force and not one
// given back here, the user picked a profile.
func (s *session) released(m *dbus.Message) {
	if m.Interface != upower.iface && m.Interface != hadess.iface {
		return
	}
	var cookie uint32
	if m.Store(&cookie) != nil || s.cookie == 0 || cookie != s.cookie {
		return
	}
	s.cookie = 0
	s.done = s.h.wanted().gen
	if s.h.o.OnOverridden != nil {
		s.h.o.OnOverridden()
	}
}

// ownerChanged reads a daemon name changing owner: the hold on it is gone,
// not overridden; a new owner is held on again.
func (s *session) ownerChanged(t target, m *dbus.Message) {
	var name, oldOwner, newOwner string
	if m.Store(&name, &oldOwner, &newOwner) != nil {
		return
	}
	if s.in != nil && s.in.name == t.name {
		s.cookie, s.in = 0, nil
		s.waiting = newOwner == ""
	}
	if newOwner != "" {
		s.waiting = false
	}
}
