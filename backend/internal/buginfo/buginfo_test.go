package buginfo

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/store"
)

type fakeCompositor struct {
	version string
	outputs []render.Output
	err     error
}

func (f fakeCompositor) Version(context.Context) (string, error) { return f.version, f.err }
func (f fakeCompositor) Outputs(context.Context) ([]render.Output, error) {
	return f.outputs, f.err
}

// programs answers git and qs as a clone on branch would, nothing when
// installed lacks the program
func programs(installed []string, described, branch string) func(context.Context, string, ...string) (string, error) {
	return func(_ context.Context, name string, args ...string) (string, error) {
		if !slices.Contains(installed, name) {
			return "", errors.New("not found")
		}
		switch {
		case name == "qs":
			return "Quickshell 0.3.2 (revision abc)\nmore\n", nil
		case slices.Contains(args, "describe") && described != "":
			return described + "\n", nil
		case slices.Contains(args, "--show-current"):
			return branch + "\n", nil
		}
		return "", errors.New("exit 128")
	}
}

func TestMachine(t *testing.T) {
	t.Parallel()
	osRelease := filepath.Join(t.TempDir(), "os-release")
	os.WriteFile(osRelease, []byte("NAME=\"Arch Linux\"\nPRETTY_NAME=\"Arch Linux\"\nID=arch\n"), 0o644)
	idOnly := filepath.Join(t.TempDir(), "os-release")
	os.WriteFile(idOnly, []byte("ID=void\n"), 0o644)
	packaged := t.TempDir()
	os.WriteFile(filepath.Join(packaged, ".packaged"), []byte("1.2.0-1\n"), 0o644)
	niri := fakeCompositor{version: "niri 26.04", outputs: []render.Output{{Name: "DP-1"}, {Name: "HDMI-A-1", Disabled: true}, {Name: "eDP-1"}}}
	tests := []struct {
		name string
		o    Options
		want Report
	}{
		{"a clone on a branch, niri", Options{
			Tree: "/repo", Compositor: niri, Output: programs([]string{"git", "qs"}, "v1.2.0-3-gabc1234", "fix"), OSRelease: []string{"/nope", osRelease},
		}, Report{Axiom: "clone v1.2.0-3-gabc1234 (branch fix)", Quickshell: "Quickshell 0.3.2 (revision abc)", Compositor: "niri 26.04", Monitors: "2", Distro: "Arch Linux"}},
		{"a clone on main", Options{
			Tree: "/repo", Output: programs([]string{"git"}, "v1.2.0", "main"), Desktop: "river", OSRelease: []string{idOnly},
		}, Report{Axiom: "clone v1.2.0", Quickshell: "not found", Compositor: "river", Monitors: Unknown, Distro: "void"}},
		{"a package", Options{
			Tree: packaged, Compositor: fakeCompositor{err: errors.New("gone")}, Output: programs(nil, "", ""),
		}, Report{Axiom: "package 1.2.0-1", Quickshell: "not found", Compositor: Unknown, Monitors: Unknown, Distro: Unknown}},
		{"neither", Options{Tree: "/repo", Output: programs([]string{"git"}, "", "")},
			Report{Axiom: "unknown (neither a clone nor a package)", Quickshell: "not found", Compositor: Unknown, Monitors: Unknown, Distro: Unknown}},
		{"no tree", Options{Output: programs(nil, "", "")},
			Report{Axiom: "unknown (no axiom tree found)", Quickshell: "not found", Compositor: Unknown, Monitors: Unknown, Distro: Unknown}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			var got Report
			Machine(context.Background(), tc.o, &got)
			if got != tc.want {
				t.Errorf("got  %+v\nwant %+v", got, tc.want)
			}
		})
	}
}

func TestConfigLine(t *testing.T) {
	t.Parallel()
	obj := func(text string) *jsonx.Object {
		v, err := jsonx.Unmarshal([]byte(text))
		if err != nil {
			t.Fatal(err)
		}
		return v.(*jsonx.Object)
	}
	tests := []struct {
		name string
		cfg  *jsonx.Object
		st   store.State
		want string
	}{
		{"loaded", obj(`{"format": 2, "version": 81, "Compositor": {"mode": "managed"}}`), store.State{}, "format 2, version 81, compositor mode managed, ok"},
		{"format 1, no mode", obj(`{"version": 70}`), store.State{}, "format 1, version 70, compositor mode detached, ok"},
		{"blocked", obj(`{"format": 2, "version": 81}`), store.State{Blocked: true, Issues: []axerr.Issue{{}, {}}}, "format 2, version 81, compositor mode detached, blocked (issues: 2)"},
		{"missing", nil, store.State{Missing: true}, "missing (the defaults apply)"},
		{"unreadable", nil, store.State{Blocked: true}, "unreadable"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := ConfigLine(tc.cfg, tc.st); got != tc.want {
				t.Errorf("got %q, want %q", got, tc.want)
			}
		})
	}
}

// Nothing personal: the report names no path, not even the tree's
func TestNoPaths(t *testing.T) {
	t.Parallel()
	tree := t.TempDir()
	var r Report
	Machine(context.Background(), Options{Tree: tree, Output: programs([]string{"git"}, "v1", "")}, &r)
	if strings.Contains(r.Axiom, tree) {
		t.Errorf("the tree's path in %q", r.Axiom)
	}
}
