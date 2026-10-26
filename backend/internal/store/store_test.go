package store

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/migrate/steps"
	"github.com/axiom-shell/axiom/backend/internal/schema"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"github.com/axiom-shell/axiom/backend/internal/tree"
)

func pipeline(t *testing.T) config.Pipeline {
	t.Helper()
	data, err := tree.BuildSchema(testkit.RepoRoot())
	if err != nil {
		t.Fatal(err)
	}
	root, err := jsonx.Unmarshal(data)
	if err != nil {
		t.Fatal(err)
	}
	return config.V2Pipeline{S: schema.New(root)}
}

func open(t *testing.T, dir string) *Store {
	t.Helper()
	s, err := Open(Options{Dir: dir, Pipeline: pipeline(t), Debounce: 20 * time.Millisecond})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	return s
}

func TestFirstRunWritesDefaults(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	s := open(t, dir)
	cfg, st := s.Config()
	if !st.FirstRun || cfg.Value("version") != float64(steps.Current()) || cfg.Value("format") != 2.0 {
		t.Fatalf("state %+v", st)
	}
	data, _ := os.ReadFile(filepath.Join(dir, FileName))
	if !strings.HasSuffix(string(data), "}\n") {
		t.Error("not written canonically")
	}
	if info, _ := os.Stat(filepath.Join(dir, FileName)); info.Mode().Perm() != 0o600 {
		t.Errorf("mode %o", info.Mode().Perm())
	}
	s.AckFirstRun()
	if _, st := s.Config(); st.FirstRun {
		t.Error("first run not acknowledged")
	}
}

func TestOneWriterPerFolder(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	open(t, dir)
	if _, err := Open(Options{Dir: dir, Pipeline: pipeline(t)}); axerr.KindOf(err) != axerr.Running {
		t.Errorf("second store: %v", err)
	}
}

func TestFormat1IsConvertedAndKept(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	old := []byte(`{"version": 74, "Widget": {"overrideRadius": true, "radius": 9}}`)
	os.WriteFile(filepath.Join(dir, FileName), old, 0o644)
	s := open(t, dir)
	cfg, st := s.Config()
	if st.Blocked || cfg.Value("version") != float64(steps.Current()) || cfg.Value("format") != 2.0 {
		t.Fatalf("version %v format %v state %+v", cfg.Value("version"), cfg.Value("format"), st)
	}
	if r := cfg.Value("Interface").(*jsonx.Object).Value("radius"); r != 9.0 {
		t.Errorf("Interface.radius %v", r)
	}
	data, _ := os.ReadFile(filepath.Join(dir, FileName))
	if !strings.Contains(string(data), `"format": 2`) {
		t.Error("the conversion wasn't written back")
	}
	// The file from before, kept once
	kept, err := os.ReadFile(filepath.Join(dir, Format1File))
	if err != nil || string(kept) != string(old) {
		t.Errorf("format-1 copy: %q %v", kept, err)
	}
}

func TestFormatsItCantReadBlock(t *testing.T) {
	t.Parallel()
	for name, content := range map[string]string{
		"no format, format 2's version": `{"version": 76}`,
		"another format":                `{"format": 3, "version": 80}`,
		"newer version":                 `{"format": 2, "version": 99}`,
	} {
		dir := t.TempDir()
		os.WriteFile(filepath.Join(dir, FileName), []byte(content), 0o644)
		s := open(t, dir)
		if _, st := s.Config(); !st.Blocked || len(st.Issues) == 0 {
			t.Errorf("%s: state %+v", name, st)
		}
		data, _ := os.ReadFile(filepath.Join(dir, FileName))
		if string(data) != content {
			t.Errorf("%s: the file was rewritten", name)
		}
	}
}

func TestSetValidatesAndRefusesTakeovers(t *testing.T) {
	t.Parallel()
	s := open(t, t.TempDir())
	var events []Event
	var mu sync.Mutex
	s.Subscribe(func(e Event) { mu.Lock(); events = append(events, e); mu.Unlock() })

	rev, err := s.Set([]config.Op{config.SetValue(config.Keys("Battery", "lowThreshold"), 15.0)}, SetOptions{})
	if err != nil || rev != 2 {
		t.Fatalf("set: %v rev %d", err, rev)
	}
	_, err = s.Set([]config.Op{config.SetValue(config.Keys("Battery", "lowThreshold"), "lots")}, SetOptions{})
	if axerr.KindOf(err) != axerr.InvalidConfig || len(axerr.IssuesOf(err)) == 0 {
		t.Errorf("invalid value: %v", err)
	}
	_, err = s.Set([]config.Op{config.SetValue(config.Keys("Battery", "nope"), 1.0)}, SetOptions{})
	if axerr.KindOf(err) != axerr.InvalidConfig {
		t.Errorf("unknown key: %v", err)
	}
	_, err = s.Set([]config.Op{config.SetValue(config.Keys("Idle", "enabled"), true)}, SetOptions{})
	if axerr.KindOf(err) != axerr.TakeoverRefused {
		t.Errorf("takeover without opt-in: %v", err)
	}
	if _, err := s.Set([]config.Op{config.SetValue(config.Keys("Idle", "enabled"), true)}, SetOptions{Takeover: true}); err != nil {
		t.Errorf("takeover with opt-in: %v", err)
	}
	mu.Lock()
	defer mu.Unlock()
	if len(events) != 2 || events[0].Config == nil || events[1].State.Revision != 3 {
		t.Errorf("events %+v", events)
	}
}

func TestReplaceKeepsTakeovers(t *testing.T) {
	t.Parallel()
	s := open(t, t.TempDir())
	current, _ := s.Config()
	next := jsonx.Clone(current).(*jsonx.Object)
	next.Value("Idle").(*jsonx.Object).Set("enabled", true)
	next.Value("Battery").(*jsonx.Object).Set("lowThreshold", 12.0)
	if _, err := s.Replace(next, SetOptions{}); err != nil {
		t.Fatal(err)
	}
	cfg, _ := s.Config()
	if cfg.Value("Idle").(*jsonx.Object).Value("enabled") != false || cfg.Value("Battery").(*jsonx.Object).Value("lowThreshold") != 12.0 {
		t.Error("a replace changed a takeover, or dropped the rest")
	}
}

func TestBrokenFileBlocksSavesUntilFixed(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	s := open(t, dir)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go s.Watch(ctx)
	time.Sleep(50 * time.Millisecond)

	path := filepath.Join(dir, FileName)
	os.WriteFile(path, []byte(`{"version": 75, "Battery": {"lowThreshold": "x"}`), 0o600)
	waitFor(t, func() bool { _, st := s.Config(); return st.Blocked })
	if _, err := s.Set([]config.Op{config.SetValue(config.Keys("Battery", "notify"), false)}, SetOptions{}); axerr.KindOf(err) != axerr.Conflict {
		t.Errorf("saved over a broken file: %v", err)
	}
	if data, _ := os.ReadFile(path); !strings.Contains(string(data), `"x"`) {
		t.Error("the broken file was overwritten")
	}
	os.WriteFile(path, []byte(`{"version": 75, "Battery": {"lowThreshold": 9}}`), 0o600)
	waitFor(t, func() bool {
		cfg, st := s.Config()
		return !st.Blocked && cfg.Value("Battery").(*jsonx.Object).Value("lowThreshold") == 9.0
	})
}

func TestOwnWritesDontReload(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	s := open(t, dir)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go s.Watch(ctx)
	time.Sleep(50 * time.Millisecond)
	n := 0
	s.Subscribe(func(Event) { n++ })
	s.Set([]config.Op{config.SetValue(config.Keys("Battery", "lowThreshold"), 16.0)}, SetOptions{})
	time.Sleep(150 * time.Millisecond)
	if n != 1 {
		t.Errorf("%d events for one write", n)
	}
}

func TestDeletedFileIsNotRecreated(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	s := open(t, dir)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go s.Watch(ctx)
	time.Sleep(50 * time.Millisecond)
	os.Remove(filepath.Join(dir, FileName))
	waitFor(t, func() bool { _, st := s.Config(); return st.Missing })
	if _, err := os.Stat(filepath.Join(dir, FileName)); err == nil {
		t.Error("recreated")
	}
}

func TestSymlinkedConfigStaysALink(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	dots := t.TempDir()
	os.WriteFile(filepath.Join(dots, "config.json"), []byte(`{"version": 75}`), 0o644)
	os.Symlink(filepath.Join(dots, "config.json"), filepath.Join(dir, FileName))
	s := open(t, dir)
	if _, err := s.Set([]config.Op{config.SetValue(config.Keys("Battery", "lowThreshold"), 11.0)}, SetOptions{}); err != nil {
		t.Fatal(err)
	}
	if info, _ := os.Lstat(filepath.Join(dir, FileName)); info.Mode()&os.ModeSymlink == 0 {
		t.Error("the link was replaced")
	}
	if data, _ := os.ReadFile(filepath.Join(dots, "config.json")); !strings.Contains(string(data), `"lowThreshold": 11`) {
		t.Error("the target wasn't written")
	}
}

func waitFor(t *testing.T, cond func() bool) {
	t.Helper()
	for i := 0; i < 100; i++ {
		if cond() {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("timed out")
}

// Breaking the file and undoing back to the bytes the store last wrote is
// read again: saves unblock without a restart.
func TestUndoToOwnBytesUnblocks(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	s := open(t, dir)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go s.Watch(ctx)
	time.Sleep(50 * time.Millisecond)
	path := filepath.Join(dir, FileName)
	good, _ := os.ReadFile(path)
	os.WriteFile(path, []byte(`{"format": 2, "Battery": `), 0o600)
	waitFor(t, func() bool { _, st := s.Config(); return st.Blocked })
	os.WriteFile(path, good, 0o600)
	waitFor(t, func() bool { _, st := s.Config(); return !st.Blocked })
}

// A file that doesn't load at the start leaves the store on the defaults;
// a restore keeps the takeover settings the file held, not the defaults'.
func TestRestoreOverUnloadedFileKeepsItsTakeovers(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	first := open(t, dir)
	if _, err := first.Set([]config.Op{config.SetValue(config.Keys("Idle", "enabled"), true)}, SetOptions{Takeover: true}); err != nil {
		t.Fatal(err)
	}
	cfg, _ := first.Config()
	restore := jsonx.Clone(cfg).(*jsonx.Object)
	restore.Value("Idle").(*jsonx.Object).Set("enabled", false)
	broken := jsonx.Clone(cfg).(*jsonx.Object)
	broken.Value("Battery").(*jsonx.Object).Set("lowThreshold", "x")
	first.Close()
	os.WriteFile(filepath.Join(dir, FileName), jsonx.Marshal(broken), 0o600)

	s := open(t, dir)
	if _, st := s.Config(); !st.Blocked {
		t.Fatal("the broken file loaded")
	}
	if _, err := s.Restore(restore, SetOptions{}); err != nil {
		t.Fatal(err)
	}
	got, _ := s.Config()
	if got.Value("Idle").(*jsonx.Object).Value("enabled") != true {
		t.Error("the restore reset a takeover the file held")
	}
}

// A replace without a takeover's section (a saved look) keeps its value
// rather than letting the defaults fill it in.
func TestReplaceWithoutTakeoverSectionKeepsIt(t *testing.T) {
	t.Parallel()
	s := open(t, t.TempDir())
	if _, err := s.Set([]config.Op{config.SetValue(config.Keys("Idle", "enabled"), true)}, SetOptions{Takeover: true}); err != nil {
		t.Fatal(err)
	}
	cfg, _ := s.Config()
	next := jsonx.Clone(cfg).(*jsonx.Object)
	next.Delete("Idle")
	if _, err := s.Replace(next, SetOptions{}); err != nil {
		t.Fatal(err)
	}
	got, _ := s.Config()
	if got.Value("Idle").(*jsonx.Object).Value("enabled") != true {
		t.Error("a replace without Idle reset Idle.enabled")
	}
}

// A subscriber may write: its change is delivered after the one it saw,
// and nothing deadlocks on the change lock.
func TestSubscriberMayWrite(t *testing.T) {
	t.Parallel()
	s := open(t, t.TempDir())
	var revisions []int64
	s.Subscribe(func(e Event) {
		revisions = append(revisions, e.State.Revision)
		if e.State.Revision == 2 {
			if _, err := s.Set([]config.Op{config.SetValue(config.Keys("Battery", "lowThreshold"), 20.0)}, SetOptions{}); err != nil {
				t.Errorf("set from a subscriber: %v", err)
			}
		}
	})
	done := make(chan struct{})
	go func() {
		defer close(done)
		s.Set([]config.Op{config.SetValue(config.Keys("Battery", "lowThreshold"), 15.0)}, SetOptions{})
	}()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("deadlocked")
	}
	if len(revisions) != 2 || revisions[0] != 2 || revisions[1] != 3 {
		t.Errorf("revisions %v", revisions)
	}
}

// An edit made outside (a saved config copied over the file, here one
// without the Idle section) changes the rest but never a takeover setting:
// the one in effect stays, and is written back so the next start loads it.
func TestReloadHoldsTakeovers(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	s := open(t, dir)
	if _, err := s.Set([]config.Op{config.SetValue(config.Keys("Idle", "enabled"), true)}, SetOptions{Takeover: true}); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go s.Watch(ctx)
	time.Sleep(50 * time.Millisecond)

	path := filepath.Join(dir, FileName)
	cfg, _ := s.Config()
	edited := jsonx.Clone(cfg).(*jsonx.Object)
	edited.Delete("Idle")
	edited.Value("Battery").(*jsonx.Object).Set("lowThreshold", 9.0)
	os.WriteFile(path, jsonx.Marshal(edited), 0o600)
	waitFor(t, func() bool {
		cfg, _ := s.Config()
		return cfg.Value("Battery").(*jsonx.Object).Value("lowThreshold") == 9.0
	})
	if cfg, st := s.Config(); cfg.Value("Idle").(*jsonx.Object).Value("enabled") != true || st.Blocked {
		t.Error("an outside edit changed a takeover")
	}
	onDisk, _, err := Peek(Options{Dir: dir, Pipeline: pipeline(t)})
	if err != nil || onDisk.Value("Idle").(*jsonx.Object).Value("enabled") != true {
		t.Errorf("the kept takeover wasn't written back: %v", err)
	}
	// Its own card still changes it
	if _, err := s.Set([]config.Op{config.SetValue(config.Keys("Idle", "enabled"), false)}, SetOptions{Takeover: true}); err != nil {
		t.Fatal(err)
	}
	if cfg, _ := s.Config(); cfg.Value("Idle").(*jsonx.Object).Value("enabled") != false {
		t.Error("the card's change didn't apply")
	}
}
