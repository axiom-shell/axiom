package outputs

import (
	"context"
	"errors"
	"slices"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"github.com/axiom-shell/axiom/backend/internal/wayland/wire"
	"github.com/axiom-shell/axiom/backend/internal/wayland/wire/wiretest"
)

// fakeOutput is how the fake describes one output: its wl_output
// geometry at gx, gy and its xdg_output place at x, y.
type fakeOutput struct {
	name     string
	gx, gy   int32
	x, y     int32
	w, h     int32
	scale    int32
	released bool
}

// fake is a compositor with outputs by global name; xdg says whether it
// offers zxdg_output_manager_v1.
type fake struct {
	*wiretest.Compositor
	mu      sync.Mutex
	outputs map[uint32]*fakeOutput
	bound   map[uint32]*fakeOutput // by object id
	manager uint32
}

func newFake(t *testing.T, xdg bool, outputs map[uint32]*fakeOutput) *fake {
	f := &fake{outputs: outputs, bound: map[uint32]*fakeOutput{}}
	var globals []wiretest.Global
	for name := range outputs {
		globals = append(globals, wiretest.Global{Name: name, Interface: "wl_output", Version: 4})
	}
	slices.SortFunc(globals, func(a, b wiretest.Global) int { return int(a.Name) - int(b.Name) })
	if xdg {
		globals = append(globals, wiretest.Global{Name: 100, Interface: "zxdg_output_manager_v1", Version: 3})
	}
	f.Compositor = wiretest.New(t, globals, f.request)
	return f
}

func (f *fake) request(c *wiretest.Compositor, r wiretest.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	switch {
	case r.Interface == "wl_output":
		id := r.Args.Uint()
		o := f.outputs[r.Global]
		f.bound[id] = o
		c.Send(id, evOutputGeometry, wire.Int(o.gx), wire.Int(o.gy), wire.Int(600), wire.Int(340), wire.Int(0),
			wire.String("Make"), wire.String("Model "+o.name), wire.Int(0))
		c.Send(id, evOutputMode, wire.Uint(modeCurrent), wire.Int(o.w), wire.Int(o.h), wire.Int(60000))
		c.Send(id, evOutputScale, wire.Int(o.scale))
		c.Send(id, evOutputName, wire.String(o.name))
		c.Send(id, evOutputDescription, wire.String("Make Model "+o.name))
		c.Send(id, evOutputDone)
	case r.Interface == "zxdg_output_manager_v1":
		f.manager = r.Args.Uint()
	case r.Object == f.manager && r.Opcode == opXdgGetOutput:
		xdg, out := r.Args.Uint(), r.Args.Uint()
		o := f.bound[out]
		c.Send(xdg, evXdgPosition, wire.Int(o.x), wire.Int(o.y))
		c.Send(xdg, evXdgSize, wire.Int(o.w/o.scale), wire.Int(o.h/o.scale))
		c.Send(out, evOutputDone)
	case r.Opcode == opOutputRelease && f.bound[r.Object] != nil:
		f.bound[r.Object].released = true
	}
}

func run(t *testing.T, f *fake) (*Tracker, chan error) {
	t.Helper()
	tr := New(nil)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- tr.Run(ctx, f.Socket) }()
	t.Cleanup(func() { cancel(); <-done })
	return tr, done
}

func waitNames(t *testing.T, tr *Tracker, want ...string) {
	t.Helper()
	if !testkit.Eventually(func() bool { got := tr.Names(); return got != nil && slices.Equal(got, want) }) {
		t.Fatalf("names %q, want %q", tr.Names(), want)
	}
}

func TestOutputsByPlace(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name string
		xdg  bool
		want []string
	}{
		// xdg_output's layout puts DP-1 right of HDMI-A-1, whatever
		// wl_output's geometry says
		{"xdg_output", true, []string{"HDMI-A-1", "DP-1"}},
		{"wl_output only", false, []string{"DP-1", "HDMI-A-1"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			f := newFake(t, tc.xdg, map[uint32]*fakeOutput{
				10: {name: "DP-1", gx: 0, x: 1920, w: 2560, h: 1440, scale: 2},
				11: {name: "HDMI-A-1", gx: 2560, x: 0, w: 1920, h: 1080, scale: 1},
			})
			tr, _ := run(t, f)
			waitNames(t, tr, tc.want...)
			outputs, _ := tr.Outputs()
			var dp Output
			for _, o := range outputs {
				if o.Name == "DP-1" {
					dp = o
				}
			}
			want := Output{Name: "DP-1", Description: "Make Model DP-1", Make: "Make", Model: "Model DP-1", X: 0, Width: 2560, Height: 1440, Scale: 2}
			if tc.xdg {
				want.X, want.Width, want.Height = 1920, 1280, 720
			}
			if dp != want {
				t.Errorf("DP-1 %+v, want %+v", dp, want)
			}
		})
	}
}

func TestList(t *testing.T) {
	t.Parallel()
	f := newFake(t, true, map[uint32]*fakeOutput{10: {name: "DP-1", w: 1920, h: 1080, scale: 1}})
	outputs, err := List(f.Socket, 5*time.Second)
	if err != nil || len(outputs) != 1 || outputs[0].Name != "DP-1" {
		t.Errorf("List: %+v %v", outputs, err)
	}
}

func TestHotplug(t *testing.T) {
	t.Parallel()
	dp := &fakeOutput{name: "DP-1", x: 0, w: 1920, h: 1080, scale: 1}
	f := newFake(t, true, map[uint32]*fakeOutput{10: dp})
	tr, _ := run(t, f)
	waitNames(t, tr, "DP-1")
	f.mu.Lock()
	f.outputs[11] = &fakeOutput{name: "DP-2", x: 1920, w: 1920, h: 1080, scale: 1}
	f.mu.Unlock()
	f.AddGlobal(wiretest.Global{Name: 11, Interface: "wl_output", Version: 4})
	waitNames(t, tr, "DP-1", "DP-2")
	f.RemoveGlobal(10)
	waitNames(t, tr, "DP-2")
	if !testkit.Eventually(func() bool { f.mu.Lock(); defer f.mu.Unlock(); return dp.released }) {
		t.Fatal("the removed output wasn't released")
	}
}

func TestNoNamesBeforeTheyAreKnown(t *testing.T) {
	t.Parallel()
	if names := New(nil).Names(); names != nil {
		t.Errorf("names %q before any roundtrip", names)
	}
	// No outputs at all is known, and empty: not nil
	f := newFake(t, true, map[uint32]*fakeOutput{})
	tr, _ := run(t, f)
	if !testkit.Eventually(func() bool { return tr.Names() != nil }) {
		t.Fatal("never ready")
	}
}

func TestNoNamesWhileAnOutputHasNone(t *testing.T) {
	t.Parallel()
	f := newFake(t, true, map[uint32]*fakeOutput{
		1: {name: "DP-1", w: 1920, h: 1080, scale: 1},
		2: {name: "", x: 1920, w: 1920, h: 1080, scale: 1},
	})
	tr, _ := run(t, f)
	if !testkit.Eventually(func() bool { _, ready := tr.Outputs(); return ready }) {
		t.Fatal("never ready")
	}
	if names := tr.Names(); names != nil {
		t.Errorf("names %q with an output unnamed, want nil", names)
	}
}

func TestRunEndsWithTheCompositor(t *testing.T) {
	t.Parallel()
	f := newFake(t, true, map[uint32]*fakeOutput{10: {name: "DP-1", w: 1, h: 1, scale: 1}})
	tr, done := run(t, f)
	waitNames(t, tr, "DP-1")
	f.Close()
	select {
	case err := <-done:
		if !errors.Is(err, wire.ErrGone) {
			t.Errorf("Run returned %v, want ErrGone", err)
		}
		done <- err // for the cleanup
	case <-time.After(testkit.Bound(5 * time.Second)):
		t.Fatal("Run didn't end with the compositor")
	}
}
