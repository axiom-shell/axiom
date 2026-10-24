// Package outputs keeps the compositor's outputs (monitors) over the
// daemon's own Wayland connection: wl_output (v4 for its connector name
// and description) and xdg_output (the position and size in the
// compositor's layout), followed through hotplug. The daemon reads them
// where it names monitors by place (share.Monitors); the same
// connection carries what later needs an output (gamma, idle).
package outputs

import (
	"cmp"
	"context"
	"log/slog"
	"slices"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/wayland/wire"
)

// Output is one output as the compositor last described it.
type Output struct {
	Name        string `json:"name"` // the connector (DP-1), as Quickshell and the compositors name it
	Description string `json:"description"`
	Make        string `json:"make"`
	Model       string `json:"model"`
	// The output's place and size in the compositor's layout (logical
	// pixels: xdg_output, else wl_output's geometry and mode)
	X      int `json:"x"`
	Y      int `json:"y"`
	Width  int `json:"width"`
	Height int `json:"height"`
	Scale  int `json:"scale"`
}

// Interfaces and versions bound, and their opcodes (wayland.xml,
// xdg-output-unstable-v1.xml)
const (
	ifaceOutput      = "wl_output"
	ifaceXdgManager  = "zxdg_output_manager_v1"
	maxOutputVersion = 4 // name and description
	maxXdgVersion    = 3 // its done deprecated: wl_output.done commits it

	opOutputRelease     = 0 // since v3
	opXdgGetOutput      = 1 // get_xdg_output(id, output)
	opXdgOutputDestroy  = 0
	evOutputGeometry    = 0 // x, y, physical w, h, subpixel, make, model, transform
	evOutputMode        = 1 // flags, width, height, refresh
	evOutputDone        = 2
	evOutputScale       = 3
	evOutputName        = 4
	evOutputDescription = 5
	evXdgPosition       = 0
	evXdgSize           = 1
	evXdgDone           = 2
	modeCurrent         = 1
)

// Tracker holds the outputs; Run keeps them current.
type Tracker struct {
	log *slog.Logger

	mu sync.Mutex
	// ready once the first outputs were described: before, there is no
	// list to give
	ready   bool
	outputs map[uint32]*output // by global name
	onReady func()             // List's
}

type output struct {
	id, version uint32
	xdg         uint32 // its xdg_output, 0 without
	// pending is changed by events; current is it as of the last done
	pending, current Output
	described        bool // a done (or, before wl_output v2, any event) came
	xdgPlace         bool // xdg_output gave the position and size
}

// New returns a tracker with no outputs yet.
func New(log *slog.Logger) *Tracker {
	if log == nil {
		log = slog.New(slog.DiscardHandler)
	}
	return &Tracker{log: log, outputs: map[uint32]*output{}}
}

// Outputs are the outputs described so far, by place (left to right,
// then top to bottom), and whether the first roundtrip is done.
func (t *Tracker) Outputs() ([]Output, bool) {
	t.mu.Lock()
	defer t.mu.Unlock()
	var out []Output
	for _, o := range t.outputs {
		if o.described && o.current.Name != "" {
			out = append(out, o.current)
		}
	}
	slices.SortFunc(out, func(a, b Output) int {
		return cmp.Or(cmp.Compare(a.X, b.X), cmp.Compare(a.Y, b.Y), cmp.Compare(a.Name, b.Name))
	})
	return out, t.ready
}

// Names are the outputs' names by place; nil until they are known.
func (t *Tracker) Names() []string {
	outputs, ready := t.Outputs()
	if !ready {
		return nil
	}
	names := make([]string, 0, len(outputs))
	for _, o := range outputs {
		names = append(names, o.Name)
	}
	return names
}

// Run connects to the compositor at socket and follows its outputs until
// ctx ends (nil) or the connection does (wire.ErrGone when the
// compositor closed it).
func (t *Tracker) Run(ctx context.Context, socket string) error {
	c, err := wire.Dial(socket)
	if err != nil {
		return err
	}
	defer c.Close()
	t.mu.Lock()
	t.ready, t.outputs = false, map[uint32]*output{}
	t.mu.Unlock()
	var registry, manager uint32
	bindXdg := func(o *output) {
		o.xdg = c.NewObject(func(op uint16, a *wire.Args) { t.xdgEvent(o, op, a) })
		c.Send(manager, opXdgGetOutput, wire.Uint(o.xdg), wire.Uint(o.id))
	}
	registry, err = c.Registry(func(op uint16, a *wire.Args) {
		switch op {
		case wire.EvGlobal:
			name, iface, version := a.Uint(), a.String(), a.Uint()
			switch iface {
			case ifaceOutput:
				o := &output{version: min(version, maxOutputVersion)}
				o.id, _ = c.Bind(registry, name, iface, o.version, func(op uint16, a *wire.Args) { t.outputEvent(o, op, a) })
				t.mu.Lock()
				t.outputs[name] = o
				t.mu.Unlock()
				if manager != 0 {
					bindXdg(o)
				}
			case ifaceXdgManager:
				if manager != 0 {
					return
				}
				manager, _ = c.Bind(registry, name, iface, min(version, maxXdgVersion), nil)
				t.mu.Lock()
				existing := make([]*output, 0, len(t.outputs))
				for _, o := range t.outputs {
					existing = append(existing, o)
				}
				t.mu.Unlock()
				for _, o := range existing {
					bindXdg(o)
				}
			}
		case wire.EvGlobalRemove:
			name := a.Uint()
			t.mu.Lock()
			o := t.outputs[name]
			delete(t.outputs, name)
			t.mu.Unlock()
			if o == nil {
				return
			}
			if o.xdg != 0 {
				c.Send(o.xdg, opXdgOutputDestroy)
				c.Forget(o.xdg)
			}
			if o.version >= 3 {
				c.Send(o.id, opOutputRelease)
			}
			c.Forget(o.id)
			t.log.Debug("output removed", "name", o.current.Name)
		}
	})
	if err != nil {
		return err
	}
	// The first sync answers once the globals are listed (and bound); the
	// second once the bound outputs have described themselves
	err = c.Sync(func() {
		c.Sync(func() {
			t.mu.Lock()
			t.ready = true
			t.mu.Unlock()
			outputs, _ := t.Outputs()
			t.log.Debug("outputs", "outputs", outputs)
			if t.onReady != nil {
				t.onReady()
			}
		})
	})
	if err != nil {
		return err
	}
	return c.Run(ctx)
}

// List connects to the compositor at socket, reads its outputs (by
// place) and disconnects.
func List(socket string, timeout time.Duration) ([]Output, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	t := New(nil)
	t.onReady = cancel
	if err := t.Run(ctx, socket); err != nil {
		return nil, err
	}
	outputs, ready := t.Outputs()
	if !ready {
		return nil, axerr.New(axerr.Unavailable, "the compositor didn't describe its outputs within %s", timeout)
	}
	return outputs, nil
}

func (t *Tracker) outputEvent(o *output, op uint16, a *wire.Args) {
	t.mu.Lock()
	defer t.mu.Unlock()
	p := &o.pending
	switch op {
	case evOutputGeometry:
		x, y := a.Int(), a.Int()
		a.Int() // physical size
		a.Int()
		a.Int() // subpixel
		p.Make, p.Model = a.String(), a.String()
		if !o.xdgPlace {
			p.X, p.Y = int(x), int(y)
		}
	case evOutputMode:
		flags, w, h := a.Uint(), a.Int(), a.Int()
		if flags&modeCurrent != 0 && !o.xdgPlace {
			p.Width, p.Height = int(w), int(h)
		}
	case evOutputScale:
		p.Scale = int(a.Int())
	case evOutputName:
		p.Name = a.String()
	case evOutputDescription:
		p.Description = a.String()
	case evOutputDone:
		t.commit(o)
		return
	default:
		return
	}
	if o.version < 2 {
		// No done event: every event stands on its own
		t.commit(o)
	}
}

func (t *Tracker) xdgEvent(o *output, op uint16, a *wire.Args) {
	t.mu.Lock()
	defer t.mu.Unlock()
	p := &o.pending
	switch op {
	case evXdgPosition:
		p.X, p.Y = int(a.Int()), int(a.Int())
		o.xdgPlace = true
	case evXdgSize:
		p.Width, p.Height = int(a.Int()), int(a.Int())
		o.xdgPlace = true
	case evXdgDone:
		// Below v3 xdg_output commits its own state
		t.commit(o)
	}
}

// commit makes o's pending state its current; t.mu is held.
func (t *Tracker) commit(o *output) {
	if o.current != o.pending || !o.described {
		t.log.Debug("output", "output", o.pending)
	}
	o.current, o.described = o.pending, true
}
