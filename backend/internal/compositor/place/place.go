// Package place gives the running compositor's windows a window rule's placement steps (windowrules.Step), turning each batch into that compositor's commands by window id (docs/dev/features/window-rules.md › Placement).
package place

import (
	"context"
	"strconv"

	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/windowrules"
)

// Options build a Dispatcher.
type Options struct {
	Getenv func(string) string
}

// backend is one compositor's side: its steps as commands, sent.
type backend interface {
	run(ctx context.Context, id string, steps []windowrules.Step) error
}

// Dispatcher sends steps to the compositor ipc.RunningFromEnv finds.
type Dispatcher struct {
	b backend
}

// New is the dispatcher for the compositor in o.Getenv, or nil when none.
// The compositor's kind isn't part of the API: what a plan may hold is the
// shell's capabilities.
func New(o Options) *Dispatcher {
	d := &Dispatcher{}
	r := ipc.RunningFromEnv(o.Getenv)
	switch {
	case r.Hypr != nil:
		d.b = hypr{r.Hypr}
	case r.Sway != nil:
		d.b = sway{r.Sway}
	case r.Niri != nil:
		d.b = niri{r.Niri}
	default:
		return nil
	}
	return d
}

// Run sends one batch of steps for window id in order, as one request where
// the compositor takes one (Hyprland, sway); every step is tried, and the
// failures come back joined.
func (d *Dispatcher) Run(ctx context.Context, id string, steps []windowrules.Step) error {
	if len(steps) == 0 {
		return nil
	}
	return d.b.run(ctx, id, steps)
}

// decimal is id as the number sway and niri give a window.
func decimal(id string) (uint64, error) {
	return strconv.ParseUint(id, 10, 64)
}
