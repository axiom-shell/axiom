package mimeapps

import (
	"bufio"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
)

// Entry is a desktop entry, as much of it as choosing and starting an app
// takes.
type Entry struct {
	ID         string   `json:"id"` // "org.gnome.Nautilus.desktop"
	Name       string   `json:"name"`
	Icon       string   `json:"icon"`
	Exec       string   `json:"-"`
	Terminal   bool     `json:"terminal"`
	MimeTypes  []string `json:"-"`
	Categories []string `json:"-"`
	NoDisplay  bool     `json:"-"`
	// The argument a terminal takes before the command it runs
	// (X-TerminalArgExec, xdg-terminal-exec's; "-e" when it says none)
	TerminalArg string `json:"-"`
	Path        string `json:"-"` // the file
}

// handles: the entry declares the type (MimeType=)
func (e Entry) handles(mime string) bool { return slices.Contains(e.MimeTypes, mime) }

// isTerminal: a terminal emulator (Categories=TerminalEmulator)
func (e Entry) isTerminal() bool { return slices.Contains(e.Categories, "TerminalEmulator") }

// readEntry reads a desktop entry's [Desktop Entry] group; ok false for a
// file that isn't an application to offer (Hidden, another Type, its
// TryExec missing).
func readEntry(path, id string, lookPath func(string) (string, error)) (Entry, bool) {
	f, err := os.Open(path)
	if err != nil {
		return Entry{}, false
	}
	defer f.Close()
	e := Entry{ID: id, Path: path}
	group := ""
	kind, tryExec, hidden := "", "", false
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 64<<10), 1<<20)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || line[0] == '#' {
			continue
		}
		if line[0] == '[' {
			group = strings.Trim(line, "[]")
			continue
		}
		if group != "Desktop Entry" {
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		k, v = strings.TrimSpace(k), unescapeValue(strings.TrimSpace(v))
		switch k {
		case "Type":
			kind = v
		case "Name":
			e.Name = v
		case "Icon":
			e.Icon = v
		case "Exec":
			e.Exec = v
		case "TryExec":
			tryExec = v
		case "Terminal":
			e.Terminal = v == "true"
		case "NoDisplay":
			e.NoDisplay = v == "true"
		case "Hidden":
			hidden = v == "true"
		case "MimeType":
			e.MimeTypes = list(v)
		case "Categories":
			e.Categories = list(v)
		case "X-TerminalArgExec":
			e.TerminalArg = v
		}
	}
	if kind != "Application" || hidden || e.Exec == "" {
		return Entry{}, false
	}
	if tryExec != "" && lookPath != nil {
		if _, err := lookPath(tryExec); err != nil {
			return Entry{}, false
		}
	}
	if e.Name == "" {
		e.Name = strings.TrimSuffix(id, ".desktop")
	}
	return e, true
}

// list splits a ;-separated value ("a;b;" → [a b])
func list(v string) []string {
	var out []string
	for _, s := range strings.Split(v, ";") {
		if s = strings.TrimSpace(s); s != "" {
			out = append(out, s)
		}
	}
	return out
}

// unescapeValue undoes a key file's escapes (\s \n \t \r \\); \; stays
// for list() to see as a literal semicolon
func unescapeValue(v string) string {
	if !strings.Contains(v, `\`) {
		return v
	}
	var b strings.Builder
	for i := 0; i < len(v); i++ {
		if v[i] != '\\' || i+1 == len(v) {
			b.WriteByte(v[i])
			continue
		}
		i++
		switch v[i] {
		case 's':
			b.WriteByte(' ')
		case 'n':
			b.WriteByte('\n')
		case 't':
			b.WriteByte('\t')
		case 'r':
			b.WriteByte('\r')
		case '\\':
			b.WriteByte('\\')
		default:
			b.WriteByte('\\')
			b.WriteByte(v[i])
		}
	}
	return b.String()
}

// scanEntries reads every applications folder (the first holding an id
// wins: data home before data dirs), ids made as the spec says
// (kde4/foo.desktop is kde4-foo.desktop).
func scanEntries(appDirs []string) map[string]Entry {
	entries := map[string]Entry{}
	for _, dir := range appDirs {
		filepath.WalkDir(dir, func(path string, d os.DirEntry, err error) error {
			if err != nil || d.IsDir() || !strings.HasSuffix(path, ".desktop") {
				return nil
			}
			rel, _ := filepath.Rel(dir, path)
			id := strings.ReplaceAll(rel, string(filepath.Separator), "-")
			if _, seen := entries[id]; seen {
				return nil
			}
			// An id seen in an earlier folder that's hidden there hides
			// it here too: record the refusal as a zero entry
			if e, ok := readEntry(path, id, exec.LookPath); ok {
				entries[id] = e
			} else {
				entries[id] = Entry{}
			}
			return nil
		})
	}
	for id, e := range entries {
		if e.ID == "" {
			delete(entries, id)
		}
	}
	return entries
}

// Argv is the command the entry runs for the files or URLs given, its
// Exec line's field codes expanded (%f %u one, %F %U all, %i its icon, %c
// its name, %k its file; the rest dropped), quoting as the spec has it.
// No argument and %f/%u: none is passed.
func (e Entry) Argv(args []string) []string {
	words := splitExec(e.Exec)
	var out []string
	used := false
	for _, w := range words {
		switch w {
		case "%f", "%u":
			if len(args) > 0 {
				out = append(out, args[0])
			}
			used = true
			continue
		case "%F", "%U":
			out = append(out, args...)
			used = true
			continue
		case "%i":
			if e.Icon != "" {
				out = append(out, "--icon", e.Icon)
			}
			continue
		}
		// Codes inside a word, and %% for a percent sign
		var b strings.Builder
		for i := 0; i < len(w); i++ {
			if w[i] != '%' || i+1 == len(w) {
				b.WriteByte(w[i])
				continue
			}
			i++
			switch w[i] {
			case '%':
				b.WriteByte('%')
			case 'c':
				b.WriteString(e.Name)
			case 'k':
				b.WriteString(e.Path)
			case 'f', 'u':
				if len(args) > 0 {
					b.WriteString(args[0])
				}
				used = true
			}
		}
		if b.Len() > 0 || !strings.HasPrefix(w, "%") {
			out = append(out, b.String())
		}
	}
	// An Exec without a file code still gets what it was asked to open
	// (as gio and xdg-open do), so `axiom open firefox-url` isn't lost
	if !used && len(args) > 0 {
		out = append(out, args...)
	}
	return out
}

// splitExec splits an Exec value into words: spaces separate them, a
// double-quoted word keeps its spaces, and inside quotes \" \` \$ \\
// are the character itself.
func splitExec(s string) []string {
	var words []string
	var b strings.Builder
	inWord, quoted := false, false
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case quoted && c == '\\' && i+1 < len(s) && strings.ContainsRune("\"`$\\", rune(s[i+1])):
			i++
			b.WriteByte(s[i])
		case c == '"':
			quoted = !quoted
			inWord = true
		case !quoted && (c == ' ' || c == '\t'):
			if inWord {
				words = append(words, b.String())
				b.Reset()
				inWord = false
			}
		default:
			b.WriteByte(c)
			inWord = true
		}
	}
	if inWord {
		words = append(words, b.String())
	}
	return words
}
