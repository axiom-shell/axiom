package footprint

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// fake is a gsettings store and a record of the commands run
type fake struct {
	mu   sync.Mutex
	vals map[string]string
	log  []string
	runs [][]string
}

func (f *fake) gsettings(_ context.Context, args ...string) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.log = append(f.log, strings.Join(args, " "))
	key := args[1] + " " + args[2]
	switch args[0] {
	case "get":
		return f.vals[key] + "\n", nil
	case "set":
		f.vals[key] = args[3]
	case "reset":
		delete(f.vals, key)
	}
	return "", nil
}

func newLedger(t *testing.T) (*Ledger, *fake, string) {
	t.Helper()
	root := t.TempDir()
	dirs := xdg.Resolve(func(k string) string {
		return map[string]string{"HOME": root, "XDG_CONFIG_HOME": root + "/c", "XDG_STATE_HOME": root + "/s", "XDG_DATA_HOME": root + "/d", "XDG_CACHE_HOME": root + "/ca"}[k]
	})
	f := &fake{vals: map[string]string{}}
	l := New(Options{Dirs: dirs, Now: func() time.Time { return time.Unix(1000, 0) }, GSettings: f.gsettings,
		Run: func(_ context.Context, argv []string) error {
			f.runs = append(f.runs, argv)
			f.log = append(f.log, "run "+strings.Join(argv, " "))
			return nil
		}})
	return l, f, root
}

func begin(t *testing.T, l *Ledger, r Row, prior func() (json.RawMessage, error)) string {
	t.Helper()
	id, err := l.Begin(r, prior)
	if err != nil {
		t.Fatal(err)
	}
	return id
}

func TestBeginRecordsPriorOnFirstWriteOnly(t *testing.T) {
	t.Parallel()
	l, _, root := newLedger(t)
	path := filepath.Join(root, "f.txt")
	os.WriteFile(path, []byte("one"), 0o644)
	id := begin(t, l, Row{Kind: KindFile, Target: path}, l.PriorFile(path))
	l.Done(id, nil)
	os.WriteFile(path, []byte("two"), 0o644)
	called := false
	begin(t, l, Row{Kind: KindFile, Target: path}, func() (json.RawMessage, error) { called = true; return Absent(), nil })
	if called {
		t.Error("prior called for a known row")
	}
	rows := l.Rows()
	var p FilePrior
	json.Unmarshal(rows[0].Prior, &p)
	if len(rows) != 1 || p.BytesPath == "" {
		t.Fatalf("%+v", rows)
	}
	if data, _ := os.ReadFile(p.BytesPath); string(data) != "one" {
		t.Errorf("kept %q", data)
	}
}

func TestPendingRowSurvivesAReload(t *testing.T) {
	t.Parallel()
	l, _, root := newLedger(t)
	begin(t, l, Row{Kind: KindFile, Target: filepath.Join(root, "x")}, PriorAbsent)
	again := New(l.o)
	rows := again.Rows()
	if len(rows) != 1 || rows[0].State != StatePending {
		t.Errorf("%+v", rows)
	}
}

func TestOwnDirsNeverRecorded(t *testing.T) {
	t.Parallel()
	l, _, _ := newLedger(t)
	for _, d := range []string{l.o.Dirs.Config, l.o.Dirs.State, l.o.Dirs.Data, l.o.Dirs.Cache} {
		if id := begin(t, l, Row{Kind: KindFile, Target: d + "dev/x.json"}, PriorAbsent); id != "" {
			t.Errorf("recorded %s", id)
		}
	}
	if len(l.Rows()) != 0 {
		t.Errorf("%+v", l.Rows())
	}
}

func TestUndoOrderByKind(t *testing.T) {
	t.Parallel()
	l, f, root := newLedger(t)
	dir := filepath.Join(root, "icons")
	file := filepath.Join(dir, "a")
	os.MkdirAll(dir, 0o755)
	os.WriteFile(file, []byte("x"), 0o644)
	// Recorded in the opposite order of their undo
	for _, r := range []Row{
		{Kind: KindRebuild, Target: "bat", Wrote: Raw([]string{"bat", "cache", "--build"})},
		{Kind: KindDir, Target: dir},
		{Kind: KindFile, Target: file},
		{Kind: KindGSetting, Target: "s k", Wrote: Raw("'a'")},
	} {
		id := begin(t, l, r, func() (json.RawMessage, error) { return Raw(GSettingPrior{Value: "'old'"}), nil })
		l.Done(id, r.Wrote)
	}
	f.vals["s k"] = "'a'"
	// The file row's prior is a gsetting's: make it absent
	rows := l.Rows()
	_ = rows
	res := l.Undo(context.Background(), l.Select(UndoOptions{}), UndoOptions{})
	var order []string
	for _, r := range res {
		order = append(order, strings.SplitN(r.ID, ":", 2)[0])
	}
	if want := []string{"gsetting", "file", "dir", "rebuild"}; !slices.Equal(order, want) {
		t.Errorf("%v: %+v", order, res)
	}
	if _, err := os.Stat(dir); err == nil {
		t.Error("the dir stayed")
	}
	if len(l.Rows()) != 0 {
		t.Errorf("%+v", l.Rows())
	}
}

func TestGSettingUndoOnlyWhenUnchanged(t *testing.T) {
	t.Parallel()
	l, f, _ := newLedger(t)
	f.vals["s k"] = "'default'"
	ctx := context.Background()
	id := begin(t, l, Row{Kind: KindGSetting, Target: "s k"}, PriorGSetting(ctx, f.gsettings, "s", "k"))
	f.vals["s k"] = "dark"
	l.Done(id, Raw("dark"))
	f.vals["s k"] = "'prefer-light'"
	res := l.Undo(ctx, []string{id}, UndoOptions{})
	if res[0].Outcome != OutcomeChanged || f.vals["s k"] != "'prefer-light'" || len(l.Rows()) != 1 {
		t.Errorf("%+v %v", res, f.vals)
	}
	f.vals["s k"] = "'dark'"
	res = l.Undo(ctx, []string{id}, UndoOptions{})
	if res[0].Outcome != OutcomeDone || f.vals["s k"] != "'default'" || len(l.Rows()) != 0 {
		t.Errorf("%+v %v", res, f.vals)
	}
}

func TestGSettingAbsentPriorResets(t *testing.T) {
	t.Parallel()
	l, f, _ := newLedger(t)
	f.vals["s k"] = "axiom-cursor-x"
	id := begin(t, l, Row{Kind: KindGSetting, Target: "s k", Wrote: Raw("axiom-cursor-x")}, PriorAbsent)
	l.Done(id, Raw("axiom-cursor-x"))
	res := l.Undo(context.Background(), []string{id}, UndoOptions{})
	if res[0].Outcome != OutcomeDone || !slices.Contains(f.log, "reset s k") {
		t.Errorf("%+v %v", res, f.log)
	}
}

func TestFileUndoRestoresPriorBytes(t *testing.T) {
	t.Parallel()
	l, _, root := newLedger(t)
	path := filepath.Join(root, "kitty", "axiom.conf")
	os.MkdirAll(filepath.Dir(path), 0o755)
	os.WriteFile(path, []byte("mine"), 0o600)
	id := begin(t, l, Row{Kind: KindFile, Target: path}, l.PriorFile(path))
	os.WriteFile(path, []byte("axiom's"), 0o644)
	l.Done(id, nil)
	if res := l.Undo(context.Background(), []string{id}, UndoOptions{}); res[0].Outcome != OutcomeDone {
		t.Fatalf("%+v", res)
	}
	data, _ := os.ReadFile(path)
	info, _ := os.Stat(path)
	if string(data) != "mine" || info.Mode().Perm() != 0o600 {
		t.Errorf("%q %v", data, info.Mode())
	}
	if entries, _ := os.ReadDir(l.priorDir()); len(entries) != 0 {
		t.Errorf("the kept bytes stayed: %v", entries)
	}
	// Absent: deleted
	other := filepath.Join(root, "new")
	id = begin(t, l, Row{Kind: KindFile, Target: other}, l.PriorFile(other))
	os.WriteFile(other, []byte("x"), 0o644)
	l.Done(id, nil)
	l.Undo(context.Background(), []string{id}, UndoOptions{})
	if _, err := os.Stat(other); err == nil {
		t.Error("not deleted")
	}
}

func TestDirUndoOnlyWhenEmpty(t *testing.T) {
	t.Parallel()
	l, _, root := newLedger(t)
	dir := filepath.Join(root, "made")
	os.MkdirAll(dir, 0o755)
	os.WriteFile(filepath.Join(dir, "users"), nil, 0o644)
	id := begin(t, l, Row{Kind: KindDir, Target: dir}, PriorAbsent)
	l.Done(id, nil)
	if res := l.Undo(context.Background(), []string{id}, UndoOptions{}); res[0].Outcome != OutcomeChanged {
		t.Errorf("%+v", res)
	}
	os.Remove(filepath.Join(dir, "users"))
	if res := l.Undo(context.Background(), []string{id}, UndoOptions{}); res[0].Outcome != OutcomeDone {
		t.Errorf("%+v", res)
	}
	if _, err := os.Stat(dir); err == nil {
		t.Error("stayed")
	}
}

func TestMarkedBlockUndo(t *testing.T) {
	t.Parallel()
	l, _, root := newLedger(t)
	path := filepath.Join(root, "config.toml")
	os.WriteFile(path, []byte("[theme]\n# begin\nbackground = \"x\"\n# end\nmine = 1\n"), 0o644)
	id := begin(t, l, Row{Kind: KindMarkedBlock, Target: path, Wrote: Raw(BlockWrote{Begin: "# begin", End: "# end"})}, PriorAbsent)
	l.Done(id, nil)
	l.Undo(context.Background(), []string{id}, UndoOptions{})
	if data, _ := os.ReadFile(path); string(data) != "[theme]\nmine = 1\n" {
		t.Errorf("%q", data)
	}
}

func TestRebuildRunsAfterFiles(t *testing.T) {
	t.Parallel()
	l, f, root := newLedger(t)
	path := filepath.Join(root, "theme.tmTheme")
	os.WriteFile(path, nil, 0o644)
	argv := Raw([]string{"bat", "cache", "--build"})
	id := begin(t, l, Row{Kind: KindRebuild, Target: "bat", Wrote: argv}, PriorAbsent)
	l.Done(id, argv)
	id2 := begin(t, l, Row{Kind: KindFile, Target: path}, PriorAbsent)
	l.Done(id2, nil)
	l.Undo(context.Background(), []string{id, id2}, UndoOptions{})
	if !slices.Equal(f.runs[0], []string{"bat", "cache", "--build"}) {
		t.Errorf("%v", f.runs)
	}
	if _, err := os.Stat(path); err == nil {
		t.Error("the file stayed")
	}
}

func TestInferredNeedsForce(t *testing.T) {
	t.Parallel()
	l, _, root := newLedger(t)
	path := filepath.Join(root, "found")
	os.WriteFile(path, nil, 0o644)
	added, ran, err := l.Backfill([]Row{{Kind: KindFile, Target: path, Prior: Absent()}})
	if err != nil || !ran || len(added) != 1 {
		t.Fatal(added, ran, err)
	}
	if _, ran, _ := l.Backfill([]Row{{Kind: KindFile, Target: path + "2"}}); ran {
		t.Error("backfilled twice")
	}
	if ids := l.Select(UndoOptions{}); len(ids) != 0 {
		t.Errorf("undo all took %v", ids)
	}
	if res := l.Undo(context.Background(), added, UndoOptions{}); res[0].Outcome != OutcomeRefused {
		t.Errorf("%+v", res)
	}
	if res := l.Undo(context.Background(), added, UndoOptions{Force: true}); res[0].Outcome != OutcomeDone {
		t.Errorf("%+v", res)
	}
}

func TestSystemSkippedByUndoAll(t *testing.T) {
	t.Parallel()
	l, _, root := newLedger(t)
	a, b := filepath.Join(root, "a"), filepath.Join(root, "b")
	begin(t, l, Row{Kind: KindFile, Target: a}, PriorAbsent)
	sys := begin(t, l, Row{Kind: KindFile, Target: b, System: true}, PriorAbsent)
	if ids := l.Select(UndoOptions{}); len(ids) != 1 || ids[0] == sys {
		t.Errorf("%v", ids)
	}
	if ids := l.Select(UndoOptions{IncludeSystem: true}); len(ids) != 2 {
		t.Errorf("%v", ids)
	}
	// Picked, it's undone
	if res := l.Undo(context.Background(), []string{sys}, UndoOptions{}); res[0].Outcome != OutcomeGone {
		t.Errorf("%+v", res)
	}
}

func TestLockSerializesWriters(t *testing.T) {
	t.Parallel()
	l, _, root := newLedger(t)
	other := New(l.o)
	var wg sync.WaitGroup
	for _, led := range []*Ledger{l, other} {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := range 25 {
				if _, err := led.Begin(Row{Kind: KindFile, Target: filepath.Join(root, "f", string(rune('a'+i)), strings.Repeat("x", len(led.path)%3))}, PriorAbsent); err != nil {
					t.Error(err)
				}
			}
		}()
	}
	wg.Wait()
	if n := len(l.Rows()); n < 25 {
		t.Errorf("rows lost: %d", n)
	}
	seen := map[string]bool{}
	for _, r := range l.Rows() {
		if seen[r.ID] {
			t.Errorf("duplicate %s", r.ID)
		}
		seen[r.ID] = true
	}
}

func TestUnknownVersionIsReadOnly(t *testing.T) {
	t.Parallel()
	l, _, root := newLedger(t)
	os.MkdirAll(filepath.Dir(l.path), 0o755)
	os.WriteFile(l.path, []byte(`{"version":9,"rows":[{"id":"file:/x","kind":"file","target":"/x"}]}`), 0o600)
	if rows := l.List(context.Background()); len(rows) != 1 {
		t.Errorf("%+v", rows)
	}
	if _, err := l.Begin(Row{Kind: KindFile, Target: filepath.Join(root, "y")}, PriorAbsent); err == nil {
		t.Error("wrote")
	}
	if res := l.Undo(context.Background(), []string{"file:/x"}, UndoOptions{}); res[len(res)-1].Outcome != OutcomeRefused {
		t.Errorf("%+v", res)
	}
	if data, _ := os.ReadFile(l.path); !strings.Contains(string(data), `"version":9`) {
		t.Errorf("rewritten: %s", data)
	}
}

func TestDryRunChangesNothing(t *testing.T) {
	t.Parallel()
	l, f, root := newLedger(t)
	path := filepath.Join(root, "x")
	os.WriteFile(path, nil, 0o644)
	id := begin(t, l, Row{Kind: KindFile, Target: path}, PriorAbsent)
	l.Done(id, nil)
	res := l.Undo(context.Background(), []string{id}, UndoOptions{DryRun: true})
	if res[0].Outcome != OutcomeDone || len(l.Rows()) != 1 || len(f.log) != 0 {
		t.Errorf("%+v", res)
	}
	if _, err := os.Stat(path); err != nil {
		t.Error("deleted")
	}
}
