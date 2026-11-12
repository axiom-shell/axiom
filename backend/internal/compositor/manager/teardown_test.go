package manager

import (
	"context"
	"io"
	"net"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/session"
)

const startPattern = `(^|[\s'"/])axiom['"]? +run\b`

func writerEnv(t *testing.T, files map[string]string, extra map[string]string) env {
	t.Helper()
	tables, schema := repo(t)
	home := t.TempDir()
	for name, text := range files {
		path := filepath.Join(home, name)
		os.MkdirAll(filepath.Dir(path), 0o755)
		if err := os.WriteFile(path, []byte(text), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	vars := map[string]string{"HOME": home, "XDG_CONFIG_HOME": home}
	for k, v := range extra {
		vars[k] = v
	}
	return env2(tables, schema, func(k string) string { return vars[k] })
}

func startIn() Inputs { return Inputs{jsonx.Obj("startPattern", startPattern)} }

func TestTeardownStepsPerCompositor(t *testing.T) {
	t.Parallel()
	h := newHypr(writerEnv(t, nil, map[string]string{"XCURSOR_THEME": "Bibata", "XCURSOR_SIZE": "32"}), nil)
	if got := h.teardownSteps(Inputs{}, false); !reflect.DeepEqual(got, []session.Step{{Op: "reload"}}) {
		t.Fatalf("hyprland: %+v", got)
	}
	h.state.LiveCursor = "Bibata 32"
	want := []session.Step{{Op: "reload"}, {Op: "setcursor", Theme: "Bibata", Size: 32}}
	if got := h.teardownSteps(Inputs{}, false); !reflect.DeepEqual(got, want) {
		t.Fatalf("hyprland with a live cursor: %+v", got)
	}
	bare := newHypr(writerEnv(t, nil, nil), nil)
	bare.state.LiveCursor = "x"
	if got := bare.teardownSteps(Inputs{}, false); got[1].Theme != "default" || got[1].Size != 24 {
		t.Fatalf("hyprland cursor fallback: %+v", got)
	}
	s := newSway(writerEnv(t, nil, nil), nil)
	if got := s.teardownSteps(Inputs{}, false); !reflect.DeepEqual(got, []session.Step{{Op: "reload"}}) {
		t.Fatalf("sway: %+v", got)
	}
	n := newNiri(writerEnv(t, map[string]string{"niri/config.kdl": "\n"}, nil), nil)
	n.state.NiriWrapper = true
	if got := n.teardownSteps(Inputs{}, false); len(got) != 1 || got[0].Op != "load" || got[0].Path != n.mainConfig {
		t.Fatalf("niri: %+v (main %s)", got, n.mainConfig)
	}
}

// the manager gives none while the runtime layer isn't applied
func TestTeardownStepsEmptyWhenTheRuntimeLayerIsOff(t *testing.T) {
	t.Parallel()
	for _, mode := range []string{"included", "managed"} {
		t.Run(mode, func(t *testing.T) {
			h := newHarness(t, mode)
			h.w.loaded = true
			h.inputs("f1", "l1", "k1")
			f := h.w.files(Inputs{})
			path := f.IncludePath
			if mode == "managed" {
				path = f.ManagedPath
			}
			h.eventually("the file is written", func() bool { return readFile(path) != "" })
			// the compositor reloaded it: loaded, so the layer stands down
			h.w.reloadCh <- ipc.Reload{}
			h.eventually("the layer is cleared", h.called("clear"))
			var steps []session.Step
			h.m.do(context.Background(), func(context.Context) { steps = h.m.teardownSteps() })
			if len(steps) != 0 {
				t.Fatalf("steps %v", steps)
			}
		})
	}
}

func TestSwayExecAlwaysAxiomMeansPartialTeardown(t *testing.T) {
	t.Parallel()
	w := newSway(writerEnv(t, map[string]string{"sway/config": "exec_always axiom run\n"}, nil), nil)
	starts, line := w.reloadStartsAxiom(startIn())
	if !starts || line != "exec_always axiom run" {
		t.Fatalf("exec_always: %v %q", starts, line)
	}
	w.state.SwayUnbinds = []render.SwayUnbind{{Key: "k", Line: "unbindsym Mod4+x"}}
	w.unbindAt = w.runtime.reloads.Load()
	got := w.teardownSteps(startIn(), true)
	if len(got) != 1 || got[0].Op != "commands" || !reflect.DeepEqual(got[0].Lines, []string{"unbindsym Mod4+x"}) {
		t.Fatalf("partial steps: %+v", got)
	}
	once := newSway(writerEnv(t, map[string]string{"sway/config": "exec axiom run\nexec_always notify-send axiom\n"}, nil), nil)
	if starts, _ := once.reloadStartsAxiom(startIn()); starts {
		t.Fatal("a plain exec runs once, not at each reload")
	}
}

func TestHyprTopLevelExecAxiomMeansPartialTeardown(t *testing.T) {
	t.Parallel()
	w := newHypr(writerEnv(t, map[string]string{"hypr/hyprland.lua": "hl.exec_cmd(\"axiom run\")\n"}, nil), nil)
	if starts, line := w.reloadStartsAxiom(startIn()); !starts || line != `hl.exec_cmd("axiom run")` {
		t.Fatalf("top-level exec: %v %q", starts, line)
	}
	got := w.teardownSteps(startIn(), true)
	if got[0].Op != "eval" || got[0].Lines[0] != hyprUnbindLua {
		t.Fatalf("partial: %+v", got)
	}
	conf := newHypr(writerEnv(t, map[string]string{"hypr/hyprland.conf": "exec-once = axiom run\nexec = axiom run\n"}, nil), nil)
	if starts, line := conf.reloadStartsAxiom(startIn()); !starts || line != "exec = axiom run" {
		t.Fatalf("conf: %v %q (exec-once doesn't count, exec does)", starts, line)
	}
	// exec-once never re-runs on a reload: a full reload
	once := newHypr(writerEnv(t, map[string]string{"hypr/hyprland.conf": "# exec = axiom run\nexec-once = axiom run\n", "hypr/x.conf": ""}, nil), nil)
	if starts, _ := once.reloadStartsAxiom(startIn()); starts {
		t.Fatal("exec-once counted as a start on reload")
	}
	sourced := newHypr(writerEnv(t, map[string]string{"hypr/hyprland.conf": "source = ./a.conf\n", "hypr/a.conf": "exec-once = axiom run\n"}, nil), nil)
	if starts, _ := sourced.reloadStartsAxiom(startIn()); starts {
		t.Fatal("a sourced exec-once counted")
	}
	commented := newHypr(writerEnv(t, map[string]string{"hypr/hyprland.conf": "# exec = axiom run\n"}, nil), nil)
	if starts, _ := commented.reloadStartsAxiom(startIn()); starts {
		t.Fatal("a comment counted")
	}
}

// axiom's own one-line handler (the autostart line) isn't a start on reload;
// a user's own handler is taken for one, multi-line or not: the safe side
func TestHyprStartHandlerAxiom(t *testing.T) {
	t.Parallel()
	own := newHypr(writerEnv(t, map[string]string{"hypr/hyprland.lua": "hl.on(\"hyprland.start\", function() hl.exec_cmd(\"/usr/bin/axiom run\") end) -- axiom\n"}, nil), nil)
	if starts, _ := own.reloadStartsAxiom(startIn()); starts {
		t.Fatal("axiom's own autostart line counted")
	}
	for name, lua := range map[string]string{
		"multi-line":        "hl.on(\"hyprland.start\", function()\n  hl.exec_cmd(\"axiom run\")\nend)\n",
		"end) mid-line":     "hl.on(\"hyprland.start\", function() if x then hl.exec_cmd(\"axiom run\") end end)\n",
		"end with options":  "hl.on(\"hyprland.start\", function()\n  hl.exec_cmd(\"axiom run\")\nend, { once = true })\n",
		"after the handler": "hl.on(\"hyprland.start\", function() end)\nhl.exec_cmd(\"axiom run\")\n",
	} {
		w := newHypr(writerEnv(t, map[string]string{"hypr/hyprland.lua": lua}, nil), nil)
		if starts, _ := w.reloadStartsAxiom(startIn()); !starts {
			t.Errorf("%s: a user's start line wasn't seen", name)
		}
	}
	comment := newHypr(writerEnv(t, map[string]string{"hypr/hyprland.lua": "-- hl.exec_cmd(\"axiom run\")\n"}, nil), nil)
	if starts, _ := comment.reloadStartsAxiom(startIn()); starts {
		t.Fatal("a comment counted")
	}
}

func TestHyprFollowsSourceAndRequire(t *testing.T) {
	t.Parallel()
	conf := newHypr(writerEnv(t, map[string]string{
		"hypr/hyprland.conf": "source = ./extra.conf\n",
		"hypr/extra.conf":    "exec = axiom run\n",
	}, nil), nil)
	if starts, line := conf.reloadStartsAxiom(startIn()); !starts || line != "exec = axiom run" {
		t.Fatalf("source: %v %q", starts, line)
	}
	glob := newHypr(writerEnv(t, map[string]string{
		"hypr/hyprland.conf": "source = ./conf.d/*.conf\n",
		"hypr/conf.d/a.conf": "bind = SUPER, A, exec, foo\n",
		"hypr/conf.d/b.conf": "exec = axiom run\n",
	}, nil), nil)
	if starts, _ := glob.reloadStartsAxiom(startIn()); !starts {
		t.Fatal("a glob source wasn't followed")
	}
	emptyGlob := newHypr(writerEnv(t, map[string]string{"hypr/hyprland.conf": "source = ./none.d/*.conf\n"}, nil), nil)
	if starts, _ := emptyGlob.reloadStartsAxiom(startIn()); starts {
		t.Fatal("a glob matching nothing counted")
	}
	for name, files := range map[string]map[string]string{
		"$var source":        {"hypr/hyprland.conf": "source = $HOME/x.conf\n"},
		"missing source":     {"hypr/hyprland.conf": "source = ./gone.conf\n"},
		"lua require":        {"hypr/hyprland.lua": "require(\"startup\")\n", "hypr/startup.lua": "hl.exec_cmd(\"axiom run\")\n"},
		"unresolved require": {"hypr/hyprland.lua": "require(\"nowhere\")\n"},
		"outside dofile":     {"hypr/hyprland.lua": "dofile(\"/etc/nowhere/start.lua\")\n"},
		"computed dofile":    {"hypr/hyprland.lua": "dofile(path .. \"/x.lua\")\n"},
	} {
		w := newHypr(writerEnv(t, files, nil), nil)
		if starts, _ := w.reloadStartsAxiom(startIn()); !starts {
			t.Errorf("%s: not counted as a start", name)
		}
	}
	harmless := newHypr(writerEnv(t, map[string]string{"hypr/hyprland.lua": "require(\"opts\")\n", "hypr/opts.lua": "hl.config({})\n"}, nil), nil)
	if starts, _ := harmless.reloadStartsAxiom(startIn()); starts {
		t.Fatal("a followed file with no start line counted")
	}
}

func TestHyprCursorRestoreTakesHyprcursorFirst(t *testing.T) {
	t.Parallel()
	w := newHypr(writerEnv(t, nil, map[string]string{"HYPRCURSOR_THEME": "Hypr", "HYPRCURSOR_SIZE": "40", "XCURSOR_THEME": "X", "XCURSOR_SIZE": "32"}), nil)
	w.state.LiveCursor = "x"
	if got := w.teardownSteps(Inputs{}, false); got[1].Theme != "Hypr" || got[1].Size != 40 {
		t.Fatalf("%+v", got)
	}
}

func TestOnStepsFollowsApplyAndClear(t *testing.T) {
	t.Parallel()
	h := newHarness(t, "detached")
	h.inputs("f1", "l1", "k1")
	want := []session.Step{{Op: "reload"}}
	waitSteps := func(want []session.Step) {
		t.Helper()
		deadline := time.After(5 * time.Second)
		for {
			select {
			case got := <-h.steps:
				if reflect.DeepEqual(got, want) || (len(got) == 0 && len(want) == 0) {
					return
				}
			case <-deadline:
				t.Fatalf("never steps %v", want)
			}
		}
	}
	waitSteps(want)
	// a file mode that loads takes the layer out
	h.w.mu.Lock()
	h.w.loaded = true
	h.w.mu.Unlock()
	h.setMode("included")
	h.w.reloadCh <- ipc.Reload{}
	waitSteps(nil)
}

func TestTeardownAfterRunSendsStepsAndResetsState(t *testing.T) {
	dir, err := os.MkdirTemp("", "axtd")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	sock := filepath.Join(dir, "hypr", "sig")
	os.MkdirAll(sock, 0o755)
	l, err := net.Listen("unix", filepath.Join(sock, ".socket.sock"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { l.Close() })
	asked := make(chan string, 8)
	go func() {
		for {
			c, err := l.Accept()
			if err != nil {
				return
			}
			buf := make([]byte, 4096)
			n, _ := c.Read(buf)
			asked <- string(buf[:n])
			io.WriteString(c, "ok")
			c.Close()
		}
	}()
	h := newHarness(t, "detached")
	vars := map[string]string{"HYPRLAND_INSTANCE_SIGNATURE": "sig", "XDG_RUNTIME_DIR": dir}
	h.m.o.Getenv = func(k string) string { return vars[k] }
	h.inputs("f1", "l1", "k1")
	h.eventually("the layer", h.called("runtime:live l1"))
	h.m.st.LiveCursor, h.m.st.SwayUnbinds = "x", []render.SwayUnbind{{Key: "k"}}
	// Run has returned once the harness is stopped
	h.stop()
	h.m.Teardown(context.Background())
	select {
	case got := <-asked:
		if got != "reload" {
			t.Fatalf("hyprland was asked %q", got)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("nothing was sent")
	}
	if st := h.m.st; st.RuntimeOn || st.LiveCursor != "" || st.SwayUnbinds != nil || st.NiriWrapper {
		t.Fatalf("state: %+v", st)
	}
}

// with the layer applied but no inputs to know what it was, nothing is sent
// and the state stays for the next start
func TestTeardownWithoutInputsLeavesTheState(t *testing.T) {
	h := newHarness(t, "detached")
	h.stop()
	h.m.runtimeOn = true
	h.m.st.NiriWrapper = true
	h.m.Teardown(context.Background())
	if !h.m.st.NiriWrapper || !h.m.runtimeOn {
		t.Fatalf("state was given back: %+v", h.m.st)
	}
}
