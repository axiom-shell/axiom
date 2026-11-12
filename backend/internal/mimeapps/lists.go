package mimeapps

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/fsx"
)

// The groups of a mimeapps.list
const (
	groupDefault = "Default Applications"
	groupAdded   = "Added Associations"
	groupRemoved = "Removed Associations"
)

// appsList is one mimeapps.list: each group's types and their desktop ids,
// in the file's order.
type appsList map[string]map[string][]string

// parseList reads a mimeapps.list (or defaults.list) text.
func parseList(text string) appsList {
	out := appsList{}
	group := ""
	for line := range strings.Lines(text) {
		line = strings.TrimSpace(line)
		if line == "" || line[0] == '#' {
			continue
		}
		if line[0] == '[' {
			group = strings.Trim(line, "[]")
			continue
		}
		mime, ids, ok := strings.Cut(line, "=")
		if !ok || group == "" {
			continue
		}
		if out[group] == nil {
			out[group] = map[string][]string{}
		}
		out[group][strings.TrimSpace(mime)] = list(ids)
	}
	return out
}

func readList(path string) appsList {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	return parseList(string(data))
}

// setDefaults writes `[Default Applications] mime=id;` for each type into
// the text of a mimeapps.list, keeping everything else as it was: the
// other groups, comments, other types and the order of the lines. A type
// already there gets id put first (the others it listed stay after it);
// a new one is added at the group's end, the group made when missing.
func setDefaults(text string, mimes []string, id string) string {
	lines := strings.Split(strings.TrimRight(text, "\n"), "\n")
	if text == "" {
		lines = nil
	}
	start, end := -1, len(lines)
	for i, line := range lines {
		t := strings.TrimSpace(line)
		if strings.HasPrefix(t, "[") {
			if start >= 0 {
				end = i
				break
			}
			if strings.Trim(t, "[]") == groupDefault {
				start = i
			}
		}
	}
	if start < 0 {
		if len(lines) > 0 && strings.TrimSpace(lines[len(lines)-1]) != "" {
			lines = append(lines, "")
		}
		lines = append(lines, "["+groupDefault+"]")
		start, end = len(lines)-1, len(lines)
	}
	done := map[string]bool{}
	for i := start + 1; i < end; i++ {
		mime, ids, ok := strings.Cut(lines[i], "=")
		mime = strings.TrimSpace(mime)
		if !ok || !contains(mimes, mime) {
			continue
		}
		rest := []string{id}
		for _, other := range list(ids) {
			if other != id {
				rest = append(rest, other)
			}
		}
		lines[i] = mime + "=" + strings.Join(rest, ";") + ";"
		done[mime] = true
	}
	// New types go after the group's last line that isn't blank
	at := end
	for at > start+1 && strings.TrimSpace(lines[at-1]) == "" {
		at--
	}
	var added []string
	for _, mime := range mimes {
		if !done[mime] {
			added = append(added, mime+"="+id+";")
		}
	}
	lines = append(lines[:at], append(added, lines[at:]...)...)
	return strings.Join(lines, "\n") + "\n"
}

// readTerminals reads an xdg-terminals.list: desktop ids, one a line, in
// order (a line's ":action" and comments dropped, "+id" / "-id" read as
// id / skipped as xdg-terminal-exec does).
func readTerminals(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var out []string
	for line := range strings.Lines(string(data)) {
		line = strings.TrimSpace(line)
		if line == "" || line[0] == '#' || line[0] == '-' {
			continue
		}
		line = strings.TrimPrefix(line, "+")
		id, _, _ := strings.Cut(line, ":")
		out = append(out, id)
	}
	return out
}

// setTerminal puts id first in an xdg-terminals.list's text, keeping the
// other lines (an older line for id is dropped).
func setTerminal(text, id string) string {
	out := []string{id}
	for line := range strings.Lines(text) {
		t := strings.TrimSpace(line)
		name, _, _ := strings.Cut(strings.TrimPrefix(t, "+"), ":")
		if t == "" || name == id {
			continue
		}
		out = append(out, strings.TrimRight(line, "\n"))
	}
	return strings.Join(out, "\n") + "\n"
}

// writeText replaces a list file atomically (folders made as needed).
func writeText(path, text string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return fsx.WriteFile(path, []byte(text), 0o644)
}

func contains(list []string, s string) bool {
	for _, v := range list {
		if v == s {
			return true
		}
	}
	return false
}

func jsonUnmarshal(data []byte, v any) error { return json.Unmarshal(data, v) }

// groupRange is the lines [start, end) of group's keys in lines (start is
// the first line after its header), ok false when it isn't there.
func groupRange(lines []string, group string) (start, end int, ok bool) {
	start = -1
	end = len(lines)
	for i, line := range lines {
		t := strings.TrimSpace(line)
		if strings.HasPrefix(t, "[") {
			if start >= 0 {
				end = i
				break
			}
			if strings.Trim(t, "[]") == group {
				start = i + 1
			}
		}
	}
	return start, end, start >= 0
}

// listGroup says whether the text has the group.
func listGroup(text, group string) (int, bool) {
	start, _, ok := groupRange(linesOf(text), group)
	return start, ok
}

// listValue is the value of mime's line in the group, as written.
func listValue(text, group, mime string) (string, bool) {
	lines := linesOf(text)
	start, end, ok := groupRange(lines, group)
	if !ok {
		return "", false
	}
	for _, line := range lines[start:end] {
		if k, v, found := strings.Cut(line, "="); found && strings.TrimSpace(k) == mime {
			return v, true
		}
	}
	return "", false
}

// setListValue sets mime's line in the group to value (nil: removes it),
// and removes the group too when axiom made it (groupMade) and nothing but
// blank lines is left in it, with the blank line before it. Every other
// line stays.
func setListValue(text, group, mime string, value *string, groupMade bool) string {
	lines := linesOf(text)
	start, end, ok := groupRange(lines, group)
	if !ok {
		return text
	}
	for i := start; i < end; i++ {
		if k, _, found := strings.Cut(lines[i], "="); found && strings.TrimSpace(k) == mime {
			if value != nil {
				lines[i] = k + "=" + *value
			} else {
				lines = slices.Delete(lines, i, i+1)
				end--
			}
			break
		}
	}
	if groupMade && value == nil && !slices.ContainsFunc(lines[start:end], func(l string) bool { return strings.TrimSpace(l) != "" }) {
		from := start - 1
		if from > 0 && strings.TrimSpace(lines[from-1]) == "" {
			from--
		}
		lines = slices.Delete(lines, from, end)
	}
	if len(lines) == 0 {
		return ""
	}
	return strings.Join(lines, "\n") + "\n"
}
