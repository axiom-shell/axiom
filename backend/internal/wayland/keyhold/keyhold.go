// Package keyhold holds the keyboard for the window switcher where the
// compositor can't tell when its modifier is let go (sway, niri): a
// 1×1 transparent Overlay layer surface with exclusive keyboard focus,
// mapped while the switcher is open. The compositor still runs its binds
// first, so the switcher's Tab keeps stepping. The modifiers held are read
// from wl_keyboard.modifiers, which follows enter with the seat's state,
// so a modifier let go before the surface had the keyboard is seen too:
// then it picks. Otherwise it picks when the held modifiers are let go,
// or on Return, and cancels on Escape. A let go counts once it lasts
// (Options.Grace): a keyboard may report a modifier still held as up for
// a report or two around another key, as Hyprland's switcher listener
// waits 10 ms for. Other keys are ignored
// (they reach no window while it's held). Not the key events' own
// releases, nor enter's keys: a keyboard that is several devices (a
// keyboard's boot and NKRO interfaces) has sway report a modifier still
// held as released, and leave it out of enter's keys after that.
package keyhold

import (
	"log/slog"
	"strings"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/wayland/client"
	"github.com/axiom-shell/axiom/backend/internal/wayland/seat"
	"github.com/axiom-shell/axiom/backend/internal/wayland/wire"
)

// The interfaces and opcodes used (wayland.xml, wlr-layer-shell-unstable-v1.xml)
const (
	ifaceCompositor = "wl_compositor"
	ifaceShm        = "wl_shm"
	ifaceLayerShell = "zwlr_layer_shell_v1"

	opCreateSurface = 0 // wl_compositor.create_surface(id)
	opCreateRegion  = 1 // wl_compositor.create_region(id)
	opRegionDestroy = 0

	opSurfaceDestroy     = 0
	opSurfaceAttach      = 1 // (buffer, x, y)
	opSurfaceDamage      = 2 // (x, y, w, h)
	opSurfaceInputRegion = 5 // (region)
	opSurfaceCommit      = 6

	opShmCreatePool    = 0 // (id, fd, size)
	opPoolCreateBuffer = 0 // (id, offset, width, height, stride, format)
	opPoolDestroy      = 1
	opBufferDestroy    = 0
	formatARGB8888     = 0

	opGetLayerSurface  = 0 // (id, surface, output, layer, namespace)
	opLayerSetSize     = 0 // (w, h)
	opLayerSetAnchor   = 1 // (anchor)
	opLayerSetKeyboard = 4 // (keyboard_interactivity)
	opLayerAck         = 6 // ack_configure(serial)
	opLayerDestroy     = 7
	evLayerConfigure   = 0 // (serial, w, h)
	evLayerClosed      = 1
	layerOverlay       = 3
	anchorTopLeft      = 1 | 4 // top | left
	keyboardExclusive  = 1

	opSeatGetKeyboard = 1 // wl_seat.get_keyboard(id)
	evKeymap          = 0 // (format, fd, size)
	evEnter           = 1 // (serial, surface, keys)
	evLeave           = 2 // (serial, surface)
	evKey             = 3 // (serial, time, key, state)
	evModifiers       = 4 // (serial, depressed, latched, locked, group)
	keyPressed        = 1
)

// Namespace is the surface's layer-shell namespace.
const Namespace = "axiom-switcher-keys"

// The evdev keycodes it acts on
const (
	keyEsc     = 1
	keyEnter   = 28
	keyKPEnter = 96
)

// modifierBits are each modifier's bit in wl_keyboard.modifiers' masks,
// by the names the switcher binds are held by (BindActions.switcherHeld):
// xkbcommon gives the eight core modifiers the same indices in every
// keymap (Shift 0, Lock 1, Control 2, Mod1 3, …, Mod4 6), Alt being Mod1
// and Super Mod4.
var modifierBits = map[string]uint32{
	"SHIFT": 1 << 0,
	"CTRL":  1 << 2,
	"ALT":   1 << 3,
	"SUPER": 1 << 6,
}

// ModifierMask is the named modifiers' (ALT, CTRL, SHIFT, SUPER) mask;
// an unknown name is an error.
func ModifierMask(names []string) (uint32, error) {
	var mask uint32
	for _, name := range names {
		bit, ok := modifierBits[strings.ToUpper(name)]
		if !ok {
			return 0, axerr.New(axerr.BadRequest, "unknown modifier %q", name)
		}
		mask |= bit
	}
	return mask, nil
}

// Verb is what a held keyboard decided.
type Verb string

const (
	Commit Verb = "commit"
	Cancel Verb = "cancel"
)

// Options configure the holder.
type Options struct {
	Seat *seat.Tracker
	// Log gets what each hold sees and decides, at debug level (nil:
	// nothing)
	Log *slog.Logger
	// Grace is how long the held modifiers must stay up to pick
	// (DefaultGrace when 0)
	Grace time.Duration
}

// DefaultGrace outlasts a keyboard's blip (its reports come every 1–8
// ms) and is too short to feel on a real let go.
const DefaultGrace = 40 * time.Millisecond

// Holder holds the keyboard on demand; it is a client.Client.
type Holder struct {
	opts Options

	mu         sync.Mutex
	s          *client.Session
	compositor uint32
	shm        uint32
	layerShell uint32
	globals    map[uint32]*uint32 // a bound global's name → its field
	keyboard   uint32             // wl_keyboard, made on the first hold
	kbSeat     uint32             // the seat it was made on
	hold       *hold
}

// hold is one held keyboard: its objects and what it waits for.
type hold struct {
	surface, layer, pool, buffer uint32
	attached                     bool
	mods                         uint32
	focused                      bool
	done                         bool
	// letGo picks once the held modifiers stay up for the grace
	letGo  *time.Timer
	onVerb func(Verb)
}

// New returns a holder, able to hold once the compositor's globals are
// bound.
func New(opts Options) *Holder {
	if opts.Log == nil {
		opts.Log = slog.New(slog.DiscardHandler)
	}
	if opts.Grace <= 0 {
		opts.Grace = DefaultGrace
	}
	return &Holder{opts: opts}
}

// Available reports whether the compositor offers what a hold needs.
func (h *Holder) Available() bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.available()
}

func (h *Holder) available() bool {
	return h.compositor != 0 && h.shm != 0 && h.layerShell != 0 && h.opts.Seat.ID() != 0
}

// Hold maps the surface and takes the keyboard until Release, telling
// onVerb (once, on the connection's goroutine or a timer's, never
// blocking nor calling back into the holder) when the switcher should
// pick or cancel. mods are the modifiers the switcher is held by (ModifierMask).
// A hold already running keeps going, with the new mods and onVerb.
func (h *Holder) Hold(mods uint32, onVerb func(Verb)) error {
	if mods == 0 {
		return axerr.New(axerr.BadRequest, "no modifiers to hold")
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.hold != nil {
		h.hold.mods, h.hold.onVerb = mods, onVerb
		return nil
	}
	if !h.available() {
		return axerr.New(axerr.Unavailable, "the compositor offers no layer surfaces to hold the keyboard with")
	}
	c := h.s.Conn
	seatID := h.opts.Seat.ID()
	if h.keyboard == 0 || h.kbSeat != seatID {
		h.keyboard = c.NewObject(h.keyboardEvent)
		h.kbSeat = seatID
		if err := c.Send(seatID, opSeatGetKeyboard, wire.Uint(h.keyboard)); err != nil {
			return axerr.Wrap(axerr.Unavailable, err, "getting the keyboard")
		}
	}
	hd := &hold{mods: mods, onVerb: onVerb}
	hd.surface = c.NewObject(nil)
	c.Send(h.compositor, opCreateSurface, wire.Uint(hd.surface))
	// No input region: the pointer passes through
	region := c.NewObject(nil)
	c.Send(h.compositor, opCreateRegion, wire.Uint(region))
	c.Send(hd.surface, opSurfaceInputRegion, wire.Uint(region))
	c.Send(region, opRegionDestroy)
	c.Forget(region)
	hd.layer = c.NewObject(func(op uint16, a *wire.Args) { h.layerEvent(hd, op, a) })
	// Output 0: the compositor's choice (the focused one)
	c.Send(h.layerShell, opGetLayerSurface, wire.Uint(hd.layer), wire.Uint(hd.surface), wire.Uint(0), wire.Uint(layerOverlay), wire.String(Namespace))
	c.Send(hd.layer, opLayerSetSize, wire.Uint(1), wire.Uint(1))
	c.Send(hd.layer, opLayerSetAnchor, wire.Uint(anchorTopLeft))
	c.Send(hd.layer, opLayerSetKeyboard, wire.Uint(keyboardExclusive))
	if err := c.Send(hd.surface, opSurfaceCommit); err != nil {
		h.destroy(hd)
		return axerr.Wrap(axerr.Unavailable, err, "mapping the surface")
	}
	h.hold = hd
	return nil
}

// Release unmaps the surface, giving the keyboard back; nothing while
// none is held.
func (h *Holder) Release() {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.hold != nil {
		h.destroy(h.hold)
		h.hold = nil
	}
}

// Held reports whether a hold is running.
func (h *Holder) Held() bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.hold != nil
}

// destroy sends hd's destructors (h.mu held).
func (h *Holder) destroy(hd *hold) {
	c := h.s.Conn
	for _, o := range []struct {
		id uint32
		op uint16
	}{{hd.layer, opLayerDestroy}, {hd.surface, opSurfaceDestroy}, {hd.buffer, opBufferDestroy}, {hd.pool, opPoolDestroy}} {
		if o.id != 0 {
			c.Send(o.id, o.op)
			c.Forget(o.id)
		}
	}
	if hd.letGo != nil {
		hd.letGo.Stop()
	}
	hd.done = true
}

func (h *Holder) layerEvent(hd *hold, op uint16, a *wire.Args) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.hold != hd {
		return
	}
	switch op {
	case evLayerConfigure:
		serial := a.Uint()
		c := h.s.Conn
		c.Send(hd.layer, opLayerAck, wire.Uint(serial))
		if !hd.attached {
			if err := h.attach(hd); err != nil {
				return
			}
			hd.attached = true
		}
		c.Send(hd.surface, opSurfaceCommit)
	case evLayerClosed:
		// The compositor took it away (its output went): let go
		h.decide(hd, Cancel)
		h.destroy(hd)
		h.hold = nil
	}
}

// attach gives the surface its buffer: one clear pixel (h.mu held).
func (h *Holder) attach(hd *hold) error {
	f, err := wire.ShmFile("axiom-switcher-keys", 4)
	if err != nil {
		return err
	}
	defer f.Close()
	c := h.s.Conn
	hd.pool = c.NewObject(nil)
	c.Send(h.shm, opShmCreatePool, wire.Uint(hd.pool), wire.Fd(f), wire.Int(4))
	hd.buffer = c.NewObject(nil)
	c.Send(hd.pool, opPoolCreateBuffer, wire.Uint(hd.buffer), wire.Int(0), wire.Int(1), wire.Int(1), wire.Int(4), wire.Uint(formatARGB8888))
	c.Send(hd.surface, opSurfaceAttach, wire.Uint(hd.buffer), wire.Int(0), wire.Int(0))
	c.Send(hd.surface, opSurfaceDamage, wire.Int(0), wire.Int(0), wire.Int(1), wire.Int(1))
	return nil
}

func (h *Holder) keyboardEvent(op uint16, a *wire.Args) {
	if op == evKeymap {
		// Unused, but its fd must be taken
		a.Uint()
		if f, err := a.Fd(); err == nil {
			f.Close()
		}
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	hd := h.hold
	if hd == nil {
		return
	}
	switch op {
	case evEnter:
		a.Uint()
		if a.Uint() != hd.surface {
			return
		}
		// The modifiers event that follows says what's held
		hd.focused = true
		h.opts.Log.Debug("the switcher's keys held: the keyboard came", "mods", hd.mods)
	case evLeave:
		a.Uint()
		if a.Uint() == hd.surface {
			hd.focused = false
		}
	case evModifiers:
		if !hd.focused {
			return
		}
		a.Uint()
		depressed := a.Uint()
		h.opts.Log.Debug("the switcher's keys held: modifiers", "depressed", depressed)
		switch {
		case depressed&hd.mods == 0 && hd.letGo == nil:
			// Let go, before the surface had the keyboard or since: picks
			// if it lasts
			hd.letGo = time.AfterFunc(h.opts.Grace, func() {
				h.mu.Lock()
				defer h.mu.Unlock()
				if h.hold == hd {
					h.decide(hd, Commit)
				}
			})
		case depressed&hd.mods != 0 && hd.letGo != nil:
			// Held again: it was a blip
			hd.letGo.Stop()
			hd.letGo = nil
			h.opts.Log.Debug("the switcher's keys held: held again within the grace")
		}
	case evKey:
		if !hd.focused {
			return
		}
		a.Uint()
		a.Uint()
		key, state := a.Uint(), a.Uint()
		h.opts.Log.Debug("the switcher's keys held: a key", "key", key, "state", state)
		switch {
		case state == keyPressed && key == keyEsc:
			h.decide(hd, Cancel)
		case state == keyPressed && (key == keyEnter || key == keyKPEnter):
			h.decide(hd, Commit)
		}
	}
}

// decide tells hd's onVerb, once (h.mu held).
func (h *Holder) decide(hd *hold, v Verb) {
	if hd.done || hd.onVerb == nil {
		return
	}
	hd.done = true
	h.opts.Log.Debug("the switcher's keys held: decided", "verb", v)
	hd.onVerb(v)
}

// Interfaces (client.Client)
func (h *Holder) Interfaces() []string {
	return []string{ifaceCompositor, ifaceShm, ifaceLayerShell}
}

// Start (client.Client): a new connection, nothing of the old one left
func (h *Holder) Start(s *client.Session) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.s = s
	h.compositor, h.shm, h.layerShell = 0, 0, 0
	h.globals = map[uint32]*uint32{}
	h.keyboard, h.kbSeat = 0, 0
	if h.hold != nil {
		h.hold.done = true
		h.hold = nil
	}
}

// Global binds the compositor, shm and layer shell (client.Client).
func (h *Holder) Global(g client.Global) {
	h.mu.Lock()
	defer h.mu.Unlock()
	var field *uint32
	var version uint32
	switch g.Interface {
	case ifaceCompositor:
		field, version = &h.compositor, 4
	case ifaceShm:
		field, version = &h.shm, 1
	case ifaceLayerShell:
		field, version = &h.layerShell, 3
	default:
		return
	}
	if *field != 0 {
		return
	}
	id, _, err := h.s.Bind(g, version, nil)
	if err != nil {
		return
	}
	*field = id
	h.globals[g.Name] = field
}

// Removed drops a global (client.Client); a hold that needed it ends.
func (h *Holder) Removed(name uint32) {
	h.mu.Lock()
	defer h.mu.Unlock()
	field, ok := h.globals[name]
	if !ok {
		return
	}
	h.s.Conn.Forget(*field)
	*field = 0
	delete(h.globals, name)
	if h.hold != nil {
		h.decide(h.hold, Cancel)
		h.destroy(h.hold)
		h.hold = nil
	}
}

// Ready (client.Client)
func (h *Holder) Ready() {}
