package hookup

import (
	"encoding/json"
	"slices"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/theme/integrations"
)

var dirs = integrations.Dirs{Home: "/h", Config: "/h/.config", State: "/h/.local/state"}

func env(existing ...string) Env {
	return Env{Dirs: dirs, Shell: "/bin/bash", Exists: func(p string) bool { return slices.Contains(existing, p) }}
}

// plan resolves one target against a writable file holding text ("" and
// exists false: missing)
func plan(t *testing.T, target Target, text string, exists bool) (Resolved, Plan, []string) {
	t.Helper()
	r := Resolve([]Target{target}, nil, env())[0]
	lines := Lines(text)
	p, err := Decide(r, Facts{Real: r.Path, Exists: exists, Lines: lines, Writable: true})
	if err != nil {
		t.Fatal(err)
	}
	return r, p, lines
}

// What Apply writes for each place, and what it reports beforehand
func TestEdit(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		name   string
		target Target
		before string
		after  string
		// what the plan says of lines already setting the key
		replaces, alongside, conflicts []string
		createsSection                 bool
	}{
		{name: "end after a blank line", target: Target{File: Files{"{config}/kitty.conf"}, Place: End, Text: "include axiom.conf"},
			before: "font_size 12\n", after: "font_size 12\n\ninclude axiom.conf\n"},
		{name: "end of a new file", target: Target{File: Files{"{config}/kitty.conf"}, Place: End, Text: "include axiom.conf"},
			after: "include axiom.conf\n"},
		{name: "start goes first", target: Target{File: Files{"{config}/gtk.css"}, Place: Start, Text: `@import url("axiom.css");`},
			before: "window { color: red; }\n", after: "@import url(\"axiom.css\");\nwindow { color: red; }\n"},
		{name: "top comments out the old key", target: Target{File: Files{"{config}/helix.toml"}, Place: Top, Text: `theme = "axiom"`},
			before:   "theme = \"onedark\"\n\n[editor]\nline-number = \"relative\"\n",
			after:    "# axiom: theme = \"onedark\"\ntheme = \"axiom\"\n\n[editor]\nline-number = \"relative\"\n",
			replaces: []string{`theme = "onedark"`}},
		{name: "top keeps", target: Target{File: Files{"{config}/foot.ini"}, Place: Top, Replace: "keep", Text: "include={config}/foot/axiom.ini"},
			before: "include=~/mine.ini\n\n[main]\nfont=x\n", after: "include=~/mine.ini\ninclude=/h/.config/foot/axiom.ini\n\n[main]\nfont=x\n",
			alongside: []string{"include=~/mine.ini"}},
		{name: "section present", target: Target{File: Files{"{config}/theme.toml"}, Place: Section, Section: "flavor", Text: "dark = \"axiom\"\nlight = \"axiom\""},
			before:   "[flavor]\ndark = \"x\"\n\n[mgr]\nfoo = 1\n",
			after:    "[flavor]\n# axiom: dark = \"x\"\ndark = \"axiom\"\nlight = \"axiom\"\n\n[mgr]\nfoo = 1\n",
			replaces: []string{`dark = "x"`}},
		{name: "section missing", target: Target{File: Files{"{config}/theme.toml"}, Place: Section, Section: "flavor", Text: "dark = \"axiom\""},
			before: "[mgr]\nfoo = 1\n", after: "[mgr]\nfoo = 1\n\n[flavor]\ndark = \"axiom\"\n", createsSection: true},
		{name: "a key in another section is left", target: Target{File: Files{"{config}/kdeglobals"}, Place: Section, Section: "UiSettings", Comment: ";", Text: "ColorScheme=Axiom"},
			before:   "[General]\nColorScheme=BreezeDark\n\n[UiSettings]\nColorScheme=BreezeDark\n",
			after:    "[General]\nColorScheme=BreezeDark\n\n[UiSettings]\n; axiom: ColorScheme=BreezeDark\nColorScheme=Axiom\n",
			replaces: []string{"ColorScheme=BreezeDark"}},
		{name: "shellrc", target: Target{Place: ShellRC, Replace: "keep", Text: "export FZF_DEFAULT_OPTS_FILE={state}/axiom/fzf-colors"},
			before: "export FZF_DEFAULT_OPTS_FILE=~/mine\n", after: "export FZF_DEFAULT_OPTS_FILE=~/mine\n\nexport FZF_DEFAULT_OPTS_FILE=/h/.local/state/axiom/fzf-colors\n",
			alongside: []string{"export FZF_DEFAULT_OPTS_FILE=~/mine"}},
		{name: "a CRLF file keeps its line ends", target: Target{File: Files{"{config}/kitty.conf"}, Place: End, Text: "include axiom.conf"},
			before: "font_size 12\r\n", after: "font_size 12\r\n\ninclude axiom.conf\n"},
	} {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			r, p, lines := plan(t, c.target, c.before, c.before != "")
			if !p.Pending() {
				t.Fatalf("nothing to do: %+v", p.Row)
			}
			if got := Text(Edit(r, p, lines)); got != c.after {
				t.Errorf("wrote %q, want %q", got, c.after)
			}
			for _, k := range []struct {
				name      string
				got, want []string
			}{{"replaces", p.Replaces, c.replaces}, {"alongside", p.Alongside, c.alongside}, {"conflicts", p.Conflicts, c.conflicts}} {
				if !slices.Equal(k.got, k.want) && len(k.got)+len(k.want) > 0 {
					t.Errorf("%s %q, want %q", k.name, k.got, k.want)
				}
			}
			if p.CreatesSection != c.createsSection {
				t.Errorf("createsSection %v", p.CreatesSection)
			}
			// Applied, it's done
			after := Lines(c.after)
			if again, _ := Decide(r, Facts{Real: r.Path, Exists: true, Lines: after, Writable: true}); !again.Done {
				t.Errorf("not done after Apply: %+v", again.Row)
			}
		})
	}
}

// What makes a target done, skipped or blocked without an edit
func TestDecide(t *testing.T) {
	t.Parallel()
	kitty := Target{File: Files{"{config}/kitty.conf"}, Place: End, Text: "include axiom.conf", Accept: `^include\s+\S*axiom\.conf`}
	for _, c := range []struct {
		name   string
		target Target
		facts  Facts
		check  func(Plan) bool
	}{
		{"accept counts another spelling", kitty, Facts{Exists: true, Writable: true, Lines: []string{"include ~/.config/kitty/axiom.conf"}},
			func(p Plan) bool { return p.Done }},
		{"a commented-out line doesn't count", kitty, Facts{Exists: true, Writable: true, Lines: []string{"# include axiom.conf"}},
			func(p Plan) bool { return !p.Done && p.Pending() }},
		{"a missing file isn't done", kitty, Facts{Writable: true},
			func(p Plan) bool { return !p.Done && p.Pending() }},
		{"conflict blocks", Target{File: Files{"{config}/a.toml"}, Place: Section, Section: "general", Replace: "conflict", Text: `import = ["x"]`},
			Facts{Exists: true, Writable: true, Lines: []string{"[general]", `import = ["~/mine.toml"]`}},
			func(p Plan) bool {
				return !p.Pending() && slices.Equal(p.Conflicts, []string{`import = ["~/mine.toml"]`})
			}},
		{"a file that can't be written is skipped", kitty, Facts{Exists: true, Lines: []string{"font_size 12"}},
			func(p Plan) bool { return p.Skipped == SkipReadonly && !p.Pending() }},
		{"but one done is done", kitty, Facts{Exists: true, Lines: []string{"include axiom.conf"}},
			func(p Plan) bool { return p.Done && p.Skipped == "" }},
		{"a link to one is wrapped when the target says how", Target{File: Files{"{config}/gtk.css"}, Place: Start, Text: "@import x;", WrapLink: "@import url(\"file://{link}\");"},
			Facts{Exists: true, CanWrap: true, Link: true, Real: "/usr/share/themes/t/gtk.css", Lines: []string{"a {}"}},
			func(p Plan) bool { return p.Wraps && p.Pending() }},
		{"copy is done when the file is there", Target{File: Files{"{config}/m.lua"}, Place: Copy, From: "templates/m.lua"}, Facts{Exists: true},
			func(p Plan) bool { return p.Done }},
		{"copy-only", Target{Text: "x", Where: "somewhere"}, Facts{},
			func(p Plan) bool { return p.CopyOnly && !p.Pending() }},
	} {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			r := Resolve([]Target{c.target}, nil, env())[0]
			p, err := Decide(r, c.facts)
			if err != nil || !c.check(p) {
				t.Errorf("%+v (%v)", p.Row, err)
			}
		})
	}
	if _, err := Decide(Resolve([]Target{{File: Files{"/x"}, Text: "x", Accept: "("}}, nil, env())[0], Facts{}); err == nil {
		t.Error("a broken accept passed")
	}
}

// The wrapped link's file loads the file it pointed at, then the text
func TestWrap(t *testing.T) {
	t.Parallel()
	r := Resolve([]Target{{File: Files{"{config}/gtk.css"}, Place: Start, Text: `@import url("axiom.css");`, WrapLink: `@import url("file://{link}");`}}, nil, env())[0]
	p, _ := Decide(r, Facts{Exists: true, CanWrap: true, Link: true, Real: "/usr/share/t.css", Lines: []string{"a {}"}})
	if got := Text(Edit(r, p, []string{"a {}"})); got != "@import url(\"file:///usr/share/t.css\");\n@import url(\"axiom.css\");\n" {
		t.Errorf("%q", got)
	}
}

// Resolving: the first existing candidate, $SHELL's rc (fish's set -gx),
// a profile per folder
func TestResolve(t *testing.T) {
	t.Parallel()
	ghostty := Target{File: Files{"{config}/ghostty/config", "{config}/ghostty/config.ghostty"}, Place: End, Text: "theme = axiom"}
	if got := Resolve([]Target{ghostty}, nil, env())[0].Path; got != "/h/.config/ghostty/config" {
		t.Errorf("none existing: %s", got)
	}
	if got := Resolve([]Target{ghostty}, nil, env("/h/.config/ghostty/config.ghostty"))[0].Path; got != "/h/.config/ghostty/config.ghostty" {
		t.Errorf("the second existing: %s", got)
	}
	rc := Target{Place: ShellRC, Text: "export A={state}/a"}
	for shell, want := range map[string][2]string{
		"/bin/zsh": {"/z/.zshrc", "export A=/h/.local/state/a"}, "/bin/bash": {"/h/.bashrc", "export A=/h/.local/state/a"},
		"/usr/bin/fish": {"/h/.config/fish/conf.d/axiom.fish", "set -gx A /h/.local/state/a"}, "/bin/tcsh": {"", "export A=/h/.local/state/a"},
	} {
		e := env()
		e.Shell, e.ZDotDir = shell, "/z"
		r := Resolve([]Target{rc}, nil, e)[0]
		if r.Path != want[0] || r.Text != want[1] || (want[0] == "") != (r.Skipped == SkipShell) {
			t.Errorf("%s: %+v", shell, r)
		}
	}
	css := Target{File: Files{"chrome/userChrome.css"}, Place: Start, Text: "x", PerProfile: true}
	if got := Resolve([]Target{css}, nil, env()); len(got) != 1 || got[0].Skipped != SkipProfiles || got[0].Path != "" {
		t.Errorf("no profiles: %+v", got)
	}
	if got := Resolve([]Target{css}, []string{"/p/a", "/p/b c"}, env()); len(got) != 2 || got[1].Path != "/p/b c/chrome/userChrome.css" {
		t.Errorf("two profiles: %+v", got)
	}
}

// A target's file is a path or a list
func TestFiles(t *testing.T) {
	t.Parallel()
	var ts []Target
	if err := json.Unmarshal([]byte(`[{"file":"a","text":""},{"file":["b","c"],"text":""}]`), &ts); err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(ts[0].File, Files{"a"}) || !slices.Equal(ts[1].File, Files{"b", "c"}) {
		t.Errorf("%+v", ts)
	}
	if err := json.Unmarshal([]byte(`[{"file":1}]`), &ts); err == nil || !strings.Contains(err.Error(), "file must be") {
		t.Errorf("a number: %v", err)
	}
}

func TestShown(t *testing.T) {
	t.Parallel()
	for in, want := range map[string]string{"/h": "~", "/h/.config/x": "~/.config/x", "/hx/y": "/hx/y", "/etc/x": "/etc/x"} {
		if got := Shown(in, "/h/"); got != want {
			t.Errorf("%s: %s", in, got)
		}
	}
}
