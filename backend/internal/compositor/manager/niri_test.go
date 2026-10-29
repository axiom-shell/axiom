package manager

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
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

// With WindowSwitcher.compositorSwitcher, the included and managed files
// bind the switch windows keys to niri's own switcher (recent-windows,
// replacing niri's default keys) instead of axiom's IPC; detached keeps
// axiom's, and without the setting nothing changes.
func TestNiriOwnSwitcher(t *testing.T) {
	t.Parallel()
	in := goldenInputs(t, "niri")
	w := goldenWriter(t, "niri").(*niriWriter)
	spec := in.get("specFile")
	off := w.moduleText(in, spec)
	if strings.Contains(off, "recent-windows") || !strings.Contains(off, `"windowSwitcher" "next"`) {
		t.Fatalf("off: niri's switcher bound, or axiom's not:\n%s", off)
	}
	in.Set("compositorSwitcher", true)
	files := map[string]string{"module.kdl": w.moduleText(in, spec), "managed.kdl": w.managedText(in, spec)}
	for name, text := range files {
		for _, want := range []string{"recent-windows {", "Ctrl+Tab {", "next-window", "Ctrl+Shift+Tab {", "previous-window"} {
			if !strings.Contains(text, want) {
				t.Errorf("%s: no %q:\n%s", name, want, text)
			}
		}
		if strings.Contains(text, `"windowSwitcher"`) {
			t.Errorf("%s still binds axiom's switcher", name)
		}
	}
	checkWithCompositor(t, "niri", files)
	detached := render.NiriModuleText(w.parts(in, spec, w.detachedPath(), "detached"))
	if strings.Contains(detached, "recent-windows") || !strings.Contains(detached, `"windowSwitcher" "next"`) {
		t.Errorf("detached: niri's switcher bound, or axiom's not:\n%s", detached)
	}
	// The setting reaches the writer only where niri's backend offers it
	f := &Facts{Kind: "niri", Supports: map[string]bool{"compositorSwitcher": true}}
	cfg := jsonx.Obj("WindowSwitcher", jsonx.Obj("compositorSwitcher", true))
	if buildInputs(cfg, f, nil).get("compositorSwitcher") != true {
		t.Error("supported and on: not passed on")
	}
	f.Supports = map[string]bool{}
	if buildInputs(cfg, f, nil).get("compositorSwitcher") != false {
		t.Error("unsupported: passed on")
	}
}

// Managed mode always writes niri's switcher binds, so niri's default keys
// are gone (the maintainer: "Binds are exactly representative of what there
// is"): empty with the setting on and no switcher bind of axiom's niri's
// switcher takes, or with the setting off; included writes none then and
// leaves niri's defaults.
func TestNiriManagedSwitcherBindsAreAxioms(t *testing.T) {
	t.Parallel()
	in := goldenInputs(t, "niri")
	w := goldenWriter(t, "niri").(*niriWriter)
	spec := in.get("specFile")
	empty := "recent-windows {\n    binds {}\n}"
	check := func(name string) {
		managed, module := w.managedText(in, spec), w.moduleText(in, spec)
		if !strings.Contains(managed, empty) {
			t.Errorf("%s: managed has no empty recent-windows binds:\n%s", name, managed)
		}
		if strings.Contains(module, "recent-windows") {
			t.Errorf("%s: included writes recent-windows:\n%s", name, module)
		}
		checkWithCompositor(t, "niri", map[string]string{name + "-managed.kdl": managed})
	}
	check("off")
	in.Set("compositorSwitcher", true)
	kept := jsonx.Arr()
	for _, b := range itemsOf(in.get("binds")) {
		if a := getAny(b, "action"); a != "windowSwitcher" && a != "windowSwitcherReverse" {
			kept.Append(b)
		}
	}
	in.Set("binds", kept)
	check("no binds")
}
