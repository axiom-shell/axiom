package place

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"slices"
	"strconv"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/windowrules"
)

// sway is one `[con_id=N] …` command list.
type sway struct{ s *ipc.Sway }

func (b sway) run(ctx context.Context, id string, steps []windowrules.Step) error {
	var marks []string
	if slices.ContainsFunc(steps, func(s windowrules.Step) bool { return s.Kind == windowrules.StepMove && s.Special != "" }) {
		if tree, err := b.s.Tree(ctx); err == nil {
			marks = specialMarks(tree, id)
		}
	}
	cmds, err := swayCommands(id, steps, marks)
	if err != nil || cmds == "" {
		return err
	}
	results, err := b.s.Run(ctx, cmds)
	if err != nil {
		return err
	}
	var errs []error
	for _, r := range results {
		if !r.Success {
			errs = append(errs, errors.New(r.Error))
		}
	}
	return errors.Join(errs...)
}

// specialMark matches the mark SwayState.specialGroup reads: the group is the
// name up to the last "-", then the con id.
var specialMark = regexp.MustCompile(`^axiom-special-(.+)-[^-]+$`)

// specialMarks are the special-group marks container id carries in tree.
func specialMarks(tree json.RawMessage, id string) []string {
	var found []string
	var walk func(n map[string]json.RawMessage)
	walk = func(n map[string]json.RawMessage) {
		var nid json.Number
		if json.Unmarshal(n["id"], &nid) == nil && nid.String() == id {
			var marks []string
			_ = json.Unmarshal(n["marks"], &marks)
			for _, m := range marks {
				if specialMark.MatchString(m) {
					found = append(found, m)
				}
			}
			return
		}
		for _, key := range []string{"nodes", "floating_nodes"} {
			var kids []map[string]json.RawMessage
			_ = json.Unmarshal(n[key], &kids)
			for _, k := range kids {
				walk(k)
			}
		}
	}
	var root map[string]json.RawMessage
	if json.Unmarshal(tree, &root) == nil {
		walk(root)
	}
	return found
}

// swayCommands are steps as the command list for window id; "" when none
// does anything. marks are the special-group marks it carries: a move into a
// group first drops them, so it is in one group at a time.
func swayCommands(id string, steps []windowrules.Step, marks []string) (string, error) {
	n, err := decimal(id)
	if err != nil {
		return "", fmt.Errorf("place: %q is not a sway container id", id)
	}
	con := "[con_id=" + strconv.FormatUint(n, 10) + "] "
	var cmds []string
	add := func(cmd ...string) {
		for _, c := range cmd {
			cmds = append(cmds, con+c)
		}
	}
	for _, m := range marks {
		add("unmark " + render.SwayQuote(m))
	}
	for _, s := range steps {
		switch s.Kind {
		case windowrules.StepOutput:
			add("move container to output " + render.SwayQuote(s.Output))
		case windowrules.StepMove:
			switch {
			case s.Special != "":
				// The mark SwayState.specialMove writes: the group is the name up to the last "-"
				add("mark --add "+render.SwayQuote("axiom-special-"+s.Special+"-"+id), "move scratchpad")
				if s.Show {
					add("scratchpad show")
				}
			case isDigits(s.Workspace):
				add("move container to workspace number " + s.Workspace)
			default:
				add("move container to workspace " + render.SwayQuote(s.Workspace))
			}
		case windowrules.StepFloat:
			add("floating enable")
		case windowrules.StepSize:
			add(fmt.Sprintf("resize set %d px %d px", s.Width, s.Height))
		case windowrules.StepCenter:
			add("move position center")
		case windowrules.StepFullscreen:
			add("fullscreen enable")
		case windowrules.StepPin:
			add("sticky enable")
		case windowrules.StepLook:
			// opacity and blur are the engine's look (State.look)
			if s.Tearing {
				add("allow_tearing yes")
			}
		case windowrules.StepFocus:
			add("focus")
		}
	}
	return strings.Join(cmds, "; "), nil
}
