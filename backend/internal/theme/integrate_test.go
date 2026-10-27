package theme

import (
	"context"
	"encoding/json"
	"errors"
	"io/fs"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/assets"
	"github.com/axiom-shell/axiom/backend/internal/theme/integrations"
)

const themes = "../../../config/themes/"

// scratch is a home with nothing installed: no command is found, and
// nothing reaches the session (Live is off).
func scratch(t *testing.T, installed ...string) (string, *Integrator) {
	t.Helper()
	home := t.TempDir()
	env := map[string]string{"HOME": home, "XDG_RUNTIME_DIR": filepath.Join(home, "run")}
	in := NewIntegrator(IntegrateOptions{
		Getenv: func(k string) string { return env[k] },
		LookPath: func(cmd string) (string, error) {
			if slices.Contains(installed, cmd) {
				return "/usr/bin/" + cmd, nil
			}
			return "", errors.New("not installed")
		},
		Profiles: func(key string) []string { return []string{"{home}/.mozilla/firefox/profiles.ini"} },
	})
	return home, in
}

func put(t *testing.T, path, text string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
}

func read(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func runAll(t *testing.T, in *Integrator, theme string) map[string]IntegrationResult {
	t.Helper()
	results, err := in.Run(context.Background(), themes+theme+".json", slices.Sorted(maps.Keys(integrations.Table)))
	if err != nil {
		t.Fatal(err)
	}
	out := map[string]IntegrationResult{}
	for _, r := range results {
		out[r.Key] = r
	}
	return out
}

// Every integration writes its files into the scratch home, and nothing
// but axiom's own files (and a main config created where there was none)
func TestIntegrateWritesOnlyItsFiles(t *testing.T) {
	t.Parallel()
	home, in := scratch(t, "qt6ct")
	put(t, home+"/.config/vesktop/settings.json", "{}")
	put(t, home+"/.vscode-oss/argv.json", "{}")
	put(t, home+"/.mozilla/firefox/profiles.ini", "[General]\nStartWithLastProfile=1\n\n[Profile0]\nName=default\nIsRelative=1\nPath=abc.default\n")
	put(t, home+"/.mozilla/firefox/abc.default/prefs.js", "")
	put(t, home+"/.config/ncspot/config.toml", "[theme]\n"+integrations.NcspotBegin+"\n"+integrations.NcspotEnd+"\n")
	put(t, home+"/.config/gtk-4.0/gtk.css", "/* mine */\n")
	before := files(t, home)

	results := runAll(t, in, "ayu-dark")
	for key, r := range results {
		if r.Error != "" || len(r.Files) == 0 {
			t.Errorf("%s: %+v", key, r)
		}
	}
	if w := results["gtk"].Warnings; len(w) != 1 || !strings.Contains(w[0], "gtk-4.0/gtk.css") {
		t.Errorf("gtk warnings: %v", w)
	}
	if read(t, home+"/.config/gtk-4.0/gtk.css") != "/* mine */\n" {
		t.Error("an existing gtk.css was changed")
	}
	if !strings.Contains(read(t, home+"/.config/gtk-3.0/gtk.css"), integrations.GTKImport) {
		t.Error("a missing gtk.css wasn't created importing the colors")
	}
	if !strings.Contains(read(t, home+"/.config/cava/config"), "include = "+home+"/.config/cava/colors/axiom.conf") {
		t.Error("cava's main config doesn't include the colors")
	}
	if _, err := os.Stat(home + "/.config/qt5ct/colors/axiom.conf"); err == nil {
		t.Error("qt5ct's colors written without qt5ct")
	}
	if !strings.Contains(read(t, home+"/.config/ncspot/config.toml"), "background = ") {
		t.Error("ncspot's config didn't get the colors")
	}
	for _, path := range files(t, home) {
		if slices.Contains(before, path) {
			continue
		}
		rel, _ := filepath.Rel(home, path)
		own := strings.Contains(strings.ToLower(rel), "axiom") || rel == ".config/cava/config" || rel == ".config/gtk-3.0/gtk.css"
		if !own {
			t.Errorf("wrote %s", rel)
		}
	}

	// A second run changes nothing it doesn't own
	ncspot := read(t, home+"/.config/ncspot/config.toml")
	runAll(t, in, "ayu-dark")
	if read(t, home+"/.config/ncspot/config.toml") != ncspot {
		t.Error("a second run changed ncspot's config")
	}
}

func files(t *testing.T, root string) []string {
	t.Helper()
	var out []string
	_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err == nil && !d.IsDir() {
			out = append(out, path)
		}
		return nil
	})
	return out
}

func TestIntegrateSaysWhereItCantWrite(t *testing.T) {
	t.Parallel()
	_, in := scratch(t)
	results, err := in.Run(context.Background(), themes+"ayu-dark.json", []string{"vesktop", "vscode", "firefox", "ncspot"})
	if err != nil {
		t.Fatal(err)
	}
	for _, r := range results {
		if r.Key == "ncspot" {
			if len(r.Warnings) != 1 || !strings.Contains(r.Warnings[0], "doesn't exist") {
				t.Errorf("ncspot: %+v", r)
			}
		} else if r.Error == "" || len(r.Files) != 0 {
			t.Errorf("%s: %+v", r.Key, r)
		}
	}
	if _, err := in.Run(context.Background(), themes+"ayu-dark.json", []string{"nope"}); err == nil {
		t.Error("an unknown key ran")
	}
	if results, _ := in.Run(context.Background(), themes+"missing.json", []string{"kitty"}); results[0].Error == "" {
		t.Error("a missing theme wasn't said")
	}
}

// A link (a dotfiles repo's file) is written through and kept
func TestIntegrateFollowsLinks(t *testing.T) {
	t.Parallel()
	home, in := scratch(t)
	real := filepath.Join(home, "dotfiles", "kitty-axiom.conf")
	put(t, real, "old\n")
	if err := os.MkdirAll(home+"/.config/kitty", 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(real, home+"/.config/kitty/axiom.conf"); err != nil {
		t.Fatal(err)
	}
	if _, err := in.Run(context.Background(), themes+"ayu-dark.json", []string{"kitty"}); err != nil {
		t.Fatal(err)
	}
	if info, err := os.Lstat(home + "/.config/kitty/axiom.conf"); err != nil || info.Mode()&fs.ModeSymlink == 0 {
		t.Error("the link was replaced")
	}
	if !strings.Contains(read(t, real), "Ayu Dark") {
		t.Error("the linked file wasn't written")
	}
}

func TestIntegrateKeepsKdeglobalsOnceChosen(t *testing.T) {
	t.Parallel()
	home, in := scratch(t)
	kdeglobals := home + "/.config/kdeglobals"
	mine := "[Colors:View]\nBackgroundNormal=1,2,3\nCustom=x\n\n[General]\nColorScheme=BreezeDark\n"
	put(t, kdeglobals, mine)
	run := func() IntegrationResult {
		results, err := in.Run(context.Background(), themes+"ayu-dark.json", []string{"qt"})
		if err != nil {
			t.Fatal(err)
		}
		return results[0]
	}
	run()
	if read(t, kdeglobals) != mine {
		t.Error("changed before it names the scheme")
	}
	put(t, kdeglobals, strings.Replace(mine, "BreezeDark", "Axiom", 1)+"\n[UiSettings]\nColorScheme=Axiom\n")
	put(t, home+"/.config/okularrc", "[UiSettings]\nColorScheme=BreezeDark\n")
	put(t, home+"/.config/dolphinrc", "[UiSettings]\nColorScheme=Axiom\n")
	r := run()
	if len(r.Warnings) != 1 || !strings.Contains(r.Warnings[0], "okularrc") {
		t.Errorf("warnings: %v", r.Warnings)
	}
	got := read(t, kdeglobals)
	if strings.Contains(got, "BackgroundNormal=1,2,3") || !strings.Contains(got, "Custom=x") || !strings.Contains(got, "[Colors:Selection]") {
		t.Errorf("kdeglobals:\n%s", got)
	}
	if read(t, home+"/.config/okularrc") != "[UiSettings]\nColorScheme=BreezeDark\n" {
		t.Error("an app's own rc was changed")
	}
}

// A call while a run is going queues its keys for that run
func TestIntegrateQueuesDuringARun(t *testing.T) {
	t.Parallel()
	home, in := scratch(t)
	in.running = true
	if results, err := in.Run(context.Background(), themes+"ayu-light.json", []string{"kitty"}); err != nil || results == nil || len(results) != 0 {
		t.Fatalf("%v %v", results, err)
	}
	in.running = false
	results, _ := in.Run(context.Background(), themes+"ayu-dark.json", []string{"alacritty"})
	if len(results) != 2 || !strings.Contains(read(t, home+"/.config/kitty/axiom.conf"), "Ayu Light") {
		t.Errorf("%+v", results)
	}
}

// The table is the schema's ThemeIntegrations switches, and ncspot's
// markers are its hookup's text
func TestTableIsTheSchemas(t *testing.T) {
	t.Parallel()
	raw, err := assets.Read("config/json/config.schema.json")
	if err != nil {
		t.Fatal(err)
	}
	var s struct {
		Properties struct {
			ThemeIntegrations struct {
				Properties map[string]struct {
					Type   string `json:"type"`
					Hookup []struct {
						Text string `json:"text"`
					} `json:"x-hookup"`
				} `json:"properties"`
			} `json:"ThemeIntegrations"`
		} `json:"properties"`
	}
	if err := json.Unmarshal(raw, &s); err != nil {
		t.Fatal(err)
	}
	var keys []string
	for k, p := range s.Properties.ThemeIntegrations.Properties {
		if p.Type == "boolean" {
			keys = append(keys, k)
		}
	}
	slices.Sort(keys)
	if table := slices.Sorted(maps.Keys(integrations.Table)); !slices.Equal(keys, table) {
		t.Errorf("schema %v, table %v", keys, table)
	}
	ncspot := s.Properties.ThemeIntegrations.Properties["ncspot"].Hookup
	if len(ncspot) == 0 || !strings.Contains(ncspot[0].Text, integrations.NcspotBegin+"\n"+integrations.NcspotEnd) {
		t.Errorf("ncspot's hookup: %+v", ncspot)
	}
}

func TestVersionAtLeast(t *testing.T) {
	t.Parallel()
	for _, tt := range []struct {
		have, want string
		ok         bool
	}{{"1.2", "1.2", true}, {"1.10.1", "1.2", true}, {"1.1.9", "1.2", false}, {"25.01.1", "23.10", true}, {"23.05", "23.10", false}} {
		if versionAtLeast(tt.have, tt.want) != tt.ok {
			t.Errorf("%s >= %s", tt.have, tt.want)
		}
	}
}
