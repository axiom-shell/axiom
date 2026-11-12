package steps

import (
	"fmt"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/specialid"
)

// v108: scratchpads became special workspaces.
//   - Workspaces.scratchpads (entries `{id, name, icon, text}`) became
//     Workspaces.specialWorkspaces (`{id, icon, text}`, the id the entry's
//     name made valid). Only when the new key isn't a list already (v107
//     dropped the old sway string). Entries with an empty or unusable name
//     are dropped, the first of a duplicated id wins, non-objects go.
//   - A special workspace's name that isn't a valid id (specialid.Valid) is
//     rewritten the same way in the keybinds (and their saved presets) and
//     hot corners that toggle or move to one. An empty or unusable argument
//     stays as it is.
//   - The Workspaces widget's scratchpads, scratchpadLabel and
//     scratchpadSplit became specialWorkspaces, specialWorkspaceLabel and
//     specialWorkspaceSplit; WorkspaceOverlay's scratchpads and
//     scratchpadColor became specialWorkspaces and specialWorkspaceColor.
//
// Each part acts on the old shape only, so a second run changes nothing.
func v108(cfg *jsonx.Object) []string {
	var changes []string
	note := func(n int, what string) {
		if n > 0 {
			changes = append(changes, fmt.Sprintf("%d %s", n, what))
		}
	}

	if ws := object(cfg, "Workspaces"); ws != nil {
		if old, _ := ws.Value("scratchpads").(*jsonx.Array); old != nil {
			if _, isList := ws.Value("specialWorkspaces").(*jsonx.Array); !isList {
				list := jsonx.Arr()
				seen := map[string]bool{}
				for _, item := range old.Items {
					entry, _ := item.(*jsonx.Object)
					if entry == nil {
						continue
					}
					name, _ := entry.Value("name").(string)
					id := normSpecialID(name)
					if id == "" || seen[id] {
						continue
					}
					seen[id] = true
					out := jsonx.NewObject()
					out.Set("id", id)
					for _, k := range []string{"icon", "text"} {
						if v, ok := entry.Get(k); ok {
							out.Set(k, v)
						}
					}
					list.Append(out)
				}
				ws.Delete("specialWorkspaces")
				ws.Set("scratchpads", list)
				renameInPlace(ws, "scratchpads", "specialWorkspaces")
				changes = append(changes, "Workspaces.scratchpads became Workspaces.specialWorkspaces (entries by special workspace id)")
			}
		}
	}

	n := 0
	fix := func(list any) {
		items, _ := list.(*jsonx.Array)
		if items == nil {
			return
		}
		for _, item := range items.Items {
			bind, _ := item.(*jsonx.Object)
			if bind == nil {
				continue
			}
			if a := bind.Value("action"); a != "toggleSpecial" && a != "moveToSpecial" {
				continue
			}
			arg, _ := bind.Value("argument").(string)
			if id := normSpecialID(arg); arg != "" && id != "" && id != arg {
				bind.Set("argument", id)
				n++
			}
		}
	}
	if keybinds := object(cfg, "Keybinds"); keybinds != nil {
		fix(keybinds.Value("binds"))
		if presets, _ := keybinds.Value("presets").(*jsonx.Array); presets != nil {
			for _, preset := range presets.Items {
				if p, _ := preset.(*jsonx.Object); p != nil {
					fix(p.Value("binds"))
				}
			}
		}
	}
	if corners := object(cfg, "HotCorners"); corners != nil {
		fix(corners.Value("items"))
	}
	note(n, "keybind(s) and hot corner(s): the special workspace name made a valid id")

	note(eachTyped(cfg.Value("Bars"), "Workspaces", func(p *jsonx.Object) bool {
		a := renameInPlace(p, "scratchpads", "specialWorkspaces")
		b := renameInPlace(p, "scratchpadLabel", "specialWorkspaceLabel")
		c := renameInPlace(p, "scratchpadSplit", "specialWorkspaceSplit")
		return a || b || c
	}), "Workspaces widget(s): the scratchpad options became special workspace options")

	if overlay := object(cfg, "WorkspaceOverlay"); overlay != nil {
		a := renameInPlace(overlay, "scratchpads", "specialWorkspaces")
		b := renameInPlace(overlay, "scratchpadColor", "specialWorkspaceColor")
		if a || b {
			changes = append(changes, "WorkspaceOverlay: scratchpads and scratchpadColor became specialWorkspaces and specialWorkspaceColor")
		}
	}
	return changes
}

// normSpecialID is name as a valid special workspace id: itself when it is
// one, else each run of characters outside [A-Za-z0-9._-] a "-", leading
// non-alphanumerics stripped, cut to the longest id; "special" (reserved)
// becomes "special-1". Empty when nothing is left.
func normSpecialID(name string) string {
	name = strings.TrimSpace(name)
	if specialid.Valid(name) {
		return name
	}
	var b strings.Builder
	dash := false
	for _, r := range name {
		if r < 128 && (r == '.' || r == '_' || r == '-' || r >= '0' && r <= '9' || r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z') {
			b.WriteRune(r)
			dash = false
		} else if !dash {
			b.WriteByte('-')
			dash = true
		}
	}
	id := strings.TrimLeft(b.String(), "-._")
	if len(id) > specialid.MaxLen {
		id = id[:specialid.MaxLen]
	}
	if id == "special" {
		return "special-1"
	}
	return id
}
