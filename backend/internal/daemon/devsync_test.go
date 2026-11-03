package daemon

import (
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/devconfig"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/migrate/steps"
	"github.com/axiom-shell/axiom/backend/internal/saved"
	"github.com/axiom-shell/axiom/backend/internal/schema"
	"github.com/axiom-shell/axiom/backend/internal/store"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// syncSchema is a small schema: General.c only the dev tree's (withC),
// Idle.enabled a takeover.
func syncSchema(t *testing.T, withC bool) *schema.Schema {
	t.Helper()
	return syncSchemaAt(t, withC, steps.Current())
}

// syncSchemaAt is syncSchema at config version version.
func syncSchemaAt(t *testing.T, withC bool, version int) *schema.Schema {
	t.Helper()
	c := ""
	if withC {
		c = `, "c": {"type": "boolean", "default": false}`
	}
	text := fmt.Sprintf(`{"type": "object", "additionalProperties": false, "properties": {
		"format": {"type": "integer", "default": 2},
		"version": {"type": "integer", "default": %d},
		"General": {"type": "object", "additionalProperties": false, "properties": {
			"a": {"type": "integer", "default": 1},
			"b": {"type": "string", "default": "x"}%s}},
		"Idle": {"type": "object", "additionalProperties": false, "properties": {
			"enabled": {"type": "boolean", "default": false, "x-takeover": true}}}}}`, version, c)
	v, err := jsonx.Unmarshal([]byte(text))
	if err != nil {
		t.Fatal(err)
	}
	return schema.New(v)
}

// liveText is a live config file: General's a and b, Idle.enabled.
func liveText(a int, b string, idle bool) string {
	return fmt.Sprintf(`{"format": 2, "version": %d, "General": {"a": %d, "b": %q}, "Idle": {"enabled": %v}}`, steps.Current(), a, b, idle)
}

// devSyncFixture is the dev image on scratch folders, its dev config
// seeded from live (liveText), the install's schema without General.c.
func devSyncFixture(t *testing.T, live string) *devMode {
	t.Helper()
	home := t.TempDir()
	d := &Daemon{opts: Options{Tree: "/dev", Log: slog.New(slog.DiscardHandler)}}
	d.dirs = xdg.Dirs{Config: home + "/config/", State: home + "/state/", UI: home + "/ui/"}
	d.installTree, d.configDir = "/install", devConfigDir(d.dirs)
	d.dev = newDevMode(d, true)
	install := syncSchema(t, false)
	d.dev.installSchemaFn = func() (*schema.Schema, error) { return install, nil }
	os.MkdirAll(d.dirs.Config, 0o700)
	writeLiveFile(t, d.dev, live)
	st, err := d.openStore(store.Options{Dir: d.configDir, Pipeline: config.Pipeline{S: syncSchema(t, true)}})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	d.store = st
	d.store.Subscribe(d.dev.onConfig)
	return d.dev
}

func writeLiveFile(t *testing.T, m *devMode, text string) {
	t.Helper()
	if err := os.WriteFile(m.d.devConfigFiles().Live, []byte(text), 0o600); err != nil {
		t.Fatal(err)
	}
}

// liveFile is the live config file, parsed.
func liveFile(t *testing.T, m *devMode) *jsonx.Object {
	t.Helper()
	data, err := os.ReadFile(m.d.devConfigFiles().Live)
	if err != nil {
		t.Fatal(err)
	}
	v, err := jsonx.Unmarshal(data)
	if err != nil {
		t.Fatal(err)
	}
	return v.(*jsonx.Object)
}

func setDev(t *testing.T, m *devMode, path string, v any, takeover bool) {
	t.Helper()
	if _, err := m.d.store.Set([]config.Op{config.SetValue(mustPath(t, path), v)}, store.SetOptions{Takeover: takeover}); err != nil {
		t.Fatal(err)
	}
}

func mustPath(t *testing.T, text string) config.Path {
	t.Helper()
	p, err := config.ParsePath(text)
	if err != nil {
		t.Fatal(err)
	}
	return p
}

func devValue(m *devMode, path string) any {
	cfg, _ := m.d.store.Config()
	p, _ := config.ParsePath(path)
	v, _ := config.Lookup(cfg, p)
	return v
}

// sidesOf is the diff's rows as path → side (" dev-only" appended).
func sidesOf(t *testing.T, m *devMode) map[string]string {
	t.Helper()
	diff, err := m.diffNow()
	if err != nil {
		t.Fatal(err)
	}
	out := map[string]string{}
	for _, r := range diff.Rows {
		side := r.Side
		if r.DevOnly {
			side += " dev-only"
		}
		out[r.Path.String()] = side
	}
	return out
}

func TestDevConfigDiff(t *testing.T) {
	t.Parallel()
	m := devSyncFixture(t, liveText(1, "x", false))
	if got := sidesOf(t, m); len(got) != 0 {
		t.Fatalf("a fresh copy differs: %v", got)
	}
	setDev(t, m, "General.a", 5.0, false)
	setDev(t, m, "General.c", true, false)
	writeLiveFile(t, m, liveText(1, "y", false))
	got := sidesOf(t, m)
	want := map[string]string{"General.a": "dev", "General.b": "live", "General.c": "dev dev-only"}
	if fmt.Sprint(got) != fmt.Sprint(want) {
		t.Errorf("rows %v, want %v", got, want)
	}
	if diff, _ := m.diffNow(); !diff.LiveChanged || !m.State().Config.LiveChanged {
		t.Error("live's change isn't told")
	}
	writeLiveFile(t, m, liveText(7, "y", false))
	if got := sidesOf(t, m); got["General.a"] != "both" {
		t.Errorf("a changed on both sides: %v", got)
	}

	m.d.configDir = m.d.dirs.Config // the install image
	if _, err := m.diffNow(); axerr.KindOf(err) != axerr.Unavailable {
		t.Errorf("a diff outside the dev image: %v", err)
	}
}

func TestDevConfigCopy(t *testing.T) {
	t.Parallel()
	m := devSyncFixture(t, liveText(1, "x", false))
	setDev(t, m, "General.a", 5.0, false)
	setDev(t, m, "General.c", true, false)
	writeLiveFile(t, m, liveText(1, "y", false))

	// To live: written to its raw file, its version kept, the base along
	res, err := m.configCopy(DevConfigCopyParams{Paths: []config.Path{mustPath(t, "General.a")}, To: "live"})
	if err != nil {
		t.Fatal(err)
	}
	live := liveFile(t, m)
	if v, _ := config.Lookup(live, mustPath(t, "General.a")); v != 5.0 || live.Value("version") != float64(steps.Current()) {
		t.Errorf("live %s", jsonx.Marshal(live))
	}
	if len(res.Copied) != 1 || len(res.Diff.Rows) != 2 {
		t.Errorf("copied %v, rows after %v", res.Copied, res.Diff.Rows)
	}
	if got := sidesOf(t, m); got["General.a"] != "" {
		t.Errorf("a still differs: %v", got)
	}

	// A dev-only setting never goes to live; nor does a path with no
	// difference
	if _, err := m.configCopy(DevConfigCopyParams{Paths: []config.Path{mustPath(t, "General.c")}, To: "live"}); axerr.KindOf(err) != axerr.Refused {
		t.Errorf("a dev-only copy to live: %v", err)
	}
	if _, err := m.configCopy(DevConfigCopyParams{Paths: []config.Path{mustPath(t, "Idle")}, To: "live"}); axerr.KindOf(err) != axerr.NotFound {
		t.Errorf("a copy of no difference: %v", err)
	}
	if v, _ := config.Lookup(liveFile(t, m), mustPath(t, "General.c")); v != nil {
		t.Errorf("live took General.c: %v", v)
	}

	// To dev: through the store, a section copying what differs under it
	if _, err := m.configCopy(DevConfigCopyParams{Paths: []config.Path{mustPath(t, "General")}, To: "dev"}); err != nil {
		t.Fatal(err)
	}
	if devValue(m, "General.b") != "y" || devValue(m, "General.c") != false {
		t.Errorf("dev after the copy: b %v, c %v", devValue(m, "General.b"), devValue(m, "General.c"))
	}
	if got := sidesOf(t, m); len(got) != 0 {
		t.Errorf("still differing: %v", got)
	}
	if _, err := m.configCopy(DevConfigCopyParams{Paths: []config.Path{mustPath(t, "General")}, To: "elsewhere"}); axerr.KindOf(err) != axerr.BadRequest {
		t.Errorf("a copy elsewhere: %v", err)
	}
}

func TestDevConfigPull(t *testing.T) {
	t.Parallel()
	for _, mode := range []string{"merge", "replace"} {
		t.Run(mode, func(t *testing.T) {
			t.Parallel()
			m := devSyncFixture(t, liveText(1, "x", false))
			setDev(t, m, "General.a", 5.0, false)
			writeLiveFile(t, m, liveText(7, "y", false))
			res, err := m.configPull(DevConfigPullParams{Mode: mode})
			if err != nil {
				t.Fatal(err)
			}
			wantA := 5.0 // changed on both sides: dev's kept
			if mode == "replace" {
				wantA = 7.0
			} else if fmt.Sprint(pathStrings(res.Merged), pathStrings(res.Conflicts)) != "[General.b] [General.a]" {
				t.Errorf("merged %v, conflicts %v", res.Merged, res.Conflicts)
			}
			if devValue(m, "General.a") != wantA || devValue(m, "General.b") != "y" {
				t.Errorf("dev after: a %v, b %v", devValue(m, "General.a"), devValue(m, "General.b"))
			}
			// The base is live now: what's left is dev's own
			if res.Diff.LiveChanged || m.State().Config.LiveChanged {
				t.Error("live still counts as changed")
			}
			base, _ := os.ReadFile(m.d.devConfigFiles().Base)
			if string(base) != liveText(7, "y", false) {
				t.Errorf("base %s", base)
			}
			for _, r := range res.Diff.Rows {
				if r.Side != devconfig.SideDev {
					t.Errorf("row %s: %s", r.Path, r.Side)
				}
			}
		})
	}
}

func TestDevConfigTakeoverMirror(t *testing.T) {
	t.Parallel()
	m := devSyncFixture(t, liveText(1, "x", false))
	setDev(t, m, "Idle.enabled", true, true)
	if v, _ := config.Lookup(liveFile(t, m), mustPath(t, "Idle.enabled")); v != true {
		t.Errorf("live's Idle.enabled %v", v)
	}
	// Not a takeover: live keeps its own
	setDev(t, m, "General.a", 3.0, false)
	if v, _ := config.Lookup(liveFile(t, m), mustPath(t, "General.a")); v != 1.0 {
		t.Errorf("live's General.a %v", v)
	}
	// Mirrored, it isn't a difference, nor live's change
	if got := sidesOf(t, m); fmt.Sprint(got) != "map[General.a:dev]" {
		t.Errorf("rows %v", got)
	}
}

// A takeover setting live and dev disagree on (live's file edited by
// hand: dev mode mirrors only dev's changes) is never a row, never merged,
// and a copy naming it is refused, either way: no copy writes one.
func TestDevConfigNeverCopiesATakeover(t *testing.T) {
	t.Parallel()
	m := devSyncFixture(t, liveText(1, "x", false))
	writeLiveFile(t, m, liveText(1, "x", true))
	if got := sidesOf(t, m); len(got) != 0 {
		t.Errorf("rows %v", got)
	}
	for _, to := range []string{"live", "dev"} {
		for _, path := range []string{"Idle.enabled", "Idle.enabled.deeper"} {
			if _, err := m.configCopy(DevConfigCopyParams{Paths: []config.Path{mustPath(t, path)}, To: to}); axerr.KindOf(err) != axerr.TakeoverRefused {
				t.Errorf("a copy of %s to %s: %v", path, to, err)
			}
		}
	}
	res, err := m.configPull(DevConfigPullParams{Mode: "merge"})
	if err != nil || len(res.Merged) != 0 || len(res.Conflicts) != 0 {
		t.Errorf("pulled %+v, %v", res, err)
	}
	if devValue(m, "Idle.enabled") != false {
		t.Errorf("dev's Idle.enabled %v", devValue(m, "Idle.enabled"))
	}
	if v, _ := config.Lookup(liveFile(t, m), mustPath(t, "Idle.enabled")); v != true {
		t.Errorf("live's Idle.enabled %v", v)
	}

	// The install image refuses it too
	m = installSyncFixture(t, liveText(1, "x", false))
	if _, err := m.configCopy(DevConfigCopyParams{Paths: []config.Path{mustPath(t, "Idle.enabled")}, To: "live"}); axerr.KindOf(err) != axerr.TakeoverRefused {
		t.Errorf("a copy of a takeover from the install image: %v", err)
	}
}

func TestDevNeverOverwritesALiveSnapshot(t *testing.T) {
	t.Parallel()
	m := devSyncFixture(t, liveText(1, "x", false))
	d := m.d
	svc := saved.New(saved.Options{
		Dir: d.dirs.Config, UIState: filepath.Join(d.dirs.UI, "dev", "savedconfigs.json"),
		Store: d.store, Pipeline: d.store.Pipeline, LiveRestores: m.liveRestores,
	})
	dir := filepath.Join(d.dirs.Config, "saved")
	snapshot := func(name string, version int) {
		os.WriteFile(filepath.Join(dir, name+".json"), fmt.Appendf(nil, `{"format": 2, "version": %d, "meta": {"title": %q}}`, version, name), 0o600)
	}
	snapshot("live", steps.Current())
	snapshot("newer", steps.Current()+1)
	if _, err := svc.Save("live", ""); axerr.KindOf(err) != axerr.Conflict {
		t.Errorf("overwriting a snapshot live restores: %v", err)
	}
	if _, err := svc.Save("newer", ""); err != nil {
		t.Errorf("overwriting one only dev reads: %v", err)
	}
	if _, err := svc.Save("brand new", ""); err != nil {
		t.Errorf("a new one: %v", err)
	}
	// The install image saves over its own
	d.configDir = d.dirs.Config
	if _, err := svc.Save("live", ""); err != nil {
		t.Errorf("the install's save: %v", err)
	}
}

func TestInstallSchemaIsCached(t *testing.T) {
	t.Parallel()
	root := testkit.RepoRoot()
	if schemaSourceKey(root) == "" {
		t.Fatal("no key for the repo's schema source")
	}
	c := treeSchemaCache{what: "the install tree's schema"}
	first, err := c.get(root)
	if err != nil {
		t.Fatal(err)
	}
	if again, _ := c.get(root); again != first {
		t.Error("built again with the source unchanged")
	}
	m := &devMode{installSchemaFn: func() (*schema.Schema, error) { return first, nil }}
	if v, err := m.installVersion(); err != nil || v != float64(steps.Current()) {
		t.Errorf("the install's version %v (%v), want %d", v, err, steps.Current())
	}
	if _, err := c.get(t.TempDir()); axerr.KindOf(err) != axerr.NotFound {
		t.Errorf("a tree without a schema source: %v", err)
	}
}

// installSyncFixture is the install image on scratch folders, live open in
// its store (the install's schema, without General.c), a dev tree set
// whose schema has General.c, and no dev config yet.
func installSyncFixture(t *testing.T, live string) *devMode {
	t.Helper()
	home := t.TempDir()
	d := &Daemon{opts: Options{Tree: "/install", Log: slog.New(slog.DiscardHandler)}}
	d.dirs = xdg.Dirs{Config: home + "/config/", State: home + "/state/", UI: home + "/ui/"}
	d.installTree, d.configDir = "/install", d.dirs.Config
	d.dev = newDevMode(d, false)
	d.dev.tree = "/dev"
	devSchema := syncSchema(t, true)
	d.dev.devSchemaFn = func() (*schema.Schema, error) { return devSchema, nil }
	d.dev.installSchemaFn = func() (*schema.Schema, error) {
		t.Error("the install image asked for the install tree's schema: its store has it")
		return nil, nil
	}
	os.MkdirAll(d.dirs.Config, 0o700)
	writeLiveFile(t, d.dev, live)
	st, err := d.openStore(store.Options{Dir: d.configDir, Pipeline: config.Pipeline{S: syncSchema(t, false)}})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	d.store = st
	d.store.Subscribe(d.dev.onConfig)
	return d.dev
}

// setLive changes live through the install's store.
func setLive(t *testing.T, m *devMode, path string, v any) {
	t.Helper()
	if _, err := m.d.store.Set([]config.Op{config.SetValue(mustPath(t, path), v)}, store.SetOptions{}); err != nil {
		t.Fatal(err)
	}
}

// devFile is the dev config file, parsed.
func devFile(t *testing.T, m *devMode) *jsonx.Object {
	t.Helper()
	data, err := os.ReadFile(m.d.devConfigFiles().Dev)
	if err != nil {
		t.Fatal(err)
	}
	v, err := jsonx.Unmarshal(data)
	if err != nil {
		t.Fatal(err)
	}
	return v.(*jsonx.Object)
}

func devFileValue(t *testing.T, m *devMode, path string) any {
	t.Helper()
	v, _ := config.Lookup(devFile(t, m), mustPath(t, path))
	return v
}

func storeValue(t *testing.T, m *devMode, path string) any {
	t.Helper()
	cfg, _ := m.d.store.Config()
	v, _ := config.Lookup(cfg, mustPath(t, path))
	return v
}

func TestDevConfigFromInstall(t *testing.T) {
	t.Parallel()
	m := installSyncFixture(t, liveText(1, "x", false))
	// The first diff seeds the dev config from live, as a dev start would
	if got := sidesOf(t, m); len(got) != 0 {
		t.Fatalf("a fresh copy differs: %v", got)
	}
	if devFile(t, m).Value("version") != float64(steps.Current()) {
		t.Fatalf("no dev config seeded: %s", jsonx.Marshal(devFile(t, m)))
	}
	// dev edited (by the dev image, earlier), live through its store
	if err := os.WriteFile(m.d.devConfigFiles().Dev, []byte(fmt.Sprintf(`{"format": 2, "version": %d, "General": {"a": 5, "b": "x", "c": true}, "Idle": {"enabled": false}}`, steps.Current())), 0o600); err != nil {
		t.Fatal(err)
	}
	setLive(t, m, "General.b", "y")
	want := map[string]string{"General.a": "dev", "General.b": "live", "General.c": "dev dev-only"}
	if got := sidesOf(t, m); fmt.Sprint(got) != fmt.Sprint(want) {
		t.Errorf("rows %v, want %v", got, want)
	}
	if !m.State().Config.LiveChanged {
		t.Error("live's change isn't told")
	}

	// To live: through the store, the base along; dev-only refused
	if _, err := m.configCopy(DevConfigCopyParams{Paths: []config.Path{mustPath(t, "General.a")}, To: "live"}); err != nil {
		t.Fatal(err)
	}
	if storeValue(t, m, "General.a") != 5.0 {
		t.Errorf("live's a %v", storeValue(t, m, "General.a"))
	}
	if _, err := m.configCopy(DevConfigCopyParams{Paths: []config.Path{mustPath(t, "General.c")}, To: "live"}); axerr.KindOf(err) != axerr.Refused {
		t.Errorf("a dev-only copy to live: %v", err)
	}
	if got := sidesOf(t, m); fmt.Sprint(got) != "map[General.b:live General.c:dev dev-only]" {
		t.Errorf("rows after the copy to live %v", got)
	}

	// To dev: on the file's raw JSON, its version untouched
	if _, err := m.configCopy(DevConfigCopyParams{Paths: []config.Path{mustPath(t, "General")}, To: "dev"}); err != nil {
		t.Fatal(err)
	}
	if devFileValue(t, m, "General.b") != "y" || devFileValue(t, m, "General.c") != false || devFile(t, m).Value("version") != float64(steps.Current()) {
		t.Errorf("dev after the copy %s", jsonx.Marshal(devFile(t, m)))
	}
	if got := sidesOf(t, m); len(got) != 0 {
		t.Errorf("still differing: %v", got)
	}
}

func TestDevConfigPullFromInstall(t *testing.T) {
	t.Parallel()
	for _, mode := range []string{"merge", "replace"} {
		t.Run(mode, func(t *testing.T) {
			t.Parallel()
			m := installSyncFixture(t, liveText(1, "x", false))
			sidesOf(t, m) // seeds dev
			if _, err := m.configCopy(DevConfigCopyParams{Paths: []config.Path{mustPath(t, "General.c")}, To: "dev"}); axerr.KindOf(err) != axerr.NotFound {
				t.Fatalf("a copy of no difference: %v", err)
			}
			if err := devconfig.WriteDev(m.d.devConfigFiles().Dev, []config.Op{config.SetValue(mustPath(t, "General.a"), 5.0)}, syncSchema(t, true)); err != nil {
				t.Fatal(err)
			}
			setLive(t, m, "General.a", 7.0)
			setLive(t, m, "General.b", "y")
			res, err := m.configPull(DevConfigPullParams{Mode: mode})
			if err != nil {
				t.Fatal(err)
			}
			wantA := 5.0
			if mode == "replace" {
				wantA = 7.0
			} else if fmt.Sprint(pathStrings(res.Merged), pathStrings(res.Conflicts)) != "[General.b] [General.a]" {
				t.Errorf("merged %v, conflicts %v", res.Merged, res.Conflicts)
			}
			if devFileValue(t, m, "General.a") != wantA || devFileValue(t, m, "General.b") != "y" || devFile(t, m).Value("version") != float64(steps.Current()) {
				t.Errorf("dev after %s", jsonx.Marshal(devFile(t, m)))
			}
			if res.Diff.LiveChanged || m.State().Config.LiveChanged {
				t.Error("live still counts as changed")
			}
		})
	}
}

func TestDevConfigFromInstallRefusals(t *testing.T) {
	t.Parallel()
	// No dev tree
	m := installSyncFixture(t, liveText(1, "x", false))
	m.tree = ""
	if _, err := m.diffNow(); axerr.KindOf(err) != axerr.Unavailable || !strings.Contains(err.Error(), "axiom dev set") {
		t.Errorf("a diff with no dev tree: %v", err)
	}
	if _, err := os.Stat(m.d.devConfigFiles().Dev); err == nil {
		t.Error("a dev config made with no dev tree")
	}

	// A dev store holding the dev config elsewhere
	m = installSyncFixture(t, liveText(1, "x", false))
	sidesOf(t, m)
	lock, err := fsx.TryLock(m.d.devConfigFiles().Dev + ".lock")
	if err != nil {
		t.Fatal(err)
	}
	defer lock.Release()
	if _, err := m.configPull(DevConfigPullParams{Mode: "replace"}); axerr.KindOf(err) != axerr.Running {
		t.Errorf("a pull while another axiom has the dev config: %v", err)
	}
	if err := devconfig.WriteDev(m.d.devConfigFiles().Dev, []config.Op{config.SetValue(mustPath(t, "General.a"), 5.0)}, syncSchema(t, true)); axerr.KindOf(err) != axerr.Running {
		t.Errorf("a dev write while another axiom has it: %v", err)
	}

	// A dev tree migrating further than this binary
	m = installSyncFixture(t, liveText(1, "x", false))
	newer := syncSchemaAt(t, true, steps.Current()+1)
	m.devSchemaFn = func() (*schema.Schema, error) { return newer, nil }
	if _, err := m.diffNow(); axerr.KindOf(err) != axerr.Unavailable {
		t.Errorf("a diff past this binary's migrations: %v", err)
	}
}
