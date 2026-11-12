package manager

import (
	"bufio"
	"context"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
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
// are gone (its binds are exactly axiom's): empty with the setting on and no switcher bind of axiom's niri's
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

// The rule turning down apps' maximize-to-edges requests comes ahead of the
// user's config in every mode axiom can put it there (managed: before their
// files; detached: the wrapper, before their config, the module without
// it), so a later rule of theirs wins
func TestNiriMaximizeRuleBeforeTheUsers(t *testing.T) {
	t.Parallel()
	w := goldenWriter(t, "niri").(*niriWriter)
	dir := t.TempDir()
	w.stateDir = dir + "/"
	w.state.NiriWrapper = true // loaded already: no niri to ask
	w.niri = filepath.Join(dir, "niri")
	if err := os.WriteFile(w.niri, []byte("#!/bin/sh\ncat >/dev/null\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	in := goldenInputs(t, "niri")
	const rule = "open-maximized-to-edges false"
	managed := w.managedText(in, in.get("specFile"))
	if at := strings.Index(managed, rule); at < 0 || at > strings.Index(managed, "// Your files") {
		t.Fatalf("managed: the rule isn't before the user's files:\n%s", managed)
	}
	w.runtimeApply(context.Background(), in, nil)
	wrapper, module := readFile(w.wrapperPath()), readFile(w.detachedPath())
	if at := strings.Index(wrapper, rule); at < 0 || at > strings.Index(wrapper, "include") {
		t.Fatalf("wrapper: the rule isn't before the user's config:\n%s", wrapper)
	}
	if module == "" || strings.Contains(module, rule) {
		t.Fatalf("detached module: missing, or has the rule after the user's config")
	}
}

// fakeNiri answers every request on its socket with {"Ok":"Handled"},
// sending what it was asked (one JSON line) on the returned channel
func fakeNiri(t *testing.T) (string, <-chan string) {
	t.Helper()
	// Unix socket paths are short: t.TempDir can be too long
	dir, err := os.MkdirTemp("", "axniri")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	path := filepath.Join(dir, "niri.sock")
	l, err := net.Listen("unix", path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { l.Close() })
	asked := make(chan string, 16)
	go func() {
		for {
			c, err := l.Accept()
			if err != nil {
				return
			}
			line, _ := bufio.NewReader(c).ReadString('\n')
			asked <- strings.TrimSpace(line)
			io.WriteString(c, `{"Ok":"Handled"}`+"\n")
			c.Close()
		}
	}()
	return path, asked
}

// niriWith is a niri writer for the detached module (its validator a stub
// that accepts it), niri answered by fakeNiri, the saved wrapper flag as
// given, its daemon carried or fresh
func niriWith(t *testing.T, carried, flag bool) (*niriWriter, Inputs, <-chan string) {
	t.Helper()
	tables, schema := repo(t)
	e := env2(tables, schema, func(k string) string {
		return map[string]string{"HOME": "/nonexistent/home", "XDG_CONFIG_HOME": "/nonexistent/home/.config"}[k]
	})
	e.carried = carried
	path, asked := fakeNiri(t)
	w := newNiri(e, &ipc.Niri{Path: path})
	dir := t.TempDir()
	w.stateDir = dir + "/"
	w.niri = filepath.Join(dir, "niri")
	if err := os.WriteFile(w.niri, []byte("#!/bin/sh\ncat >/dev/null\nexit 0\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	w.state.NiriWrapper = flag
	return w, goldenInputs(t, "niri"), asked
}

// sent is what's been asked so far, without waiting
func sent(asked <-chan string) []string {
	var out []string
	for {
		select {
		case l := <-asked:
			out = append(out, l)
		default:
			return out
		}
	}
}

// A daemon that isn't carried over loads the wrapper once, though the saved
// flag says niri runs it: an earlier daemon's word
func TestNiriFreshDaemonLoadsTheWrapperDespiteTheSavedFlag(t *testing.T) {
	t.Parallel()
	w, in, asked := niriWith(t, false, true)
	w.runtimeApply(context.Background(), in, nil)
	got := sent(asked)
	if len(got) != 1 || !strings.Contains(got[0], "LoadConfigFile") || !strings.Contains(got[0], w.wrapperPath()) {
		t.Fatalf("first apply sent %q, want one load of %s", got, w.wrapperPath())
	}
	w.runtimeApply(context.Background(), in, nil)
	if got := sent(asked); len(got) != 0 {
		t.Fatalf("second apply sent %q, want none", got)
	}
}

func TestNiriCarriedDaemonTrustsTheSavedFlag(t *testing.T) {
	t.Parallel()
	w, in, asked := niriWith(t, true, true)
	w.runtimeApply(context.Background(), in, nil)
	if got := sent(asked); len(got) != 0 {
		t.Fatalf("sent %q, want none", got)
	}
}

// niri keeps its old config when it can't load the wrapper (and watches the
// wrapper's path from then on: E2 of the container probe), so the flag stays
// and the next apply loads it again
func TestNiriFailedWrapperLoadRetriesOnTheNextApply(t *testing.T) {
	t.Parallel()
	w, in, asked := niriWith(t, false, false)
	w.runtimeApply(context.Background(), in, nil)
	sent(asked)
	w.loadResult(true)
	if !w.state.NiriWrapper {
		t.Fatal("the wrapper flag was cleared: niri watches the wrapper's path after a failed load")
	}
	w.runtimeApply(context.Background(), in, nil)
	if got := sent(asked); len(got) != 1 || !strings.Contains(got[0], w.wrapperPath()) {
		t.Fatalf("the next apply sent %q, want the wrapper loaded again", got)
	}
}

func TestNiriFailedLoadOfTheUsersConfigKeepsTheWrapperFlag(t *testing.T) {
	t.Parallel()
	w, _, asked := niriWith(t, true, true)
	w.loadConfig(context.Background(), w.mainConfig, false)
	sent(asked)
	if w.pending != "main" {
		t.Fatalf("pending = %q, want main", w.pending)
	}
	w.state.NiriWrapper = true
	w.loadResult(true)
	if !w.state.NiriWrapper || !w.wrapperChecked {
		t.Fatalf("a failed load of the user's config changed the wrapper state: flag %v, checked %v", w.state.NiriWrapper, w.wrapperChecked)
	}
}

func TestNiriSuccessfulLoadClearsPending(t *testing.T) {
	t.Parallel()
	w, _, asked := niriWith(t, false, false)
	w.loadConfig(context.Background(), w.wrapperPath(), true)
	sent(asked)
	if w.pending != "wrapper" || !w.wrapperChecked {
		t.Fatalf("after the load: pending %q, checked %v", w.pending, w.wrapperChecked)
	}
	w.loadResult(false)
	if w.pending != "" || !w.wrapperChecked || !w.state.NiriWrapper {
		t.Fatalf("after the answer: pending %q, checked %v, flag %v", w.pending, w.wrapperChecked, w.state.NiriWrapper)
	}
}
