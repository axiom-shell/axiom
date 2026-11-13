package place

import (
	"context"
	"fmt"
	"strconv"

	"errors"
	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/windowrules"
)

// niri is one action per step. niri answers Handled even for an id that no
// longer exists, so a failure is only a refused request.
type niri struct{ n *ipc.Niri }

func (b niri) run(ctx context.Context, id string, steps []windowrules.Step) error {
	actions, err := niriActions(id, steps)
	if err != nil {
		return err
	}
	var errs []error
	for _, a := range actions {
		if err := b.n.Action(ctx, a); err != nil {
			errs = append(errs, err)
		}
	}
	return errors.Join(errs...)
}

// niriActions are steps as niri actions for window id. A special workspace,
// maximize (a toggle), pin and the look have no by-id action: they aren't
// planned without their capabilities, and are skipped here.
func niriActions(id string, steps []windowrules.Step) ([]any, error) {
	n, err := decimal(id)
	if err != nil {
		return nil, fmt.Errorf("place: %q is not a niri window id", id)
	}
	var out []any
	act := func(name string, args map[string]any) { out = append(out, map[string]any{name: args}) }
	for _, s := range steps {
		switch s.Kind {
		case windowrules.StepOutput:
			act("MoveWindowToMonitor", map[string]any{"id": n, "output": s.Output})
		case windowrules.StepMove:
			if s.Special != "" {
				continue
			}
			ref := map[string]any{"Name": s.Workspace}
			if isDigits(s.Workspace) {
				idx, err := strconv.ParseUint(s.Workspace, 10, 8)
				if err != nil {
					continue
				}
				ref = map[string]any{"Index": idx}
			}
			act("MoveWindowToWorkspace", map[string]any{"window_id": n, "reference": ref, "focus": false})
		case windowrules.StepFloat:
			act("MoveWindowToFloating", map[string]any{"id": n})
		case windowrules.StepSize:
			act("SetWindowWidth", map[string]any{"id": n, "change": map[string]any{"SetFixed": s.Width}})
			act("SetWindowHeight", map[string]any{"id": n, "change": map[string]any{"SetFixed": s.Height}})
		case windowrules.StepCenter:
			act("CenterWindow", map[string]any{"id": n})
		case windowrules.StepFullscreen:
			// A toggle: Batches leaves it out when the window is fullscreen already
			act("FullscreenWindow", map[string]any{"id": n})
		case windowrules.StepFocus:
			act("FocusWindow", map[string]any{"id": n})
		}
	}
	return out, nil
}
