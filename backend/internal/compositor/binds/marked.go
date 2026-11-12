package binds

import (
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"unicode/utf8"

	"github.com/axiom-shell/axiom/backend/internal/compositor/edit"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// What comments a moved bind out
const (
	swayMark = "# (moved into axiom) "
	// KDL's /- takes the whole node out, its block too
	niriMark = "/* (moved into axiom) */ /-"
	// Hyprland's: a line comment at each line of the call (the space after
	// -- keeps a line from ever opening a long comment, --[[)
	hyprMark = "-- (moved into axiom) "
)

// markLines puts mark at the start of each line of text
func markLines(text, mark string) string {
	var b strings.Builder
	for _, l := range splitKeepEnds(text) {
		b.WriteString(mark + l)
	}
	return b.String()
}

// UnmarkMoved takes the merge's marks out of text (a compositor config's
// file of kind "sway", "niri" or "hyprland"), giving the binds back: the
// inverse of what removing them did. Pure; any other kind is returned as it
// is.
func UnmarkMoved(kind, text string) string {
	var cut func(string) string
	switch kind {
	case "sway":
		cut = func(l string) string { return strings.TrimPrefix(l, swayMark) }
	case "niri":
		cut = func(l string) string { return strings.ReplaceAll(l, niriMark, "") }
	case "hyprland":
		cut = func(l string) string { return strings.TrimPrefix(l, hyprMark) }
	default:
		return text
	}
	var b strings.Builder
	for _, l := range splitKeepEnds(text) {
		b.WriteString(cut(l))
	}
	return b.String()
}

// removeMarked comments the sites' lines out (sway's, niri's): the mark at
// the line's start, or at the bind's column (atCol), after a dated backup
// of each file it changes in user/.backups/ (a backup beside it in user/
// would be loaded by the managed config's include of user/). A line that
// changed since extract is left. A file that can't be read, backed up or
// written is failed (io) and the others go on: what's done is reported, so
// nothing removed is put back as kept. The bytes are kept as they are (a
// file in another encoding too): only the marks are added.
func removeMarked(o Options, sites *jsonx.Array, mark string, atCol bool) (*jsonx.Object, error) {
	done := jsonx.Obj("removed", float64(0), "files", jsonx.Arr(), "failed", jsonx.Arr())
	user := filepath.Join(o.Dir, "user")
	var files []string
	byFile := map[string][]site{}
	for _, s := range readSites(sites) {
		if _, ok := byFile[s.file]; !ok {
			files = append(files, s.file)
		}
		byFile[s.file] = append(byFile[s.file], s)
	}
	removed := 0
	for _, name := range files {
		if filepath.Dir(filepath.Clean(name)) != filepath.Clean(user) || !fsx.IsFile(name) {
			push(done, "failed", failedEntry(name, 0, "notUser", ""))
			continue
		}
		data, err := os.ReadFile(name)
		if err != nil {
			push(done, "failed", failedEntry(name, 0, "io", err.Error()))
			continue
		}
		lines := splitKeepEnds(string(data))
		// As read: a line holding two binds is checked unmarked for both
		read := slices.Clone(lines)
		fileSites := byFile[name]
		if atCol {
			// Right to left, so a column still points where it did
			sort.SliceStable(fileSites, func(i, j int) bool {
				a, b := fileSites[i], fileSites[j]
				return a.line > b.line || (a.line == b.line && a.col > b.col)
			})
		}
		var marked []site
		for _, s := range fileSites {
			i := s.line - 1
			// Extract read the text with invalid bytes as U+FFFD
			if i < 0 || i >= len(lines) || (s.hasText && strings.ToValidUTF8(strings.TrimRight(read[i], "\r\n"), "\uFFFD") != s.text) {
				push(done, "failed", failedEntry(name, s.line, "changed", ""))
				continue
			}
			if atCol {
				// A column counts characters: one past a run of invalid
				// bytes can't be placed
				at, ok := byteOffset(lines[i], s.col)
				if !ok {
					push(done, "failed", failedEntry(name, s.line, "changed", ""))
					continue
				}
				lines[i] = lines[i][:at] + mark + lines[i][at:]
			} else {
				lines[i] = mark + lines[i]
			}
			marked = append(marked, s)
		}
		if len(marked) == 0 {
			continue
		}
		backups := filepath.Join(user, ".backups")
		err = os.MkdirAll(backups, 0o755)
		if err == nil {
			err = backup(o, name, backups)
		}
		if err == nil {
			err = edit.Replace(name, []byte(strings.Join(lines, "")))
		}
		if err != nil {
			for _, s := range marked {
				push(done, "failed", failedEntry(name, s.line, "io", err.Error()))
			}
			continue
		}
		removed += len(marked)
		push(done, "files", name)
	}
	done.Set("removed", float64(removed))
	return done, nil
}

// byteOffset is where character col of line starts, its bytes valid UTF-8
// up to there; ok false past the end or after an invalid byte
func byteOffset(line string, col int) (int, bool) {
	at := 0
	for n := 0; n < max(col, 0); n++ {
		if at >= len(line) {
			return 0, false
		}
		r, size := utf8.DecodeRuneInString(line[at:])
		if r == utf8.RuneError && size <= 1 {
			return 0, false
		}
		at += size
	}
	return at, true
}

// splitKeepEnds splits text into lines that keep their \n, \r\n or \r
// (str.splitlines(keepends=True))
func splitKeepEnds(text string) []string {
	var lines []string
	start := 0
	for i := 0; i < len(text); i++ {
		switch text[i] {
		case '\n':
			lines = append(lines, text[start:i+1])
			start = i + 1
		case '\r':
			if i+1 < len(text) && text[i+1] == '\n' {
				i++
			}
			lines = append(lines, text[start:i+1])
			start = i + 1
		}
	}
	if start < len(text) {
		lines = append(lines, text[start:])
	}
	return lines
}
