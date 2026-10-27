package cursortheme

import (
	"context"
	"errors"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// scratch is a home, a data home and a system data folder in a temp dir.
type scratch struct {
	t                  *testing.T
	home, data, system string
	gsettings          map[string]string // key → value, nil for no gsettings
	sets               []string
}

func newScratch(t *testing.T) *scratch {
	dir := t.TempDir()
	s := &scratch{t: t, home: filepath.Join(dir, "home"), data: filepath.Join(dir, "data"), system: filepath.Join(dir, "system")}
	if err := os.MkdirAll(s.home, 0o755); err != nil {
		t.Fatal(err)
	}
	return s
}

func (s *scratch) theme(name string, cursors []string, inherits string) {
	folder := filepath.Join(s.system, "icons", name)
	if err := os.MkdirAll(filepath.Join(folder, "cursors"), 0o755); err != nil {
		s.t.Fatal(err)
	}
	for _, c := range cursors {
		if err := os.WriteFile(filepath.Join(folder, "cursors", c), []byte(c), 0o644); err != nil {
			s.t.Fatal(err)
		}
	}
	if inherits != "" {
		if err := os.WriteFile(filepath.Join(folder, "index.theme"), []byte("[Icon Theme]\nInherits="+inherits+"\n"), 0o644); err != nil {
			s.t.Fatal(err)
		}
	}
}

func (s *scratch) resolver() *Resolver {
	env := map[string]string{"HOME": s.home, "XDG_DATA_HOME": s.data, "XDG_DATA_DIRS": s.system}
	opts := Options{Getenv: func(k string) string { return env[k] }}
	if s.gsettings != nil {
		opts.GSettings = func(_ context.Context, args ...string) (string, error) {
			switch args[0] {
			case "get":
				v, ok := s.gsettings[args[2]]
				if !ok {
					return "", errors.New("no such key")
				}
				return "'" + v + "'\n", nil
			case "set":
				s.gsettings[args[2]] = args[3]
				s.sets = append(s.sets, args[2]+"="+args[3])
			}
			return "", nil
		}
	}
	return New(opts)
}

func (s *scratch) resolve(theme string, size int) Result {
	s.t.Helper()
	r, err := s.resolver().Resolve(context.Background(), theme, size)
	if err != nil {
		s.t.Fatal(err)
	}
	return r
}

func (s *scratch) companion(theme string) string {
	return filepath.Join(s.data, "icons", CompanionName(theme))
}

func exists(path string) bool { _, err := os.Lstat(path); return err == nil }

func TestFillsMissingNames(t *testing.T) {
	t.Parallel()
	s := newScratch(t)
	s.theme("Old", []string{"left_ptr", "hand2", "xterm", "text"}, "")
	if got := s.resolve("Old", 0); got != (Result{Theme: "axiom-cursor-Old", Filled: 2}) {
		t.Fatalf("got %+v", got)
	}
	made := s.companion("Old")
	index, _ := os.ReadFile(filepath.Join(made, "index.theme"))
	if !strings.Contains(string(index), "Inherits=Old\n") {
		t.Errorf("index.theme: %q", index)
	}
	for name, want := range map[string]string{"default": "left_ptr", "pointer": "hand2"} {
		if got, _ := os.Readlink(filepath.Join(made, "cursors", name)); got != filepath.Join(s.system, "icons/Old/cursors", want) {
			t.Errorf("%s → %q", name, got)
		}
	}
	// The theme has `text` itself: not linked
	if exists(filepath.Join(made, "cursors", "text")) {
		t.Error("text linked")
	}
	// As wanted already: not rewritten
	before, _ := os.Stat(filepath.Join(made, "index.theme"))
	s.resolve("Old", 0)
	after, _ := os.Stat(filepath.Join(made, "index.theme"))
	if !os.SameFile(before, after) {
		t.Error("rewritten while already as wanted")
	}
	// Nothing staged is left beside it
	entries, _ := os.ReadDir(filepath.Join(s.data, "icons"))
	if len(entries) != 1 {
		t.Errorf("icons holds %d entries", len(entries))
	}
}

func TestResolve(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name   string
		setup  func(s *scratch)
		before []string // resolved first
		theme  string
		want   Result
		gone   []string // companions removed
	}{
		{
			name: "inherited names count",
			setup: func(s *scratch) {
				s.theme("Base", []string{"default", "pointer"}, "")
				s.theme("Child", []string{"left_ptr", "hand2"}, "Base")
			},
			theme: "Child", want: Result{Theme: "Child"},
		},
		{
			name: "inherits through a comma or semicolon list, nearest first",
			setup: func(s *scratch) {
				s.theme("A", []string{"arrow"}, "")
				s.theme("B", []string{"hand2"}, "")
				s.theme("Child", []string{"xterm"}, "A; B")
			},
			theme: "Child", want: Result{Theme: "axiom-cursor-Child", Filled: 3},
		},
		{
			name: "a complete theme removes the old companion",
			setup: func(s *scratch) {
				s.theme("Old", []string{"left_ptr"}, "")
				s.theme("New", []string{"default", "left_ptr"}, "")
			},
			before: []string{"Old"}, theme: "New", want: Result{Theme: "New"}, gone: []string{"Old"},
		},
		{
			// A hyprcursor-only theme keeps its name
			name:  "no XCursor cursors",
			setup: func(s *scratch) {},
			theme: "Missing", want: Result{Theme: "Missing"},
		},
		{
			// One name for both would leave readers on the cursors they loaded
			name: "each theme its own name",
			setup: func(s *scratch) {
				s.theme("Old", []string{"left_ptr"}, "")
				s.theme("Other Theme", []string{"arrow"}, "")
			},
			before: []string{"Old"}, theme: "Other Theme", want: Result{Theme: "axiom-cursor-Other_Theme", Filled: 1}, gone: []string{"Old"},
		},
		{
			name: "an inheritance loop ends",
			setup: func(s *scratch) {
				s.theme("A", []string{"left_ptr"}, "B")
				s.theme("B", []string{"hand2"}, "A")
			},
			theme: "A", want: Result{Theme: "axiom-cursor-A", Filled: 2},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			s := newScratch(t)
			tc.setup(s)
			for _, b := range tc.before {
				s.resolve(b, 0)
			}
			if got := s.resolve(tc.theme, 0); got != tc.want {
				t.Errorf("got %+v, want %+v", got, tc.want)
			}
			for _, g := range tc.gone {
				if exists(s.companion(g)) {
					t.Errorf("%s's companion is still there", g)
				}
			}
		})
	}
}

func TestLeavesAFolderNotItsOwn(t *testing.T) {
	t.Parallel()
	s := newScratch(t)
	s.theme("Old", []string{"left_ptr"}, "")
	s.theme("Other", []string{"left_ptr"}, "")
	mine := s.companion("Old")
	if err := os.MkdirAll(mine, 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := s.resolver().Resolve(context.Background(), "Old", 0); axerr.KindOf(err) != axerr.Conflict {
		t.Fatalf("got %v, want a conflict", err)
	}
	// Nor is it removed as another theme's companion
	s.resolve("Other", 0)
	if !exists(mine) {
		t.Error("a folder not axiom's was removed")
	}
}

func TestRefusesNames(t *testing.T) {
	t.Parallel()
	s := newScratch(t)
	for _, theme := range []string{"", ".", "..", "a/b", "axiom-cursor-Old"} {
		if _, err := s.resolver().Resolve(context.Background(), theme, 0); axerr.KindOf(err) != axerr.BadRequest {
			t.Errorf("%q: got %v", theme, err)
		}
	}
}

func TestGTK(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name string
		have map[string]string
		size int
		want map[string]string
		sets int
	}{
		{"sets what differs", map[string]string{"cursor-theme": "Adwaita", "cursor-size": "24"}, 24,
			map[string]string{"cursor-theme": "axiom-cursor-Old", "cursor-size": "24"}, 1},
		{"no size leaves the size", map[string]string{"cursor-theme": "Adwaita", "cursor-size": "32"}, 0,
			map[string]string{"cursor-theme": "axiom-cursor-Old", "cursor-size": "32"}, 1},
		{"no schema sets nothing", map[string]string{}, 24, map[string]string{}, 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			s := newScratch(t)
			s.theme("Old", []string{"left_ptr"}, "")
			s.gsettings = maps.Clone(tc.have)
			s.resolve("Old", tc.size)
			if !maps.Equal(s.gsettings, tc.want) || len(s.sets) != tc.sets {
				t.Errorf("got %v after %v", s.gsettings, s.sets)
			}
		})
	}
}

func TestLinks(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name string
		have map[string]string
		want map[string]string
	}{
		{"first alias wins", map[string]string{"arrow": "/a", "left_ptr": "/l"}, map[string]string{"default": "/l"}},
		{"a standard name is kept", map[string]string{"default": "/d", "left_ptr": "/l"}, map[string]string{}},
		{"one X11 cursor fills several", map[string]string{"fleur": "/f"},
			map[string]string{"move": "/f", "grabbing": "/f", "all-scroll": "/f"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := Links(tc.have); !maps.Equal(got, tc.want) {
				t.Errorf("got %v", got)
			}
		})
	}
}

func TestNames(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct{ theme, want string }{
		{"Bibata-Modern_Ice", "axiom-cursor-Bibata-Modern_Ice"},
		{"Oxygen White", "axiom-cursor-Oxygen_White"},
		{"a  \"b\"", "axiom-cursor-a_b_"},
	} {
		if got := CompanionName(tc.theme); got != tc.want {
			t.Errorf("%q → %q", tc.theme, got)
		}
	}
	for _, tc := range []struct {
		index string
		want  []string
	}{
		{"[Icon Theme]\nName=x\nInherits = A, B;C\n", []string{"A", "B", "C"}},
		{"[Icon Theme]\nName=x\n", nil},
	} {
		if got := inherits(tc.index); !slices.Equal(got, tc.want) {
			t.Errorf("%q → %v", tc.index, got)
		}
	}
}
