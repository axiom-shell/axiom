// Package vkbd types text into the focused window over
// zwp_virtual_keyboard_v1, in place of wtype: a keyboard of its own for
// each text, with a keymap giving each character a key (keymap.go), each
// key pressed and released in turn, then the keyboard let go, so the
// user's own keymap is untouched.
package vkbd

import (
	"context"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/wayland/client"
	"github.com/axiom-shell/axiom/backend/internal/wayland/seat"
	"github.com/axiom-shell/axiom/backend/internal/wayland/wire"
)

// The interface and its opcodes (virtual-keyboard-unstable-v1.xml)
const (
	ifaceManager = "zwp_virtual_keyboard_manager_v1"

	opCreateKeyboard = 0 // create_virtual_keyboard(seat, id)
	opKeymap         = 0 // keymap(format, fd, size)
	opKey            = 1 // key(time, key, state)
	opModifiers      = 2 // modifiers(depressed, latched, locked, group)
	opDestroy        = 3
	formatXKBv1      = 1
	pressed          = 1
	released         = 0
)

// MaxText is the longest text Type takes, in characters.
const MaxText = 4096

// Options configure the keyboard.
type Options struct {
	Seat *seat.Tracker
	// OnChange is told when the compositor's manager comes or goes
	OnChange func()
	// Gap is the pause after each key event (wtype's pace; tests set 0)
	Gap time.Duration
}

// Keyboard types text; it is a client.Client.
type Keyboard struct {
	opts Options

	typing sync.Mutex // one text at a time

	mu      sync.Mutex
	s       *client.Session
	manager uint32
	global  uint32
}

// New returns a keyboard, ready once the compositor's manager is bound.
func New(opts Options) *Keyboard {
	return &Keyboard{opts: opts}
}

// Available reports whether the compositor offers virtual keyboards.
func (k *Keyboard) Available() bool {
	k.mu.Lock()
	defer k.mu.Unlock()
	return k.manager != 0
}

// Type types text into the focused window, returning once it's typed.
func (k *Keyboard) Type(ctx context.Context, text string) error {
	if n := len([]rune(text)); n > MaxText {
		return axerr.New(axerr.BadRequest, "a text of %d characters (at most %d)", n, MaxText)
	}
	chunks := Plan(text)
	if len(chunks) == 0 {
		return nil
	}
	k.typing.Lock()
	defer k.typing.Unlock()
	k.mu.Lock()
	s, manager := k.s, k.manager
	k.mu.Unlock()
	seatID := k.opts.Seat.ID()
	if manager == 0 || seatID == 0 {
		return axerr.New(axerr.Unavailable, "the compositor offers no virtual keyboard")
	}
	c := s.Conn
	kb := c.NewObject(nil)
	if err := c.Send(manager, opCreateKeyboard, wire.Uint(seatID), wire.Uint(kb)); err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "creating a virtual keyboard")
	}
	defer func() {
		// The last keys reach the window before the keyboard goes
		k.pause(ctx, 4)
		c.Send(kb, opDestroy)
		c.Forget(kb)
	}()
	start := time.Now()
	stamp := func() wire.Arg { return wire.Uint(uint32(time.Since(start).Milliseconds())) }
	for _, chunk := range chunks {
		f, err := wire.SealedFile("axiom-keymap", append([]byte(chunk.Keymap), 0))
		if err != nil {
			return err
		}
		err = c.Send(kb, opKeymap, wire.Uint(formatXKBv1), wire.Fd(f), wire.Uint(uint32(len(chunk.Keymap)+1)))
		f.Close()
		if err != nil {
			return axerr.Wrap(axerr.Unavailable, err, "sending the keymap")
		}
		c.Send(kb, opModifiers, wire.Uint(0), wire.Uint(0), wire.Uint(0), wire.Uint(0))
		// The keymap reaches the focused window before its keys
		if err := roundtrip(ctx, c); err != nil {
			return err
		}
		for _, key := range chunk.Keys {
			if err := c.Send(kb, opKey, stamp(), wire.Uint(key), wire.Uint(pressed)); err != nil {
				return axerr.Wrap(axerr.Unavailable, err, "typing")
			}
			k.pause(ctx, 1)
			c.Send(kb, opKey, stamp(), wire.Uint(key), wire.Uint(released))
			k.pause(ctx, 1)
			if ctx.Err() != nil {
				return ctx.Err()
			}
		}
	}
	return nil
}

func (k *Keyboard) pause(ctx context.Context, gaps int) {
	if k.opts.Gap <= 0 {
		return
	}
	select {
	case <-time.After(time.Duration(gaps) * k.opts.Gap):
	case <-ctx.Done():
	}
}

// roundtrip waits for the compositor to have handled every request sent.
func roundtrip(ctx context.Context, c *wire.Conn) error {
	done := make(chan struct{})
	if err := c.Sync(func() { close(done) }); err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "syncing with the compositor")
	}
	select {
	case <-done:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	case <-time.After(2 * time.Second):
		return axerr.New(axerr.Unavailable, "the compositor didn't answer")
	}
}

// Interfaces (client.Client)
func (k *Keyboard) Interfaces() []string { return []string{ifaceManager} }

// Start (client.Client)
func (k *Keyboard) Start(s *client.Session) {
	k.mu.Lock()
	k.s, k.manager, k.global = s, 0, 0
	k.mu.Unlock()
}

// Global binds the manager (client.Client).
func (k *Keyboard) Global(g client.Global) {
	k.mu.Lock()
	if k.manager != 0 {
		k.mu.Unlock()
		return
	}
	k.manager, _, _ = k.s.Bind(g, 1, nil)
	k.global = g.Name
	k.mu.Unlock()
	k.changed()
}

// Removed drops the manager (client.Client).
func (k *Keyboard) Removed(name uint32) {
	k.mu.Lock()
	if name != k.global {
		k.mu.Unlock()
		return
	}
	k.s.Conn.Forget(k.manager)
	k.manager, k.global = 0, 0
	k.mu.Unlock()
	k.changed()
}

// Ready (client.Client)
func (k *Keyboard) Ready() {}

func (k *Keyboard) changed() {
	if k.opts.OnChange != nil {
		k.opts.OnChange()
	}
}
