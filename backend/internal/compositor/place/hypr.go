package place

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/windowrules"
)

// hypr is one Lua chunk by window address: every step runs in its own pcall,
// the errors are raised together at the end (as HyprlandManager._luaPrelude).
type hypr struct{ h *ipc.Hypr }

const hyprPrelude = `local errs = {}
local function run(f)
  local ok, e = pcall(function() hl.dispatch(f()) end)
  if not ok then errs[#errs + 1] = tostring(e) end
end
`

const hyprEpilogue = `
if #errs > 0 then error(table.concat(errs, "; ")) end`

var hyprAddress = regexp.MustCompile(`^0x[0-9a-f]+$`)

func (b hypr) run(ctx context.Context, id string, steps []windowrules.Step) error {
	lua, err := hyprChunk(id, steps)
	if err != nil {
		return err
	}
	reply, err := b.h.Eval(ctx, lua)
	if err != nil {
		return err
	}
	if reply != "" {
		return errors.New(reply)
	}
	return nil
}

// hyprChunk is the Lua chunk running steps on window id.
func hyprChunk(id string, steps []windowrules.Step) (string, error) {
	if !hyprAddress.MatchString(id) {
		return "", fmt.Errorf("place: %q is not a Hyprland window address", id)
	}
	w := "window = " + render.LuaString("address:"+id)
	var lines []string
	add := func(dispatch string) {
		lines = append(lines, "run(function() return "+dispatch+" end)")
	}
	for _, s := range steps {
		switch s.Kind {
		case windowrules.StepOutput:
			add("hl.dsp.window.move({ monitor = " + render.LuaString(s.Output) + ", " + w + " })")
		case windowrules.StepMove:
			ws, follow := "name:"+s.Workspace, false
			switch {
			case s.Special != "":
				ws, follow = "special:"+s.Special, s.Show
			case isDigits(s.Workspace):
				ws = s.Workspace
			}
			add(fmt.Sprintf("hl.dsp.window.move({ workspace = %s, follow = %t, %s })", render.LuaString(ws), follow, w))
		case windowrules.StepFloat:
			add(`hl.dsp.window.float({ action = "enable", ` + w + ` })`)
		case windowrules.StepSize:
			add(fmt.Sprintf("hl.dsp.window.resize({ x = %d, y = %d, %s })", s.Width, s.Height, w))
		case windowrules.StepCenter:
			add("hl.dsp.window.center({ " + w + " })")
		case windowrules.StepFullscreen:
			add(`hl.dsp.window.fullscreen({ action = "set", ` + w + ` })`)
		case windowrules.StepMaximize:
			add(`hl.dsp.window.fullscreen({ mode = "maximized", action = "set", ` + w + ` })`)
		case windowrules.StepPin:
			add(`hl.dsp.window.pin({ action = "enable", ` + w + ` })`)
		case windowrules.StepLook:
			for _, rule := range s.Rules {
				add(`hl.dsp.window.tag({ tag = ` + render.LuaString("+"+render.HyprTag(rule)) + ", " + w + " })")
			}
		case windowrules.StepFocus:
			add("hl.dsp.focus({ " + w + " })")
		}
	}
	if len(lines) == 0 {
		return "", nil
	}
	return hyprPrelude + strings.Join(lines, "\n") + hyprEpilogue, nil
}
