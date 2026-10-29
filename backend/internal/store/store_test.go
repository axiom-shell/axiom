package store

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
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

// A takeover can't be changed around its own key either: replacing or
// deleting its section, deleting the key back to its default, or an op
// list that ends on another value is refused, and the value stays
func TestNoOpChangesATakeoverSideways(t *testing.T) {
	t.Parallel()
	s := open(t, t.TempDir())
	if _, err := s.Set([]config.Op{config.SetValue(config.Keys("Idle", "enabled"), true)}, SetOptions{Takeover: true}); err != nil {
		t.Fatal(err)
	}
	section, _ := jsonx.Unmarshal([]byte(`{"enabled": false}`))
	for name, ops := range map[string][]config.Op{
		"the section replaced":  {config.SetValue(config.Keys("Idle"), section)},
		"the section deleted":   {{Op: "delete", Path: config.Keys("Idle")}},
		"the key deleted":       {{Op: "delete", Path: config.Keys("Idle", "enabled")}},
		"ending off":            {config.SetValue(config.Keys("Idle", "enabled"), true), config.SetValue(config.Keys("Idle", "enabled"), false)},
		"hidden among the rest": {config.SetValue(config.Keys("Battery", "lowThreshold"), 12.0), config.SetValue(config.Keys("Idle", "enabled"), false)},
	} {
		if _, err := s.Set(ops, SetOptions{}); axerr.KindOf(err) != axerr.TakeoverRefused {
			t.Errorf("%s: %v", name, err)
		}
		if cfg, _ := s.Config(); cfg.Value("Idle").(*jsonx.Object).Value("enabled") != true {
			t.Fatalf("%s changed Idle.enabled", name)
		}
	}
}

// An event carries the ops from the config before it: a write's, and an
// edit made outside's (diffed after the takeovers are held)
func TestEventsCarryTheChange(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	s := open(t, dir)
	events := make(chan Event, 4)
	s.Subscribe(func(e Event) {
		if e.Config != nil {
			events <- e
		}
	})
	if _, err := s.Replace(func() *jsonx.Object {
		cfg, _ := s.Config()
		next := jsonx.Clone(cfg).(*jsonx.Object)
		next.Value("Battery").(*jsonx.Object).Set("lowThreshold", 12.0)
		return next
	}(), SetOptions{}); err != nil {
		t.Fatal(err)
	}
	if got := changesOf(t, <-events); got != `[{"op":"set","path":["Battery","lowThreshold"],"value":12}]` {
		t.Errorf("a write's changes: %s", got)
	}
	cfg, _ := s.Config()
	edited := jsonx.Clone(cfg).(*jsonx.Object)
	edited.Value("Battery").(*jsonx.Object).Set("notify", false)
	edited.Value("Idle").(*jsonx.Object).Set("enabled", true)
	if err := os.WriteFile(s.Path(), jsonx.Marshal(edited), 0o600); err != nil {
		t.Fatal(err)
	}
	s.reload()
	if got := changesOf(t, <-events); got != `[{"op":"set","path":["Battery","notify"],"value":false}]` {
		t.Errorf("an outside edit's changes: %s", got)
	}
}

func changesOf(t *testing.T, ev Event) string {
	t.Helper()
	data, err := json.Marshal(ev.Changes)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
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
	watch(t, s)

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
	watch(t, s)
	// Delivered by whichever goroutine publishes next (a reload too)
	var n atomic.Int32
	s.Subscribe(func(Event) { n.Add(1) })
	s.Set([]config.Op{config.SetValue(config.Keys("Battery", "lowThreshold"), 16.0)}, SetOptions{})
	waitFor(t, func() bool { return n.Load() > 0 })
	time.Sleep(150 * time.Millisecond)
	if n := n.Load(); n != 1 {
		t.Errorf("%d events for one write", n)
	}
}

func TestDeletedFileIsNotRecreated(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	s := open(t, dir)
	watch(t, s)
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

// watch runs s.Watch until the test ends, once it watches the folders:
// an edit before then would go unseen.
func watch(t *testing.T, s *Store) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	s.watching = make(chan struct{})
	ended := make(chan error, 1)
	go func() { ended <- s.Watch(ctx) }()
	t.Cleanup(func() { cancel(); <-ended })
	select {
	case <-s.watching:
	case err := <-ended:
		t.Fatalf("Watch ended: %v", err)
	case <-time.After(testkit.Bound(5 * time.Second)):
		t.Fatal("not watching")
	}
}

func waitFor(t *testing.T, cond func() bool) {
	t.Helper()
	if !testkit.Eventually(cond) {
		t.Fatal("timed out")
	}
}

// Breaking the file and undoing back to the bytes the store last wrote is
// read again: saves unblock without a restart.
func TestUndoToOwnBytesUnblocks(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	s := open(t, dir)
	watch(t, s)
	path := filepath.Join(dir, FileName)
	good, _ := os.ReadFile(path)
	os.WriteFile(path, []byte(`{"format": 2, "Battery": `), 0o600)
	waitFor(t, func() bool { _, st := s.Config(); return st.Blocked })
	os.WriteFile(path, good, 0o600)
	waitFor(t, func() bool { _, st := s.Config(); return !st.Blocked })
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
	case <-time.After(testkit.Bound(5 * time.Second)):
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
	watch(t, s)

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

// An edit of nothing but a takeover is put back once: no new revision, and
// the write-back isn't read again as another edit.
func TestTakeoverOnlyEditIsWrittenBackOnce(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	s := open(t, dir)
	watch(t, s)

	path := filepath.Join(dir, FileName)
	cfg, st := s.Config()
	edited := jsonx.Clone(cfg).(*jsonx.Object)
	edited.Value("Idle").(*jsonx.Object).Set("enabled", true)
	os.WriteFile(path, jsonx.Marshal(edited), 0o600)
	idle := func() any {
		cfg, _, _ := Peek(Options{Dir: dir, Pipeline: pipeline(t)})
		return cfg.Value("Idle").(*jsonx.Object).Value("enabled")
	}
	waitFor(t, func() bool { return idle() == false })
	time.Sleep(100 * time.Millisecond)
	if got, now := s.Config(); now.Revision != st.Revision || got.Value("Idle").(*jsonx.Object).Value("enabled") != false {
		t.Errorf("revision %d → %d, Idle.enabled %v", st.Revision, now.Revision, got.Value("Idle").(*jsonx.Object).Value("enabled"))
	}
}

// Over a file that wasn't JSON at the start nothing about its takeovers is
// known (the store ran on the defaults), so the fixed file's own values load.
func TestFixedUnparsableFileKeepsItsTakeovers(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	first := open(t, dir)
	if _, err := first.Set([]config.Op{config.SetValue(config.Keys("Idle", "enabled"), true)}, SetOptions{Takeover: true}); err != nil {
		t.Fatal(err)
	}
	good, _ := first.Config()
	first.Close()
	path := filepath.Join(dir, FileName)
	os.WriteFile(path, []byte(`{"version": `), 0o600)

	s := open(t, dir)
	watch(t, s)
	os.WriteFile(path, jsonx.Marshal(good), 0o600)
	waitFor(t, func() bool { _, st := s.Config(); return !st.Blocked })
	if cfg, _ := s.Config(); cfg.Value("Idle").(*jsonx.Object).Value("enabled") != true {
		t.Error("the fixed file's takeover was reset to the default")
	}
	if onDisk, _, _ := Peek(Options{Dir: dir, Pipeline: pipeline(t)}); onDisk.Value("Idle").(*jsonx.Object).Value("enabled") != true {
		t.Error("the fixed file was written back with the default")
	}
}

// A file that doesn't load at the start: the takeover settings in effect
// are the file's when it parsed, unknown when it isn't JSON
func TestTakeoversOverAnUnloadedFile(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	first := open(t, dir)
	if _, err := first.Set([]config.Op{config.SetValue(config.Keys("Compositor", "mode"), "managed")}, SetOptions{Takeover: true}); err != nil {
		t.Fatal(err)
	}
	cfg, _ := first.Config()
	broken := jsonx.Clone(cfg).(*jsonx.Object)
	broken.Value("Battery").(*jsonx.Object).Set("lowThreshold", "x")
	first.Close()
	path := filepath.Join(dir, FileName)
	for _, c := range []struct {
		name, file string
		known      bool
	}{
		{"invalid", string(jsonx.Marshal(broken)), true},
		{"not JSON", `{"version": `, false},
	} {
		os.WriteFile(path, []byte(c.file), 0o600)
		s, err := Open(Options{Dir: dir, Pipeline: pipeline(t)})
		if err != nil {
			t.Fatal(err)
		}
		running, _ := s.Config()
		if v, _ := config.Lookup(running, config.Keys("Compositor", "mode")); v != "detached" {
			t.Errorf("%s: not running on the defaults (mode %v)", c.name, v)
		}
		takeovers, known := s.Takeovers()
		mode, _ := config.Lookup(takeovers, config.Keys("Compositor", "mode"))
		if known != c.known || (known && mode != "managed") {
			t.Errorf("%s: takeovers known %v, mode %v", c.name, known, mode)
		}
		s.Close()
	}
}

func openKeeping(t *testing.T, dir string) *Store {
	t.Helper()
	s, err := Open(Options{Dir: dir, Pipeline: pipeline(t), Debounce: 20 * time.Millisecond, TakeoversFile: filepath.Join(dir, "state", TakeoversFile)})
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func takeover(t *testing.T, cfg *jsonx.Object, path ...string) any {
	t.Helper()
	v, _ := config.Lookup(cfg, config.Keys(path...))
	return v
}

// A config.json that isn't JSON at the start: the takeover settings last in
// effect, kept on disk, are the ones in effect. A restore (a saved config,
// which holds none) keeps them, and so does a hand fix, written back.
func TestKeptTakeoversOverAFileThatIsntJSON(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	first := openKeeping(t, dir)
	for _, op := range []config.Op{config.SetValue(config.Keys("Compositor", "mode"), "managed"), config.SetValue(config.Keys("Idle", "enabled"), true)} {
		if _, err := first.Set([]config.Op{op}, SetOptions{Takeover: true}); err != nil {
			t.Fatal(err)
		}
	}
	first.Close()
	path := filepath.Join(dir, FileName)
	os.WriteFile(path, []byte(`{"version": `), 0o600)

	s := openKeeping(t, dir)
	t.Cleanup(func() { s.Close() })
	if cfg, known := s.Takeovers(); !known || takeover(t, cfg, "Compositor", "mode") != "managed" {
		t.Fatalf("takeovers known %v, mode %v", known, takeover(t, cfg, "Compositor", "mode"))
	}
	look := s.Pipeline().Defaults()
	look.Delete("Compositor")
	look.Delete("Idle")
	if _, err := s.Replace(look, SetOptions{Restore: true}); err != nil {
		t.Fatal(err)
	}
	got, st := s.Config()
	if st.Blocked || takeover(t, got, "Compositor", "mode") != "managed" || takeover(t, got, "Idle", "enabled") != true {
		t.Fatalf("restore: blocked %v, mode %v, idle %v", st.Blocked, takeover(t, got, "Compositor", "mode"), takeover(t, got, "Idle", "enabled"))
	}

	watch(t, s)
	edited := jsonx.Clone(got).(*jsonx.Object)
	edited.Value("Compositor").(*jsonx.Object).Set("mode", "detached")
	edited.Value("Battery").(*jsonx.Object).Set("lowThreshold", 7.0)
	os.WriteFile(path, jsonx.Marshal(edited), 0o600)
	waitFor(t, func() bool { cfg, _ := s.Config(); return takeover(t, cfg, "Battery", "lowThreshold") == 7.0 })
	cfg, _ := s.Config()
	data, _ := os.ReadFile(path)
	onDisk, _ := jsonx.Unmarshal(data)
	if takeover(t, cfg, "Compositor", "mode") != "managed" || takeover(t, onDisk.(*jsonx.Object), "Compositor", "mode") != "managed" {
		t.Fatalf("the outside edit released the mode: in effect %v, on disk %v", takeover(t, cfg, "Compositor", "mode"), takeover(t, onDisk.(*jsonx.Object), "Compositor", "mode"))
	}
}

// A first run keeps the defaults' takeovers. With none kept (the file
// removed), a config.json that isn't JSON leaves them unknown and a restore
// is refused rather than writing the defaults'.
func TestNoKeptTakeoversRefusesARestore(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	first := openKeeping(t, dir)
	first.Close()
	kept := filepath.Join(dir, "state", TakeoversFile)
	data, err := os.ReadFile(kept)
	if v, _ := jsonx.Unmarshal(data); err != nil || takeover(t, v.(*jsonx.Object), "Compositor", "mode") != "detached" {
		t.Fatalf("first run kept %s (%v)", data, err)
	}
	os.Remove(kept)
	os.WriteFile(filepath.Join(dir, FileName), []byte(`{"version": `), 0o600)
	s := openKeeping(t, dir)
	defer s.Close()
	if _, known := s.Takeovers(); known {
		t.Fatal("takeovers known with none kept")
	}
	if _, err := s.Replace(s.Pipeline().Defaults(), SetOptions{Restore: true}); axerr.KindOf(err) != axerr.Conflict {
		t.Fatalf("restore with the takeovers unknown: %v", err)
	}
}
