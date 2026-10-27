package edit

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/assets"
	"github.com/axiom-shell/axiom/backend/internal/hookup"
)

// scratch is a home for the hookups, with every command but one installed
type scratch struct {
	t                  *testing.T
	root, home, config string
	h                  *Hookups
	schema             map[string]entry
	shell              string
}

type entry struct {
	Hookup   []hookup.Target `json:"x-hookup"`
	Profiles []string        `json:"x-profiles"`
}

func newScratch(t *testing.T) *scratch {
	t.Helper()
	s := &scratch{t: t, root: t.TempDir(), shell: "/bin/bash"}
	s.home = filepath.Join(s.root, "home")
	s.config = filepath.Join(s.home, ".config")
	if err := os.MkdirAll(s.config, 0o755); err != nil {
		t.Fatal(err)
	}
	env := map[string]string{"HOME": s.home, "XDG_CONFIG_HOME": s.config, "XDG_STATE_HOME": s.home + "/.local/state"}
	s.h = NewHookups(HookupOptions{
		Getenv: func(k string) string {
			if k == "SHELL" {
				return s.shell
			}
			return env[k]
		},
		LookPath: func(cmd string) (string, error) {
			if cmd == "axiom-no-such-command" {
				return "", errors.New("not found")
			}
			return "/usr/bin/" + cmd, nil
		},
		Scripts: filepath.Join("..", "..", "..", "..", "scripts"),
		Now:     func() time.Time { return time.Date(2026, 10, 27, 12, 0, 0, 0, time.Local) },
	})
	data, err := assets.Read("config/json/config.schema.json")
	if err != nil {
		t.Fatal(err)
	}
	var schema struct {
		Properties struct {
			ThemeIntegrations struct {
				Properties map[string]entry `json:"properties"`
			} `json:"ThemeIntegrations"`
		} `json:"properties"`
	}
	if err := json.Unmarshal(data, &schema); err != nil {
		t.Fatal(err)
	}
	s.schema = schema.Properties.ThemeIntegrations.Properties
	return s
}

func (s *scratch) status(key string) []hookup.Row {
	s.t.Helper()
	rows, err := s.h.Status(s.schema[key].Hookup, s.schema[key].Profiles)
	if err != nil {
		s.t.Fatal(err)
	}
	return rows
}

func (s *scratch) apply(key string) []HookupResult {
	return s.h.Apply(s.schema[key].Hookup, s.schema[key].Profiles)
}

func (s *scratch) write(rel, text string) string {
	s.t.Helper()
	path := filepath.Join(s.config, rel)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		s.t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		s.t.Fatal(err)
	}
	return path
}

func read(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func backups(t *testing.T, path string) []string {
	t.Helper()
	found, err := filepath.Glob(path + ".axiom-bak-*")
	if err != nil {
		t.Fatal(err)
	}
	return found
}

// readonly is a file in a folder the user can't write (/usr/share/themes)
func (s *scratch) readonly(name, text string) string {
	s.t.Helper()
	if os.Geteuid() == 0 {
		s.t.Skip("root can write anywhere")
	}
	dir := filepath.Join(s.root, "system-"+name)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		s.t.Fatal(err)
	}
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte(text), 0o444); err != nil {
		s.t.Fatal(err)
	}
	if err := os.Chmod(dir, 0o555); err != nil {
		s.t.Fatal(err)
	}
	s.t.Cleanup(func() { os.Chmod(dir, 0o755) })
	return path
}

func (s *scratch) link(rel, to string) string {
	s.t.Helper()
	path := filepath.Join(s.config, rel)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		s.t.Fatal(err)
	}
	if err := os.Symlink(to, path); err != nil {
		s.t.Fatal(err)
	}
	return path
}

// Every integration's hookup applies to empty configs, and is then done
func TestEveryHookupApplies(t *testing.T) {
	t.Parallel()
	s := newScratch(t)
	if len(s.schema) == 0 {
		t.Fatal("no theme integrations in the schema")
	}
	for key, e := range s.schema {
		if e.Hookup == nil {
			t.Errorf("%s has no x-hookup", key)
			continue
		}
		for _, r := range s.apply(key) {
			if r.Error != "" {
				t.Errorf("%s: %s", key, r.Error)
			}
		}
		for _, row := range s.status(key) {
			if !row.CopyOnly && row.Skipped == "" && !row.Done {
				t.Errorf("%s: not done after Apply: %+v", key, row)
			}
		}
	}
}

// Apply edits the file a link names (the link stays), backs it up beside
// it, and changes nothing once done
func TestApplyThroughALink(t *testing.T) {
	t.Parallel()
	s := newScratch(t)
	real := filepath.Join(s.root, "dotfiles", "kitty.conf")
	os.MkdirAll(filepath.Dir(real), 0o755)
	os.WriteFile(real, []byte("font_size 12\n"), 0o600)
	link := s.link("kitty/kitty.conf", real)
	if row := s.status("kitty")[0]; !row.Link || row.Path != "~/.config/kitty/kitty.conf" {
		t.Errorf("status: %+v", row)
	}
	result := s.apply("kitty")[0]
	if !result.Changed || !strings.HasSuffix(result.Backup, "kitty.conf.axiom-bak-20261027-120000") {
		t.Errorf("apply: %+v", result)
	}
	if info, err := os.Lstat(link); err != nil || info.Mode()&os.ModeSymlink == 0 {
		t.Error("the link was replaced")
	}
	check(t, real, "font_size 12\n\ninclude axiom.conf\n", 0o600)
	b := backups(t, real)
	if len(b) != 1 || read(t, b[0]) != "font_size 12\n" {
		t.Errorf("backups %v", b)
	}
	if again := s.apply("kitty")[0]; again.Changed || len(backups(t, real)) != 1 {
		t.Errorf("a second apply: %+v", again)
	}
}

// A file missing from a linked folder (a config kept in a dotfiles repo)
// is shown as a link to where it will be created
func TestMissingFileInALinkedFolder(t *testing.T) {
	t.Parallel()
	s := newScratch(t)
	real := filepath.Join(s.root, "dotfiles", "kitty")
	os.MkdirAll(real, 0o755)
	s.link("kitty", real)
	row := s.status("kitty")[0]
	if !row.Link || row.Exists || row.Resolved != filepath.Join(real, "kitty.conf") {
		t.Errorf("status: %+v", row)
	}
	if result := s.apply("kitty")[0]; !result.Changed {
		t.Errorf("apply: %+v", result)
	}
	if _, err := os.Stat(filepath.Join(real, "kitty.conf")); err != nil {
		t.Error(err)
	}
}

// A link to a file the user can't write is skipped, or, with wrapLink
// (GTK 4), replaced by a file loading it, the link kept as the backup
func TestReadonlyLinks(t *testing.T) {
	t.Parallel()
	s := newScratch(t)
	kitty := s.readonly("kitty.conf", "font_size 12\n")
	link := s.link("kitty/kitty.conf", kitty)
	if row := s.status("kitty")[0]; row.Skipped != hookup.SkipReadonly {
		t.Errorf("status: %+v", row)
	}
	if r := s.apply("kitty")[0]; r.Changed || r.Error != "" {
		t.Errorf("apply: %+v", r)
	}
	if read(t, link) != "font_size 12\n" {
		t.Error("the read-only file changed")
	}

	gtk := s.readonly("gtk.css", "@define-color window_bg_color #fff;\n")
	s.write("gtk-3.0/gtk.css", "")
	gtk4 := s.link("gtk-4.0/gtk.css", gtk)
	if row := s.status("gtk")[1]; !row.Wraps || row.Skipped != "" {
		t.Errorf("gtk status: %+v", row)
	}
	s.apply("gtk")
	if info, err := os.Lstat(gtk4); err != nil || info.Mode()&os.ModeSymlink != 0 {
		t.Fatal("the link wasn't replaced")
	}
	if got := read(t, gtk4); got != "@import url(\"file://"+gtk+"\");\n@import url(\"axiom.css\");\n" {
		t.Errorf("wrapped: %q", got)
	}
	if b := backups(t, gtk4); len(b) != 1 {
		t.Errorf("backups %v", b)
	} else if to, _ := os.Readlink(b[0]); to != gtk {
		t.Errorf("the backup links to %q", to)
	}
	if !s.status("gtk")[1].Done {
		t.Error("not done once wrapped")
	}
}

// Per-profile targets: one per folder profiles.ini lists, skipped with none
func TestPerProfile(t *testing.T) {
	t.Parallel()
	s := newScratch(t)
	for _, row := range s.status("firefox") {
		if row.Skipped != hookup.SkipProfiles {
			t.Errorf("no profiles: %+v", row)
		}
	}
	root := filepath.Join(s.home, ".mozilla", "firefox")
	for _, p := range []string{"a.default-release", "b c.other"} {
		os.MkdirAll(filepath.Join(root, p), 0o755)
	}
	os.WriteFile(filepath.Join(root, "profiles.ini"), []byte("[Profile0]\nIsRelative=1\nPath=a.default-release\n\n[Profile1]\nIsRelative=1\nPath=b c.other\n\n[General]\nVersion=2\n"), 0o644)
	os.WriteFile(filepath.Join(root, "a.default-release", "user.js"), []byte("user_pref(\"toolkit.legacyUserProfileCustomizations.stylesheets\", false);\n"), 0o644)
	if rows := s.status("firefox"); len(rows) != 4 {
		t.Fatalf("%d targets", len(rows))
	}
	s.apply("firefox")
	for _, row := range s.status("firefox") {
		if !row.Done {
			t.Errorf("not done: %+v", row)
		}
	}
	for _, p := range []string{"a.default-release", "b c.other"} {
		if css := read(t, filepath.Join(root, p, "chrome", "userChrome.css")); !strings.HasPrefix(css, "@import url(\"axiom.css\");") {
			t.Errorf("%s: %q", p, css)
		}
		if prefs := strings.Split(strings.TrimSpace(read(t, filepath.Join(root, p, "user.js"))), "\n"); prefs[len(prefs)-1] != "user_pref(\"toolkit.legacyUserProfileCustomizations.stylesheets\", true);" {
			t.Errorf("%s: %q", p, prefs)
		}
	}
}

// kdeglobals: two targets in one file, the user's choice commented out in
// both groups, and [UiSettings] added when missing
func TestKdeglobals(t *testing.T) {
	t.Parallel()
	s := newScratch(t)
	path := s.write("kdeglobals", "[General]\nColorScheme=BreezeDark\n\n[UiSettings]\nColorScheme=BreezeDark\n\n[KDE]\nwidgetStyle=Fusion\n")
	s.apply("qt")
	want := "[General]\n# axiom: ColorScheme=BreezeDark\nColorScheme=Axiom\n\n[UiSettings]\n# axiom: ColorScheme=BreezeDark\nColorScheme=Axiom\n\n[KDE]\nwidgetStyle=Fusion\n"
	if got := read(t, path); got != want {
		t.Errorf("%q", got)
	}
	// Backed up once, before the first of its two targets
	if b := backups(t, path); len(b) != 1 || read(t, b[0]) != "[General]\nColorScheme=BreezeDark\n\n[UiSettings]\nColorScheme=BreezeDark\n\n[KDE]\nwidgetStyle=Fusion\n" {
		t.Errorf("backups %v", b)
	}
	os.WriteFile(path, []byte("[General]\nColorScheme=Axiom\n"), 0o644)
	s.apply("qt")
	if got := read(t, path); got != "[General]\nColorScheme=Axiom\n\n[UiSettings]\nColorScheme=Axiom\n" {
		t.Errorf("%q", got)
	}
}

// A conflict leaves the file alone; requires skips; copy never overwrites;
// a shell rc follows $SHELL
func TestApplyCases(t *testing.T) {
	t.Parallel()
	s := newScratch(t)
	alacritty := s.write("alacritty/alacritty.toml", "[general]\nimport = [\"~/mine.toml\"]\n")
	if r := s.apply("alacritty")[0]; r.Error != "conflict" || r.Changed {
		t.Errorf("conflict: %+v", r)
	}
	if read(t, alacritty) != "[general]\nimport = [\"~/mine.toml\"]\n" {
		t.Error("a conflicting file changed")
	}

	requires := []hookup.Target{{File: hookup.Files{"{config}/x.conf"}, Place: hookup.End, Text: "x", Requires: "axiom-no-such-command"}}
	if rows, _ := s.h.Status(requires, nil); rows[0].Skipped != hookup.SkipRequires {
		t.Errorf("requires: %+v", rows[0])
	}
	s.h.Apply(requires, nil)
	if _, err := os.Stat(filepath.Join(s.config, "x.conf")); err == nil {
		t.Error("a target without its command was applied")
	}

	module := s.write("nvim/lua/axiom_theme.lua", "-- mine\n")
	s.apply("nvim")
	if read(t, module) != "-- mine\n" {
		t.Error("copy overwrote the user's module")
	}
	os.Remove(module)
	s.apply("nvim")
	if read(t, module) != read(t, filepath.Join("..", "..", "..", "..", "scripts", "templates", "nvim", "axiom_theme.lua")) {
		t.Error("the module wasn't copied")
	}

	s.apply("fzf")
	if !strings.Contains(read(t, filepath.Join(s.home, ".bashrc")), "export FZF_DEFAULT_OPTS_FILE=") {
		t.Error("bash rc")
	}
	s.shell = "/usr/bin/fish"
	s.apply("fzf")
	if !strings.HasPrefix(read(t, filepath.Join(s.config, "fish", "conf.d", "axiom.fish")), "set -gx FZF_DEFAULT_OPTS_FILE ") {
		t.Error("fish conf.d")
	}
}

// The compositor's own targets (passed in): include first, autostart last,
// and install.sh's spelling of the autostart line counts as done
func TestGivenTargets(t *testing.T) {
	t.Parallel()
	s := newScratch(t)
	path := s.write("hypr/hyprland.lua", "-- mine\nhl.bind(\"SUPER + Q\", hl.dsp.exec_cmd(\"kitty\"))\n")
	include := hookup.Target{File: hookup.Files{path}, Place: hookup.Start, Comment: "--", Accept: `axiom\.setup\(`,
		Text: "local ok, axiom = pcall(dofile, \"/x/axiom/hyprland.lua\")\nif ok then axiom.setup() end"}
	autostart := hookup.Target{File: hookup.Files{path}, Place: hookup.End, Comment: "--", Accept: `(^|[\s'"/])axiom['"]? +run\b`,
		Text: `hl.on("hyprland.start", function() hl.exec_cmd("'/x/axiom' run") end) -- axiom`}
	targets := []hookup.Target{include, autostart}
	s.h.Apply(targets, nil)
	lines := strings.Split(strings.TrimSuffix(read(t, path), "\n"), "\n")
	if strings.Join(lines[:2], "\n") != include.Text || lines[len(lines)-1] != autostart.Text {
		t.Errorf("%q", lines)
	}
	if b := backups(t, path); len(b) != 1 {
		t.Errorf("backups %v", b)
	}
	if rows, _ := s.h.Status(targets, nil); !rows[0].Done || !rows[1].Done {
		t.Errorf("%+v", rows)
	}
	os.WriteFile(path, []byte("hl.on(\"hyprland.start\", function() hl.exec_cmd(\"'/usr/bin/axiom' run\") end) -- axiom\n"), 0o644)
	if rows, _ := s.h.Status([]hookup.Target{autostart}, nil); !rows[0].Done {
		t.Errorf("install.sh's line: %+v", rows[0])
	}
	if _, err := s.h.Status([]hookup.Target{{File: hookup.Files{path}, Text: "x", Accept: "("}}, nil); err == nil {
		t.Error("a broken accept passed")
	}
}
