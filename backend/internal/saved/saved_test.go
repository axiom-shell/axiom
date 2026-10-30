package saved

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/schema"
	"github.com/axiom-shell/axiom/backend/internal/store"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"github.com/axiom-shell/axiom/backend/internal/tree"
)

type fixture struct {
	svc   *Service
	store *store.Store
	dir   string
	home  string
	ex    string
}

func setup(t *testing.T) fixture {
	t.Helper()
	return setupSchema(t, func(*jsonx.Object) {})
}

// setupSchema is setup with the tree's schema changed by edit first.
func setupSchema(t *testing.T, edit func(root *jsonx.Object)) fixture {
	t.Helper()
	data, err := tree.BuildSchema(testkit.RepoRoot())
	if err != nil {
		t.Fatal(err)
	}
	root, err := jsonx.Unmarshal(data)
	if err != nil {
		t.Fatal(err)
	}
	edit(root.(*jsonx.Object))
	pipeline := config.V2Pipeline{S: schema.New(root)}
	dir, home, ex := t.TempDir(), t.TempDir(), t.TempDir()
	st, err := store.Open(store.Options{Dir: dir, Pipeline: pipeline, Debounce: 20 * time.Millisecond})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	svc := New(Options{
		Dir: dir, Examples: ex, Home: home, UIState: filepath.Join(dir, "ui", "savedconfigs.json"),
		Store: st, Pipeline: func() config.Pipeline { return pipeline },
		Now: func() time.Time { return time.Date(2026, 10, 23, 12, 0, 0, 0, time.UTC) },
	})
	return fixture{svc: svc, store: st, dir: dir, home: home, ex: ex}
}

func set(t *testing.T, st *store.Store, path string, value any) {
	t.Helper()
	p, err := config.ParsePath(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := st.Set([]config.Op{config.SetValue(p, value)}, store.SetOptions{}); err != nil {
		t.Fatal(err)
	}
}

func get(t *testing.T, st *store.Store, path string) any {
	t.Helper()
	cfg, _ := st.Config()
	p, _ := config.ParsePath(path)
	v, _ := config.Lookup(cfg, p)
	return v
}

func TestSaveRestoreModified(t *testing.T) {
	t.Parallel()
	f := setup(t)
	set(t, f.store, "Bars.style.widgetStyle", "outline")
	name, err := f.svc.Save("My look", "")
	if err != nil || name != "My look" {
		t.Fatalf("save: %q %v", name, err)
	}
	if st := f.svc.State(); st.Active != "My look" || st.Modified {
		t.Errorf("state after save: %+v", st)
	}
	saved, _ := os.ReadFile(filepath.Join(f.dir, "saved", "My look.json"))
	if !strings.Contains(string(saved), `"format": 2`) || !strings.Contains(string(saved), `"outline"`) {
		t.Errorf("saved file:\n%s", saved)
	}
	set(t, f.store, "Bars.style.widgetStyle", "plain")
	f.svc.Changed()
	if !f.svc.State().Modified {
		t.Error("not modified after a change")
	}
	if _, err := f.svc.Restore("My look"); err != nil {
		t.Fatal(err)
	}
	if v := get(t, f.store, "Bars.style.widgetStyle"); v != "outline" {
		t.Errorf("restored widgetStyle %v", v)
	}
	if st := f.svc.State(); st.Modified {
		t.Errorf("modified right after restoring: %+v", st)
	}
	// Remembered across a restart
	again := New(Options{Dir: f.dir, UIState: filepath.Join(f.dir, "ui", "savedconfigs.json"), Store: f.store, Pipeline: f.svc.opts.Pipeline})
	if again.State().Active != "My look" {
		t.Errorf("active after a restart: %+v", again.State())
	}
}

// An example of format 1 (as examples/ ship today) applies converted, after
// the running config is kept, and is saved as example-<name>; takeovers stay.
func TestApplyExampleFormat1(t *testing.T) {
	t.Parallel()
	f := setup(t)
	os.WriteFile(filepath.Join(f.ex, "tall.json"), []byte(`{"_example": {"title": "Tall"}, "version": 60,
		"Bars": [{"id": "primary", "location": "Left", "widgetSize": 40}], "Compositor": {"mode": "managed"}}`), 0o644)
	applied, err := f.svc.ApplyExample("tall", nil)
	if err != nil {
		t.Fatal(err)
	}
	if applied.Backup != "unsaved" || applied.Saved != "example-tall" {
		t.Errorf("applied %+v", applied)
	}
	if v := get(t, f.store, "Bars.items[primary].location"); v != "left" {
		t.Errorf("location %v", v)
	}
	if v := get(t, f.store, "Compositor.mode"); v != "detached" {
		t.Errorf("a takeover changed: %v", v)
	}
	if _, err := os.Stat(filepath.Join(f.dir, "saved", "unsaved.json")); err != nil {
		t.Error("the running config wasn't kept")
	}
	got := f.svc.Examples()
	if len(got) != 1 || got[0].Title != "Tall" {
		t.Fatalf("examples %+v", got)
	}
	// What its preview draws, read converted and filled
	if bars := got[0].Bars; len(bars) != 1 || bars[0].Location != "left" || bars[0].Background == "" {
		t.Errorf("bars %+v", bars)
	}
	if got[0].Theme == "" || len(got[0].Docks) != 0 {
		t.Errorf("theme %q, docks %+v (the default dock is off)", got[0].Theme, got[0].Docks)
	}
}

// What an apply or restore keeps of the running config: nothing while the
// active snapshot is unchanged (it's on disk), else one "unsaved" file; and
// the copy the last applied file was saved as goes once it's replaced,
// unless the user saved over it.
func TestApplyKeepsOnlyWhatIsntSaved(t *testing.T) {
	t.Parallel()
	type step struct {
		do      string // "a"/"b": apply that example; "edit"; "save <name>"; "restore <name>"
		backup  string // Applied.Backup of an apply or restore
		files   string // saved/ afterwards, sorted, space-separated
		content string // what saved/unsaved.json then holds of Bars.style.widgetStyle ("" to skip)
	}
	tests := []struct {
		name  string
		steps []step
	}{
		{"switching back and forth", []step{
			{do: "a", backup: "unsaved", files: "example-a unsaved"},
			{do: "b", files: "example-b unsaved"},
			{do: "a", files: "example-a unsaved"},
			{do: "a", files: "example-a unsaved"},
		}},
		{"edits are kept, in one file", []step{
			{do: "a", backup: "unsaved", files: "example-a unsaved"},
			{do: "edit outline", files: "example-a unsaved"},
			{do: "b", backup: "unsaved", files: "example-b unsaved", content: "outline"},
			{do: "edit plain", files: "example-b unsaved"},
			{do: "a", backup: "unsaved", files: "example-a unsaved", content: "plain"},
		}},
		{"a named snapshot is never touched", []step{
			{do: "save mine", files: "mine"},
			{do: "a", files: "example-a mine"},
			{do: "restore mine", files: "mine"},
			{do: "edit outline", files: "mine"},
			{do: "b", backup: "unsaved", files: "example-b mine unsaved", content: "outline"},
		}},
		{"a copy saved over stays", []step{
			{do: "save mine", files: "mine"},
			{do: "a", files: "example-a mine"},
			{do: "save example-a", files: "example-a mine"},
			{do: "b", files: "example-a example-b mine"},
		}},
		{"restoring unsaved takes it as it was", []step{
			{do: "save mine", files: "mine"},
			{do: "edit outline", files: "mine"},
			{do: "a", backup: "unsaved", files: "example-a mine unsaved", content: "outline"},
			{do: "edit plain", files: "example-a mine unsaved"},
			{do: "restore unsaved", files: "mine unsaved", content: "outline"},
		}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			f := setup(t)
			for _, name := range []string{"a", "b"} {
				os.WriteFile(filepath.Join(f.ex, name+".json"), []byte(`{"format": 2, "version": 76, "meta": {"title": "`+name+`"},
					"Appearance": {"theme": {"name": "`+map[string]string{"a": "nord", "b": "gruvbox-dark"}[name]+`"}}}`), 0o644)
			}
			for i, st := range tt.steps {
				verb, arg, _ := strings.Cut(st.do, " ")
				var applied Applied
				var err error
				switch verb {
				case "a", "b":
					applied, err = f.svc.ApplyExample(verb, nil)
				case "edit":
					set(t, f.store, "Bars.style.widgetStyle", arg)
				case "save":
					_, err = f.svc.Save(arg, "")
				case "restore":
					applied, err = f.svc.Restore(arg)
				}
				if err != nil {
					t.Fatalf("step %d (%s): %v", i, st.do, err)
				}
				if applied.Backup != st.backup {
					t.Errorf("step %d (%s): kept as %q, want %q", i, st.do, applied.Backup, st.backup)
				}
				var files []string
				list, _ := f.svc.List()
				for _, e := range list {
					files = append(files, e.Name)
				}
				sort.Strings(files)
				if got := strings.Join(files, " "); got != st.files {
					t.Errorf("step %d (%s): saved/ holds %q, want %q", i, st.do, got, st.files)
				}
				if st.content != "" {
					data, _ := os.ReadFile(filepath.Join(f.dir, "saved", "unsaved.json"))
					if !strings.Contains(string(data), `"`+st.content+`"`) {
						t.Errorf("step %d (%s): unsaved.json doesn't hold %q:\n%s", i, st.do, st.content, data)
					}
				}
			}
		})
	}
}

func TestOpenAndImport(t *testing.T) {
	t.Parallel()
	f := setup(t)
	path := filepath.Join(f.home, "shared.json")
	os.WriteFile(path, []byte(`{"format": 2, "version": 76, "meta": {"title": "Shared look", "description": "d"},
		"Appearance": {"theme": {"name": "nord"}}, "Keybinds": {"binds": [{"id": "x", "key": "SUPER + X", "action": "launcher"}]}}`), 0o644)
	preview, err := f.svc.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	if preview.Title != "Shared look" || !preview.HasPersonal || preview.HasCommands {
		t.Errorf("preview %+v", preview)
	}
	if _, err := f.svc.Import(path, false, false, nil); err != nil {
		t.Fatal(err)
	}
	if v := get(t, f.store, "Appearance.theme.name"); v != "nord" {
		t.Errorf("theme %v", v)
	}
	if binds := get(t, f.store, "Keybinds.binds").(*jsonx.Array); binds.Len() > 0 && binds.Items[0].(*jsonx.Object).Value("key") == "SUPER + X" {
		t.Error("personal parts taken without asking")
	}
	// A newer one is refused
	os.WriteFile(path, []byte(`{"format": 2, "version": 999}`), 0o644)
	if _, err := f.svc.Open(path); err == nil || !strings.Contains(err.Error(), "newer") {
		t.Errorf("newer: %v", err)
	}
}

// Import reads the file once: a change after its preview was judged isn't
// what gets applied.
func TestImportReadsTheFileOnce(t *testing.T) {
	t.Parallel()
	f := setup(t)
	path := filepath.Join(f.home, "shared.json")
	os.WriteFile(path, []byte(`{"format": 2, "version": 76, "Appearance": {"theme": {"name": "nord"}}}`), 0o644)
	pipeline := f.svc.opts.Pipeline
	var once sync.Once
	f.svc.opts.Pipeline = func() config.Pipeline {
		// The first use is the preview's: the file changes right after
		once.Do(func() {
			os.WriteFile(path, []byte(`{"format": 2, "version": 76, "Appearance": {"theme": {"name": "gruvbox"}}}`), 0o644)
		})
		return pipeline()
	}
	if _, err := f.svc.Import(path, false, false, nil); err != nil {
		t.Fatal(err)
	}
	if v := get(t, f.store, "Appearance.theme.name"); v != "nord" {
		t.Errorf("theme %v, want the previewed nord", v)
	}
}

// Applying an example keeps the running Workspaces (personal scope): the
// onboarder offers the examples after its Workspaces step.
func TestApplyExampleKeepsWorkspaces(t *testing.T) {
	t.Parallel()
	f := setup(t)
	set(t, f.store, "Workspaces.layout", "grid")
	data, err := os.ReadFile(filepath.Join(testkit.RepoRoot(), "examples", "clean.json"))
	if err != nil {
		t.Fatal(err)
	}
	os.WriteFile(filepath.Join(f.ex, "clean.json"), data, 0o644)
	if _, err := f.svc.ApplyExample("clean", nil); err != nil {
		t.Fatal(err)
	}
	cfg, _ := f.store.Config()
	if got := cfg.Value("Workspaces").(*jsonx.Object).Value("layout"); got != "grid" {
		t.Errorf("layout %v", got)
	}
}

func TestExport(t *testing.T) {
	t.Parallel()
	f := setup(t)
	set(t, f.store, "Bars.style.widgetStyle", "tinted")
	path, err := f.svc.Export(false, false, true, nil)
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Base(path) != "axiom-2026-10-23-120000.json" {
		t.Errorf("path %s", path)
	}
	data, _ := os.ReadFile(path)
	if !strings.Contains(string(data), `"tinted"`) || strings.Contains(string(data), `"detached"`) {
		t.Errorf("export:\n%s", data)
	}
}

// Every shipped example (examples/, format 1 for now) applies, converted,
// to a valid config.
func TestShippedExamplesApply(t *testing.T) {
	t.Parallel()
	entries, err := os.ReadDir(filepath.Join(testkit.RepoRoot(), "examples"))
	if err != nil {
		t.Fatal(err)
	}
	checked := 0
	for _, e := range entries {
		if !strings.HasSuffix(e.Name(), ".json") {
			continue
		}
		name := strings.TrimSuffix(e.Name(), ".json")
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			f := setup(t)
			data, err := os.ReadFile(filepath.Join(testkit.RepoRoot(), "examples", e.Name()))
			if err != nil {
				t.Fatal(err)
			}
			os.WriteFile(filepath.Join(f.ex, e.Name()), data, 0o644)
			if got := f.svc.Examples(); len(got) != 1 || got[0].Theme == "" || len(got[0].Bars) == 0 {
				t.Errorf("preview %+v", got)
			}
			if _, err := f.svc.ApplyExample(name, nil); err != nil {
				t.Fatal(err)
			}
			if _, st := f.store.Config(); st.Blocked {
				t.Errorf("blocked: %v", st.Issues)
			}
		})
		checked++
	}
	if checked == 0 {
		t.Fatal("no examples")
	}
}

// No way of loading a config changes a takeover setting (x-takeover): a
// file setting every one, imported with all its parts, applied as an
// example or a shared setup, restored as a saved config, or the defaults
// applied, leaves each as it was. Each is made part of the look here, which
// every load carries, so the store's keeping them is what's tested, not
// their machine scope
func TestNoLoadChangesATakeover(t *testing.T) {
	t.Parallel()
	running := map[string]any{"Compositor.mode": "included", "Greeter.enabled": true, "Idle.enabled": true,
		"Lockscreen.mode": "none", "Polkit.enabled": true}
	f := setupSchema(t, func(root *jsonx.Object) {
		for path := range running {
			section, key, _ := strings.Cut(path, ".")
			props := root.Value("properties").(*jsonx.Object).Value(section).(*jsonx.Object).Value("properties").(*jsonx.Object)
			props.Value(key).(*jsonx.Object).Set("x-scope", "look")
		}
	})
	for path, v := range running {
		p, _ := config.ParsePath(path)
		if _, err := f.store.Set([]config.Op{config.SetValue(p, v)}, store.SetOptions{Takeover: true}); err != nil {
			t.Fatalf("%s: %v", path, err)
		}
	}
	hostile := `{"format": 2, "version": 76, "meta": {"title": "Hostile"}, "Compositor": {"mode": "managed"},
		"Greeter": {"enabled": false}, "Idle": {"enabled": false}, "Lockscreen": {"mode": "quickshell"},
		"Polkit": {"enabled": false}, "Appearance": {"theme": {"name": "nord"}}}`
	file := filepath.Join(f.home, "hostile.json")
	for _, name := range []string{file, filepath.Join(f.ex, "hostile.json"), filepath.Join(f.dir, "saved", "hostile.json")} {
		os.MkdirAll(filepath.Dir(name), 0o755)
		os.WriteFile(name, []byte(hostile), 0o644)
	}
	for _, c := range []struct {
		name string
		load func() error
	}{
		{"import", func() error { _, err := f.svc.Import(file, true, true, nil); return err }},
		{"example", func() error { _, err := f.svc.ApplyExample("hostile", nil); return err }},
		{"shared", func() error { _, err := f.svc.ApplyShared(file, "Hostile", "", nil); return err }},
		{"restore", func() error { _, err := f.svc.Restore("hostile"); return err }},
		{"defaults", func() error { _, err := f.svc.Defaults(); return err }},
	} {
		if err := c.load(); err != nil {
			t.Errorf("%s: %v", c.name, err)
		}
		if c.name == "import" && get(t, f.store, "Appearance.theme.name") != "nord" {
			t.Error("the import loaded nothing: the test proves nothing")
		}
		for path, v := range running {
			if got := get(t, f.store, path); got != v {
				t.Errorf("%s changed %s to %v", c.name, path, got)
			}
		}
	}
}
