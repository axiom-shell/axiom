package footprint

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/hookup"
)

func TestUnreadableLedgerIsMovedAside(t *testing.T) {
	t.Parallel()
	l, _, root := newLedger(t)
	os.MkdirAll(filepath.Dir(l.path), 0o755)
	os.WriteFile(l.path, []byte("{not json"), 0o600)
	begin(t, l, Row{Kind: KindFile, Target: filepath.Join(root, "x")}, PriorAbsent)
	if len(l.Rows()) != 1 {
		t.Errorf("%+v", l.Rows())
	}
	if bad, _ := filepath.Glob(l.path + ".bad-*"); len(bad) != 1 {
		t.Errorf("no moved-aside copy: %v", bad)
	}
}

func TestReadErrorStopsTheWrite(t *testing.T) {
	t.Parallel()
	l, _, root := newLedger(t)
	// A folder where the file is: not "missing", not JSON
	os.MkdirAll(l.path, 0o755)
	if _, err := l.Begin(Row{Kind: KindFile, Target: filepath.Join(root, "x")}, PriorAbsent); err == nil {
		t.Error("Begin went on over a ledger it couldn't read")
	}
}

// A row with nothing written yet (the write may never have been made) is
// compared with what was there before
func TestPendingGSettingIsComparedWithPrior(t *testing.T) {
	t.Parallel()
	l, f, _ := newLedger(t)
	ctx := context.Background()
	f.vals["s k"] = "'old'"
	id := begin(t, l, Row{Kind: KindGSetting, Target: "s k"}, l.PriorGSetting(ctx, f.gsettings, "s", "k"))
	// The write never happened: nothing of axiom's to take out
	if res := l.Undo(ctx, []string{id}, UndoOptions{}); res[0].Outcome != OutcomeGone || len(l.Rows()) != 0 {
		t.Errorf("%+v", res)
	}
	id = begin(t, l, Row{Kind: KindGSetting, Target: "s k"}, l.PriorGSetting(ctx, f.gsettings, "s", "k"))
	f.vals["s k"] = "'theirs'"
	if res := l.Undo(ctx, []string{id}, UndoOptions{}); res[0].Outcome != OutcomeChanged || f.vals["s k"] != "'theirs'" {
		t.Errorf("%+v %v", res, f.vals)
	}
}

// A key with no value of the user's own is recorded absent: undone it's reset
func TestAbsentPriorWhenNoUserValue(t *testing.T) {
	t.Parallel()
	l, f, root := newLedger(t)
	config := filepath.Join(root, "cfg")
	l.o.Getenv = func(k string) string {
		return map[string]string{"GSETTINGS_BACKEND": "keyfile", "XDG_CONFIG_HOME": config, "HOME": root}[k]
	}
	run := func(ctx context.Context, args ...string) (string, error) {
		if args[0] == "list-schemas" {
			return "other /other/\ns /desk/top/\n", nil
		}
		return f.gsettings(ctx, args...)
	}
	f.vals["s k"] = "'default'"
	f.vals["s mine"] = "'x'"
	prior := func(key string) string {
		raw, err := l.PriorGSetting(context.Background(), run, "s", key)()
		if err != nil {
			t.Fatal(err)
		}
		return string(raw)
	}
	// No keyfile: nothing is the user's
	if got := prior("k"); got != `{"absent":true}` {
		t.Errorf("no keyfile: %s", got)
	}
	os.MkdirAll(filepath.Join(config, "glib-2.0", "settings"), 0o755)
	os.WriteFile(filepath.Join(config, "glib-2.0", "settings", "keyfile"), []byte("[desk/top]\nmine='x'\n[other]\nk='y'\n"), 0o644)
	if got := prior("k"); got != `{"absent":true}` {
		t.Errorf("k isn't in the group: %s", got)
	}
	if got := prior("mine"); !strings.Contains(got, `"value":"'x'"`) {
		t.Errorf("mine is set: %s", got)
	}
	// An unknown backend: today's behaviour, the value
	l.o.Getenv = func(string) string { return "memory" }
	if got := prior("k"); !strings.Contains(got, "default") {
		t.Errorf("unknown backend: %s", got)
	}
	// The undo of an absent prior resets
	id := begin(t, l, Row{Kind: KindGSetting, Target: "s k", Wrote: Raw("new")}, PriorAbsent)
	l.Done(id, Raw("new"))
	f.vals["s k"] = "'new'"
	l.Undo(context.Background(), []string{id}, UndoOptions{})
	if _, ok := f.vals["s k"]; ok {
		t.Errorf("not reset: %v", f.vals)
	}
}

func TestRebuildRunsAfterTheLock(t *testing.T) {
	t.Parallel()
	l, _, root := newLedger(t)
	var inner error
	l.o.Run = func(ctx context.Context, argv []string) error {
		// The ledger is free while the command runs
		_, inner = l.Begin(Row{Kind: KindFile, Target: filepath.Join(root, "during")}, PriorAbsent)
		return nil
	}
	argv := Raw([]string{"bat"})
	id := begin(t, l, Row{Kind: KindRebuild, Target: "bat", Wrote: argv}, PriorAbsent)
	l.Done(id, argv)
	res := l.Undo(context.Background(), []string{id}, UndoOptions{})
	if inner != nil || res[0].Outcome != OutcomeDone {
		t.Errorf("%v %+v", inner, res)
	}
	if rows := l.Rows(); len(rows) != 1 || rows[0].Kind != KindFile {
		t.Errorf("%+v", rows)
	}
}

func TestBackfillHalvesAreOnceEach(t *testing.T) {
	t.Parallel()
	l, _, root := newLedger(t)
	a, b := filepath.Join(root, "a"), filepath.Join(root, "b")
	if _, ran, _ := l.BackfillFiles([]Row{{Kind: KindFile, Target: a, Prior: Absent()}}); !ran {
		t.Error("files didn't run")
	}
	if l.Backfilled() || !l.BackfilledFiles() {
		t.Error("flags")
	}
	if _, ran, _ := l.Backfill([]Row{{Kind: KindFile, Target: b, Prior: Absent()}}); !ran {
		t.Error("hookups didn't run after the files")
	}
	if _, ran, _ := l.BackfillFiles(nil); ran {
		t.Error("files ran twice")
	}
}

func TestNilLedgerIsSafe(t *testing.T) {
	t.Parallel()
	var l *Ledger
	l.Register("x", nil, nil)
	if res := l.Undo(context.Background(), []string{"a"}, UndoOptions{}); len(res) != 0 {
		t.Errorf("%+v", res)
	}
	if added, ran, err := l.Backfill(nil); added != nil || ran || err != nil {
		t.Error("Backfill")
	}
	l.Drop("x")
	if _, ok := l.Get("x"); ok || l.Rows() != nil || l.Select(UndoOptions{}) != nil {
		t.Error("reads")
	}
}

func TestDropAmendGetSelectOwner(t *testing.T) {
	t.Parallel()
	l, _, root := newLedger(t)
	var ids []string
	for _, c := range []struct{ name, owner string }{{"a", "O1"}, {"b", "O1"}, {"c", "O2"}} {
		ids = append(ids, begin(t, l, Row{Kind: KindFile, Target: filepath.Join(root, c.name), Owner: c.owner}, PriorAbsent))
	}
	if got := l.SelectOwner("O1"); !slices.Equal(got, ids[:2]) {
		t.Errorf("SelectOwner %v", got)
	}
	if got := l.SelectOwner("none"); len(got) != 0 {
		t.Errorf("SelectOwner of none %v", got)
	}
	if _, ok := l.Get("nope"); ok {
		t.Error("Get of nothing")
	}
	if r, ok := l.Get(ids[2]); !ok || r.Owner != "O2" {
		t.Errorf("Get %+v", r)
	}
	changes := 0
	l.o.OnChange = func() { changes++ }
	if err := l.Amend(ids[0], func(r *Row) { r.Owner = "O9" }); err != nil {
		t.Fatal(err)
	}
	if r, _ := l.Get(ids[0]); r.Owner != "O9" {
		t.Errorf("Amend %+v", r)
	}
	if err := l.Amend("nope", func(r *Row) { r.Owner = "X" }); err != nil {
		t.Error(err)
	}
	l.Drop("nope")
	if changes != 0 {
		t.Errorf("a change was announced for nothing: %d", changes)
	}
	l.Drop(ids[1])
	if changes != 1 || len(l.Rows()) != 2 {
		t.Errorf("Drop: %d changes, %+v", changes, l.Rows())
	}
}

func TestMergeHookup(t *testing.T) {
	t.Parallel()
	first := &HookupRec{CreatedFile: true, NoFinalNewline: true, LastLine: "z", LinkTarget: "/l", Backup: "/b1",
		Edit: hookup.EditRecord{Comment: "#", Inserted: []hookup.Inserted{{Text: "a", Index: 1}}, Commented: []string{"o1"}, WrapLine: "w", Wrapped: true, CreatedSection: "s"}}
	second := &HookupRec{Backup: "/b2", Edit: hookup.EditRecord{Comment: "#", Inserted: []hookup.Inserted{{Text: "b", Index: 2}}, Commented: []string{"o2"}}}
	got := mergeHookup(first, second)
	if !got.CreatedFile || !got.NoFinalNewline || got.LastLine != "z" || got.LinkTarget != "/l" || got.Backup != "/b1" || !slices.Equal(got.Backups, []string{"/b2"}) ||
		len(got.Edit.Inserted) != 2 || !slices.Equal(got.Edit.Commented, []string{"o1", "o2"}) || got.Edit.WrapLine != "w" || !got.Edit.Wrapped || got.Edit.CreatedSection != "s" {
		t.Errorf("%+v", got)
	}
	if mergeHookup(nil, second) != second || mergeHookup(first, nil) != first {
		t.Error("a missing record")
	}
}

func TestBeginDirsRecordsEachLevel(t *testing.T) {
	t.Parallel()
	l, _, root := newLedger(t)
	os.MkdirAll(filepath.Join(root, "have"), 0o755)
	done, err := l.BeginDirs(filepath.Join(root, "have", "a", "b"), "O")
	if err != nil {
		t.Fatal(err)
	}
	var targets []string
	for _, r := range l.Rows() {
		targets = append(targets, r.Target)
		if r.State != StatePending {
			t.Errorf("%s: %s", r.ID, r.State)
		}
	}
	if !slices.Equal(targets, []string{filepath.Join(root, "have", "a"), filepath.Join(root, "have", "a", "b")}) {
		t.Errorf("%v", targets)
	}
	done()
	for _, r := range l.Rows() {
		if r.State != StateApplied {
			t.Errorf("%s: %s", r.ID, r.State)
		}
	}
	if done, err := l.BeginDirs(filepath.Join(root, "have"), "O"); err != nil || len(l.Rows()) != 2 {
		t.Errorf("an existing folder is recorded: %v %d", err, len(l.Rows()))
	} else {
		done()
	}
}

func TestDirMarkerTree(t *testing.T) {
	t.Parallel()
	l, _, root := newLedger(t)
	mk := func(name, index string) string {
		dir := filepath.Join(root, name)
		os.MkdirAll(filepath.Join(dir, "cursors"), 0o755)
		os.WriteFile(filepath.Join(dir, "index.theme"), []byte(index), 0o644)
		id := begin(t, l, Row{Kind: KindDir, Target: dir, Wrote: Raw(DirWrote{MarkerFile: "index.theme", Marker: "X-Mine=true"})}, PriorAbsent)
		l.Done(id, nil)
		return id
	}
	ours, notours := mk("ours", "X-Mine=true\n"), mk("theirs", "nothing\n")
	res := l.Undo(context.Background(), []string{ours, notours}, UndoOptions{})
	outcomes := map[string]string{}
	for _, r := range res {
		outcomes[r.ID] = r.Outcome
	}
	if outcomes[ours] != OutcomeDone || outcomes[notours] != OutcomeChanged {
		t.Errorf("%v", outcomes)
	}
	if _, err := os.Stat(filepath.Join(root, "ours")); err == nil {
		t.Error("the marked tree stayed")
	}
	if _, err := os.Stat(filepath.Join(root, "theirs")); err != nil {
		t.Error("an unmarked folder was removed")
	}
}

func TestFileSHARefusesAChangedFile(t *testing.T) {
	t.Parallel()
	l, _, root := newLedger(t)
	path := filepath.Join(root, "config.toml")
	data := []byte("written\n")
	os.WriteFile(path, data, 0o644)
	id := begin(t, l, Row{Kind: KindFile, Target: path}, PriorAbsent)
	l.Done(id, SHA256Of(data))
	os.WriteFile(path, []byte("written\nmine\n"), 0o644)
	if res := l.Undo(context.Background(), []string{id}, UndoOptions{}); res[0].Outcome != OutcomeChanged {
		t.Errorf("%+v", res)
	}
	if _, err := os.Stat(path); err != nil {
		t.Error("a changed file was deleted")
	}
	os.WriteFile(path, data, 0o644)
	if res := l.Undo(context.Background(), []string{id}, UndoOptions{}); res[0].Outcome != OutcomeDone {
		t.Errorf("%+v", res)
	}
}

func TestDryRunOutcomes(t *testing.T) {
	t.Parallel()
	l, f, root := newLedger(t)
	ctx := context.Background()
	here, gone := filepath.Join(root, "here"), filepath.Join(root, "gone")
	os.WriteFile(here, nil, 0o644)
	idHere := begin(t, l, Row{Kind: KindFile, Target: here}, PriorAbsent)
	idGone := begin(t, l, Row{Kind: KindFile, Target: gone}, PriorAbsent)
	f.vals["s k"] = "'x'"
	idChanged := begin(t, l, Row{Kind: KindGSetting, Target: "s k", Wrote: Raw("y")}, PriorAbsent)
	l.Done(idChanged, Raw("y"))
	want := map[string]string{idHere: OutcomeDone, idGone: OutcomeGone, idChanged: OutcomeChanged}
	got := map[string]string{}
	for _, r := range l.Undo(ctx, []string{idHere, idGone, idChanged}, UndoOptions{DryRun: true}) {
		got[r.ID] = r.Outcome
	}
	for id, o := range want {
		if got[id] != o {
			t.Errorf("%s: %s, want %s", id, got[id], o)
		}
	}
	if len(l.Rows()) != 3 {
		t.Errorf("a dry run removed rows: %d", len(l.Rows()))
	}
}

// The mode kept is the file's, through a link
func TestPriorFileModeFollowsALink(t *testing.T) {
	t.Parallel()
	l, _, root := newLedger(t)
	real, link := filepath.Join(root, "real"), filepath.Join(root, "link")
	os.WriteFile(real, []byte("x"), 0o600)
	os.Symlink(real, link)
	raw, err := l.PriorFile(link)()
	if err != nil {
		t.Fatal(err)
	}
	var p FilePrior
	json.Unmarshal(raw, &p)
	if p.Mode != 0o600 {
		t.Errorf("mode %o", p.Mode)
	}
}

func TestBeginMakesAnInferredRowRecorded(t *testing.T) {
	t.Parallel()
	l, _, root := newLedger(t)
	path := filepath.Join(root, "a")
	if _, _, err := l.BackfillFiles([]Row{{Kind: KindFile, Target: path, Owner: "ThemeIntegrations.gtk", Prior: Absent()}}); err != nil {
		t.Fatal(err)
	}
	id := ID(KindFile, path, "")
	if r, _ := l.Get(id); !r.Inferred {
		t.Fatal("backfilled row not inferred")
	}
	begin(t, l, Row{Kind: KindFile, Target: path, Owner: "ThemeIntegrations.gtk"}, l.PriorFile(path))
	r, _ := l.Get(id)
	if r.Inferred || string(r.Prior) != string(Absent()) {
		t.Errorf("want recorded with the backfill's prior: %+v", r)
	}
}
