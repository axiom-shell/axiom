package edit

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/footprint"
	"github.com/axiom-shell/axiom/backend/internal/hookup"
)

// Two targets on one file (the compositor's include and autostart lines)
// are one inferred row, their lines together; undone it's the file as it
// was
func TestInferredMergesTargetsOfOneFile(t *testing.T) {
	t.Parallel()
	s, l := footprinted(t)
	path := s.write("kitty/kitty.conf", "font_size 12\n\ninclude a.conf\nexec b\n")
	os.WriteFile(path+".axiom-bak-20250101-000000", []byte("font_size 12\n"), 0o644)
	targets := []hookup.Target{
		{File: hookup.Files{"{config}/kitty/kitty.conf"}, Place: hookup.End, Text: "include a.conf"},
		{File: hookup.Files{"{config}/kitty/kitty.conf"}, Place: hookup.End, Text: "exec b"},
	}
	rows := s.h.Inferred(targets, nil, "")
	if len(rows) != 1 {
		t.Fatalf("%d rows: %+v", len(rows), rows)
	}
	var texts []string
	for _, in := range rows[0].Hookup.Edit.Inserted {
		texts = append(texts, in.Text)
	}
	if !slices.Equal(texts, []string{"", "include a.conf", "exec b"}) {
		t.Errorf("inserted %q", texts)
	}
	if _, _, err := l.Backfill(rows); err != nil {
		t.Fatal(err)
	}
	l.Undo(context.Background(), l.Select(footprint.UndoOptions{Force: true}), footprint.UndoOptions{Force: true})
	if got := read(t, path); got != "font_size 12\n" {
		t.Errorf("after undo %q", got)
	}
}

// A "# axiom: " line counts only when it comments out what the target sets
func TestInferredCountsOnlyLinesOfTheTargetsKeys(t *testing.T) {
	t.Parallel()
	s, _ := footprinted(t)
	s.write("helix/config.toml", "# axiom: unrelated = 1\n# axiom: theme = \"old\"\ntheme = \"axiom\"\n")
	targets := []hookup.Target{{File: hookup.Files{"{config}/helix/config.toml"}, Place: hookup.Top, Text: `theme = "axiom"`}}
	rows := s.h.Inferred(targets, nil, "")
	if len(rows) != 1 || !slices.Equal(rows[0].Hookup.Edit.Commented, []string{`theme = "old"`}) {
		t.Errorf("%+v", rows)
	}
}

// The file's missing final newline comes back only while axiom's lines
// were the last, not when the user wrote after them
func TestUndoRestoresAMissingFinalNewline(t *testing.T) {
	t.Parallel()
	s, l := footprinted(t)
	path := s.write("kitty/kitty.conf", "font_size 12")
	s.apply("kitty")
	undoAll(t, l)
	if got := read(t, path); got != "font_size 12" {
		t.Errorf("%q", got)
	}
	// The user wrote after axiom's lines
	s2, l2 := footprinted(t)
	path = s2.write("kitty/kitty.conf", "font_size 12")
	s2.apply("kitty")
	f, _ := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0)
	f.WriteString("mine 1\n")
	f.Close()
	undoAll(t, l2)
	if got := read(t, path); got != "font_size 12\nmine 1\n" {
		t.Errorf("%q", got)
	}
}

// A failed write puts back the record the edit was merged into
func TestFailedApplyRestoresTheRecord(t *testing.T) {
	t.Parallel()
	s, l := footprinted(t)
	path := s.write("kitty/kitty.conf", "font_size 12\n")
	s.apply("kitty")
	id := footprint.ID(footprint.KindHookup, path, "")
	prev, had := l.Get(id)
	if !had {
		t.Fatal("no row")
	}
	// Another edit of the file is recorded, then its write fails
	if _, err := l.Begin(footprint.Row{Kind: footprint.KindHookup, Target: path, Hookup: &footprint.HookupRec{Edit: hookup.EditRecord{Inserted: []hookup.Inserted{{Text: "late", Index: 9}}}}}, footprint.PriorAbsent); err != nil {
		t.Fatal(err)
	}
	s.h.finish(id, prev, had, errors.New("disk full"))
	got, _ := l.Get(id)
	if len(got.Hookup.Edit.Inserted) != len(prev.Hookup.Edit.Inserted) || got.State != prev.State {
		t.Errorf("%+v", got)
	}
	// A new row stays pending for its undo to look at
	other := filepath.Join(s.config, "new.conf")
	nid, _ := l.Begin(footprint.Row{Kind: footprint.KindHookup, Target: other, Hookup: &footprint.HookupRec{}}, footprint.PriorAbsent)
	s.h.finish(nid, footprint.Row{}, false, errors.New("disk full"))
	if r, _ := l.Get(nid); r.State != footprint.StatePending {
		t.Errorf("%+v", r)
	}
}
