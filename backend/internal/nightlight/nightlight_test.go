package nightlight

import (
	"context"
	"encoding/binary"
	"io"
	"math"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"github.com/axiom-shell/axiom/backend/internal/wayland/client"
	"github.com/axiom-shell/axiom/backend/internal/wayland/ctm"
	"github.com/axiom-shell/axiom/backend/internal/wayland/gamma"
	"github.com/axiom-shell/axiom/backend/internal/wayland/outputs"
	"github.com/axiom-shell/axiom/backend/internal/wayland/wire"
	"github.com/axiom-shell/axiom/backend/internal/wayland/wire/wiretest"
)

func near(a, b float64) bool { return math.Abs(a-b) < 1e-9 }

func TestWhitepoint(t *testing.T) {
	t.Parallel()
	if r, g, b := Whitepoint(Neutral, 1); !near(r, 1) || !near(g, 1) || !near(b, 1) {
		t.Errorf("6500 K: %v %v %v", r, g, b)
	}
	r, g, b := Whitepoint(4500, 1)
	if !near(r, 1) || !(g < 1 && b < g) {
		t.Errorf("4500 K: %v %v %v", r, g, b)
	}
	if r, g, b := Whitepoint(1000, 1); !near(r, 1) || g > 0.3 || b != 0 {
		t.Errorf("1000 K: %v %v %v", r, g, b)
	}
	// Above neutral nothing gets brighter than the screen's own
	if r, g, b := Whitepoint(10000, 1); r > 1 || g > 1 || b > 1 {
		t.Errorf("10000 K: %v %v %v", r, g, b)
	}
	hr, hg, hb := Whitepoint(4500, 0.5)
	if !near(hr, r/2) || !near(hg, g/2) || !near(hb, b/2) {
		t.Errorf("half brightness: %v %v %v", hr, hg, hb)
	}
}

func TestRamps(t *testing.T) {
	t.Parallel()
	got := Ramps(3, 1, 0.5, 0)
	want := []uint16{0, 32768, 65535, 0, 16384, 32768, 0, 0, 0}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("got %v, want %v", got, want)
		}
	}
	if m := Matrix(0.9, 0.8, 0.7); m[0] != 0.9 || m[4] != 0.8 || m[8] != 0.7 || m[1] != 0 {
		t.Errorf("matrix %v", m)
	}
}

// fake is a compositor with two outputs and either protocol.
type fake struct {
	*wiretest.Compositor
	kind     string // "ctm" | "gamma"
	mu       sync.Mutex
	outputs  map[uint32]bool // bound wl_output objects
	manager  uint32
	controls map[uint32]uint32 // gamma control → output
	got      chan string
	ramps    chan []uint16
	matrices chan []float64
}

func newFake(t *testing.T, kind string) *fake {
	iface := map[string]string{"ctm": "hyprland_ctm_control_manager_v1", "gamma": "zwlr_gamma_control_manager_v1"}[kind]
	f := &fake{kind: kind, outputs: map[uint32]bool{}, controls: map[uint32]uint32{}, got: make(chan string, 64), ramps: make(chan []uint16, 8), matrices: make(chan []float64, 8)}
	f.Compositor = wiretest.New(t, []wiretest.Global{
		{Name: 1, Interface: "wl_output", Version: 4},
		{Name: 2, Interface: "wl_output", Version: 4},
		{Name: 3, Interface: iface, Version: 2},
	}, f.request)
	return f
}

func (f *fake) request(c *wiretest.Compositor, r wiretest.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	switch {
	case r.Interface == "wl_output":
		f.outputs[r.Args.Uint()] = true
	case r.Interface != "":
		f.manager = r.Args.Uint()
		f.got <- "bind"
	case r.Object == f.manager:
		f.managerRequest(c, r)
	default:
		if _, ok := f.controls[r.Object]; ok {
			switch r.Opcode {
			case 0: // set_gamma
				fd, err := r.Args.Fd()
				if err != nil {
					return
				}
				data, _ := io.ReadAll(fd)
				fd.Close()
				ramps := make([]uint16, len(data)/2)
				for i := range ramps {
					ramps[i] = binary.LittleEndian.Uint16(data[2*i:])
				}
				f.ramps <- ramps
			case 1:
				delete(f.controls, r.Object)
				f.got <- "control destroy"
			}
		}
	}
}

func (f *fake) managerRequest(c *wiretest.Compositor, r wiretest.Request) {
	switch f.kind {
	case "ctm":
		switch r.Opcode {
		case 0: // set_ctm_for_output
			out := r.Args.Uint()
			if !f.outputs[out] {
				panic("not an output")
			}
			m := make([]float64, 9)
			for i := range m {
				m[i] = r.Args.Fixed()
			}
			f.matrices <- m
		case 1:
			f.got <- "commit"
		case 2:
			f.got <- "destroy"
		}
	case "gamma":
		if r.Opcode == 0 { // get_gamma_control
			id, out := r.Args.Uint(), r.Args.Uint()
			f.controls[id] = out
			f.got <- "control"
			c.Send(id, 0, wire.Uint(4)) // gamma_size
		}
	}
}

func run(t *testing.T, f *fake) (*Service, chan State) {
	t.Helper()
	tr := outputs.New(nil)
	states := make(chan State, 32)
	var svc *Service
	changed := func() {
		if svc != nil {
			svc.Changed()
		}
	}
	c := ctm.New(ctm.Options{Outputs: tr, OnChange: changed})
	g := gamma.New(gamma.Options{Outputs: tr, OnChange: changed})
	svc = New(Options{CTM: c, Gamma: g, OnState: func(s State) { states <- s }})
	// After theirs: told once the controls have applied too
	described := make(chan struct{}, 8)
	tr.OnChange(func() { described <- struct{}{} })
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- client.Run(ctx, f.Socket, tr, c, g) }()
	t.Cleanup(func() { cancel(); <-done })
	// The first outputs described: past the tracker's Ready, which applies
	// again
	next(t, described)
	return svc, states
}

func next[T any](t *testing.T, ch chan T) T {
	t.Helper()
	select {
	case v := <-ch:
		return v
	case <-time.After(testkit.Bound(3 * time.Second)):
		t.Fatal("timed out")
	}
	var zero T
	return zero
}

func until(t *testing.T, states chan State, cond func(State) bool) State {
	t.Helper()
	for {
		if s := next(t, states); cond(s) {
			return s
		}
	}
}

func TestCTM(t *testing.T) {
	t.Parallel()
	f := newFake(t, "ctm")
	svc, states := run(t, f)
	until(t, states, func(s State) bool { return s.Mode == ModeCTM })
	svc.Set(Settings{On: true, Temperature: 4500, Gamma: 100})
	if got := next(t, f.got); got != "bind" {
		t.Fatalf("got %s", got)
	}
	r, g, _ := Whitepoint(4500, 1)
	for range 2 {
		m := next(t, f.matrices)
		if math.Abs(m[0]-r) > 1.0/256 || math.Abs(m[4]-g) > 1.0/256 || m[1] != 0 {
			t.Errorf("matrix %v", m)
		}
	}
	if got := next(t, f.got); got != "commit" {
		t.Errorf("got %s", got)
	}
	// Off: the identity, then the manager let go
	svc.Set(Settings{On: false, Temperature: 4500, Gamma: 100})
	for range 2 {
		if m := next(t, f.matrices); m[0] != 1 || m[4] != 1 || m[8] != 1 {
			t.Errorf("identity %v", m)
		}
	}
	if a, b := next(t, f.got), next(t, f.got); a != "commit" || b != "destroy" {
		t.Errorf("got %s, %s", a, b)
	}
	// Another client took it
	svc.Set(Settings{On: true, Temperature: 3000, Gamma: 80})
	next(t, f.got)
	f.mu.Lock()
	manager := f.manager
	f.mu.Unlock()
	f.Send(manager, 0) // blocked
	until(t, states, func(s State) bool { return s.Blocked })
}

func TestGamma(t *testing.T) {
	t.Parallel()
	f := newFake(t, "gamma")
	svc, states := run(t, f)
	next(t, f.got) // the manager, bound as offered
	until(t, states, func(s State) bool { return s.Mode == ModeGamma })
	svc.Set(Settings{On: true, Temperature: 4500, Gamma: 50})
	r, g, b := Whitepoint(4500, 0.5)
	want := Ramps(4, r, g, b)
	for range 2 {
		if got := next(t, f.got); got != "control" {
			t.Fatalf("got %s", got)
		}
	}
	for range 2 {
		got := next(t, f.ramps)
		if len(got) != 12 || got[3] != want[3] || got[7] != want[7] || got[11] != want[11] {
			t.Errorf("ramps %v, want %v", got, want)
		}
	}
	// Another value: the same controls, new ramps
	svc.Set(Settings{On: true, Temperature: 3000, Gamma: 100})
	next(t, f.ramps)
	next(t, f.ramps)
	// Off: every output's own back
	svc.Set(Settings{On: false, Temperature: 3000, Gamma: 100})
	for range 2 {
		if got := next(t, f.got); got != "control destroy" {
			t.Errorf("got %s", got)
		}
	}
	// Taken by another client
	svc.Set(Settings{On: true, Temperature: 3000, Gamma: 100})
	next(t, f.got)
	next(t, f.got)
	f.mu.Lock()
	var control uint32
	for id := range f.controls {
		control = id
	}
	f.mu.Unlock()
	f.Send(control, 1) // failed
	if s := until(t, states, func(s State) bool { return s.Blocked }); s.Mode != ModeGamma {
		t.Errorf("state %+v", s)
	}
}
