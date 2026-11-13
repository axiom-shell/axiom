package manager

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/session"
	"github.com/axiom-shell/axiom/backend/internal/windowrules"
)

func pauseBinds(ids ...string) *jsonx.Array {
	a := jsonx.Arr()
	for _, id := range ids {
		a.Append(jsonx.Obj("id", id, "key", "SUPER + "+id, "action", "exec", "argument", id))
	}
	return a
}

func hold(allExcept bool, keep, these []string) windowrules.BindsHold {
	if keep == nil {
		keep = []string{}
	}
	if these == nil {
		these = []string{}
	}
	return windowrules.BindsHold{Rules: []string{"r"}, AllExcept: allExcept, Keep: keep, These: these}
}

func (h *harness) pauseCalls() int {
	n := 0
	for _, c := range h.w.seen() {
		if strings.HasPrefix(c, "pause:") {
			n++
		}
	}
	return n
}

// pauseHarness is a detached layer whose runtime layer is applied, with
// binds a, b and c
func pauseHarness(t *testing.T) *harness {
	t.Helper()
	h := newHarness(t, "detached")
	h.modeMu.Lock()
	h.config = jsonx.Obj("Keybinds", jsonx.Obj("binds", pauseBinds("a", "b", "c")))
	h.modeMu.Unlock()
	h.m.SetFacts(Facts{Kind: "hyprland", Supports: map[string]bool{}})
	h.eventually("the runtime layer", func() bool {
		for _, c := range h.w.seen() {
			if strings.HasPrefix(c, "runtime:") {
				return true
			}
		}
		return false
	})
	return h
}

// One owner: a hold is applied once, again after a reload or a runtime
// re-apply (they drop it), not for the same hold, and given back when it
// ends; a mode left puts an all-except pause back, and only from another mode
func TestPauseOwner(t *testing.T) {
	t.Parallel()
	h := pauseHarness(t)
	if n := h.pauseCalls(); n != 1 {
		t.Fatalf("only the give-back of an earlier image so far: %d calls", n)
	}
	h.m.SetPause(hold(false, nil, []string{"a"}))
	h.eventually("paused", func() bool { return h.pauseCalls() == 2 })
	h.m.SetPause(hold(false, nil, []string{"a"}))
	h.w.reloadCh <- ipc.Reload{}
	h.eventually("again after a reload", func() bool { return h.pauseCalls() == 3 })
	time.Sleep(100 * time.Millisecond)
	if n := h.pauseCalls(); n != 3 {
		t.Fatalf("the same hold applied again: %d", n)
	}
	// Ended: applied once more, nothing paused
	h.m.SetPause(windowrules.BindsHold{Rules: []string{}, Keep: []string{}, These: []string{}})
	h.eventually("given back", func() bool { return h.pauseCalls() == 4 })
	if last := h.w.seen(); last[len(last)-1] != `pause:{"allExcept":false,"keep":[],"paused":[]}` {
		t.Fatalf("last call %q", last[len(last)-1])
	}
	h.w.reloadCh <- ipc.Reload{}
	h.eventually("the reload is taken", func() bool {
		h.w.mu.Lock()
		defer h.w.mu.Unlock()
		return h.w.reloaded >= 2
	})
	time.Sleep(600 * time.Millisecond) // past the debounce of its re-apply
	if n := h.pauseCalls(); n != 4 {
		t.Fatalf("nothing paused, yet applied: %d", n)
	}

	h.m.SetPause(hold(true, []string{"b"}, nil))
	h.eventually("all except", func() bool { return h.pauseCalls() == 5 })
	// A leaver (the key recorder) drops to the default mode: put back
	h.w.reloadCh <- ipc.Reload{ModeChanged: true, Mode: "axiom_record"}
	h.w.reloadCh <- ipc.Reload{ModeChanged: true}
	h.eventually("entered again", func() bool { return h.pauseCalls() == 6 })
	// A default with no mode before it is no leave
	h.w.reloadCh <- ipc.Reload{ModeChanged: true}
	time.Sleep(100 * time.Millisecond)
	if n := h.pauseCalls(); n != 6 {
		t.Fatalf("a mode that wasn't left: %d", n)
	}
}

// A pause is given back on stop in every mode, first, even where the
// runtime layer isn't applied
func TestPauseIsGivenBackAtTeardown(t *testing.T) {
	t.Parallel()
	h := pauseHarness(t)
	h.m.SetPause(hold(false, nil, []string{"a"}))
	h.eventually("paused", func() bool { return h.pauseCalls() == 2 })
	var steps []session.Step
	h.m.do(context.Background(), func(context.Context) { steps = h.m.teardownSteps() })
	if len(steps) < 2 || steps[0].Op != "unpause" || steps[1].Op != "reload" {
		t.Fatalf("steps %+v", steps)
	}
	h.m.SetPause(hold(false, nil, nil))
	h.eventually("given back", func() bool { return h.pauseCalls() == 3 })
	h.m.do(context.Background(), func(context.Context) { steps = h.m.teardownSteps() })
	if len(steps) != 1 || steps[0].Op != "reload" {
		t.Fatalf("steps with nothing paused %+v", steps)
	}

	for _, mode := range []string{"included", "managed"} {
		h := newHarness(t, mode)
		h.modeMu.Lock()
		h.config = jsonx.Obj("Keybinds", jsonx.Obj("binds", pauseBinds("a")))
		h.modeMu.Unlock()
		h.w.loaded = true
		h.m.SetFacts(Facts{Kind: "hyprland", Supports: map[string]bool{}})
		h.m.SetPause(hold(false, nil, []string{"a"}))
		h.w.reloadCh <- ipc.Reload{}
		h.eventually(mode+": paused", func() bool { return h.pauseCalls() >= 1 })
		h.m.do(context.Background(), func(context.Context) { steps = h.m.teardownSteps() })
		if len(steps) != 1 || steps[0].Op != "unpause" {
			t.Fatalf("%s: steps %+v", mode, steps)
		}
	}
}

// The paused set rides in the inputs without touching what's written; niri's
// (binds only from files) leaves the paused ones out of the binds
func TestBuildInputsPause(t *testing.T) {
	t.Parallel()
	cfg := jsonx.Obj("Keybinds", jsonx.Obj("binds", pauseBinds("a", "b", "c")))
	plain := buildInputs(cfg, &Facts{Kind: "hyprland"}, nil)
	for name, f := range map[string]Facts{
		"these":      {Kind: "hyprland", Pause: hold(false, nil, []string{"b", "x"})},
		"all except": {Kind: "hyprland", Pause: hold(true, []string{"c"}, nil)},
	} {
		in := buildInputs(cfg, &f, nil)
		if in.str("layerKey") != plain.str("layerKey") || in.str("liveKey") != plain.str("liveKey") ||
			string(jsonx.MarshalCompact(in.get("binds"))) != string(jsonx.MarshalCompact(plain.get("binds"))) {
			t.Errorf("%s: a pause changed what's written", name)
		}
		if in.str("pauseKey") == plain.str("pauseKey") {
			t.Errorf("%s: the pause key is the same", name)
		}
	}
	if got := string(jsonx.MarshalCompact(buildInputs(cfg, &Facts{Kind: "hyprland", Pause: hold(false, nil, []string{"b", "x"})}, nil).get("pause"))); got != `{"allExcept":false,"keep":[],"paused":["b"]}` {
		t.Errorf("these: %s", got)
	}
	if got := buildInputs(cfg, &Facts{Kind: "hyprland", Pause: hold(true, []string{"c"}, nil)}, nil).pause(); !got.AllExcept || len(got.Paused) != 2 || got.Keep[0] != "c" {
		t.Errorf("all except: %+v", got)
	}
	file := buildInputs(cfg, &Facts{Kind: "niri", PauseInFile: true, Pause: hold(false, nil, []string{"b"})}, nil)
	if got := string(jsonx.MarshalCompact(file.get("binds"))); strings.Contains(got, `"id":"b"`) || !strings.Contains(got, `"id":"a"`) {
		t.Errorf("niri: binds %s", got)
	}
	if file.str("layerKey") == buildInputs(cfg, &Facts{Kind: "niri", PauseInFile: true}, nil).str("layerKey") {
		t.Error("niri: the files aren't rewritten")
	}
	if isPaused(file.pause()) {
		t.Error("niri: left in the files, not paused live")
	}
}

// Hyprland: the paused binds' handles are switched off in one eval; the
// teardown step gives them back
func TestHyprPause(t *testing.T) {
	t.Parallel()
	tables, schema := repo(t)
	dir, asked := fakeHyprland(t)
	w := newHypr(env2(tables, schema, func(string) string { return "" }), &ipc.Hypr{Dir: dir})
	in := buildInputs(jsonx.Obj("Keybinds", jsonx.Obj("binds", pauseBinds("a", "b"))),
		&Facts{Kind: "hyprland", Ctx: BindCtx{ShellCommand: "axiom"}, Pause: hold(false, nil, []string{"b"})}, nil)
	if !w.pause(context.Background(), in) {
		t.Fatal("not applied")
	}
	if got, want := <-asked, `AXIOM_PAUSED = { "b" }`; !strings.Contains(got, want) || !strings.HasPrefix(got, "eval ") {
		t.Errorf("sent %q", got)
	}
	in = buildInputs(jsonx.Obj("Keybinds", jsonx.Obj("binds", pauseBinds("a", "b"))),
		&Facts{Kind: "hyprland", Ctx: BindCtx{ShellCommand: "axiom"}, Pause: hold(true, []string{"a"}, nil)}, nil)
	w.pause(context.Background(), in)
	got := <-asked
	if !strings.Contains(got, `hl.define_submap("axiom_paused"`) || !strings.Contains(got, `hl.bind("SUPER + a"`) || strings.Contains(got, `hl.bind("SUPER + b"`) {
		t.Errorf("all except: %q", got)
	}
	if steps := w.unpauseSteps(in); len(steps) != 1 || steps[0].Op != "eval" || !strings.Contains(steps[0].Lines[0], "set_enabled(true)") {
		t.Errorf("unpause: %+v", steps)
	}
}

// sway: these are unbound and bound again when it ends; all except defines a
// mode named by the kept lines, enters it and binds them; each apply gives
// the last back first; the record is made ahead of the commands and a reload
// clears it; only binds sway has bound are touched
func TestSwayPause(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	w := swayWith(t, "", true, nil)
	path, asked := fakeSway(t)
	w.ipc = &ipc.Sway{Path: path}
	facts := func(h windowrules.BindsHold) Inputs {
		return buildInputs(jsonx.Obj("Keybinds", jsonx.Obj("binds", pauseBinds("a", "b", "c"))),
			&Facts{Kind: "sway", Ctx: BindCtx{ShellCommand: "axiom"}, Pause: h}, nil)
	}
	got := func() string { return strings.Join(sent(asked), " | ") }

	w.pause(ctx, facts(hold(false, nil, []string{"b", "c"})))
	if want := "unbindsym Mod4+b; unbindsym Mod4+c"; got() != want {
		t.Errorf("these: %q", got())
	}
	if r := w.state.SwayPaused.Restore; len(r) != 2 || !strings.Contains(r[0], "Mod4+b") {
		t.Errorf("restore %v", r)
	}
	if steps := w.unpauseSteps(Inputs{}); len(steps) != 1 || steps[0].Op != "commands" || len(steps[0].Lines) != 2 {
		t.Errorf("unpause steps %+v", steps)
	}

	w.pause(ctx, facts(hold(true, []string{"a"}, nil)))
	cmds := got()
	if !strings.HasPrefix(cmds, "bindsym --no-warn --no-repeat Mod4+b ") {
		t.Errorf("the earlier pause isn't given back first: %q", cmds)
	}
	mode := w.state.SwayPaused.Mode
	if !strings.HasPrefix(mode, "axiom_paused_") || len(w.state.SwayPaused.Restore) != 0 {
		t.Fatalf("recorded %+v", w.state.SwayPaused)
	}
	if !strings.Contains(cmds, `mode "`+mode+`" bindsym --no-warn Mod4+Ctrl+Mod1+Shift+F24 nop`) || strings.Index(cmds, `mode "`+mode+`"`) > strings.Index(cmds, "Mod4+a") {
		t.Errorf("all except: %q", cmds)
	}
	// the same kept set is the same mode; entering it leaves nothing to give back but it
	w.pause(ctx, facts(hold(true, []string{"a"}, nil)))
	if again := got(); strings.Contains(again, "mode default") || w.state.SwayPaused.Mode != mode {
		t.Errorf("again: %q, mode %s", again, w.state.SwayPaused.Mode)
	}
	if steps := w.unpauseSteps(Inputs{}); len(steps) != 1 || steps[0].Lines[len(steps[0].Lines)-1] != "mode default" {
		t.Errorf("unpause steps %+v", steps)
	}
	w.pause(ctx, facts(hold(false, nil, nil)))
	if end := got(); end != "mode default" || w.state.SwayPaused.Mode != "" {
		t.Errorf("ended: %q %+v", end, w.state.SwayPaused)
	}

	// A reload brought the file's binds back and left the mode
	w.pause(ctx, facts(hold(false, nil, []string{"b"})))
	got()
	w.configReloaded(ctx, Inputs{})
	if w.state.SwayPaused.Restore != nil || w.state.SwayPaused.Mode != "" {
		t.Errorf("a reload kept %+v", w.state.SwayPaused)
	}

	// Detached: only binds the runtime layer bound (the user's own key is
	// skipped, never unbound)
	w.runtimeOn = true
	w.runtime.applied = []any{jsonx.Obj("id", "a", "key", "SUPER + a", "action", "exec", "argument", "a")}
	w.pause(ctx, facts(hold(false, nil, []string{"a", "b"})))
	if cmds := got(); cmds != "unbindsym Mod4+a" {
		t.Errorf("detached: %q", cmds)
	}
	// A fresh daemon doesn't carry a record
	e := w.env
	e.state = &runtimeState{SwayPaused: swayPaused{Mode: "x"}}
	e.carried = false
	if newSway(e, nil); e.state.SwayPaused.Mode != "" {
		t.Error("a fresh daemon kept the pause record")
	}
}

// A pause the last image left is given back by the first send, whatever the
// first hold is
func TestPauseUnknownAtStartIsGivenBack(t *testing.T) {
	t.Parallel()
	h := pauseHarness(t)
	h.eventually("the give-back", func() bool { return h.pauseCalls() == 1 })
	for _, c := range h.w.seen() {
		if strings.HasPrefix(c, "pause:") && c != `pause:{"allExcept":false,"keep":[],"paused":[]}` {
			t.Fatalf("first send %q", c)
		}
	}
}

// A pause that failed to send is retried on the next inputs, and teardown
// gives back meanwhile
func TestPauseFailedSendIsRetried(t *testing.T) {
	t.Parallel()
	h := pauseHarness(t)
	h.eventually("the give-back", func() bool { return h.pauseCalls() == 1 })
	h.w.mu.Lock()
	h.w.pauseFails = true
	h.w.mu.Unlock()
	h.m.SetPause(hold(false, nil, []string{"a"}))
	h.eventually("tried", func() bool { return h.pauseCalls() == 2 })
	var steps []session.Step
	h.m.do(context.Background(), func(context.Context) { steps = h.m.teardownSteps() })
	if len(steps) == 0 || steps[0].Op != "unpause" {
		t.Fatalf("a failed pause isn't given back: %+v", steps)
	}
	h.w.mu.Lock()
	h.w.pauseFails = false
	h.w.mu.Unlock()
	h.m.SetPause(hold(false, nil, []string{"a", "b"}))
	h.eventually("retried", func() bool { return h.pauseCalls() == 3 })
	// The same hold again: nothing more to send
	h.m.SetPause(hold(false, nil, []string{"a", "b"}))
	time.Sleep(100 * time.Millisecond)
	if n := h.pauseCalls(); n != 3 {
		t.Fatalf("sent again: %d", n)
	}
}

// niri keeps its binds in the files: a clean stop in included or managed mode
// writes them again without the pause (no step does it)
func TestNiriTeardownRewritesPausedFiles(t *testing.T) {
	t.Parallel()
	for _, mode := range []string{"included", "managed"} {
		h := newHarness(t, mode)
		h.w.byFile, h.w.bindsInText = true, true
		h.w.loaded = true
		h.modeMu.Lock()
		h.config = jsonx.Obj("Keybinds", jsonx.Obj("binds", pauseBinds("a", "b")))
		h.modeMu.Unlock()
		h.m.SetFacts(Facts{Kind: "hyprland", PauseInFile: true, Supports: map[string]bool{}})
		f := h.w.files(Inputs{})
		path := f.IncludePath
		if mode == "managed" {
			path = f.ManagedPath
		}
		h.eventually(mode+": written", func() bool { return readFile(path) != "" })
		plain := readFile(path)
		h.m.SetPause(hold(false, nil, []string{"b"}))
		h.eventually(mode+": paused in the file", func() bool { return readFile(path) != plain })
		h.stop()
		h.m.Teardown(context.Background())
		if got := readFile(path); got != plain {
			t.Errorf("%s: the file keeps the pause: %q, want %q", mode, got, plain)
		}
	}
}

// sway after a re-exec: the carried record is given back by a zero pause (the
// manager's first send), and a zero pause with no record sends nothing
func TestSwayPauseGivesBackACarriedRecord(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	w := swayWith(t, "", true, nil)
	path, asked := fakeSway(t)
	w.ipc = &ipc.Sway{Path: path}
	zero := buildInputs(jsonx.Obj("Keybinds", jsonx.Obj("binds", pauseBinds("a"))), &Facts{Kind: "sway", Ctx: BindCtx{ShellCommand: "axiom"}}, nil)
	w.pause(ctx, zero)
	if got := sent(asked); len(got) != 0 {
		t.Fatalf("nothing to give back, sent %v", got)
	}
	w.state.SwayPaused = swayPaused{Mode: "axiom_paused_x", Restore: []string{"bindsym Mod4+a nop"}}
	w.pause(ctx, zero)
	if got := strings.Join(sent(asked), " | "); !strings.Contains(got, "bindsym Mod4+a nop") || !strings.Contains(got, "mode default") {
		t.Fatalf("sent %q", got)
	}
	if w.state.SwayPaused.Mode != "" || len(w.state.SwayPaused.Restore) != 0 {
		t.Fatalf("record kept: %+v", w.state.SwayPaused)
	}
}
