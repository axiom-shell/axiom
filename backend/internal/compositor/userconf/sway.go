package userconf

import (
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
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
		if fsx.IsFile(p) {
			return p
		}
	}
	return ""
}

var includeLine = regexp.MustCompile(`^include\s+(.+)$`)

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
	vars := &render.Vars{}
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
			if m := render.SwaySetLine.FindStringSubmatch(stripped); m != nil {
				vars.Set(m[1], strings.TrimSpace(vars.Expand(m[2])))
			}
			names, ok := SwayIncludes(stripped, path, vars, getenv)
			if !ok {
				if !ours {
					out = append(out, line)
				}
				continue
			}
			for _, name := range names {
				out = append(out, inline(name))
			}
		}
		return strings.Join(out, "\n")
	}
	text = inline(main)
	return text, unread
}

// SwayIncludes are the files an `include` line (trimmed) in the file from
// reads, as sway's wordexp reads it: one path or several, quoted or not,
// environment variables, ~ and the $variables set so far expanded, each a
// glob relative to from's folder. ok: line is an include.
func SwayIncludes(line, from string, vars *render.Vars, getenv func(string) string) (names []string, ok bool) {
	m := includeLine.FindStringSubmatch(line)
	if m == nil {
		return nil, false
	}
	text := vars.Expand(strings.TrimSpace(m[1]))
	words, err := shellSplit(text)
	if err != nil {
		words = []string{strings.Trim(text, `"'`)}
	}
	for _, word := range words {
		pattern := expandUser(expandVars(word, getenv), getenv)
		if !filepath.IsAbs(pattern) {
			pattern = filepath.Join(filepath.Dir(from), pattern)
		}
		for _, name := range glob(pattern) {
			if fsx.IsFile(name) {
				names = append(names, name)
			}
		}
	}
	return names, true
}

// SwayVars sets into vars the $variables the files at paths set, as sway
// reads them: in order, an include's files where it is, each file once
// (seen: the files read so far, shared by the calls of one walk).
func SwayVars(paths []string, vars *render.Vars, seen map[string]bool, getenv func(string) string) {
	var read func(path string)
	read = func(path string) {
		real := realPath(path)
		if seen[real] {
			return
		}
		seen[real] = true
		data, err := os.ReadFile(path)
		if err != nil {
			return
		}
		for _, line := range SplitLines(strings.ToValidUTF8(string(data), "�")) {
			line = strings.TrimSpace(line)
			if m := render.SwaySetLine.FindStringSubmatch(line); m != nil {
				vars.Set(m[1], strings.TrimSpace(vars.Expand(m[2])))
			} else if names, ok := SwayIncludes(line, path, vars, getenv); ok {
				for _, name := range names {
					read(name)
				}
			}
		}
	}
	for _, path := range paths {
		read(path)
	}
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
