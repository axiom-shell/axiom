// Package userconf reads the user's own compositor config, for what axiom
// needs to know of it: niri's (the config the running niri loads, its
// includes, the binds in effect, its gaps, struts, layouts and blur) and
// sway's (the config with its includes put in). Nothing is written.
package userconf

import (
	"context"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"sort"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/compositor/kdl"
	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// File is one file's own nodes, in the order niri reads them.
type File struct {
	Path  string
	Nodes []*kdl.Node
}

// Resolved is what a niri config loads.
type Resolved struct {
	// Files: the config's nodes as runs, an included file's where its
	// include was (so later ones win), the includes taken out
	Files []File
	// Missing: the includes that weren't there; Loaded: every file read
	Missing, Loaded []string
}

func configHome(getenv func(string) string) string {
	if dir := getenv("XDG_CONFIG_HOME"); dir != "" {
		return dir
	}
	return filepath.Join(getenv("HOME"), ".config")
}

var niriSocketPID = regexp.MustCompile(`\.(\d+)\.sock$`)

// proc is a /proc file of pid split at its NULs, nil when unreadable
func proc(pid, name string) []string {
	data, err := os.ReadFile(filepath.Join("/proc", pid, name))
	if err != nil {
		return nil
	}
	return strings.Split(strings.ToValidUTF8(string(data), "�"), "\x00")
}

// startedWith is the -c / --config in the command line of the process pid
// named comm (a relative one from that process's folder), or ""
func startedWith(pid, comm string) (string, bool) {
	if strings.TrimSpace(strings.Join(proc(pid, "comm"), "")) != comm {
		return "", false
	}
	args := proc(pid, "cmdline")
	config := ""
	for i, arg := range args {
		if (arg == "-c" || arg == "--config") && i+1 < len(args) {
			config = args[i+1]
			break
		}
		if v, ok := strings.CutPrefix(arg, "--config="); ok {
			config = v
			break
		}
	}
	if config != "" && !filepath.IsAbs(config) {
		if cwd, err := os.Readlink(filepath.Join("/proc", pid, "cwd")); err == nil {
			config = filepath.Join(cwd, config)
		}
	}
	return config, true
}

// NiriMain is the config file of the niri $NIRI_SOCKET names, as it
// started: its -c, else its NIRI_CONFIG, else where niri looks. A config
// loaded later (load-config-file: axiom's detached wrapper) doesn't change
// it.
func NiriMain(getenv func(string) string) string {
	pid := ""
	if m := niriSocketPID.FindStringSubmatch(getenv("NIRI_SOCKET")); m != nil {
		pid = m[1]
	}
	// A NIRI_SOCKET left over from an earlier session can name a pid some
	// other process has since
	if pid != "" {
		config, isNiri := startedWith(pid, "niri")
		if !isNiri {
			pid = ""
		} else if config != "" {
			return config
		}
	}
	if pid != "" {
		for _, entry := range proc(pid, "environ") {
			if v, ok := strings.CutPrefix(entry, "NIRI_CONFIG="); ok && v != "" {
				return v
			}
		}
	} else if v := getenv("NIRI_CONFIG"); v != "" {
		return v
	}
	user := filepath.Join(configHome(getenv), "niri", "config.kdl")
	if fsx.IsFile(user) || !fsx.IsFile("/etc/niri/config.kdl") {
		return user
	}
	return "/etc/niri/config.kdl"
}

// realPath is path with its links followed as far as they go
// (Path.resolve)
func realPath(path string) string {
	abs, err := filepath.Abs(path)
	if err != nil {
		return path
	}
	if real, err := filepath.EvalSymlinks(abs); err == nil {
		return real
	}
	dir, base := filepath.Split(abs)
	if dir == abs || dir == "" {
		return abs
	}
	return filepath.Join(realPath(filepath.Clean(dir)), base)
}

// ResolveNiri reads main and what it includes. Files in skip (axiom's own)
// are left out; a file starting with skipHeader (axiom's managed config)
// gives only what it includes. Each file once.
func ResolveNiri(main string, skip []string, skipHeader string, getenv func(string) string) (*Resolved, error) {
	skipped := map[string]bool{}
	for _, p := range skip {
		skipped[realPath(p)] = true
	}
	r := &Resolved{}
	seen := map[string]bool{}
	var visit func(path string) error
	visit = func(path string) error {
		real := realPath(path)
		if seen[real] || skipped[real] {
			return nil
		}
		seen[real] = true
		data, err := os.ReadFile(path)
		if err != nil {
			r.Missing = append(r.Missing, path)
			return nil
		}
		r.Loaded = append(r.Loaded, path)
		text := strings.ToValidUTF8(string(data), "�")
		nodes, err := kdl.Parse(text)
		if err != nil {
			return err
		}
		ownSkipped := skipHeader != "" && strings.HasPrefix(text, skipHeader)
		var own []*kdl.Node
		flush := func() {
			if len(own) > 0 && !ownSkipped {
				r.Files = append(r.Files, File{path, own})
			}
			own = nil
		}
		for _, node := range nodes {
			target, ok := "", false
			if node.Name == "include" && len(node.Args) > 0 {
				target, ok = node.Args[0].(string)
			}
			if !ok {
				own = append(own, node)
				continue
			}
			flush()
			target = expandVars(target, getenv)
			if !filepath.IsAbs(target) {
				target = filepath.Join(filepath.Dir(path), target)
			}
			optional, _ := node.Props.Get("optional")
			if exists(target) || optional != true {
				if err := visit(target); err != nil {
					return err
				}
			}
		}
		flush()
		return nil
	}
	if err := visit(main); err != nil {
		return nil, err
	}
	return r, nil
}

var envVar = regexp.MustCompile(`\$(\w+|\{[^}]*\})`)

// expandVars puts in $NAME and ${NAME} that are set, leaving the rest as
// written (os.path.expandvars)
func expandVars(text string, getenv func(string) string) string {
	return envVar.ReplaceAllStringFunc(text, func(m string) string {
		name := strings.Trim(m[1:], "{}")
		if v, ok := lookupEnv(getenv, name); ok {
			return v
		}
		return m
	})
}

func lookupEnv(getenv func(string) string, name string) (string, bool) {
	v := getenv(name)
	return v, v != ""
}

// RunningNested is whether the niri $NIRI_SOCKET names runs nested, in a
// window (its winit backend, whose only output is "winit").
func RunningNested(getenv func(string) string) bool {
	n := ipc.NiriFromEnv(getenv)
	if n == nil {
		return false
	}
	outputs, err := n.Outputs(context.Background())
	return err == nil && len(outputs) == 1 && outputs[0].Name == "winit"
}

// --- Binds ---

// niri's modifier names (lower case) as X11 mask bits, and as axiom's
var (
	modBits = map[string]int{"shift": 1, "ctrl": 4, "control": 4, "alt": 8, "super": 64, "win": 64, "iso_level3_shift": 128,
		"mod5": 128, "iso_level5_shift": 32, "mod3": 32}
	// ModNames are niri's modifier names (lower case) as axiom's
	ModNames = map[string]string{"shift": "SHIFT", "ctrl": "CTRL", "control": "CTRL", "alt": "ALT", "super": "SUPER", "win": "SUPER",
		"iso_level3_shift": "MOD5", "mod5": "MOD5"}
	// niri's mouse and wheel keys as axiom's (Hyprland's names)
	mouse = map[string]string{"mouseleft": "mouse:272", "mouseright": "mouse:273", "mousemiddle": "mouse:274", "mouseback": "mouse:275",
		"mouseforward": "mouse:276", "wheelscrollup": "mouse_up", "wheelscrolldown": "mouse_down",
		"wheelscrollleft": "mouse_left", "wheelscrollright": "mouse_right"}
	axiomModOrder = []string{"SUPER", "CTRL", "ALT", "SHIFT", "MOD5"}
	// niri's other names for a modifier (lower case), as the one it's
	// compared by
	modAliases = map[string]string{"control": "ctrl", "win": "super", "mod5": "iso_level3_shift", "mod3": "iso_level5_shift"}
)

// ModKey is what `Mod` stands for: input.mod-key (Super by default), or
// nested input.mod-key-nested (Alt by default). axiom never writes Mod.
func ModKey(files []File, nested bool) string {
	option, name := "mod-key", "Super"
	if nested {
		option, name = "mod-key-nested", "Alt"
	}
	for _, f := range files {
		for _, node := range f.Nodes {
			if node.Name != "input" {
				continue
			}
			if found := node.Child(option); found != nil && len(found.Args) > 0 {
				if s, ok := found.Args[0].(string); ok {
					name = s
				}
			}
		}
	}
	return name
}

// splitCombo is a niri key combo ("Mod+Shift+T") as its modifiers (lower
// case, Mod put in) and key
func splitCombo(combo, mod string) ([]string, string, bool) {
	var parts []string
	for _, p := range strings.Split(combo, "+") {
		if p != "" {
			parts = append(parts, p)
		}
	}
	if len(parts) == 0 {
		return nil, "", false
	}
	mods := make([]string, 0, len(parts)-1)
	for _, p := range parts[:len(parts)-1] {
		if strings.ToLower(p) == "mod" {
			p = mod
		}
		mods = append(mods, strings.ToLower(p))
	}
	return mods, parts[len(parts)-1], true
}

// AxiomKey is a niri key combo as axiom writes keys ("SUPER + SHIFT + T"),
// or "" when a modifier has no name of axiom's.
func AxiomKey(combo, mod string) string {
	mods, key, ok := splitCombo(combo, mod)
	if !ok {
		return ""
	}
	have := map[string]bool{}
	for _, m := range mods {
		name, ok := ModNames[m]
		if !ok {
			return ""
		}
		have[name] = true
	}
	var names []string
	for _, name := range axiomModOrder {
		if have[name] {
			names = append(names, name)
		}
	}
	return strings.Join(append(names, keyName(key, true)), " + ")
}

// keyName is a key as axiom writes it: a mouse key by Hyprland's name, else
// a single character upper case (with upper) or as written
func keyName(key string, upper bool) string {
	if m, ok := mouse[strings.ToLower(key)]; ok {
		return m
	}
	if upper && len([]rune(key)) == 1 {
		return strings.ToUpper(key)
	}
	return key
}

// actionText is a bind's action as niri's config writes it, or ""
func actionText(bind *kdl.Node) string {
	if len(bind.Children) == 0 {
		return ""
	}
	return render.KdlNodeText(bind.Children[0])
}

// NiriBinds are the binds in effect as BindKeys' entries ({ modmask, key,
// keycode, submap, description }), a later one on the same key (niri
// compares keys without case, a modifier by any of its names) winning.
func NiriBinds(files []File, nested bool) *jsonx.Array {
	mod := ModKey(files, nested)
	var order []string
	found := map[string]*kdl.Node{}
	for _, f := range files {
		for _, node := range f.Nodes {
			if node.Name != "binds" {
				continue
			}
			for _, bind := range node.Children {
				mods, key, ok := splitCombo(bind.Name, mod)
				if !ok {
					continue
				}
				set := map[string]bool{}
				for _, m := range mods {
					if alias, ok := modAliases[m]; ok {
						m = alias
					}
					set[m] = true
				}
				names := make([]string, 0, len(set))
				for m := range set {
					names = append(names, m)
				}
				slices.Sort(names)
				id := strings.Join(names, "+") + "\x00" + strings.ToLower(key)
				if _, ok := found[id]; !ok {
					order = append(order, id)
				}
				found[id] = bind
			}
		}
	}
	out := jsonx.Arr()
	for _, id := range order {
		bind := found[id]
		mods, key, _ := splitCombo(bind.Name, mod)
		mask, ok := 0, true
		for _, m := range mods {
			bit, known := modBits[m]
			if !known {
				ok = false
				break
			}
			mask |= bit
		}
		if !ok {
			continue
		}
		var description any = actionText(bind)
		if title, _ := bind.Props.Get("hotkey-overlay-title"); kdl.Truthy(title) {
			description = kdl.JSON(title)
		}
		out.Append(jsonx.Obj("modmask", float64(mask), "key", keyName(key, false), "keycode", float64(0), "submap", "",
			"description", description))
	}
	return out
}

// NiriInfo is what NiriManager follows: { gaps, struts: { top, right,
// bottom, left }, layouts ("us,de", or ""), blur: { enabled, passes,
// offset }, modKey (what Mod stands for, as axiom names it: "SUPER") }.
func NiriInfo(files []File, nested bool) *jsonx.Object {
	var gaps any = float64(16)
	struts := jsonx.Obj("top", float64(0), "right", float64(0), "bottom", float64(0), "left", float64(0))
	layouts := ""
	blur := jsonx.Obj("enabled", true, "passes", float64(3), "offset", float64(3))
	for _, f := range files {
		for _, node := range f.Nodes {
			switch node.Name {
			case "blur":
				if node.Child("off") != nil {
					blur.Set("enabled", false)
				}
				for _, key := range []string{"passes", "offset"} {
					if found := node.Child(key); found != nil && len(found.Args) > 0 {
						blur.Set(key, kdl.JSON(found.Args[0]))
					}
				}
			case "layout":
				if found := node.Child("gaps"); found != nil && len(found.Args) > 0 {
					gaps = kdl.JSON(found.Args[0])
				}
				for _, side := range struts.Keys() {
					if strut := node.Child("struts").Child(side); strut != nil && len(strut.Args) > 0 {
						struts.Set(side, kdl.JSON(strut.Args[0]))
					}
				}
			case "input":
				if layout := node.Child("keyboard").Child("xkb").Child("layout"); layout != nil && len(layout.Args) > 0 {
					layouts, _ = layout.Args[0].(string)
				}
			}
		}
	}
	mod := ModKey(files, nested)
	modKey, ok := ModNames[strings.ToLower(mod)]
	if !ok {
		modKey = strings.ToUpper(mod)
	}
	return jsonx.Obj("gaps", gaps, "struts", struts, "layouts", layouts, "blur", blur, "modKey", modKey)
}

// UserFiles are the names of dir's regular files (a link followed) that
// keep takes (nil: all), sorted, hidden ones left out (a staged write, an
// editor's swap file): the managed config's user/ files.
func UserFiles(dir string, keep func(name string) bool) []string {
	var names []string
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		if !strings.HasPrefix(e.Name(), ".") && (keep == nil || keep(e.Name())) && fsx.IsFile(filepath.Join(dir, e.Name())) {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	return names
}

// NiriUserFiles are user/*.kdl as the managed config includes them, by name
// (niri takes no globs).
func NiriUserFiles(dir string) []string {
	return UserFiles(dir, func(name string) bool { return strings.HasSuffix(name, ".kdl") })
}

func exists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
