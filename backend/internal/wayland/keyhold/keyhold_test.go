package keyhold

import (
	"context"
	"encoding/binary"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"github.com/axiom-shell/axiom/backend/internal/wayland/client"
	"github.com/axiom-shell/axiom/backend/internal/wayland/seat"
	"github.com/axiom-shell/axiom/backend/internal/wayland/wire"
	"github.com/axiom-shell/axiom/backend/internal/wayland/wire/wiretest"
)

// fake is a compositor offering what a hold needs, recording what was
// asked of it.
type fake struct {
	*wiretest.Compositor

	mu                                    sync.Mutex
	seat, compositor, shm, layerShell     uint32
	surface, layer, keyboard              uint32
	namespace                             string
	layerLevel, keyboardMode, ackedSerial uint32
	attached, layerGone, surfaceGone      bool
}

func newFake(t *testing.T) *fake {
	f := &fake{}
	f.Compositor = wiretest.New(t, []wiretest.Global{
		{Name: 1, Interface: "wl_seat", Version: 7},
		{Name: 2, Interface: ifaceCompositor, Version: 6},
		{Name: 3, Interface: ifaceShm, Version: 1},
		{Name: 4, Interface: ifaceLayerShell, Version: 4},
	}, f.request)
	return f
}

func (f *fake) request(c *wiretest.Compositor, r wiretest.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	switch {
	case r.Interface == "wl_seat":
		f.seat = r.Args.Uint()
	case r.Interface == ifaceCompositor:
		f.compositor = r.Args.Uint()
	case r.Interface == ifaceShm:
		f.shm = r.Args.Uint()
	case r.Interface == ifaceLayerShell:
		f.layerShell = r.Args.Uint()
	case r.Interface != "":
	case r.Object == f.seat && r.Opcode == opSeatGetKeyboard:
		f.keyboard = r.Args.Uint()
	case r.Object == f.compositor && r.Opcode == opCreateSurface:
		f.surface = r.Args.Uint()
	case r.Object == f.shm && r.Opcode == opShmCreatePool:
		r.Args.Uint()
		if fd, err := r.Args.Fd(); err == nil {
			fd.Close()
		}
	case r.Object == f.layerShell && r.Opcode == opGetLayerSurface:
		f.layer = r.Args.Uint()
		r.Args.Uint() // surface
		r.Args.Uint() // output
		f.layerLevel = r.Args.Uint()
		f.namespace = r.Args.String()
	case r.Object == f.layer && r.Opcode == opLayerSetKeyboard:
		f.keyboardMode = r.Args.Uint()
	case r.Object == f.layer && r.Opcode == opLayerAck:
		f.ackedSerial = r.Args.Uint()
	case r.Object == f.layer && r.Opcode == opLayerDestroy:
		f.layerGone = true
	case r.Object == f.surface && r.Opcode == opSurfaceAttach:
		f.attached = r.Args.Uint() != 0
	case r.Object == f.surface && r.Opcode == opSurfaceDestroy:
		f.surfaceGone = true
	case r.Object == f.surface && r.Opcode == opSurfaceCommit && f.ackedSerial == 0 && f.layer != 0:
		// The first commit: the compositor configures it
		layer := f.layer
		go c.Send(layer, evLayerConfigure, wire.Uint(7), wire.Uint(1), wire.Uint(1))
	}
}

func (f *fake) state() fake {
	f.mu.Lock()
	defer f.mu.Unlock()
	return fake{seat: f.seat, surface: f.surface, layer: f.layer, keyboard: f.keyboard, namespace: f.namespace, layerLevel: f.layerLevel, keyboardMode: f.keyboardMode, ackedSerial: f.ackedSerial, attached: f.attached, layerGone: f.layerGone, surfaceGone: f.surfaceGone}
}

func keysArray(keys ...uint32) wire.Arg {
	b := make([]byte, 4*len(keys))
	for i, k := range keys {
		binary.LittleEndian.PutUint32(b[4*i:], k)
	}
	return wire.Array(b)
}

const (
	keyCtrl = 29
	keyTab  = 15
	// The mask bits
	ctrl  = 1 << 2
	shift = 1 << 0
)

// step is a keyboard event the test sends: an enter with the keys down,
// the modifiers held, or a key pressed or let go
type step struct {
	enter   bool
	keys    []uint32
	mods    bool
	held    uint32
	key     uint32
	pressed bool
	// wait outlasts the grace
	wait bool
}

func TestHold(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name  string
		steps []step
		want  Verb
	}{
		{"let go before the keyboard came", []step{{enter: true}, {mods: true}}, Commit},
		{"let go after", []step{{enter: true, keys: []uint32{keyCtrl}}, {mods: true, held: ctrl}, {key: keyCtrl}, {mods: true}}, Commit},
		{"other keys and modifiers wait", []step{{enter: true, keys: []uint32{keyCtrl, keyTab}}, {mods: true, held: ctrl}, {key: keyTab}, {key: keyTab, pressed: true}, {mods: true, held: ctrl | shift}, {mods: true, held: ctrl}, {mods: true}}, Commit},
		// A keyboard of several devices: sway reports the held Ctrl
		// let go and leaves it out of enter, while its mask holds it
		{"the mask, not the keys", []step{{enter: true}, {mods: true, held: ctrl}, {key: keyCtrl}, {key: keyEsc, pressed: true}}, Cancel},
		// A keyboard's blip: Ctrl reported up for a moment around Tab
		{"a blip isn't a let go", []step{{enter: true}, {mods: true, held: ctrl}, {mods: true}, {mods: true, held: ctrl}, {wait: true}, {key: keyEsc, pressed: true}}, Cancel},
		{"a blip on arrival", []step{{enter: true}, {mods: true}, {mods: true, held: ctrl}, {wait: true}, {key: keyEsc, pressed: true}}, Cancel},
		{"escape cancels", []step{{enter: true, keys: []uint32{keyCtrl}}, {mods: true, held: ctrl}, {key: keyEsc, pressed: true}}, Cancel},
		{"return picks", []step{{enter: true, keys: []uint32{keyCtrl}}, {mods: true, held: ctrl}, {key: keyEnter, pressed: true}}, Commit},
		{"only once", []step{{enter: true}, {mods: true, held: ctrl}, {key: keyEsc, pressed: true}, {mods: true}}, Cancel},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			f := newFake(t)
			st := seat.New()
			// Long enough that the blips' two reports land within it
			// however slow the runner
			grace := testkit.Bound(200 * time.Millisecond)
			h := New(Options{Seat: st, Grace: grace})
			ctx, cancel := context.WithCancel(context.Background())
			done := make(chan error, 1)
			go func() { done <- client.Run(ctx, f.Socket, st, h) }()
			t.Cleanup(func() { cancel(); <-done })
			if !testkit.Eventually(h.Available) {
				t.Fatal("not bound")
			}

			mods, err := ModifierMask([]string{"ctrl"})
			if err != nil {
				t.Fatal(err)
			}
			verbs := make(chan Verb, 4)
			if err := h.Hold(mods, func(v Verb) { verbs <- v }); err != nil {
				t.Fatal(err)
			}
			if !testkit.Eventually(func() bool { s := f.state(); return s.ackedSerial == 7 && s.attached && s.keyboard != 0 }) {
				t.Fatalf("not configured: %+v", f.state())
			}
			s := f.state()
			if s.namespace != Namespace || s.layerLevel != layerOverlay || s.keyboardMode != keyboardExclusive {
				t.Errorf("layer surface %q on layer %d, keyboard %d", s.namespace, s.layerLevel, s.keyboardMode)
			}
			// A keymap first, whose fd must be taken
			km, err := wire.ShmFile("keymap", 8)
			if err != nil {
				t.Fatal(err)
			}
			f.Send(s.keyboard, evKeymap, wire.Uint(1), wire.Fd(km), wire.Uint(8))
			km.Close()
			for _, e := range tc.steps {
				if e.enter {
					f.Send(s.keyboard, evEnter, wire.Uint(1), wire.Uint(s.surface), keysArray(e.keys...))
					continue
				}
				if e.wait {
					time.Sleep(2 * grace)
					continue
				}
				if e.mods {
					f.Send(s.keyboard, evModifiers, wire.Uint(1), wire.Uint(e.held), wire.Uint(0), wire.Uint(0), wire.Uint(0))
					continue
				}
				state := uint32(0)
				if e.pressed {
					state = keyPressed
				}
				f.Send(s.keyboard, evKey, wire.Uint(2), wire.Uint(0), wire.Uint(e.key), wire.Uint(state))
			}
			select {
			case v := <-verbs:
				if v != tc.want {
					t.Errorf("got %s, want %s", v, tc.want)
				}
			case <-time.After(testkit.Bound(3 * time.Second)):
				t.Fatal("no verb")
			}
			// Nothing more: one verb per hold
			f.Send(s.keyboard, evModifiers, wire.Uint(3), wire.Uint(0), wire.Uint(0), wire.Uint(0), wire.Uint(0))
			select {
			case v := <-verbs:
				t.Errorf("a second verb: %s", v)
			case <-time.After(50 * time.Millisecond):
			}

			h.Release()
			if h.Held() {
				t.Error("still held")
			}
			if !testkit.Eventually(func() bool { s := f.state(); return s.layerGone && s.surfaceGone }) {
				t.Errorf("not unmapped: %+v", f.state())
			}
		})
	}
}

func TestHoldBeforeTheKeyboardIsntFocused(t *testing.T) {
	t.Parallel()
	f := newFake(t)
	st := seat.New()
	h := New(Options{Seat: st})
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- client.Run(ctx, f.Socket, st, h) }()
	t.Cleanup(func() { cancel(); <-done })
	if !testkit.Eventually(h.Available) {
		t.Fatal("not bound")
	}
	verbs := make(chan Verb, 1)
	if err := h.Hold(ctrl, func(v Verb) { verbs <- v }); err != nil {
		t.Fatal(err)
	}
	if !testkit.Eventually(func() bool { return f.state().keyboard != 0 }) {
		t.Fatal("no keyboard")
	}
	// Modifiers while another surface has the keyboard: not ours
	f.Send(f.state().keyboard, evModifiers, wire.Uint(1), wire.Uint(0), wire.Uint(0), wire.Uint(0), wire.Uint(0))
	select {
	case v := <-verbs:
		t.Errorf("decided %s without the keyboard", v)
	case <-time.After(50 * time.Millisecond):
	}
}

func TestModifierMask(t *testing.T) {
	t.Parallel()
	mask, err := ModifierMask([]string{"SUPER", "ctrl", "Alt"})
	if err != nil || mask != 1<<6|1<<2|1<<3 {
		t.Errorf("got %b, %v", mask, err)
	}
	if _, err := ModifierMask([]string{"HYPER"}); err == nil {
		t.Error("an unknown modifier was taken")
	}
}

func TestHoldWithoutTheProtocols(t *testing.T) {
	t.Parallel()
	h := New(Options{Seat: seat.New()})
	if err := h.Hold(ctrl, nil); err == nil {
		t.Error("held without a compositor")
	}
}
