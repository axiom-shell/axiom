package binds

import (
	"context"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/compositor/kdl"
	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/compositor/userconf"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

var (
	// Options a moved bind can keep (as axiom's flags or its label);
	// anything else keeps the bind in its file
	niriHarmless = map[string]bool{"repeat": true, "cooldown-ms": true, "hotkey-overlay-title": true, "allow-when-locked": true}
	// niri's actions that are an axiom action of their own
	niriSimple = map[string]string{"close-window": "closeWindow", "fullscreen-window": "fullscreen", "toggle-window-floating": "toggleFloat",
		"center-window": "centerWindow", "quit": "exitSession", "toggle-column-tabbed-display": "toggleGroup",
		"expand-column-to-available-width": "stripFit", "center-column": "stripCenter",
		// (axiom's overview opens niri's while WorkspaceOverlay.compositorOverview
		// is on: the bind goes through axiom's)
		"toggle-overview": "workspaceOverview"}
	// niri's actions taking a direction: axiom's action and direction
	niriDirectional = map[string][2]string{
		"focus-column-left": {"focusDir", "left"}, "focus-column-right": {"focusDir", "right"},
		"focus-column-or-monitor-left": {"focusDir", "left"}, "focus-column-or-monitor-right": {"focusDir", "right"},
		"focus-window-up": {"focusDir", "up"}, "focus-window-down": {"focusDir", "down"},
		"focus-window-or-monitor-up": {"focusDir", "up"}, "focus-window-or-monitor-down": {"focusDir", "down"},
		"move-column-left": {"stripSwapColumn", "left"}, "move-column-right": {"stripSwapColumn", "right"},
		"consume-or-expel-window-left":          {"stripConsume", "left"},
		"consume-or-expel-window-right":         {"stripConsume", "right"},
		"move-column-left-or-to-monitor-left":   {"moveWindowDir", "left"},
		"move-column-right-or-to-monitor-right": {"moveWindowDir", "right"},
		"move-window-up":                        {"moveWindowDir", "up"}, "move-window-down": {"moveWindowDir", "down"},
		"focus-workspace-down": {"workspaceStep", "down"}, "focus-workspace-up": {"workspaceStep", "up"},
		"move-column-to-workspace-down": {"moveWindowStep", "down"},
		"move-column-to-workspace-up":   {"moveWindowStep", "up"},
		"move-window-to-workspace-down": {"moveWindowStep", "down"},
		"move-window-to-workspace-up":   {"moveWindowStep", "up"},
	}
	// niri's actions taking a workspace number (its index on the output, as
	// axiom's nth is)
	niriNumbered = map[string]string{"focus-workspace": "workspaceNth", "move-column-to-workspace": "moveWindowNth",
		"move-window-to-workspace": "moveWindowNth"}
)

func niriAction(node *kdl.Node) *jsonx.Object {
	args := node.Args
	plain := len(args) == 0 && node.Props.Len() == 0
	// A plain quit asks first and axiom's log out doesn't: only quit
	// skip-confirmation=true is one, a confirming quit stays niri's (raw)
	skip, _ := node.Props.Get("skip-confirmation")
	unconfirmed := len(args) == 0 && node.Props.Len() == 1 && skip == true
	if action, ok := niriSimple[node.Name]; ok && (node.Name == "quit" && unconfirmed || node.Name != "quit" && plain) {
		return jsonx.Obj("action", action)
	}
	if d, ok := niriDirectional[node.Name]; ok && plain {
		return jsonx.Obj("action", d[0], "argument", d[1])
	}
	if action, ok := niriNumbered[node.Name]; ok && len(args) == 1 {
		focus, _ := node.Props.Get("focus")
		if n, isInt := args[0].(int64); isInt && n >= 1 && focus != false {
			return jsonx.Obj("action", action, "argument", strconv.FormatInt(n, 10))
		}
	}
	if node.Name == "set-column-width" && len(args) == 1 && (args[0] == "+10%" || args[0] == "-10%") {
		if args[0] == "+10%" {
			return jsonx.Obj("action", "stripWider")
		}
		return jsonx.Obj("action", "stripNarrower")
	}
	if node.Name == "spawn" && len(args) > 0 {
		words := make([]string, 0, len(args))
		for _, a := range args {
			if s, ok := a.(string); ok {
				words = append(words, s)
			}
		}
		if len(words) == len(args) {
			// niri runs them without a shell, putting home in for the
			// program's leading ~
			if home, ok := strings.CutPrefix(words[0], "~/"); ok {
				return execBind("~/" + shellJoin(append([]string{home}, words[1:]...)))
			}
			return execBind(shellJoin(words))
		}
	}
	if node.Name == "spawn-sh" && len(args) == 1 {
		if s, ok := args[0].(string); ok {
			return execBind(s)
		}
	}
	return jsonx.Obj("action", "raw", "argument", render.KdlNodeText(node), "compositor", "niri")
}

var shellSafe = regexp.MustCompile(`^[\w@%+=:,./-]+$`)

// shellJoin quotes each word for a POSIX shell where it needs it
// (shlex.join)
func shellJoin(words []string) string {
	out := make([]string, len(words))
	for i, w := range words {
		switch {
		case w == "":
			out[i] = "''"
		case shellSafe.MatchString(w):
			out[i] = w
		default:
			out[i] = "'" + strings.ReplaceAll(w, "'", `'"'"'`) + "'"
		}
	}
	return strings.Join(out, " ")
}

// niriFiles are user/*.kdl as the managed config includes them
func niriFiles(o Options) []string {
	return userFiles(o.Dir, o.Only, func(name string) bool { return strings.HasSuffix(name, ".kdl") })
}

type parsedFile struct {
	path  string
	lines []string
	nodes []*kdl.Node
}

// extractNiri reads the binds in top-level `binds` blocks, files in name
// order as the managed config includes them; a file that doesn't parse is
// an error, and nothing of it moves
func extractNiri(ctx context.Context, o Options) *jsonx.Object {
	result := emptyResult()
	var parsed []parsedFile
	var files []userconf.File
	for _, path := range niriFiles(o) {
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		text := strings.ToValidUTF8(string(data), "�")
		nodes, err := kdl.Parse(text)
		if err != nil {
			push(result, "errors", jsonx.Obj("file", path, "detail", err.Error()))
			continue
		}
		parsed = append(parsed, parsedFile{path, userconf.SplitLines(text), nodes})
		files = append(files, userconf.File{Path: path, Nodes: nodes})
	}
	mod := userconf.ModKey(files, userconf.RunningNested(o.Getenv))
	for _, f := range parsed {
		if o.Tracked(ctx, f.path) {
			push(result, "tracked", f.path)
		}
		for _, block := range f.nodes {
			if block.Name != "binds" {
				continue
			}
			for _, bind := range block.Children {
				var other []string
				for _, k := range bind.Props.Keys() {
					if !niriHarmless[k] {
						other = append(other, k)
					}
				}
				sort.Strings(other)
				if len(other) > 0 {
					push(result, "kept", keptEntry(f.path, bind.Line, bind.Name, "options", strings.Join(other, " ")))
					continue
				}
				key := userconf.AxiomKey(bind.Name, mod)
				if key == "" || len(bind.Children) == 0 {
					push(result, "kept", keptEntry(f.path, bind.Line, bind.Name, "key", ""))
					continue
				}
				extra := jsonx.NewObject()
				if locked, _ := bind.Props.Get("allow-when-locked"); locked == true {
					extra.Set("locked", true)
				}
				if title, _ := bind.Props.Get("hotkey-overlay-title"); title != nil && title != "" {
					extra.Set("description", title)
				}
				repeat, _ := bind.Props.Get("repeat")
				entry := movedBind(key, niriAction(bind.Children[0]), extra, repeat != false)
				text := ""
				if bind.Line-1 < len(f.lines) {
					text = f.lines[bind.Line-1]
				}
				push(result, "binds", entry)
				push(result, "sites", jsonx.Obj("file", f.path, "line", float64(bind.Line), "col", float64(bind.Col),
					"binds", jsonx.Arr(entry), "text", text))
			}
		}
	}
	return result
}
