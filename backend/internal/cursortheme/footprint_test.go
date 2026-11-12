package cursortheme

import (
	"context"
	"path/filepath"
	"slices"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/footprint"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

func TestResolveRecordsCompanionAndGSettings(t *testing.T) {
	t.Parallel()
	s := newScratch(t)
	s.gsettings = map[string]string{"cursor-theme": "Adwaita", "cursor-size": "24"}
	s.theme("Old", []string{"left_ptr", "hand2"}, "")
	r := s.resolver()
	l := footprint.New(footprint.Options{
		Dirs: xdg.Resolve(func(k string) string {
			return map[string]string{"HOME": s.home, "XDG_STATE_HOME": s.home + "/state", "XDG_CONFIG_HOME": s.home + "/config", "XDG_CACHE_HOME": s.home + "/cache"}[k]
		}),
		GSettings: r.opts.GSettings,
	})
	r.opts.Ledger = l
	if _, err := r.Resolve(context.Background(), "Old", 32, "Input.cursor.enabled"); err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, row := range l.Rows() {
		got = append(got, row.Kind+" "+row.Target+" "+row.Owner)
		if row.State != footprint.StateApplied {
			t.Errorf("%s is %s", row.ID, row.State)
		}
	}
	// The icons folder was made for it too (the scratch data dir is empty)
	want := []string{
		"dir " + s.data + " Input.cursor.enabled",
		"dir " + s.data + "/icons Input.cursor.enabled",
		"dir " + s.companion("Old") + " Input.cursor.enabled",
		"gsetting org.gnome.desktop.interface cursor-theme Input.cursor.enabled",
		"gsetting org.gnome.desktop.interface cursor-size Input.cursor.enabled",
	}
	if !slices.Equal(got, want) {
		t.Fatalf("rows %q, want %q", got, want)
	}
	s.sets = nil
	res := l.Undo(context.Background(), l.Select(footprint.UndoOptions{}), footprint.UndoOptions{})
	for _, x := range res {
		if x.Outcome != footprint.OutcomeDone {
			t.Errorf("%+v", x)
		}
	}
	if !exists(filepath.Join(s.data)) {
		return
	}
	t.Errorf("the folders it made stayed")
}
