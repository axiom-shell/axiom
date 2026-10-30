package manager

import (
	"flag"
	"io"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

var update = flag.Bool("update", false, "rewrite testdata/golden from what the writers make now")

var (
	repoOnce   sync.Once
	repoTables *render.Tables
	repoSchema any
	repoErr    error
)

// repo is the tree's tables and built schema, read once
func repo(t *testing.T) (*render.Tables, any) {
	t.Helper()
	repoOnce.Do(func() {
		root := testkit.RepoRoot()
		repoTables, repoErr = render.ParseTables(func(p string) (string, error) {
			data, err := os.ReadFile(filepath.Join(root, p))
			return string(data), err
		})
		if repoErr != nil {
			return
		}
		data, err := os.ReadFile(filepath.Join(root, "config/json/config.schema.json"))
		if err != nil {
			repoErr = err
			return
		}
		repoSchema, repoErr = jsonx.Unmarshal(data)
	})
	if repoErr != nil {
		t.Fatal(repoErr)
	}
	return repoTables, repoSchema
}

// goldenInputs are what the layer is made of for kind: testdata/config.json
// (a config's sections the layer reads) with testdata/facts.json (what a
// shell sent as compositor.inputs, its machine's paths and names made
// generic) and the one output its profile names connected, decoded as the
// daemon decodes them
func goldenInputs(t *testing.T, kind string) Inputs {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("testdata", "facts.json"))
	if err != nil {
		t.Fatal(err)
	}
	var f Facts
	if err := rpc.DecodeStrict(data, &f); err != nil {
		t.Fatalf("compositor.inputs doesn't decode the shell's facts: %v", err)
	}
	f.Kind = kind
	data, err = os.ReadFile(filepath.Join("testdata", "config.json"))
	if err != nil {
		t.Fatal(err)
	}
	cfg, err := jsonx.Unmarshal(data)
	if err != nil {
		t.Fatal(err)
	}
	return buildInputs(cfg.(*jsonx.Object), &f, []render.Output{{Name: "DP-1", Description: "Example Display 0001"}})
}

// goldenWriter is kind's writer in a home that doesn't exist, with no
// compositor to reach (the texts need neither)
func goldenWriter(t *testing.T, kind string) writer {
	t.Helper()
	tables, schema := repo(t)
	env := map[string]string{"HOME": "/nonexistent/home", "XDG_CONFIG_HOME": "/nonexistent/home/.config"}
	e := env2(tables, schema, func(k string) string { return env[k] })
	switch kind {
	case "hyprland":
		return newHypr(e, nil)
	case "sway":
		return newSway(e, nil)
	}
	return newNiri(e, nil)
}

func env2(tables *render.Tables, schema any, getenv func(string) string) env {
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	return env{getenv: getenv, stateDir: "/nonexistent/home/.local/state/axiom/", tables: tables,
		schema: func() any { return schema }, logf: func(f string, a ...any) { log.Info(sprintf(f, a...)) },
		state: &runtimeState{}}
}

// The whole files each writer makes from one shell's inputs, byte for byte
// (testdata/golden/<kind>/; `go test -run Golden -update` rewrites them
// after a change meant to show there): what lands in a user's config
// changes only on purpose. Each is also read by its compositor's own check
// where it's installed.
func TestGoldenFiles(t *testing.T) {
	t.Parallel()
	for _, c := range []struct{ kind, ext string }{{"hyprland", ".lua"}, {"sway", ".conf"}, {"niri", ".kdl"}} {
		t.Run(c.kind, func(t *testing.T) {
			t.Parallel()
			in := goldenInputs(t, c.kind)
			w := goldenWriter(t, c.kind)
			spec := in.get("specFile")
			files := map[string]string{
				"module" + c.ext:            w.moduleText(in, spec),
				"managed" + c.ext:           w.managedText(in, spec),
				"released-detached" + c.ext: w.releasedText(in, "detached"),
				"released-included" + c.ext: w.releasedText(in, "included"),
				"empty-module" + c.ext:      w.emptyModuleText(),
			}
			if live := w.liveLines(in, in.get("specLive")); len(live) > 0 {
				files["live.txt"] = strings.Join(live, "\n") + "\n"
			}
			dir := filepath.Join("testdata", "golden", c.kind)
			if *update {
				os.RemoveAll(dir)
				os.MkdirAll(dir, 0o755)
			}
			for name, text := range files {
				path := filepath.Join(dir, name)
				if *update {
					if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
						t.Fatal(err)
					}
					continue
				}
				want, err := os.ReadFile(path)
				if err != nil {
					t.Fatalf("%v (go test -run Golden -update writes it)", err)
				}
				if text != string(want) {
					g, x := strings.Split(text, "\n"), strings.Split(string(want), "\n")
					for i := 0; i < len(g) || i < len(x); i++ {
						var a, b string
						if i < len(g) {
							a = g[i]
						}
						if i < len(x) {
							b = x[i]
						}
						if a != b {
							t.Errorf("%s/%s: line %d: got %q, want %q", c.kind, name, i+1, a, b)
							break
						}
					}
				}
			}
			entries, _ := os.ReadDir(dir)
			if len(entries) != len(files) {
				t.Errorf("%s holds %d files, the writer makes %d", dir, len(entries), len(files))
			}
			checkWithCompositor(t, c.kind, files)
		})
	}
}

// checkWithCompositor has each file read by the tool that will read it,
// where it's installed (not in CI)
func checkWithCompositor(t *testing.T, kind string, files map[string]string) {
	dir := t.TempDir()
	run := func(name, tool string, args ...string) {
		t.Helper()
		if _, err := exec.LookPath(tool); err != nil {
			return
		}
		cmd := exec.Command(tool, args...)
		done := make(chan struct{})
		var out []byte
		var err error
		go func() { out, err = cmd.CombinedOutput(); close(done) }()
		select {
		case <-done:
		case <-time.After(testkit.Bound(30 * time.Second)):
			cmd.Process.Kill()
			t.Fatalf("%s took too long", tool)
		}
		if err != nil || (tool == "Hyprland" && !strings.Contains(string(out), "config ok")) {
			var kept []string
			for _, l := range strings.Split(string(out), "\n") {
				if !strings.Contains(l, "DEBUG") {
					kept = append(kept, l)
				}
			}
			t.Errorf("%s: %s %s: %v\n%s", name, tool, strings.Join(args, " "), err, strings.Join(kept, "\n"))
		}
	}
	for name, text := range files {
		if name == "live.txt" {
			continue
		}
		// What the file includes are the user's files, checked when the
		// compositor loads them (as the writers validate)
		var own []string
		for _, l := range strings.Split(text, "\n") {
			if !strings.HasPrefix(strings.TrimSpace(l), "include ") {
				own = append(own, l)
			}
		}
		path := filepath.Join(dir, name)
		if err := os.WriteFile(path, []byte(strings.Join(own, "\n")), 0o644); err != nil {
			t.Fatal(err)
		}
		switch kind {
		case "hyprland":
			run(name, "luac", "-p", path)
			if name == "managed.lua" {
				run(name, "Hyprland", "--verify-config", "-c", path)
			}
		case "sway":
			run(name, "sway", "--validate", "--config", path)
		case "niri":
			run(name, "niri", "validate", "-c", path)
		}
	}
}
