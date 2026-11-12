package edit

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/footprint"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// footprinted is a scratch whose Hookups record in a ledger
func footprinted(t *testing.T) (*scratch, *footprint.Ledger) {
	t.Helper()
	s := newScratch(t)
	l := footprint.New(footprint.Options{Dirs: xdg.Resolve(func(k string) string {
		return map[string]string{"HOME": s.home, "XDG_CONFIG_HOME": s.config, "XDG_STATE_HOME": s.home + "/.local/state"}[k]
	})})
	RegisterUndo(l)
	o := s.h.opts
	o.Ledger = l
	s.h = NewHookups(o)
	return s, l
}

func undoAll(t *testing.T, l *footprint.Ledger) []footprint.Result {
	t.Helper()
	return l.Undo(context.Background(), l.Select(footprint.UndoOptions{}), footprint.UndoOptions{})
}

func TestApplyRecordsWhenALedgerIsGiven(t *testing.T) {
	t.Parallel()
	s, l := footprinted(t)
	path := s.write("kitty/kitty.conf", "font_size 12\n")
	s.h.Apply(s.schema["kitty"].Hookup, nil, "ThemeIntegrations.kitty")
	rows := l.Rows()
	if len(rows) != 1 {
		t.Fatalf("%+v", rows)
	}
	r := rows[0]
	if r.Kind != footprint.KindHookup || r.Target != path || r.Owner != "ThemeIntegrations.kitty" || r.State != footprint.StateApplied ||
		len(r.Hookup.Edit.Inserted) == 0 || !strings.HasSuffix(r.Hookup.Backup, ".axiom-bak-20261027-120000") {
		t.Errorf("%+v %+v", r, r.Hookup)
	}
	undoAll(t, l)
	if got := read(t, path); got != "font_size 12\n" {
		t.Errorf("after undo %q", got)
	}
	if len(l.Rows()) != 0 {
		t.Errorf("%+v", l.Rows())
	}
}

func TestApplyWithoutLedgerUnchanged(t *testing.T) {
	t.Parallel()
	s := newScratch(t)
	path := s.write("kitty/kitty.conf", "font_size 12\n")
	if r := s.apply("kitty")[0]; !r.Changed || r.Error != "" {
		t.Errorf("%+v", r)
	}
	if got := read(t, path); got != "font_size 12\n\ninclude axiom.conf\n" {
		t.Errorf("%q", got)
	}
}

func TestUndoRestoresTheWrappedLink(t *testing.T) {
	t.Parallel()
	s, l := footprinted(t)
	gtk := s.readonly("gtk.css", "@define-color window_bg_color #fff;\n")
	s.write("gtk-3.0/gtk.css", "")
	gtk4 := s.link("gtk-4.0/gtk.css", gtk)
	s.apply("gtk")
	if info, _ := os.Lstat(gtk4); info.Mode()&os.ModeSymlink != 0 {
		t.Fatal("not wrapped")
	}
	undoAll(t, l)
	if to, err := os.Readlink(gtk4); err != nil || to != gtk {
		t.Errorf("link %q %v", to, err)
	}
	if got := read(t, gtk); got != "@define-color window_bg_color #fff;\n" {
		t.Errorf("the system file: %q", got)
	}
}

func TestUndoLeavesAWrappedFileTheUserChanged(t *testing.T) {
	t.Parallel()
	s, l := footprinted(t)
	gtk := s.readonly("gtk.css", "a {}\n")
	s.write("gtk-3.0/gtk.css", "")
	gtk4 := s.link("gtk-4.0/gtk.css", gtk)
	s.apply("gtk")
	f, _ := os.OpenFile(gtk4, os.O_APPEND|os.O_WRONLY, 0)
	f.WriteString("mine {}\n")
	f.Close()
	var changed bool
	for _, r := range undoAll(t, l) {
		changed = changed || r.Outcome == footprint.OutcomeChanged
	}
	if !changed {
		t.Error("no changed outcome")
	}
	if info, _ := os.Lstat(gtk4); info.Mode()&os.ModeSymlink != 0 || !strings.Contains(read(t, gtk4), "mine {}") {
		t.Error("the file wasn't left")
	}
}

func TestCopyUndoOnlyWhenUnchanged(t *testing.T) {
	t.Parallel()
	s, l := footprinted(t)
	s.write("nvim/init.lua", "")
	s.apply("nvim")
	copied := filepath.Join(s.config, "nvim", "lua", "axiom_theme.lua")
	if _, err := os.Stat(copied); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(copied, append([]byte(read(t, copied)), "-- mine\n"...), 0o644)
	res := undoAll(t, l)
	if len(res) == 0 || res[0].Outcome != footprint.OutcomeChanged {
		t.Errorf("%+v", res)
	}
	if _, err := os.Stat(copied); err != nil {
		t.Error("a changed copy was deleted")
	}
	// Unchanged: deleted
	s2, l2 := footprinted(t)
	s2.apply("nvim")
	undoAll(t, l2)
	if _, err := os.Stat(filepath.Join(s2.config, "nvim", "lua", "axiom_theme.lua")); err == nil {
		t.Error("the copy stayed")
	}
}

func TestCreatedFileDeletedOnUndo(t *testing.T) {
	t.Parallel()
	s, l := footprinted(t)
	path := filepath.Join(s.config, "kitty", "kitty.conf")
	s.apply("kitty")
	if _, err := os.Stat(path); err != nil {
		t.Fatal(err)
	}
	undoAll(t, l)
	if _, err := os.Stat(path); err == nil {
		t.Error("the created file stayed")
	}
	if _, err := os.Stat(filepath.Dir(path)); err == nil {
		t.Error("the created folder stayed")
	}
	if len(l.Rows()) != 0 {
		t.Errorf("%+v", l.Rows())
	}
}

func TestBackupKeptAndListed(t *testing.T) {
	t.Parallel()
	s, l := footprinted(t)
	path := s.write("kitty/kitty.conf", "font_size 12\n")
	s.apply("kitty")
	row := l.Rows()[0]
	b := backups(t, path)
	if len(b) != 1 || row.Hookup.Backup != b[0] {
		t.Fatalf("backups %v, row %q", b, row.Hookup.Backup)
	}
	undoAll(t, l)
	if got := backups(t, path); len(got) != 1 || read(t, got[0]) != "font_size 12\n" {
		t.Errorf("backups after undo %v", got)
	}
}
