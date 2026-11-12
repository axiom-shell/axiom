//go:build container

package containertest

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io/fs"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/daemon"
	"github.com/axiom-shell/axiom/backend/internal/footprint"
	"github.com/axiom-shell/axiom/backend/internal/hookup"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"github.com/axiom-shell/axiom/backend/internal/theme/integrations"
)

// The footprint ledger's round trip (docs/dev/backend/footprint.md): a
// seeded home, every integration and hookup applied, then everything undone
// and the home compared byte for byte. gsettings runs on glib's keyfile
// backend, in the scratch home, never a dconf.

// Entry is one path of a home's snapshot.
type Entry struct {
	Type string // file, dir, link
	Mode fs.FileMode
	// SHA is a file's sha256, Link a link's target
	SHA, Link string
}

// Snapshot is a home's files and its gsettings.
type Snapshot struct {
	Files     map[string]Entry
	GSettings string
}

// skipped are the places a snapshot leaves out: axiom's own folders, glib's
// keyfile, and what the harness itself puts in the home.
var skipped = []string{".config/axiom", ".local/state/axiom", ".local/share/axiom", ".cache", ".config/glib-2.0", ".config/sway", "bin"}

// SeedHome copies dir (testdata/home-seed) into the session's home, keeping
// links and modes. dotfiles/ is then made read-only, so Apply wraps the link
// that points into it.
func (s *Session) SeedHome(dir string) {
	s.t.Helper()
	err := filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(dir, path)
		if rel == "." {
			return nil
		}
		dest := filepath.Join(s.Home, rel)
		info, err := d.Info()
		if err != nil {
			return err
		}
		switch {
		case info.Mode()&fs.ModeSymlink != 0:
			to, err := os.Readlink(path)
			if err != nil {
				return err
			}
			return os.Symlink(to, dest)
		case d.IsDir():
			return os.MkdirAll(dest, 0o755)
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		return os.WriteFile(dest, data, 0o644)
	})
	if err != nil {
		s.t.Fatal(err)
	}
	if err := os.Chmod(filepath.Join(s.Home, "dotfiles"), 0o555); err != nil {
		s.t.Fatal(err)
	}
	s.t.Cleanup(func() { os.Chmod(filepath.Join(s.Home, "dotfiles"), 0o755) })
	for k, v := range map[string]string{"color-scheme": "'default'", "gtk-theme": "'adw-gtk3'", "cursor-theme": "'Adwaita'"} {
		s.GSettings("set", "org.gnome.desktop.interface", k, strings.Trim(v, "'"))
	}
}

// GSettings runs gsettings in the session (the keyfile backend).
func (s *Session) GSettings(args ...string) string {
	s.t.Helper()
	cmd := exec.Command("gsettings", args...)
	cmd.Env = s.env()
	out, err := cmd.CombinedOutput()
	if err != nil {
		s.t.Fatalf("gsettings %v: %v\n%s", args, err, out)
	}
	return string(out)
}

// Snapshot is the home's files (type, mode, content or link target) and
// GNOME's interface settings.
func (s *Session) Snapshot() Snapshot {
	s.t.Helper()
	snap := Snapshot{Files: map[string]Entry{}}
	err := filepath.WalkDir(s.Home, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(s.Home, path)
		if rel == "." {
			return nil
		}
		for _, skip := range skipped {
			if rel == skip || strings.HasPrefix(rel, skip+"/") {
				return filepath.SkipDir
			}
		}
		info, err := os.Lstat(path)
		if err != nil {
			return err
		}
		e := Entry{Mode: info.Mode().Perm()}
		switch {
		case info.Mode()&fs.ModeSymlink != 0:
			e.Type = "link"
			e.Link, _ = os.Readlink(path)
			e.Mode = 0
		case d.IsDir():
			e.Type = "dir"
		default:
			e.Type = "file"
			data, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			sum := sha256.Sum256(data)
			e.SHA = hex.EncodeToString(sum[:])
		}
		snap.Files[rel] = e
		return nil
	})
	if err != nil {
		s.t.Fatal(err)
	}
	snap.GSettings = s.GSettings("list-recursively", "org.gnome.desktop.interface")
	return snap
}

// Diff is what differs between two snapshots, a line each (+ added, -
// removed, ~ changed), sorted.
func Diff(a, b Snapshot) []string {
	var out []string
	for _, path := range slices.Sorted(maps.Keys(a.Files)) {
		got, ok := b.Files[path]
		switch {
		case !ok:
			out = append(out, "- "+path)
		case got != a.Files[path]:
			out = append(out, fmt.Sprintf("~ %s: %+v -> %+v", path, a.Files[path], got))
		}
	}
	for _, path := range slices.Sorted(maps.Keys(b.Files)) {
		if _, ok := a.Files[path]; !ok {
			out = append(out, "+ "+path)
		}
	}
	if a.GSettings != b.GSettings {
		out = append(out, "~ gsettings:\n"+a.GSettings+"\n->\n"+b.GSettings)
	}
	return out
}

// withoutBackups is diff with the .axiom-bak-* files it lists (they're kept
// by design) taken out, and those paths returned.
func withoutBackups(diff []string) (rest, backups []string) {
	for _, line := range diff {
		if path, ok := strings.CutPrefix(line, "+ "); ok && strings.Contains(path, ".axiom-bak-") {
			backups = append(backups, path)
			continue
		}
		rest = append(rest, line)
	}
	return rest, backups
}

// footprintSession is a seeded home with sway and axiom running, GSETTINGS
// on the keyfile backend, bash as the shell.
func footprintSession(t *testing.T) (*Session, *Proc) {
	t.Helper()
	s := NewSessionWith(t, "GSETTINGS_BACKEND=keyfile", "SHELL=/bin/bash")
	s.SeedHome("testdata/home-seed")
	// bat is there (a cache to rebuild)
	s.FakeProgram("bat", "exit 0")
	s.StartSway(swayMinimal)
	return s, s.StartAxiom("sway")
}

func (s *Session) src(rel string) string { return filepath.Join(os.Getenv("AXIOM_SRC"), rel) }

// schemaHookups are each ThemeIntegrations key's x-hookup targets, from the
// built schema (no copy of the list here).
func schemaHookups(t *testing.T, s *Session) map[string][]hookup.Target {
	t.Helper()
	data, err := os.ReadFile(s.src("qml/config/json/config.schema.json"))
	if err != nil {
		t.Fatal(err)
	}
	var schema struct {
		Properties struct {
			ThemeIntegrations struct {
				Properties map[string]struct {
					Hookup []hookup.Target `json:"x-hookup"`
				} `json:"properties"`
			} `json:"ThemeIntegrations"`
		} `json:"properties"`
	}
	if err := json.Unmarshal(data, &schema); err != nil {
		t.Fatal(err)
	}
	out := map[string][]hookup.Target{}
	for key, p := range schema.Properties.ThemeIntegrations.Properties {
		if len(p.Hookup) > 0 {
			out[key] = p.Hookup
		}
	}
	return out
}

func (s *Session) integrate(keys []string) {
	s.t.Helper()
	owners := map[string]string{}
	for _, k := range keys {
		owners[k] = "ThemeIntegrations." + k
	}
	if _, err := s.ShellCall("theme.integrate", map[string]any{"theme": s.src("qml/config/themes/ayu-dark.json"), "keys": keys, "owners": owners}); err != nil {
		s.t.Fatal(err)
	}
}

func integrationKeys() []string { return slices.Sorted(maps.Keys(integrations.Table)) }

func (s *Session) footprintRows() []footprint.RowStatus {
	s.t.Helper()
	var list daemon.FootprintListResult
	if err := json.Unmarshal([]byte(s.Axiom("--json", "footprint", "list")), &list); err != nil {
		s.t.Fatal(err)
	}
	return list.Rows
}

// applyEverything is what the settings do over a session: the integrations,
// each hookup, the sway screen-sharing line, a cursor theme, a default app.
func applyEverything(t *testing.T, s *Session) {
	t.Helper()
	keys := integrationKeys()
	s.integrate(keys)
	for key := range schemaHookups(t, s) {
		if _, err := s.ShellCall("hookup.apply", map[string]any{"key": key, "owner": "ThemeIntegrations." + key}); err != nil {
			t.Fatalf("hookup.apply %s: %v", key, err)
		}
	}
	data, err := os.ReadFile("testdata/hookups-sway.json")
	if err != nil {
		t.Fatal(err)
	}
	var sway []hookup.Target
	if err := json.Unmarshal(data, &sway); err != nil {
		t.Fatal(err)
	}
	// (mirrors ScreenShareSources.hookupTargets("sway", bin))
	if _, err := s.ShellCall("hookup.apply", map[string]any{"key": "screenSharing", "targets": sway, "owner": "ScreenSharing.enabled"}); err != nil {
		t.Fatal(err)
	}
	// ncspot's block exists now: the colors go into it (as Apply does)
	s.integrate(keys)
	if _, err := s.ShellCall("cursor.theme", map[string]any{"theme": "whiteglass", "size": 24, "owner": "Input.cursor.theme"}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.ShellCall("apps.setDefault", map[string]any{"role": "textEditor", "id": "axiom-test.desktop"}); err != nil {
		t.Fatal(err)
	}
}

func TestContainerFootprintRoundTrip(t *testing.T) {
	s, p := footprintSession(t)
	a := s.Snapshot()
	applyEverything(t, s)

	rows := s.footprintRows()
	kinds := map[string]int{}
	backups := map[string]bool{}
	for _, r := range rows {
		kinds[r.Kind]++
		if r.State != footprint.StateApplied {
			t.Errorf("%s is %s", r.ID, r.State)
		}
		if r.Hookup != nil {
			for _, b := range append([]string{r.Hookup.Backup}, r.Hookup.Backups...) {
				backups[b] = true
			}
		}
	}
	t.Logf("kinds recorded: %v", kinds)
	for _, kind := range []string{footprint.KindFile, footprint.KindDir, footprint.KindHookup, footprint.KindGSetting, footprint.KindINIGroups, footprint.KindMarkedBlock, footprint.KindMimeapps, footprint.KindRebuild} {
		if kinds[kind] == 0 {
			t.Errorf("no %s row", kind)
		}
	}
	if len(Diff(a, s.Snapshot())) == 0 {
		t.Fatal("applying everything changed nothing")
	}

	out := s.Axiom("footprint", "undo", "--all", "--include-system")
	t.Logf("undo:\n%s", out)
	stopAxiom(t, p)
	b := s.Snapshot()
	rest, listed := withoutBackups(Diff(a, b))
	if len(rest) > 0 {
		t.Errorf("the home isn't as it was:\n%s", strings.Join(rest, "\n"))
		data, _ := os.ReadFile(filepath.Join(s.Home, ".config/kdeglobals"))
		t.Logf("kdeglobals now:\n%s", data)
	}
	for _, path := range listed {
		if !backups[filepath.Join(s.Home, path)] {
			t.Errorf("%s is a backup no row lists", path)
		}
	}
	if len(listed) == 0 {
		t.Error("no backups were kept")
	}
	if to, _ := os.Readlink(filepath.Join(s.Home, ".config/gtk-4.0/gtk.css")); to != "../../dotfiles/gtk4.css" {
		t.Errorf("the gtk-4.0 link points to %q", to)
	}
}

func TestContainerFootprintChangedSinceIsLeft(t *testing.T) {
	s, _ := footprintSession(t)
	s.integrate([]string{"gtk"})
	if got := s.GSettings("get", "org.gnome.desktop.interface", "color-scheme"); !strings.Contains(got, "prefer-dark") {
		t.Fatalf("gtk didn't set the scheme: %s", got)
	}
	s.GSettings("set", "org.gnome.desktop.interface", "color-scheme", "prefer-light")
	out := s.Axiom("footprint", "undo", "--all", "--include-system")
	if !strings.Contains(out, "changed: gsetting:org.gnome.desktop.interface color-scheme") {
		t.Errorf("no changed outcome:\n%s", out)
	}
	if got := s.GSettings("get", "org.gnome.desktop.interface", "color-scheme"); !strings.Contains(got, "prefer-light") {
		t.Errorf("the value was changed: %s", got)
	}
	// The row stays, saying so
	var left *footprint.RowStatus
	for _, r := range s.footprintRows() {
		if r.Kind == footprint.KindGSetting && strings.HasSuffix(r.Target, "color-scheme") {
			left = &r
		}
	}
	if left == nil || left.Status != footprint.StatusChanged {
		t.Errorf("the row: %+v", left)
	}
}

func TestContainerFootprintBackfillInfersOldHookups(t *testing.T) {
	s := NewSessionWith(t, "GSETTINGS_BACKEND=keyfile", "SHELL=/bin/bash")
	s.SeedHome("testdata/home-seed")
	a := s.Snapshot()
	// What an old axiom left: its line, a backup, its file
	kitty := filepath.Join(s.Config, "kitty")
	if err := os.WriteFile(filepath.Join(kitty, "kitty.conf"), []byte("font_size 12\n\ninclude axiom.conf\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(kitty, "kitty.conf.axiom-bak-20250101-000000"), []byte("font_size 12\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(kitty, "axiom.conf"), []byte("# old colors\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	s.StartSway(swayMinimal)
	p := s.StartAxiom("sway")
	targets := schemaHookups(t, s)["kitty"]
	if len(targets) == 0 {
		t.Fatal("no kitty hookup in the schema")
	}
	res, err := s.ShellCall("footprint.backfill", daemon.FootprintBackfillRequest{Targets: map[string]daemon.FootprintBackfillTargets{
		"kitty": {Owner: "ThemeIntegrations.kitty", Targets: targets},
	}})
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("backfill: %s", res)
	var found []string
	for _, r := range s.footprintRows() {
		if !r.Inferred {
			t.Errorf("%s isn't inferred", r.ID)
		}
		found = append(found, r.ID)
	}
	t.Logf("rows found: %v", found)
	if len(found) < 2 {
		t.Fatalf("the backfill found %v", found)
	}
	// Inferred rows aren't undone without force
	if out := s.Axiom("footprint", "undo", "--all"); strings.Contains(out, "done:") {
		t.Errorf("undo --all took inferred rows:\n%s", out)
	}
	t.Logf("undo --force:\n%s", s.Axiom("footprint", "undo", "--all", "--force"))
	stopAxiom(t, p)
	rest, _ := withoutBackups(Diff(a, s.Snapshot()))
	if len(rest) > 0 {
		t.Errorf("not as before axiom:\n%s", strings.Join(rest, "\n"))
	}
}

func TestContainerFootprintUndoWithoutDaemon(t *testing.T) {
	s, p := footprintSession(t)
	a := s.Snapshot()
	s.integrate([]string{"gtk", "kitty"})
	if _, err := s.ShellCall("hookup.apply", map[string]any{"key": "kitty", "owner": "ThemeIntegrations.kitty"}); err != nil {
		t.Fatal(err)
	}
	stopAxiom(t, p)
	// No daemon: the command line works on the ledger itself
	cmd := exec.Command(os.Getenv("AXIOM_BIN"), "--offline", "footprint", "undo", "--all", "--include-system")
	cmd.Env = s.env()
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("undo without a daemon: %v\n%s", err, out)
	}
	if rest, _ := withoutBackups(Diff(a, s.Snapshot())); len(rest) > 0 {
		t.Errorf("not as before:\n%s", strings.Join(rest, "\n"))
	}
	// The next daemon lists nothing
	s.StartAxiom("sway")
	if rows := s.footprintRows(); len(rows) != 0 {
		t.Errorf("rows after the undo: %+v", rows)
	}
}

// fcitx5 on the session bus, when it starts headless: its options and group
// are set through the daemon and undone
func TestContainerFcitxRoundTrip(t *testing.T) {
	s := NewSessionWith(t, "GSETTINGS_BACKEND=keyfile", "SHELL=/bin/bash", "QT_QPA_PLATFORM=offscreen")
	if _, err := exec.LookPath("fcitx5"); err != nil {
		t.Skip("fcitx5 isn't in the image")
	}
	s.StartSway(swayMinimal)
	s.StartProgram(nil, "fcitx5", "--disable=all", "--enable=keyboard,dbus")
	if !testkit.Eventually(func() bool {
		cmd := exec.Command("busctl", "--user", "list")
		cmd.Env = s.env()
		out, err := cmd.Output()
		return err == nil && strings.Contains(string(out), "org.fcitx.Fcitx5")
	}) {
		t.Skipf("fcitx5 didn't start headless; log:\n%s", s.Tail("fcitx5.out", 10))
	}
	s.StartAxiom("sway")
	if !testkit.Eventually(func() bool {
		raw, err := s.ShellCall("inputMethod.get", nil)
		return err == nil && strings.Contains(string(raw), `"running":true`)
	}) {
		t.Skip("the daemon doesn't follow fcitx5 here")
	}
	owner := "Input.keyboard.method.enabled"
	if _, err := s.ShellCall("inputMethod.options", map[string]any{"shareState": "All", "owner": owner}); err != nil {
		t.Fatal(err)
	}
	kinds := map[string]bool{}
	for _, r := range s.footprintRows() {
		kinds[r.Kind] = true
	}
	if !kinds[footprint.KindFcitxConfig] {
		t.Errorf("no fcitx-config row: %v", kinds)
	}
	t.Logf("undo:\n%s", s.Axiom("footprint", "undo", "--all", "--include-system"))
	if rows := s.footprintRows(); len(rows) != 0 {
		t.Errorf("rows left: %+v", rows)
	}
}
