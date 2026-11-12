package hookup

import (
	"slices"
	"strings"
	"testing"
)

// edited applies a target to text and returns the edit's record
func edited(t *testing.T, target Target, before string) (after []string, rec EditRecord) {
	t.Helper()
	r, p, lines := plan(t, target, before, before != "")
	if !p.Pending() {
		t.Fatalf("nothing to do: %+v", p.Row)
	}
	return Edit(r, p, lines)
}

var undoCases = []struct {
	name   string
	target Target
	before string
}{
	{"start", Target{File: Files{"{config}/gtk.css"}, Place: Start, Text: `@import url("axiom.css");`}, "window { color: red; }\n"},
	{"end", Target{File: Files{"{config}/kitty.conf"}, Place: End, Text: "include axiom.conf"}, "font_size 12\n"},
	{"end after a blank", Target{File: Files{"{config}/kitty.conf"}, Place: End, Text: "include axiom.conf"}, "font_size 12\n\n"},
	{"end of a new file", Target{File: Files{"{config}/kitty.conf"}, Place: End, Text: "include axiom.conf"}, ""},
	{"top", Target{File: Files{"{config}/helix.toml"}, Place: Top, Text: `theme = "axiom"`}, "theme = \"onedark\"\n\n[editor]\nline-number = \"relative\"\n"},
	{"section", Target{File: Files{"{config}/theme.toml"}, Place: Section, Section: "flavor", Text: "dark = \"axiom\""}, "[flavor]\ndark = \"x\"\n\n[mgr]\nfoo = 1\n"},
	{"new section", Target{File: Files{"{config}/theme.toml"}, Place: Section, Section: "flavor", Text: "dark = \"axiom\""}, "[mgr]\nfoo = 1\n"},
	{"shellrc", Target{Place: ShellRC, Replace: "keep", Text: "export FZF_DEFAULT_OPTS_FILE={state}/axiom/fzf-colors"}, "export A=1\n"},
	{"two lines", Target{File: Files{"{config}/theme.toml"}, Place: Section, Section: "flavor", Text: "dark = \"axiom\"\nlight = \"axiom\""}, "[flavor]\n[mgr]\n"},
}

// Undo of an Edit gives back the file it started from, byte for byte
func TestEditRecordsWhatItInserted(t *testing.T) {
	t.Parallel()
	for _, c := range undoCases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			after, rec := edited(t, c.target, c.before)
			if len(rec.Inserted) == 0 {
				t.Fatalf("no inserted lines recorded: %+v", rec)
			}
			for _, in := range rec.Inserted {
				if in.Index < 0 || in.Index >= len(after) || after[in.Index] != in.Text {
					t.Errorf("inserted %q isn't at %d in %q", in.Text, in.Index, after)
				}
			}
			out, gone := Undo(after, rec)
			if len(gone) != 0 {
				t.Errorf("gone %q", gone)
			}
			if got := strings.Join(out, "\n"); got != strings.Join(Lines(c.before), "\n") {
				t.Errorf("undone to %q, want %q", got, c.before)
			}
		})
	}
}

func TestUndoRemovesOnlyInsertedLines(t *testing.T) {
	t.Parallel()
	rec := EditRecord{Comment: "#", Inserted: []Inserted{{"include axiom.conf", 1}}}
	out, _ := Undo([]string{"a", "include axiom.conf", "b", "include other.conf"}, rec)
	if want := []string{"a", "b", "include other.conf"}; !slices.Equal(out, want) {
		t.Errorf("%q", out)
	}
}

func TestUndoUncommentsReplacedLines(t *testing.T) {
	t.Parallel()
	after, rec := edited(t, Target{File: Files{"{config}/helix.toml"}, Place: Top, Text: `theme = "axiom"`}, "theme = \"onedark\"\n")
	if !slices.Equal(rec.Commented, []string{`theme = "onedark"`}) {
		t.Fatalf("%+v", rec)
	}
	if out, _ := Undo(after, rec); !slices.Equal(out, []string{`theme = "onedark"`}) {
		t.Errorf("%q", out)
	}
}

func TestUndoKeepsUserEditsElsewhere(t *testing.T) {
	t.Parallel()
	after, rec := edited(t, Target{File: Files{"{config}/kitty.conf"}, Place: End, Text: "include axiom.conf"}, "font_size 12\n")
	after = slices.Insert(after, 0, "# my line")
	after = append(after, "tail 1")
	out, gone := Undo(after, rec)
	if want := []string{"# my line", "font_size 12", "tail 1"}; !slices.Equal(out, want) || len(gone) != 0 {
		t.Errorf("%q (gone %q)", out, gone)
	}
}

func TestUndoOfAGoneLineIsOK(t *testing.T) {
	t.Parallel()
	rec := EditRecord{Comment: "#", Inserted: []Inserted{{"include axiom.conf", 1}}}
	out, gone := Undo([]string{"a", "b"}, rec)
	if !slices.Equal(out, []string{"a", "b"}) || !slices.Equal(gone, []string{"include axiom.conf"}) {
		t.Errorf("%q gone %q", out, gone)
	}
}

func TestUndoRemovesACreatedEmptySection(t *testing.T) {
	t.Parallel()
	after, rec := edited(t, Target{File: Files{"{config}/theme.toml"}, Place: Section, Section: "flavor", Text: "dark = \"axiom\""}, "[mgr]\nfoo = 1\n")
	if rec.CreatedSection != "flavor" {
		t.Fatalf("%+v", rec)
	}
	if out, _ := Undo(after, rec); slices.Contains(out, "[flavor]") {
		t.Errorf("%q", out)
	}
}

func TestUndoKeepsASectionTheUserAddedTo(t *testing.T) {
	t.Parallel()
	after, rec := edited(t, Target{File: Files{"{config}/theme.toml"}, Place: Section, Section: "flavor", Text: "dark = \"axiom\""}, "[mgr]\nfoo = 1\n")
	after = append(after, "mine = 1")
	out, _ := Undo(after, rec)
	if !slices.Contains(out, "[flavor]") || !slices.Contains(out, "mine = 1") || slices.Contains(out, `dark = "axiom"`) {
		t.Errorf("%q", out)
	}
}

func TestUndoKeepsCRLF(t *testing.T) {
	t.Parallel()
	after, rec := edited(t, Target{File: Files{"{config}/kitty.conf"}, Place: End, Text: "include axiom.conf"}, "font_size 12\r\nother\r\n")
	out, _ := Undo(after, rec)
	if got := Text(out); got != "font_size 12\r\nother\r\n" {
		t.Errorf("%q", got)
	}
}

func TestUndoPicksTheNearestDuplicate(t *testing.T) {
	t.Parallel()
	rec := EditRecord{Comment: "#", Inserted: []Inserted{{"x", 5}}}
	out, _ := Undo([]string{"x", "a", "b", "c", "x", "x", "d", "x"}, rec)
	if want := []string{"x", "a", "b", "c", "x", "d", "x"}; !slices.Equal(out, want) {
		t.Errorf("%q", out)
	}
}

func TestEditRecordsAWrap(t *testing.T) {
	t.Parallel()
	r := Resolve([]Target{{File: Files{"{config}/gtk.css"}, Place: Start, Text: `@import url("axiom.css");`, WrapLink: `@import url("file://{link}");`}}, nil, env())[0]
	p, _ := Decide(r, Facts{Exists: true, CanWrap: true, Link: true, Real: "/usr/share/t.css", Lines: []string{"a {}"}})
	got, rec := Edit(r, p, []string{"a {}"})
	if !rec.Wrapped || rec.WrapLine != got[0] {
		t.Errorf("%+v", rec)
	}
	if out, _ := Undo(got, rec); !slices.Equal(out, []string{rec.WrapLine}) {
		t.Errorf("%q", out)
	}
}

// A blank line axiom set goes only before a line it removed: one a
// formatter stripped isn't replaced by taking the user's away
func TestUndoKeepsTheUsersBlankLines(t *testing.T) {
	t.Parallel()
	// axiom added a blank line (index 3) and its text
	rec := EditRecord{Comment: "#", Inserted: []Inserted{{"", 3}, {"include axiom.conf", 4}}}
	after := []string{"font_size 12", "", "other 1", "", "include axiom.conf"}
	// a formatter stripped axiom's blank: the one above stays
	stripped := []string{"font_size 12", "", "other 1", "include axiom.conf"}
	if out, _ := Undo(stripped, rec); !slices.Equal(out, []string{"font_size 12", "", "other 1"}) {
		t.Errorf("%q", out)
	}
	if out, _ := Undo(after, rec); !slices.Equal(out, []string{"font_size 12", "", "other 1"}) {
		t.Errorf("%q", out)
	}
}

// A section the user added to keeps its header and the blank line before it
func TestUndoKeepsTheBlankBeforeAKeptSection(t *testing.T) {
	t.Parallel()
	after, rec := edited(t, Target{File: Files{"{config}/theme.toml"}, Place: Section, Section: "flavor", Text: "dark = \"axiom\""}, "[mgr]\nfoo = 1\n")
	after = append(after, "mine = 1")
	out, _ := Undo(after, rec)
	if want := []string{"[mgr]", "foo = 1", "", "[flavor]", "mine = 1"}; !slices.Equal(out, want) {
		t.Errorf("%q, want %q", out, want)
	}
}
