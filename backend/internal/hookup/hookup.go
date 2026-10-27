// Package hookup decides how the line loading axiom's file goes into an
// app's own config (a ThemeIntegrations switch's x-hookup targets, and the
// compositor's include and autostart lines): whether it's there already,
// what Apply would change, and the edited text. Pure: the edge
// (compositor/edit) reads the files, finds what may be written, and writes.
package hookup

import (
	"encoding/json"
	"errors"
	"fmt"
	"path"
	"regexp"
	"slices"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/theme/integrations"
)

// The places a target's text goes.
const (
	End     = "end"     // appended, so it's read last and wins
	Start   = "start"   // first (CSS: @import must come first)
	Top     = "top"     // before the first [section] (TOML keys, INI main)
	Section = "section" // inside [Section], added at the end when missing
	ShellRC = "shellrc" // $SHELL's rc file (fish: conf.d/axiom.fish, as set -gx)
	Copy    = "copy"    // From copied to File when that's missing
)

// Why a target is skipped (Row.Skipped).
const (
	SkipShell    = "shell"    // a ShellRC target under a shell it doesn't know
	SkipRequires = "requires" // Requires isn't installed
	SkipProfiles = "profiles" // a PerProfile target with no profile found
	SkipReadonly = "readonly" // the file (or its folder) can't be written
)

// Target is one x-hookup entry: something Apply can do ({file, text,
// place}), or a text to copy by hand ({text, where}).
type Target struct {
	// File is a path, or candidates of which the first existing one is
	// used, with {config}, {state} and {home}
	File  Files  `json:"file,omitempty"`
	Text  string `json:"text"`
	Place string `json:"place,omitempty"`
	// Section is the [section] of a Section target
	Section string `json:"section,omitempty"`
	// Comment is the format's comment prefix ("#" when empty)
	Comment string `json:"comment,omitempty"`
	// Accept is a regexp: a line matching it anywhere (not commented out)
	// means the target is done, however it's spelled
	Accept string `json:"accept,omitempty"`
	// Replace is what happens to a line already setting a key the text
	// sets: "comment" (the default: commented out), "keep" (left beside
	// it) or "conflict" (nothing is done)
	Replace string `json:"replace,omitempty"`
	// Requires names a command without which the target is skipped
	Requires string `json:"requires,omitempty"`
	// From is a Copy target's source, relative to the tree's scripts/
	From string `json:"from,omitempty"`
	// WrapLink: a link to a file the user can't write is replaced by a
	// file holding this ({link}: the file it pointed at) and the text
	WrapLink string `json:"wrapLink,omitempty"`
	// PerProfile repeats the target in each browser profile (File is then
	// relative to the profile's folder)
	PerProfile bool `json:"perProfile,omitempty"`
	// Where says where a copy-only text goes; Note replaces the line about
	// where the text goes; Title names the target above its path
	Where string `json:"where,omitempty"`
	Note  string `json:"note,omitempty"`
	Title string `json:"title,omitempty"`
}

// Files is a target's file: one path, or candidates (JSON: a string or a
// list).
type Files []string

// UnmarshalJSON reads a string or a list of strings.
func (f *Files) UnmarshalJSON(data []byte) error {
	var one string
	if err := json.Unmarshal(data, &one); err == nil {
		*f = Files{one}
		return nil
	}
	var list []string
	if err := json.Unmarshal(data, &list); err != nil {
		return errors.New("file must be a path or a list of paths")
	}
	*f = list
	return nil
}

// Resolved is a target with its file chosen and its text filled in.
type Resolved struct {
	Target
	// Path is the file the target edits ("" for a copy-only one)
	Path    string
	Shell   string
	Skipped string
}

// Env is what resolving a target needs to know of the session.
type Env struct {
	Dirs    integrations.Dirs
	Shell   string // $SHELL
	ZDotDir string // $ZDOTDIR
	// Exists says whether a candidate file is there (a dangling link counts)
	Exists func(string) bool
}

// Resolve fills each target's {config}, {state} and {home} and picks its
// file: $SHELL's rc for a ShellRC target (fish's lines become set -gx),
// else the first of its candidates that exists (or the first). A
// PerProfile target is repeated for every profile folder, its file
// relative to it; with none, it's skipped (SkipProfiles).
func Resolve(targets []Target, profiles []string, env Env) []Resolved {
	var out []Resolved
	for _, t := range targets {
		if !t.PerProfile {
			out = append(out, resolve(t, env))
			continue
		}
		if len(profiles) == 0 {
			t.File = nil
			r := resolve(t, env)
			r.Skipped = SkipProfiles
			out = append(out, r)
		}
		for _, dir := range profiles {
			each := t
			each.File = nil
			for _, f := range t.File {
				each.File = append(each.File, path.Join(dir, f))
			}
			out = append(out, resolve(each, env))
		}
	}
	return out
}

func resolve(t Target, env Env) Resolved {
	r := Resolved{Target: t}
	r.Text = env.Dirs.Expand(t.Text)
	if t.Place == ShellRC {
		r.Shell = path.Base(env.Shell)
		switch r.Shell {
		case "zsh":
			r.Path = cmpOr(env.ZDotDir, env.Dirs.Home) + "/.zshrc"
		case "bash":
			r.Path = env.Dirs.Home + "/.bashrc"
		case "fish":
			r.Path = env.Dirs.Config + "/fish/conf.d/axiom.fish"
			lines := strings.Split(r.Text, "\n")
			for i, line := range lines {
				if m := export.FindStringSubmatch(strings.TrimSpace(line)); m != nil {
					lines[i] = "set -gx " + m[1] + " " + m[2]
				}
			}
			r.Text = strings.Join(lines, "\n")
		default:
			r.Skipped = SkipShell
		}
		return r
	}
	for _, f := range t.File {
		if f = env.Dirs.Expand(f); env.Exists(f) {
			r.Path = f
			return r
		}
	}
	if len(t.File) > 0 {
		r.Path = env.Dirs.Expand(t.File[0])
	}
	return r
}

func cmpOr(a, b string) string {
	if a != "" {
		return a
	}
	return b
}

// Facts are what the edge found about a resolved target's file.
type Facts struct {
	// Real is Path with its links followed; Link: Path is (or passes
	// through) a link
	Real string
	Link bool
	// Exists: Real is a regular file, its lines Lines
	Exists bool
	Lines  []string
	// Writable: Real and its folder (the nearest existing one when it's
	// missing) may be written; CanWrap: Path is a link in a folder that
	// may (for WrapLink)
	Writable, CanWrap bool
}

// Row is what the settings show for one target (hookup.status).
type Row struct {
	Text           string   `json:"text"`
	Place          string   `json:"place"`
	Skipped        string   `json:"skipped"`
	Where          string   `json:"where"`
	Note           string   `json:"note"`
	Title          string   `json:"title"`
	CopyOnly       bool     `json:"copyOnly"`
	Exists         bool     `json:"exists"`
	Link           bool     `json:"link"`
	Done           bool     `json:"done"`
	Replaces       []string `json:"replaces"`
	Alongside      []string `json:"alongside"`
	Conflicts      []string `json:"conflicts"`
	CreatesSection bool     `json:"createsSection"`
	Wraps          bool     `json:"wraps"`
	Shell          string   `json:"shell"`
	Section        string   `json:"section"`
	Requires       string   `json:"requires"`
	// Path and Resolved are the file as named and with its links followed
	Path     string `json:"path"`
	Resolved string `json:"resolved"`
}

// Plan is what applying a target would do.
type Plan struct {
	Row
	// missing are the text's lines not there yet; [start, end) the lines
	// the target's keys live in
	missing    []string
	start, end int
}

// Pending says whether Apply has something to write.
func (p Plan) Pending() bool {
	return !p.CopyOnly && p.Skipped == "" && !p.Done && len(p.Conflicts) == 0
}

var (
	header      = regexp.MustCompile(`^\s*\[`)
	namedHeader = regexp.MustCompile(`^\s*\[\s*([^\[\]"]+?)\s*\]\s*(?:[#;].*)?$`)
	export      = regexp.MustCompile(`^export\s+([A-Za-z_][A-Za-z0-9_]*)=(.*)$`)
)

// Decide plans a resolved target against what the edge found about its
// file. An Accept that isn't a valid regexp is an error.
func Decide(r Resolved, f Facts) (Plan, error) {
	p := Plan{Row: Row{Text: r.Text, Place: r.Place, Skipped: r.Skipped, Where: r.Where, Note: r.Note, Title: r.Title,
		CopyOnly: r.Path == "" && r.Skipped == "", Replaces: []string{}, Alongside: []string{}, Conflicts: []string{},
		Shell: r.Shell, Section: r.Section, Requires: r.Requires}}
	if r.Path == "" || p.Skipped != "" {
		return p, nil
	}
	p.Exists, p.Link, p.Path, p.Resolved = f.Exists, f.Link, r.Path, f.Real
	if r.Place == Copy {
		p.Done = f.Exists
		if !p.Done && !f.Writable {
			p.Skipped = SkipReadonly
		}
		return p, nil
	}
	var accept *regexp.Regexp
	if r.Accept != "" {
		var err error
		if accept, err = regexp.Compile(r.Accept); err != nil {
			return p, fmt.Errorf("accept: %w", err)
		}
	}
	if !f.Writable {
		// A link to a file the user doesn't own: replaced by a file loading
		// it when the target says how, else left alone
		if f.CanWrap && r.WrapLink != "" {
			p.Wraps = true
		} else {
			p.Skipped = SkipReadonly
		}
	}
	lines := f.Lines
	start, end, found := scope(lines, r.Place, r.Section)
	if !found {
		p.CreatesSection = true
		start, end = len(lines), len(lines)
	}
	region := make([]string, 0, end-start)
	for _, line := range lines[start:end] {
		region = append(region, strings.TrimSpace(line))
	}
	var missing []string
	for _, line := range strings.Split(r.Text, "\n") {
		if t := strings.TrimSpace(line); t != "" && !slices.Contains(region, t) {
			missing = append(missing, line)
		}
	}
	// An equivalent line anywhere (another spelling of the path, a key set
	// elsewhere) counts as hooked up too
	if accept != nil && slices.ContainsFunc(lines, func(line string) bool {
		return !isComment(line, r.comment()) && accept.MatchString(strings.TrimSpace(line))
	}) {
		missing = nil
	}
	p.Done = f.Exists && len(missing) == 0
	if p.Done {
		p.Skipped, p.Wraps = "", false
	} else if p.Skipped != "" {
		return p, nil
	}
	p.missing, p.start, p.end = missing, start, end
	if keys := r.keys(missing); len(keys) > 0 {
		same := []string{}
		for _, line := range lines[start:end] {
			if !isComment(line, r.comment()) && slices.Contains(keys, keyOf(line, r.Place)) {
				same = append(same, strings.TrimSpace(line))
			}
		}
		switch r.Replace {
		case "keep":
			p.Alongside = same
		case "conflict":
			p.Conflicts = same
		default:
			p.Replaces = same
		}
	}
	return p, nil
}

// Edit is the file's lines with a Pending plan applied. A line setting a
// key the text sets is commented out unless Replace says otherwise;
// nothing is deleted. A wrapped link's new file is WrapLink, then the text.
func Edit(r Resolved, p Plan, lines []string) []string {
	if p.Wraps {
		return append([]string{strings.ReplaceAll(r.WrapLink, "{link}", p.Resolved)}, p.missing...)
	}
	lines = slices.Clone(lines)
	if r.Replace == "" || r.Replace == "comment" {
		keys := r.keys(p.missing)
		for i := p.start; i < p.end; i++ {
			if !isComment(lines[i], r.comment()) && slices.Contains(keys, keyOf(lines[i], r.Place)) {
				lines[i] = r.comment() + " axiom: " + lines[i]
			}
		}
	}
	switch {
	case r.Place == Start:
		return slices.Insert(lines, 0, p.missing...)
	case r.Place == Top || r.Place == Section && !p.CreatesSection:
		// After any blank lines ending the block, so the text reads as
		// part of it, not of the section below
		at := p.end
		for at > p.start && strings.TrimSpace(lines[at-1]) == "" {
			at--
		}
		return slices.Insert(lines, at, p.missing...)
	}
	if len(lines) > 0 && strings.TrimSpace(lines[len(lines)-1]) != "" {
		lines = append(lines, "")
	}
	if r.Place == Section {
		lines = append(lines, "["+r.Section+"]")
	}
	return append(lines, p.missing...)
}

// Lines splits a file's text into lines (a last newline ends the last
// line, and a \r stays on its line).
func Lines(text string) []string {
	if text == "" {
		return nil
	}
	return strings.Split(strings.TrimSuffix(text, "\n"), "\n")
}

// Text is lines joined, newline-terminated.
func Text(lines []string) string { return strings.Join(lines, "\n") + "\n" }

func (r Resolved) comment() string { return cmpOr(r.Comment, "#") }

// keys are the keys the missing lines set, where a second setting of a key
// matters (fish's set -gx lines are never matched)
func (r Resolved) keys(missing []string) []string {
	if (r.Place != Top && r.Place != Section && r.Place != ShellRC) || r.Shell == "fish" {
		return nil
	}
	var keys []string
	for _, line := range missing {
		if k := keyOf(line, r.Place); k != "" {
			keys = append(keys, k)
		}
	}
	return keys
}

// scope is [start, end) of the lines a target's keys live in; found is
// false for a Section that isn't there.
func scope(lines []string, place, section string) (start, end int, found bool) {
	next := func(from int) int {
		for i := from; i < len(lines); i++ {
			if header.MatchString(lines[i]) {
				return i
			}
		}
		return len(lines)
	}
	switch place {
	case Top:
		return 0, next(0), true
	case Section:
		for i, line := range lines {
			if m := namedHeader.FindStringSubmatch(line); m != nil && m[1] == section {
				return i + 1, next(i + 1), true
			}
		}
		return 0, 0, false
	}
	return 0, len(lines), true
}

// keyOf is the key a config line sets ("" for none): KEY in export KEY=…
// for a shell rc, else what's before = (not in a comment or a header).
func keyOf(line, place string) string {
	line = strings.TrimSpace(line)
	if place == ShellRC {
		if m := export.FindStringSubmatch(line); m != nil {
			return m[1]
		}
		return ""
	}
	if line == "" || strings.ContainsRune("#;[", rune(line[0])) {
		return ""
	}
	key, _, ok := strings.Cut(line, "=")
	if !ok {
		return ""
	}
	return strings.TrimSpace(key)
}

func isComment(line, comment string) bool {
	s := strings.TrimLeft(line, " \t")
	return strings.HasPrefix(s, comment) || strings.HasPrefix(s, "#") || strings.HasPrefix(s, ";")
}

// Shown is a path with $HOME as ~.
func Shown(p, home string) string {
	home = strings.TrimRight(home, "/")
	if home != "" && (p == home || strings.HasPrefix(p, home+"/")) {
		return "~" + p[len(home):]
	}
	return p
}
