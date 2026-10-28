package manager

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// A detached module niri refuses isn't written and is the Runtime problem
// (the card shows it, as a file mode's refusal); accepted again, the
// problem goes and the module is written
func TestNiriRefusedDetachedModuleIsAProblem(t *testing.T) {
	t.Parallel()
	w := goldenWriter(t, "niri").(*niriWriter)
	dir := t.TempDir()
	w.stateDir = dir + "/"
	w.state.NiriWrapper = true // loaded already: no niri to ask
	w.niri = filepath.Join(dir, "niri")
	in := goldenInputs(t, "niri")
	niri := func(script string) {
		if err := os.WriteFile(w.niri, []byte("#!/bin/sh\ncat >/dev/null\n"+script), 0o700); err != nil {
			t.Fatal(err)
		}
	}
	niri("echo 'error: bad bind' >&2\nexit 1\n")
	w.runtimeApply(context.Background(), in, nil)
	if p := w.problems(in).Runtime; !strings.Contains(p, "refuses") || !strings.Contains(p, "bad bind") {
		t.Fatalf("Runtime = %q, want niri's refusal", p)
	}
	if _, err := os.Stat(w.detachedPath()); err == nil {
		t.Fatal("a refused module was written")
	}
	niri("exit 0\n")
	w.runtimeApply(context.Background(), in, nil)
	if p := w.problems(in).Runtime; p != "" {
		t.Fatalf("Runtime = %q after niri accepted the module", p)
	}
	if _, err := os.Stat(w.detachedPath()); err != nil {
		t.Fatalf("the accepted module wasn't written: %v", err)
	}
}
