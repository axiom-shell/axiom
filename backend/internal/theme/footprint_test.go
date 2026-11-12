package theme

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/footprint"
	"github.com/axiom-shell/axiom/backend/internal/theme/integrations"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// fakeGSettings is a gsettings key store
type fakeGSettings struct {
	mu   sync.Mutex
	vals map[string]string
}

func (f *fakeGSettings) run(_ context.Context, args ...string) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	key := args[1] + " " + args[2]
	switch args[0] {
	case "get":
		return f.vals[key] + "\n", nil
	case "set":
		f.vals[key] = args[3]
		if !strings.HasPrefix(args[3], "'") {
			f.vals[key] = "'" + args[3] + "'"
		}
	case "reset":
		delete(f.vals, key)
	}
	return "", nil
}

// recorded is a scratch home whose Integrator records in a ledger
func recorded(t *testing.T, live bool, gs *fakeGSettings) (string, *Integrator, *footprint.Ledger) {
	t.Helper()
	home := t.TempDir()
	env := map[string]string{"HOME": home, "XDG_RUNTIME_DIR": filepath.Join(home, "run")}
	getenv := func(k string) string { return env[k] }
	l := footprint.New(footprint.Options{Dirs: xdg.Resolve(getenv), GSettings: gs.run})
	RegisterUndo(l)
	in := NewIntegrator(IntegrateOptions{
		Getenv:    getenv,
		LookPath:  func(string) (string, error) { return "", errors.New("not installed") },
		Profiles:  func(string) []string { return nil },
		Ledger:    l,
		GSettings: gs.run,
		Live:      live,
	})
	return home, in, l
}

func undoAll(t *testing.T, l *footprint.Ledger) []footprint.Result {
	t.Helper()
	return l.Undo(context.Background(), l.Select(footprint.UndoOptions{}), footprint.UndoOptions{})
}

func runKeys(t *testing.T, in *Integrator, owners map[string]string, keys ...string) []IntegrationResult {
	t.Helper()
	results, err := in.Run(context.Background(), themes+"ayu-dark.json", keys, owners)
	if err != nil {
		t.Fatal(err)
	}
	return results
}

func TestIntegrationWriteRecordsFilesAndDirs(t *testing.T) {
	t.Parallel()
	home, in, l := recorded(t, false, &fakeGSettings{})
	os.MkdirAll(home+"/.config", 0o755)
	runKeys(t, in, map[string]string{"kitty": "ThemeIntegrations.kitty"}, "kitty")
	rows := l.Rows()
	if len(rows) != 2 || rows[0].Kind != footprint.KindDir || rows[0].Target != home+"/.config/kitty" ||
		rows[1].Kind != footprint.KindFile || rows[1].Target != home+"/.config/kitty/axiom.conf" ||
		rows[0].Owner != "ThemeIntegrations.kitty" || rows[1].Owner != "ThemeIntegrations.kitty" {
		t.Fatalf("%+v", rows)
	}
	// A second run is the same rows
	runKeys(t, in, map[string]string{"kitty": "ThemeIntegrations.kitty"}, "kitty")
	if len(l.Rows()) != 2 {
		t.Errorf("%+v", l.Rows())
	}
	// Under axiom's own folders nothing is recorded: foot's neighbor, a file of state
	undoAll(t, l)
	if _, err := os.Stat(home + "/.config/kitty"); err == nil {
		t.Error("the folder it made stayed")
	}
}

func TestGtkEffectRecordsGSettings(t *testing.T) {
	t.Parallel()
	gs := &fakeGSettings{vals: map[string]string{
		"org.gnome.desktop.interface color-scheme": "'default'", "org.gnome.desktop.interface gtk-theme": "'adw-gtk3'"}}
	_, in, l := recorded(t, true, gs)
	runKeys(t, in, map[string]string{"gtk": "ThemeIntegrations.gtk"}, "gtk")
	if gs.vals["org.gnome.desktop.interface color-scheme"] != "'prefer-dark'" || gs.vals["org.gnome.desktop.interface gtk-theme"] != "'adw-gtk3-dark'" {
		t.Fatalf("%v", gs.vals)
	}
	var targets []string
	for _, r := range l.Rows() {
		if r.Kind == footprint.KindGSetting {
			targets = append(targets, r.Target)
		}
	}
	if !slices.Equal(targets, []string{"org.gnome.desktop.interface color-scheme", "org.gnome.desktop.interface gtk-theme"}) {
		t.Fatalf("%v", l.Rows())
	}
	undoAll(t, l)
	if gs.vals["org.gnome.desktop.interface color-scheme"] != "'default'" || gs.vals["org.gnome.desktop.interface gtk-theme"] != "'adw-gtk3'" {
		t.Errorf("after undo %v", gs.vals)
	}
}

const kdeSeed = "[Colors:View]\nBackgroundNormal=1,2,3\nCustom=x\n\n[General]\nColorScheme=Axiom\nmine=1\n"

func kdeScratch(t *testing.T) (string, *Integrator, *footprint.Ledger, string) {
	t.Helper()
	home, in, l := recorded(t, false, &fakeGSettings{})
	path := home + "/.config/kdeglobals"
	put(t, path, kdeSeed)
	runKeys(t, in, map[string]string{"qt": "ThemeIntegrations.qt"}, "qt")
	return home, in, l, path
}

func TestKdeMergeRecordsPriorGroupsAndUndoes(t *testing.T) {
	t.Parallel()
	_, _, l, path := kdeScratch(t)
	if got := read(t, path); got == kdeSeed || !strings.Contains(got, "[Colors:Selection]") {
		t.Fatalf("not merged:\n%s", got)
	}
	var row footprint.Row
	for _, r := range l.Rows() {
		if r.Kind == footprint.KindINIGroups {
			row = r
		}
	}
	if row.Target != path || row.Owner != "" && row.Owner != "ThemeIntegrations.qt" {
		t.Fatalf("%+v", l.Rows())
	}
	var prior integrations.Keys
	if err := jsonUnmarshal(row.Prior, &prior); err != nil || prior.Groups["Colors:View"]["BackgroundNormal"] == nil || *prior.Groups["Colors:View"]["BackgroundNormal"] != "1,2,3" {
		t.Errorf("prior %s", row.Prior)
	}
	undoAll(t, l)
	if got := read(t, path); got != kdeSeed {
		t.Errorf("after undo:\n%s", got)
	}
}

func TestKdeUndoIgnoresOtherKeysInTheGroup(t *testing.T) {
	t.Parallel()
	_, _, l, path := kdeScratch(t)
	// The user edits a key of a group axiom changed, and one it didn't
	text := read(t, path)
	text = strings.Replace(text, "Custom=x", "Custom=mine-now", 1)
	text += "[Colors:View]\n"
	put(t, path, strings.Replace(text, "mine=1", "mine=2", 1)+"")
	// And one key axiom wrote, changed
	text = read(t, path)
	text = strings.Replace(text, "ForegroundNormal=", "ForegroundNormal=9,9,9;", 1)
	put(t, path, text)
	res := undoAll(t, l)
	var changed bool
	for _, r := range res {
		changed = changed || r.Outcome == footprint.OutcomeChanged
	}
	got := read(t, path)
	if !changed || !strings.Contains(got, "ForegroundNormal=9,9,9;") || !strings.Contains(got, "Custom=mine-now") || !strings.Contains(got, "mine=2") ||
		strings.Contains(got, "BackgroundNormal=") && !strings.Contains(got, "BackgroundNormal=1,2,3") {
		t.Errorf("changed=%v\n%s", changed, got)
	}
}

func TestNcspotRecordsTheMarkedBlock(t *testing.T) {
	t.Parallel()
	home, in, l := recorded(t, false, &fakeGSettings{})
	path := home + "/.config/ncspot/config.toml"
	put(t, path, "[theme]\n"+integrations.NcspotBegin+"\n"+integrations.NcspotEnd+"\nmine = 1\n")
	runKeys(t, in, map[string]string{"ncspot": "ThemeIntegrations.ncspot"}, "ncspot")
	var found bool
	for _, r := range l.Rows() {
		found = found || r.Kind == footprint.KindMarkedBlock && r.Target == path
	}
	if !found {
		t.Fatalf("%+v", l.Rows())
	}
	undoAll(t, l)
	if got := read(t, path); got != "[theme]\nmine = 1\n" {
		t.Errorf("%q", got)
	}
}

func jsonUnmarshal(data []byte, v any) error { return json.Unmarshal(data, v) }
