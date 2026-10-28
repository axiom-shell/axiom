package userconf

import (
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

var swaySocketPID = regexp.MustCompile(`sway-ipc\.\d+\.(\d+)\.sock$`)

// SwayMain is the config the running sway was started with (-c in the
// command line of the sway $SWAYSOCK names), else the first of the places
// sway looks, or "" with none.
func SwayMain(getenv func(string) string) string {
	var places []string
	if m := swaySocketPID.FindStringSubmatch(getenv("SWAYSOCK")); m != nil {
		// A SWAYSOCK left over from an earlier session can name a pid some
		// other process has since
		if config, isSway := startedWith(m[1], "sway"); isSway && config != "" {
			places = append(places, config)
		}
	}
	home, xdg := getenv("HOME"), configHome(getenv)
	places = append(places, filepath.Join(home, ".sway/config"), filepath.Join(xdg, "sway/config"),
		filepath.Join(home, ".i3/config"), filepath.Join(xdg, "i3/config"), "/etc/sway/config")
	for _, p := range places {
		if isFile(p) {
			return p
		}
	}
	return ""
}

// Vars are sway's $variables as set so far, in the order they were set.
type Vars struct {
	names  []string
	values map[string]string
}

// Set sets name (with its $) to value.
func (v *Vars) Set(name, value string) {
	if v.values == nil {
		v.values = map[string]string{}
	}
	if _, ok := v.values[name]; !ok {
		v.names = append(v.names, name)
	}
	v.values[name] = value
}

// Expand puts the variables into text, the longest names first (so $mod
// doesn't take $modifier's place).
func (v *Vars) Expand(text string) string {
	names := append([]string(nil), v.names...)
	sort.SliceStable(names, func(i, j int) bool { return len(names[i]) > len(names[j]) })
	for _, name := range names {
		text = strings.ReplaceAll(text, name, v.values[name])
	}
	return text
}

var (
	// SetLine is a `set $name value` line (trimmed)
	SetLine     = regexp.MustCompile(`^set\s+(\$\S+)\s+(.*)$`)
	includeLine = regexp.MustCompile(`^include\s+(.+)$`)
)

// SwayText is the sway config main with its includes put in, each file
// once (one path or several, globs, ~, environment variables and the
// $variables set before them, relative to the including file's folder).
// Files in skip (axiom's own) are left out; a file starting with
// skipHeader gives only what it includes (axiom's managed config: only
// what it includes is the user's). unread are the files that couldn't be
// read, left out.
func SwayText(main string, skip []string, skipHeader string, getenv func(string) string) (text string, unread []string) {
	skipped := map[string]bool{}
	for _, p := range skip {
		skipped[realPath(expandUser(p, getenv))] = true
	}
	seen := map[string]bool{}
	vars := &Vars{}
	var inline func(path string) string
	inline = func(path string) string {
		real := realPath(path)
		if seen[real] || skipped[real] {
			return ""
		}
		seen[real] = true
		data, err := os.ReadFile(path)
		if err != nil {
			unread = append(unread, path)
			return ""
		}
		lines := SplitLines(strings.ToValidUTF8(string(data), "�"))
		out := []string{"# axiom: from " + path}
		ours := skipHeader != "" && len(lines) > 0 && strings.HasPrefix(lines[0], skipHeader)
		for _, line := range lines {
			stripped := strings.TrimSpace(line)
			if m := SetLine.FindStringSubmatch(stripped); m != nil {
				vars.Set(m[1], strings.TrimSpace(vars.Expand(m[2])))
			}
			m := includeLine.FindStringSubmatch(stripped)
			if m == nil {
				if !ours {
					out = append(out, line)
				}
				continue
			}
			// As sway's wordexp reads it: one path or several, quoted or
			// not, environment variables and ~ expanded, each a glob
			text := vars.Expand(strings.TrimSpace(m[1]))
			words, err := shellSplit(text)
			if err != nil {
				words = []string{strings.Trim(text, `"'`)}
			}
			for _, word := range words {
				pattern := expandUser(expandVars(word, getenv), getenv)
				if !filepath.IsAbs(pattern) {
					pattern = filepath.Join(filepath.Dir(path), pattern)
				}
				for _, name := range glob(pattern) {
					if isFile(name) {
						out = append(out, inline(name))
					}
				}
			}
		}
		return strings.Join(out, "\n")
	}
	text = inline(main)
	return text, unread
}

// SplitLines splits text into lines at \n, \r\n or \r, without a last
// empty one (str.splitlines).
func SplitLines(text string) []string {
	text = strings.ReplaceAll(text, "\r\n", "\n")
	text = strings.ReplaceAll(text, "\r", "\n")
	if text == "" {
		return nil
	}
	return strings.Split(strings.TrimSuffix(text, "\n"), "\n")
}

// expandUser puts $HOME in for a leading ~ (~ or ~/…)
func expandUser(path string, getenv func(string) string) string {
	if path == "~" || strings.HasPrefix(path, "~/") {
		return getenv("HOME") + path[1:]
	}
	return path
}

// glob is pattern's matches, sorted, leaving out hidden names a wildcard
// matched (as Python's and the shell's globs do)
func glob(pattern string) []string {
	matches, _ := filepath.Glob(pattern)
	parts := strings.Split(filepath.Clean(pattern), "/")
	var out []string
	for _, m := range matches {
		got := strings.Split(filepath.Clean(m), "/")
		hidden := false
		for i := range min(len(parts), len(got)) {
			magic := strings.ContainsAny(parts[i], "*?[")
			if magic && !strings.HasPrefix(parts[i], ".") && strings.HasPrefix(got[i], ".") {
				hidden = true
			}
		}
		if !hidden {
			out = append(out, m)
		}
	}
	sort.Strings(out)
	return out
}

// shellSplit splits text into words as a POSIX shell (shlex.split): quotes
// group, a backslash escapes outside single quotes
func shellSplit(text string) ([]string, error) {
	var words []string
	var word strings.Builder
	inWord := false
	quote := rune(0)
	escaped := false
	for _, ch := range text {
		switch {
		case escaped:
			// In double quotes a backslash escapes only " and \ itself
			if quote == '"' && ch != '"' && ch != '\\' {
				word.WriteRune('\\')
			}
			word.WriteRune(ch)
			escaped = false
		case ch == '\\' && quote != '\'':
			escaped, inWord = true, true
		case quote != 0:
			if ch == quote {
				quote = 0
			} else {
				word.WriteRune(ch)
			}
		case ch == '"' || ch == '\'':
			quote, inWord = ch, true
		case ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r':
			if inWord {
				words = append(words, word.String())
				word.Reset()
				inWord = false
			}
		default:
			word.WriteRune(ch)
			inWord = true
		}
	}
	if quote != 0 {
		return nil, errors.New("no closing quotation")
	}
	if escaped {
		return nil, errors.New("no escaped character")
	}
	if inWord {
		words = append(words, word.String())
	}
	return words, nil
}
