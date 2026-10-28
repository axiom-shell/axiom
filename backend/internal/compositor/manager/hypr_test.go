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
)

// fakeHyprland answers every request on dir's request socket with "ok",
// sending what it was asked on the returned channel
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
			io.WriteString(c, "ok")
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
