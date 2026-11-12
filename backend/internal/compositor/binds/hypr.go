package binds

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"sort"
	"strconv"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/compositor/edit"
	"github.com/axiom-shell/axiom/backend/internal/compositor/luacheck"
	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

var (
	// The files a takeover moves the previous hyprland.lua to
	// (00-previous.lua, or 00-previous-<date>.lua when that's taken)
	adoptedName = regexp.MustCompile(`^00-previous(-[0-9-]+)?\.lua$`)
	// Bind options axiom's binds carry; `mouse` comes with a mouse: key
	hyprFlags     = []string{"locked", "repeating", "release"}
	hyprKnownOpts = map[string]bool{"locked": true, "repeating": true, "release": true, "mouse": true, "description": true}
	// Hyprland's example config's binds that move to another key, where
	// theirs would take one of axiom's defaults (SUPER + J is focus down,
	// SUPER + S and SUPER + SHIFT + S WASD's workspace and window down):
	// key id and action → key. Its float leaves SUPER + V for the special
	// workspace, onto axiom's. Only for binds in an adopted file: elsewhere
	// a key was the user's own choice.
	exampleKeys = map[[2]string]string{
		{"64:j", "toggleSplit"}:   "SUPER + X",
		{"64:s", "toggleSpecial"}: "SUPER + V",
		{"65:s", "moveToSpecial"}: "SUPER + SHIFT + V",
		{"64:v", "toggleFloat"}:   "SUPER + Z",
	}
)

// --- Mapping ---

var (
	stepPattern   = regexp.MustCompile(`^[erm]?([+-])1$`)
	numberPattern = regexp.MustCompile(`^[1-9][0-9]*$`)
)

// pyStr is a JSON value as Python's str writes it, for matching
func pyStr(v any) string {
	switch v := v.(type) {
	case string:
		return v
	case float64:
		return numberText(v)
	case bool:
		if v {
			return "True"
		}
		return "False"
	}
	return fmt.Sprint(v)
}

// step is a relative workspace ("e+1", "+1", "r-1", "m+1") as left/right
func step(workspace any) string {
	m := stepPattern.FindStringSubmatch(pyStr(workspace))
	if m == nil {
		return ""
	}
	if m[1] == "+" {
		return "right"
	}
	return "left"
}

func workspaceNumber(workspace any) string {
	switch w := workspace.(type) {
	case float64:
		if isWhole(w) && w >= 1 {
			return strconv.FormatInt(int64(w), 10)
		}
	case string:
		if numberPattern.MatchString(w) {
			return w
		}
	}
	return ""
}

// execAction is an exec_cmd's command as an axiom bind, or nil
func execAction(command string) *jsonx.Object {
	command = strings.TrimSpace(command)
	if command == render.HyprExitCommand {
		return jsonx.Obj("action", "exitSession")
	}
	if command == "" {
		return nil
	}
	return execBind(command)
}

// mapDispatcher is the axiom bind ({ action, argument, call }, the last two
// when it has them) for a dispatcher and its arguments, or nil
func mapDispatcher(name string, args []any) *jsonx.Object {
	to := func(action, argument string) *jsonx.Object { return jsonx.Obj("action", action, "argument", argument) }
	var one any
	if len(args) == 1 {
		one = args[0]
	}
	table, isTable := one.(map[string]any)
	if s, ok := one.(string); ok && name == "exec_cmd" {
		return execAction(s)
	}
	if len(args) == 0 {
		simple := map[string]string{"window.close": "closeWindow", "window.pseudo": "pseudo", "window.fullscreen": "fullscreen",
			"window.pin": "pin", "window.center": "centerWindow", "group.toggle": "toggleGroup",
			"window.drag": "mouseDrag", "window.resize": "mouseResize"}
		if action, ok := simple[name]; ok {
			return to(action, "")
		}
	}
	if name == "layout" && one == "togglesplit" {
		return to("toggleSplit", "")
	}
	if s, ok := one.(string); ok && name == "workspace.toggle_special" && validSpecialID(s) {
		return to("toggleSpecial", s)
	}
	if isTable && len(table) == 1 {
		for key, value := range table {
			s, isString := value.(string)
			switch {
			case name == "window.float" && key == "action" && value == "toggle":
				return to("toggleFloat", "")
			case name == "focus" && key == "direction" && isString && directions[s]:
				return to("focusDir", s)
			case name == "window.move" && key == "direction" && isString && directions[s]:
				return to("moveWindowDir", s)
			case (name == "focus" || name == "window.move") && key == "workspace":
				goTo := name == "focus"
				if n := workspaceNumber(value); n != "" {
					if goTo {
						return to("workspaceNth", n)
					}
					return to("moveWindowNth", n)
				}
				if d := step(value); d != "" {
					if goTo {
						return to("workspaceStep", d)
					}
					return to("moveWindowStep", d)
				}
				if !goTo && isString && strings.HasPrefix(s, "special:") && validSpecialID(strings.TrimPrefix(s, "special:")) {
					return to("moveToSpecial", strings.TrimPrefix(s, "special:"))
				}
			}
		}
	}
	if name == "window.resize" && isTable && len(table) == 3 && table["relative"] == true {
		x, xOK := table["x"].(float64)
		y, yOK := table["y"].(float64)
		if xOK && yOK {
			return to("resizeWindow", pyG(x)+" "+pyG(y))
		}
	}
	return nil
}

var specialIDPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]*$`)

// validSpecialID mirrors SpecialWorkspaces.validId: a special workspace id
// is ItemId's pattern, at most 32 chars, and not the reserved "special"
// (Hyprland's bare special workspace). Anything else stays a raw bind, so a
// merged bind never holds an invalid id.
func validSpecialID(id string) bool {
	return len(id) <= 32 && id != "special" && specialIDPattern.MatchString(id)
}

// pyG is a number as Python's :g writes it
func pyG(f float64) string {
	return strconv.FormatFloat(f, 'g', 6, 64)
}

// toAxiom is the axiom bind for an extracted bind, or why it stays
// (adopted: it's from an adopted file, so exampleKeys applies)
func toAxiom(b luaBind, adopted bool) (*jsonx.Object, [2]string) {
	if b.key == "" {
		return nil, [2]string{"key", ""}
	}
	if b.lua == "" {
		return nil, [2]string{"function", ""}
	}
	var unknown []string
	for k := range b.opts {
		if !hyprKnownOpts[k] {
			unknown = append(unknown, k)
		}
	}
	if len(unknown) > 0 {
		sort.Strings(unknown)
		return nil, [2]string{"options", strings.Join(unknown, ", ")}
	}
	mapped := mapDispatcher(b.dispatcher, b.args)
	if mapped == nil {
		mapped = jsonx.Obj("action", "raw", "argument", b.lua)
	}
	action, _ := mapped.Value("action").(string)
	argument, _ := mapped.Value("argument").(string)
	call, hasCall := mapped.Value("call").(string)
	if !hasCall {
		call = "toggle"
	}
	key := b.key
	if moved, ok := exampleKeys[[2]string{render.KeyID(b.key), action}]; ok && adopted {
		key = moved
	}
	bind := jsonx.Obj("key", key, "action", action, "argument", argument, "call", call)
	if action == "raw" {
		bind.Set("compositor", "hyprland")
	}
	for _, flag := range hyprFlags {
		bind.Set(flag, b.opts[flag] == true)
	}
	description, _ := b.opts["description"].(string)
	bind.Set("description", description)
	return bind, [2]string{}
}

// --- Lua source ---

var assignedTo = regexp.MustCompile(`^\s*(?:local\s+)?([A-Za-z_]\w*)\s*=\s*$`)

// statementSpan is where the statement made of the call ("hl.bind")
// starting on line is, with the whole line when nothing else is on it, or
// why it can't be taken out
func statementSpan(text, code string, line int, call string) (int, int, [2]string) {
	starts := []int{0}
	for i := 0; i < len(text); i++ {
		if text[i] == '\n' {
			starts = append(starts, i+1)
		}
	}
	fail := func(reason, detail string) (int, int, [2]string) { return 0, 0, [2]string{reason, detail} }
	if line < 1 || line > len(starts) {
		return fail("changed", "")
	}
	lineStart := starts[line-1]
	lineEnd := len(text)
	if line < len(starts) {
		lineEnd = starts[line] - 1
	}
	found := regexp.MustCompile(regexp.QuoteMeta(call)+`\s*\(`).FindAllStringIndex(code[lineStart:lineEnd], -1)
	if len(found) != 1 {
		if len(found) > 0 {
			return fail("notOnly", "")
		}
		return fail("changed", "")
	}
	openParen := lineStart + found[0][1] - 1
	depth, closeAt := 0, -1
	for i := openParen; i < len(code); i++ {
		if code[i] == '(' {
			depth++
		} else if code[i] == ')' {
			depth--
			if depth == 0 {
				closeAt = i
				break
			}
		}
	}
	if closeAt < 0 {
		return fail("unclosed", "")
	}
	before := code[lineStart : lineStart+found[0][0]]
	assigned := assignedTo.FindStringSubmatch(before)
	if strings.TrimSpace(before) != "" && assigned == nil {
		return fail("statement", "")
	}
	afterEnd := strings.IndexByte(code[closeAt:], '\n')
	if afterEnd < 0 {
		afterEnd = len(code)
	} else {
		afterEnd += closeAt
	}
	if rest := strings.TrimSpace(code[closeAt+1 : afterEnd]); rest != "" && rest != ";" {
		return fail("followed", "")
	}
	if assigned != nil {
		name := assigned[1]
		if usedElsewhere(code[:lineStart]+code[afterEnd:], name) {
			return fail("used", name)
		}
	}
	end := afterEnd
	if afterEnd < len(text) {
		end = afterEnd + 1
	}
	return lineStart, end, [2]string{}
}

func isWordByte(c byte) bool {
	return c == '_' || (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

// usedElsewhere: name appears in code as a variable of its own (not a
// field, x.name or x:name, nor part of a longer name)
func usedElsewhere(code, name string) bool {
	for i := 0; ; {
		j := strings.Index(code[i:], name)
		if j < 0 {
			return false
		}
		at := i + j
		end := at + len(name)
		before := at > 0 && (isWordByte(code[at-1]) || code[at-1] == '.' || code[at-1] == ':')
		after := end < len(code) && isWordByte(code[end])
		if !before && !after {
			return true
		}
		i = at + 1
	}
}

// --- Extract and remove ---

// hyprFiles are user/*.lua (only: just that one)
func hyprFiles(dir, only string) []string {
	return userFiles(dir, only, func(name string) bool { return strings.HasSuffix(name, ".lua") })
}

type siteKey struct {
	file string
	line int
}

func sortedSites[T any](groups map[siteKey][]T) []siteKey {
	keys := make([]siteKey, 0, len(groups))
	for k := range groups {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].file != keys[j].file {
			return keys[i].file < keys[j].file
		}
		return keys[i].line < keys[j].line
	})
	return keys
}

// extractHypr runs user/*.lua for their binds. A bind moves only when every
// bind its call makes can (a call in a loop makes several), the call is
// the whole statement, and it's in a user/*.lua file itself (not a shared
// module) and its main chunk. Binds inside submaps or hl.on handlers
// aren't seen, since those functions never run here: a call in a function
// (a helper) may make some, so it stays. A site carries its statement's
// text, so remove leaves one that changed since.
func extractHypr(ctx context.Context, o Options) (*jsonx.Object, error) {
	files := hyprFiles(o.Dir, o.Only)
	result := emptyResult()
	if len(files) == 0 {
		return result, nil
	}
	var modules, dotted []string
	allowed, adopted := map[string]bool{}, map[string]bool{}
	for _, f := range files {
		// require reads a dot as a folder, so Hyprland never loads it
		name := strings.TrimSuffix(filepath.Base(f), ".lua")
		if strings.Contains(name, ".") {
			dotted = append(dotted, "user/"+filepath.Base(f)+": "+render.DottedUserFile)
			continue
		}
		modules = append(modules, "user."+name)
		real := realPath(f)
		allowed[real] = true
		if adoptedName.MatchString(filepath.Base(f)) {
			adopted[real] = true
		}
	}
	runCtx, cancel := context.WithTimeout(ctx, o.Timeout)
	defer cancel()
	found, err := runHyprFiles(runCtx, o.Dir, modules, o.Getenv)
	if err != nil {
		return nil, err
	}
	type source struct{ text, code string }
	texts := map[string]source{}
	// span is why the call on line can't be taken out, or its statement's
	// text (what remove finds there again)
	span := func(file string, line int, call string) ([2]string, string) {
		if !allowed[file] {
			return [2]string{"shared", ""}, ""
		}
		src, ok := texts[file]
		if !ok {
			data, _ := os.ReadFile(file)
			src = source{string(data), luacheck.CodeOnly(string(data))}
			texts[file] = src
		}
		start, end, reason := statementSpan(src.text, src.code, line, call)
		// As JSON carries it: invalid bytes as U+FFFD
		return reason, strings.ToValidUTF8(src.text[start:end], "\uFFFD")
	}
	resolve := func(file string) string {
		if file == "" {
			return ""
		}
		return realPath(file)
	}

	// Grouped by call site: one hl.bind in a loop makes several binds
	sites := map[siteKey][]luaBind{}
	for _, b := range found.binds {
		k := siteKey{resolve(b.file), b.line}
		sites[k] = append(sites[k], b)
	}
	movedKeys := map[string]bool{}
	read := map[string]bool{}
	for _, k := range sortedSites(sites) {
		entries := sites[k]
		made := make([]*jsonx.Object, len(entries))
		reason, text := span(k.file, k.line, "hl.bind")
		for i, e := range entries {
			bind, why := toAxiom(e, adopted[k.file])
			made[i] = bind
			if e.inFunction {
				why = [2]string{"inFunction", ""}
			}
			if reason[0] == "" && why[0] != "" {
				reason = why
			}
		}
		if reason[0] != "" {
			for _, e := range entries {
				push(result, "kept", keptEntry(k.file, k.line, e.key, reason[0], reason[1]))
			}
			if allowed[k.file] {
				read[k.file] = true
			}
			continue
		}
		moved, keys := jsonx.Arr(), jsonx.Arr()
		for i, e := range entries {
			push(result, "binds", made[i])
			moved.Append(made[i])
			if to := made[i].Value("key").(string); to != e.key {
				push(result, "remapped", jsonx.Obj("from", e.key, "to", to, "action", made[i].Value("action")))
			}
			movedKeys[render.KeyID(e.key)] = true
			keys.Append(render.KeyID(e.key))
		}
		push(result, "sites", jsonx.Obj("file", k.file, "line", float64(k.line), "binds", moved, "keys", keys, "text", text))
		read[k.file] = true
	}

	unbinds := map[siteKey][]luaUnbind{}
	for _, u := range found.unbinds {
		k := siteKey{resolve(u.file), u.line}
		unbinds[k] = append(unbinds[k], u)
	}
	for _, k := range sortedSites(unbinds) {
		all, keys := true, jsonx.Arr()
		for _, u := range unbinds[k] {
			if id := render.KeyID(u.key); id == "" || !movedKeys[id] || u.inFunction {
				all = false
			} else {
				keys.Append(id)
			}
		}
		if reason, text := span(k.file, k.line, "hl.unbind"); all && reason[0] == "" {
			push(result, "sites", jsonx.Obj("file", k.file, "line", float64(k.line), "binds", jsonx.Arr(), "keys", keys,
				"unbind", true, "text", text))
			read[k.file] = true
		}
	}

	names := make([]string, 0, len(read))
	for f := range read {
		names = append(names, f)
	}
	sort.Strings(names)
	for _, f := range names {
		if o.Tracked(ctx, f) {
			push(result, "tracked", f)
		}
	}
	for _, e := range append(dotted, found.errors...) {
		push(result, "errors", e)
	}
	return result, nil
}

// removeHypr comments the sites' calls out (each whole statement's lines,
// marked with hyprMark: UnmarkMoved gives them back), after a dated backup of each file it changes
// beside it (<file>.axiom-backup-<date>, which Hyprland doesn't load). A
// file whose result doesn't parse is left alone (failed with line 0); a
// call that isn't found any more is failed on its line; a file that can't
// be read, backed up or written is failed (io) and the others go on. A
// moved key's hl.unbind and its binds go together or stay together
// (paired), in whichever files they are: every file is planned before any
// is written, so only a failed write can still split them.
func removeHypr(ctx context.Context, o Options, sites *jsonx.Array) (*jsonx.Object, error) {
	allowed := map[string]bool{}
	for _, f := range hyprFiles(o.Dir, "") {
		allowed[realPath(f)] = true
	}
	byFile := map[string][]site{}
	unbound := map[string]bool{}
	for _, s := range readSites(sites) {
		f := realPath(s.file)
		byFile[f] = append(byFile[f], s)
		if s.unbind {
			for _, k := range s.keys {
				unbound[k] = true
			}
		}
	}
	files := make([]string, 0, len(byFile))
	for f := range byFile {
		files = append(files, f)
		sort.SliceStable(byFile[f], func(i, j int) bool { return byFile[f][i].line < byFile[f][j].line })
	}
	sort.Strings(files)
	// Planned again until no failed site holds back a key an unbind covers
	plans := map[string]hyprPlan{}
	blocked := map[string]bool{}
	for again := true; again; {
		again = false
		for _, file := range files {
			plans[file] = planHypr(ctx, o, file, byFile[file], allowed[file], blocked)
		}
		for _, file := range files {
			for _, f := range plans[file].failed {
				for _, s := range byFile[file] {
					if line := f.Value("line"); line != 0.0 && line != float64(s.line) {
						continue
					}
					for _, k := range s.keys {
						if unbound[k] && !blocked[k] {
							blocked[k], again = true, true
						}
					}
				}
			}
		}
	}
	done := jsonx.Obj("removed", float64(0), "files", jsonx.Arr(), "failed", jsonx.Arr())
	removed := 0
	for _, file := range files {
		p := plans[file]
		if p.spans > 0 {
			err := backup(o, file, filepath.Dir(file))
			if err == nil {
				err = edit.Replace(file, []byte(p.edited))
			}
			if err != nil {
				p.failed = []*jsonx.Object{failedEntry(file, 0, "io", err.Error())}
			} else {
				removed += p.spans
				push(done, "files", file)
			}
		}
		for _, f := range p.failed {
			push(done, "failed", f)
		}
	}
	done.Set("removed", float64(removed))
	return done, nil
}

// hyprPlan is one file's edit: its text with the calls that go (spans of
// them) commented out, and the sites that stay
type hyprPlan struct {
	edited string
	spans  int
	failed []*jsonx.Object
}

// planHypr is what removing fileSites (by line) does to file, sites holding
// a blocked key left (paired)
func planHypr(ctx context.Context, o Options, file string, fileSites []site, allowed bool, blocked map[string]bool) hyprPlan {
	if !allowed {
		return hyprPlan{failed: []*jsonx.Object{failedEntry(file, 0, "notUser", "")}}
	}
	data, err := os.ReadFile(file)
	if err != nil {
		return hyprPlan{failed: []*jsonx.Object{failedEntry(file, 0, "io", err.Error())}}
	}
	text := string(data)
	code := luacheck.CodeOnly(text)
	type span struct{ start, end int }
	var spans []span
	var failed []*jsonx.Object
	last := -1
	for _, s := range fileSites {
		if s.line == last {
			continue
		}
		last = s.line
		start, end, reason := statementSpan(text, code, s.line, "hl.bind")
		if reason[0] != "" {
			start, end, reason = statementSpan(text, code, s.line, "hl.unbind")
		}
		// A statement other than the one extract read there is left
		if reason[0] != "" || (s.hasText && strings.ToValidUTF8(text[start:end], "\uFFFD") != s.text) {
			failed = append(failed, failedEntry(file, s.line, "changed", ""))
			continue
		}
		if slices.ContainsFunc(s.keys, func(k string) bool { return blocked[k] }) {
			failed = append(failed, failedEntry(file, s.line, "paired", ""))
			continue
		}
		spans = append(spans, span{start, end})
	}
	sort.Slice(spans, func(i, j int) bool { return spans[i].start > spans[j].start })
	edited := text
	for _, s := range spans {
		edited = edited[:s.start] + markLines(edited[s.start:s.end], hyprMark) + edited[s.end:]
	}
	if len(spans) > 0 {
		if err := o.Lua.Check(ctx, edited); err != nil {
			// The file is left alone: every call in it stays, found or not
			return hyprPlan{failed: []*jsonx.Object{failedEntry(file, 0, "syntax", err.Error())}}
		}
	}
	return hyprPlan{edited, len(spans), failed}
}
