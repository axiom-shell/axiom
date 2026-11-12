package edit

import (
	"context"
	"os"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/footprint"
	"github.com/axiom-shell/axiom/backend/internal/theme"
)

// kdeglobals through the qt integration, its hookup and the integration
// again, then every undo: the file is as it was
func TestKdeglobalsRoundTrip(t *testing.T) {
	t.Parallel()
	s, l := footprinted(t)
	theme.RegisterUndo(l)
	seed := "[General]\nColorScheme=Axiom\n\n[Colors:View]\nBackgroundNormal=1,2,3\nCustom=x\n"
	path := s.write("kdeglobals", seed)
	in := theme.NewIntegrator(theme.IntegrateOptions{Getenv: s.h.opts.Getenv, Ledger: l})
	run := func() {
		if _, err := in.Run(context.Background(), "../../../../qml/config/themes/ayu-dark.json", []string{"qt"}, map[string]string{"qt": "ThemeIntegrations.qt"}); err != nil {
			t.Fatal(err)
		}
	}
	run()
	s.apply("qt")
	run()
	merged, _ := os.ReadFile(path)
	t.Logf("merged:\n%s", merged)
	l.Undo(context.Background(), []string{"ini-groups:" + path}, footprint.UndoOptions{})
	mid, _ := os.ReadFile(path)
	t.Logf("after the ini undo: %q", mid)
	for _, r := range l.Undo(context.Background(), l.Select(footprint.UndoOptions{}), footprint.UndoOptions{}) {
		t.Logf("%+v", r)
	}
	if got := read(t, path); got != seed {
		t.Errorf("after undo:\n%q\nwant\n%q", got, seed)
	}
}
