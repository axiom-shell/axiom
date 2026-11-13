package manager

import (
	"context"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	lua "github.com/yuin/gopher-lua"
)

// fakeHyprland answers every request on dir's request socket with "ok"
// ("[]" to a JSON one), sending what it was asked on the returned channel
func fakeHyprland(t *testing.T) (string, <-chan string) {
	t.Helper()
	// Unix socket paths are short: t.TempDir can be too long
	dir, err := os.MkdirTemp("", "axhypr")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	l, err := net.Listen("unix", filepath.Join(dir, ".socket.sock"))
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
			buf := make([]byte, 1<<20)
			n, _ := c.Read(buf)
			asked <- string(buf[:n])
			if strings.HasPrefix(string(buf[:n]), "j/") {
				io.WriteString(c, "[]")
			} else {
				io.WriteString(c, "ok")
			}
			c.Close()
		}
	}()
	return dir, asked
}

// Hyprland's layer rules, added in one eval (each rule in its own pcall)
// when the shell asks (compositor.layerRules) and again on every config
// reload, live or not: a reload drops them
func TestLayerRules(t *testing.T) {
	t.Parallel()
	tables, schema := repo(t)
	dir, asked := fakeHyprland(t)
	w := newHypr(env2(tables, schema, func(string) string { return "" }), &ipc.Hypr{Dir: dir})
	m := &Manager{w: w}
	want := "eval "
	for i, rule := range tables.LayerRulesLua() {
		if i > 0 {
			want += "\n"
		}
		want += "pcall(function() " + rule + " end)"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	for name, run := range map[string]func(){
		"asked":    func() { m.AddLayerRules(ctx) },
		"reloaded": func() { m.configReloaded(ctx, ipc.Reload{}) },
	} {
		run()
		select {
		case got := <-asked:
			if got != want {
				t.Errorf("%s: sent %q, want %q", name, got, want)
			}
		case <-ctx.Done():
			t.Fatalf("%s: nothing sent", name)
		}
	}
	if !strings.Contains(want, `name = "axiom-bar"`) {
		t.Errorf("no bar rule in %q", want)
	}
	if err := (&Manager{w: &fakeWriter{}}).AddLayerRules(ctx); err == nil {
		t.Error("layer rules added on another compositor")
	}
}

// The runtime layer records its keys right after the binds, ahead of the
// look and strips: a Lua error there (an hl function this version lacks)
// would leave the binds live but unrecorded
func TestRuntimeKeysFollowTheBinds(t *testing.T) {
	t.Parallel()
	tables, schema := repo(t)
	dir, asked := fakeHyprland(t)
	w := newHypr(env2(tables, schema, func(string) string { return "" }), &ipc.Hypr{Dir: dir})
	w.runtimeApply(context.Background(), Inputs{}, func() []string { return []string{"hl.look()"} })
	for range 3 { // the unbind, the binds and the animations read
		<-asked
	}
	sent := <-asked
	if k, l := strings.Index(sent, "AXIOM_RUNTIME_KEYS = {"), strings.Index(sent, "hl.look()"); k < 0 || l < k {
		t.Errorf("the keys aren't recorded ahead of the look: %q", sent)
	}
}

// The window rules go in the runtime eval after the strips; the last ones
// are turned off by their handles, then each is added, turned on and
// recorded; a clear turns them off
func TestRuntimeRulesFollowTheRules(t *testing.T) {
	t.Parallel()
	off := hyprRulesOffLua
	if got := strings.Join(hyprRuntimeRules(nil), "\n"); got != off+"\nAXIOM_RULES = {}" {
		t.Errorf("no rules: %q", got)
	}
	two := strings.Join(hyprRuntimeRules([]string{"hl.window_rule({ name = \"a\" })", "hl.window_rule({ name = \"b\" })"}), "\n")
	want := off + "\nAXIOM_RULES = {}\n" +
		"pcall(function() local r = hl.window_rule({ name = \"a\" }); r:set_enabled(true); AXIOM_RULES[#AXIOM_RULES + 1] = r end)\n" +
		"pcall(function() local r = hl.window_rule({ name = \"b\" }); r:set_enabled(true); AXIOM_RULES[#AXIOM_RULES + 1] = r end)"
	if two != want {
		t.Errorf("two rules:\n%s\nwant\n%s", two, want)
	}

	tables, schema := repo(t)
	dir, asked := fakeHyprland(t)
	w := newHypr(env2(tables, schema, func(string) string { return "" }), &ipc.Hypr{Dir: dir})
	in := Inputs{jsonx.Obj("windowRules", strs([]string{"hl.window_rule({ name = \"a\" })"}))}
	w.runtimeApply(context.Background(), in, func() []string { return []string{"hl.look()"} })
	for range 3 {
		<-asked
	}
	sent := <-asked
	if l, r := strings.Index(sent, "hl.look()"), strings.Index(sent, "AXIOM_RULES = {}"); l < 0 || r < l {
		t.Errorf("the rules aren't after the look and strips: %q", sent)
	}
	w.runtimeClear(context.Background())
	if cleared := <-asked; !strings.Contains(cleared, hyprRulesOffLua) {
		t.Errorf("clear doesn't turn the rules off: %q", cleared)
	}

	// The chunks as Hyprland's Lua runs them, hl.window_rule a stub
	// returning a handle that records set_enabled
	L := lua.NewState()
	defer L.Close()
	script := `handles = {}
hl = { window_rule = function(spec)
  local h = { name = spec.name }
  function h:set_enabled(v) self.on = v end
  handles[#handles + 1] = h
  return h
end }`
	if err := L.DoString(script); err != nil {
		t.Fatal(err)
	}
	rule := func(name string) string { return "hl.window_rule({ name = \"" + name + "\" })" }
	for _, names := range [][]string{{"a", "b"}, {"b"}} {
		var lines []string
		for _, n := range names {
			lines = append(lines, rule(n))
		}
		if err := L.DoString(strings.Join(hyprRuntimeRules(lines), "\n")); err != nil {
			t.Fatal(err)
		}
	}
	if err := L.DoString(`result = ""
for _, h in ipairs(handles) do result = result .. h.name .. "=" .. tostring(h.on) .. " " end`); err != nil {
		t.Fatal(err)
	}
	// a and b of the first apply, then b again; the first two turned off
	// by the second apply, the last one on
	if got := L.GetGlobal("result").String(); got != "a=false b=false b=true " {
		t.Errorf("handles: %q", got)
	}
}
