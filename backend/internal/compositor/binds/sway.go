package binds

import (
	"context"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"sort"
	"strings"
	"unicode"

	"github.com/axiom-shell/axiom/backend/internal/compositor/actions"
	"github.com/axiom-shell/axiom/backend/internal/compositor/userconf"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

var (
	swayMods = map[string]string{"mod4": "SUPER", "super": "SUPER", "mod1": "ALT", "alt": "ALT", "ctrl": "CTRL", "control": "CTRL",
		"shift": "SHIFT", "lock": "CAPS", "mod2": "MOD2", "mod3": "MOD3", "mod5": "MOD5"}
	swayModOrder = []string{"SUPER", "CTRL", "ALT", "SHIFT", "CAPS", "MOD2", "MOD3", "MOD5"}
	swayMouse    = map[string]string{"button1": "mouse:272", "button2": "mouse:274", "button3": "mouse:273", "button4": "mouse_up",
		"button5": "mouse_down", "button6": "mouse_left", "button7": "mouse_right", "btn_left": "mouse:272",
		"btn_right": "mouse:273", "btn_middle": "mouse:274", "btn_side": "mouse:275", "btn_extra": "mouse:276"}
	// Options a moved bind keeps as axiom's flags, in this order
	swayFlags = [][2]string{{"--release", "release"}, {"--locked", "locked"}}
	// Options a moved bind can drop (not --to-code: axiom binds by keysym,
	// which would change the bind on another layout)
	swayHarmless   = map[string]bool{"--no-warn": true, "--whole-window": true, "--no-repeat": true}
	swayDirections = map[string]bool{"left": true, "right": true, "up": true, "down": true}

	swayBlock = regexp.MustCompile(`^(bindsym|bindcode)(\s+--\S+)*\s*\{$`)
	swayBind  = regexp.MustCompile(`^(bindsym|bindcode)\s+(.*)$`)
	swayParts = regexp.MustCompile(`^((?:--\S+\s+)*)(\S*)\s*(.*)$`)
)

func isSwayFlag(flag string) bool {
	for _, f := range swayFlags {
		if f[0] == flag {
			return true
		}
	}
	return false
}

func swayKey(combo string, code bool) string {
	var parts []string
	for _, p := range strings.Split(combo, "+") {
		if p != "" {
			parts = append(parts, p)
		}
	}
	if len(parts) == 0 {
		return ""
	}
	var mods []string
	for _, mod := range parts[:len(parts)-1] {
		name, ok := swayMods[strings.ToLower(mod)]
		if !ok {
			return ""
		}
		mods = append(mods, name)
	}
	last := parts[len(parts)-1]
	var key string
	if code {
		for _, r := range last {
			if !unicode.IsDigit(r) {
				return ""
			}
		}
		key = "code:" + last
	} else if m, ok := swayMouse[strings.ToLower(last)]; ok {
		key = m
	} else if len([]rune(last)) == 1 {
		key = strings.ToUpper(last)
	} else {
		key = last
	}
	sort.SliceStable(mods, func(i, j int) bool {
		return slices.Index(swayModOrder, mods[i]) < slices.Index(swayModOrder, mods[j])
	})
	return strings.Join(append(mods, key), " + ")
}

// How sway reads a bind's command (checked against sway 1.12): a config
// file's line is split into words (split_args), each unescaped
// (unescape_string) and joined again; an `exec` of a single quoted word
// then has its quotes taken out (strip_quotes), of several runs as joined
var swayEscapes = map[rune]rune{'\\': '\\', '"': '"', '\'': '\'', 'n': '\n', 't': '\t', 'r': '\r', 'a': '\a', 'b': '\b', 'f': '\f',
	'v': '\v'}

// splitArgs splits at whitespace outside quotes; a backslash escapes
func splitArgs(text string) []string {
	var words []string
	var word strings.Builder
	quote := rune(0)
	escaped := false
	for _, ch := range text {
		switch {
		case escaped:
			word.WriteRune(ch)
			escaped = false
		case ch == '\\':
			word.WriteRune(ch)
			escaped = true
		case quote != 0:
			word.WriteRune(ch)
			if ch == quote {
				quote = 0
			}
		case ch == '"' || ch == '\'':
			word.WriteRune(ch)
			quote = ch
		case unicode.IsSpace(ch):
			if word.Len() > 0 {
				words = append(words, word.String())
			}
			word.Reset()
		default:
			word.WriteRune(ch)
		}
	}
	if word.Len() > 0 {
		words = append(words, word.String())
	}
	return words
}

func unescape(text string) string {
	r := []rune(text)
	var out strings.Builder
	for i := 0; i < len(r); i++ {
		if r[i] == '\\' && i+1 < len(r) {
			if e, ok := swayEscapes[r[i+1]]; ok {
				out.WriteRune(e)
				i++
				continue
			}
		}
		out.WriteRune(r[i])
	}
	return out.String()
}

// stripQuotes takes unescaped quotes out; a ' inside "…" and a " inside
// '…' stay
func stripQuotes(text string) string {
	var out strings.Builder
	inStr, inChr, escaped := false, false, false
	for _, ch := range text {
		switch {
		case ch == '\'' && !inStr && !escaped:
			inChr = !inChr
		case ch == '"' && !inChr && !escaped:
			inStr = !inStr
		default:
			escaped = ch == '\\' && !escaped
			out.WriteRune(ch)
		}
	}
	return out.String()
}

// storedCommand is a bind's command (after its key) as sway keeps it from
// a config file
func storedCommand(text string) string {
	words := splitArgs(text)
	for i, w := range words {
		words[i] = unescape(w)
	}
	return strings.Join(words, " ")
}

// execText is what an `exec` of arguments (as sway keeps them) runs (sway
// drops a leading --no-startup-id)
func execText(arguments string) string {
	words := splitArgs(arguments)
	if len(words) > 0 && words[0] == "--no-startup-id" {
		words = words[1:]
	}
	if len(words) == 1 && (words[0][0] == '"' || words[0][0] == '\'') {
		return stripQuotes(words[0])
	}
	return strings.Join(words, " ")
}

func swayAction(o Options, command string) *jsonx.Object {
	words := strings.Fields(command)
	simple := map[string]string{"kill": "closeWindow", "fullscreen": "fullscreen", "fullscreen toggle": "fullscreen",
		"floating toggle": "toggleFloat", "sticky toggle": "pin", "layout toggle split": "toggleSplit",
		"move position center": "centerWindow", "exit": "exitSession"}
	if action, ok := simple[command]; ok {
		return jsonx.Obj("action", action)
	}
	if len(words) == 2 && words[0] == "focus" && swayDirections[words[1]] {
		return jsonx.Obj("action", "focusDir", "argument", words[1])
	}
	if len(words) == 2 && words[0] == "move" && swayDirections[words[1]] {
		return jsonx.Obj("action", "moveWindowDir", "argument", words[1])
	}
	if len(words) > 0 && words[0] == "exec" {
		argument := execText(string([]rune(command)[4:]))
		if entry := actions.Default().IPCAction(argument); entry != nil {
			return entry
		}
		return jsonx.Obj("action", "exec", "argument", argument)
	}
	return jsonx.Obj("action", "raw", "argument", command, "compositor", "sway")
}

func swayFiles(o Options) []string {
	user := filepath.Join(o.Dir, "user")
	if o.Only != "" {
		if path := filepath.Join(user, o.Only); isFile(path) {
			return []string{path}
		}
		return nil
	}
	// As sway's `include user/*` reads them: no hidden files (a staged
	// write, an editor's swap file), no backups
	var out []string
	entries, _ := os.ReadDir(user)
	for _, e := range entries {
		path := filepath.Join(user, e.Name())
		if isFile(path) && !strings.HasPrefix(e.Name(), ".") && !strings.Contains(e.Name(), ".axiom-backup-") {
			out = append(out, path)
		}
	}
	sort.Strings(out)
	return out
}

// extractSway reads the bindsym and bindcode lines outside a mode, in
// files read in name order as sway includes them, with the $variables set
// in each so far
func extractSway(ctx context.Context, o Options) *jsonx.Object {
	result := emptyResult()
	vars := &userconf.Vars{}
	for _, path := range swayFiles(o) {
		if o.Tracked(ctx, path) {
			push(result, "tracked", path)
		}
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		// The open blocks: whether each is a bindsym/bindcode one
		var blocks []bool
		for n, raw := range userconf.SplitLines(strings.ToValidUTF8(string(data), "�")) {
			number := n + 1
			line := strings.TrimSpace(raw)
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			if m := userconf.SetLine.FindStringSubmatch(line); m != nil {
				vars.Set(m[1], strings.TrimSpace(vars.Expand(m[2])))
				continue
			}
			if strings.HasSuffix(line, "{") {
				blocks = append(blocks, swayBlock.MatchString(line))
				continue
			}
			if line == "}" {
				if len(blocks) > 0 {
					blocks = blocks[:len(blocks)-1]
				}
				continue
			}
			if len(blocks) > 0 && !slices.Contains(blocks, false) {
				combo := strings.Fields(vars.Expand(line))[0]
				push(result, "kept", keptEntry(path, number, combo, "block", ""))
				continue
			}
			bind := swayBind.FindStringSubmatch(line)
			if bind == nil || len(blocks) > 0 {
				continue
			}
			parts := swayParts.FindStringSubmatch(vars.Expand(bind[2]))
			flags := strings.Fields(parts[1])
			combo := parts[2]
			command := storedCommand(parts[3])
			if strings.HasSuffix(strings.TrimRightFunc(raw, unicode.IsSpace), `\`) {
				push(result, "kept", keptEntry(path, number, combo, "continued", ""))
				continue
			}
			var other []string
			device := false
			for _, f := range flags {
				if strings.HasPrefix(f, "--input-device") {
					device = true
				} else if !isSwayFlag(f) && !swayHarmless[f] {
					other = append(other, f)
				}
			}
			if len(other) > 0 || device {
				detail := other
				if len(detail) == 0 {
					detail = flags
				}
				push(result, "kept", keptEntry(path, number, combo, "options", strings.Join(detail, " ")))
				continue
			}
			key := swayKey(combo, bind[1] == "bindcode")
			if key == "" || command == "" {
				push(result, "kept", keptEntry(path, number, combo, "key", ""))
				continue
			}
			entry := jsonx.Obj("key", key)
			action := swayAction(o, command)
			for _, k := range action.Keys() {
				entry.Set(k, action.Value(k))
			}
			for _, f := range swayFlags {
				if slices.Contains(flags, f[0]) {
					entry.Set(f[1], true)
				}
			}
			// Sway repeats a held bind unless told not to, but that's rarely
			// meant (a held close would close one window after another): an
			// action repeats as axiom's own does, a raw command as sway had it
			name, _ := entry.Value("action").(string)
			if !slices.Contains(flags, "--no-repeat") && (actions.Default().Repeating[name] || name == "raw") {
				entry.Set("repeating", true)
			}
			push(result, "binds", entry)
			push(result, "sites", jsonx.Obj("file", path, "line", float64(number), "binds", jsonx.Arr(entry), "text", raw))
		}
	}
	return result
}
