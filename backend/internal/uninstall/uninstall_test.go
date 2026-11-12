package uninstall

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"flag"
	"io/fs"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
	"github.com/axiom-shell/axiom/backend/internal/footprint"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/secrets"
	"github.com/axiom-shell/axiom/backend/internal/session"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

var update = flag.Bool("update", false, "rewrite the golden files")

// fixture is a scratch home: its XDG folders, a runtime folder, and the
// options an uninstall of it takes.
type fixture struct {
	t       *testing.T
	home    string
	runtime string
	env     map[string]string
	o       Options
	// signaled are the pids the portal restart signalled
	signaled *[]int
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	home := t.TempDir()
	runtime, err := os.MkdirTemp("", "uxr")
	if err != nil {
		t.Fatal(err)
	}
	os.Chmod(runtime, 0o700)
	t.Cleanup(func() { os.RemoveAll(runtime) })
	f := &fixture{t: t, home: home, runtime: runtime, env: map[string]string{
		"HOME": home, "XDG_CONFIG_HOME": filepath.Join(home, ".config"), "XDG_STATE_HOME": filepath.Join(home, ".local/state"),
		"XDG_DATA_HOME": filepath.Join(home, ".local/share"), "XDG_CACHE_HOME": filepath.Join(home, ".cache"),
		"XDG_RUNTIME_DIR": runtime, "WAYLAND_DISPLAY": "wayland-t",
	}}
	getenv := func(k string) string { return f.env[k] }
	dirs := xdg.Resolve(getenv)
	var mu sync.Mutex
	f.signaled = new([]int)
	f.o = Options{
		Dirs: dirs, Getenv: getenv, Bin: "/home/x/.local/bin/axiom",
		Ledger: footprint.New(footprint.Options{Dirs: dirs}),
		Session: session.Seams{
			Systemctl: func(context.Context, ...string) (string, error) { return "", errors.New("no systemd here") },
			Spawn:     func(context.Context, []string, []string, string) error { return nil },
			Signal: func(pid int, _ syscall.Signal) error {
				mu.Lock()
				defer mu.Unlock()
				*f.signaled = append(*f.signaled, pid)
				return nil
			},
		},
	}
	return f
}

// write makes a file (and its folders), relative to the home.
func (f *fixture) write(rel, text string) string {
	f.t.Helper()
	p := filepath.Join(f.home, rel)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		f.t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(text), 0o644); err != nil {
		f.t.Fatal(err)
	}
	return p
}

func (f *fixture) read(rel string) string {
	f.t.Helper()
	data, err := os.ReadFile(filepath.Join(f.home, rel))
	if err != nil {
		f.t.Fatal(err)
	}
	return string(data)
}

func (f *fixture) exists(rel string) bool {
	_, err := os.Lstat(filepath.Join(f.home, rel))
	return err == nil
}

// run is Build then Run with the answers.
func (f *fixture) run(a Answers) Report {
	f.t.Helper()
	plan, err := Build(context.Background(), f.o)
	if err != nil {
		f.t.Fatal(err)
	}
	r, err := Run(context.Background(), f.o, plan, a)
	if err != nil {
		f.t.Fatal(err)
	}
	return r
}

// keepAll is the defaults.
var keepAll = Answers{KeepConfig: true, KeepUserContent: true, KeepSecrets: true, UndoInferred: true, RestartPortal: true}

// snapshot is every file of dir: path, mode, link target and the checksum.
func snapshot(t *testing.T, dir string) map[string]string {
	t.Helper()
	out := map[string]string{}
	err := filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		info, err := os.Lstat(path)
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(dir, path)
		entry := info.Mode().String()
		switch {
		case info.Mode()&fs.ModeSymlink != 0:
			to, _ := os.Readlink(path)
			entry += " -> " + to
		case info.Mode().IsRegular():
			data, _ := os.ReadFile(path)
			sum := sha256.Sum256(data)
			entry += " " + string(sum[:8])
		}
		out[rel] = entry
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return out
}

const swayUser = "# my sway\nset $mod Mod4\nbindsym $mod+Return exec foot\n"

// installSh is what install.sh leaves in a sway config: a backup beside it
// and the line at the end.
func (f *fixture) installSh() string {
	f.t.Helper()
	cfg := f.write(".config/sway/config", swayUser+"exec '"+f.o.Bin+"' run\n")
	f.write(".config/sway/config.bak-20261112-101010", swayUser)
	return cfg
}

func TestCompositorConfigNeverDeleted(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	// install.sh made it from the stock default: a copy of it and the line
	cfg := f.installSh()
	f.write(".config/niri/config.kdl", "// stock\nbinds {}\nspawn-sh-at-startup \"'"+f.o.Bin+"' run\"\n")
	f.write(".config/hypr/hyprland.lua", "-- stock\nhl.on(\"hyprland.start\", function() hl.exec_cmd(\"'"+f.o.Bin+"' run\") end) -- axiom\n")
	r := f.run(keepAll)
	if got := f.read(".config/sway/config"); got != swayUser {
		t.Errorf("sway config: %q", got)
	}
	if got := f.read(".config/niri/config.kdl"); got != "// stock\nbinds {}\n" {
		t.Errorf("niri config: %q", got)
	}
	if got := f.read(".config/hypr/hyprland.lua"); got != "-- stock\n" {
		t.Errorf("hyprland config: %q", got)
	}
	if _, err := os.Stat(cfg); err != nil {
		t.Fatal("the config is gone")
	}
	// The backup is kept and listed
	backup := filepath.Join(f.home, ".config/sway/config.bak-20261112-101010")
	if !f.exists(".config/sway/config.bak-20261112-101010") || !slices.Contains(r.Backups, backup) {
		t.Errorf("backup kept: %v, listed in %v", f.exists(".config/sway/config.bak-20261112-101010"), r.Backups)
	}
}

func TestSymlinkedConfigEditedThroughItsLink(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	real := f.write("dotfiles/sway.conf", swayUser+"exec axiom run\n")
	if err := os.Chmod(real, 0o600); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(f.home, ".config/sway/config")
	os.MkdirAll(filepath.Dir(link), 0o755)
	if err := os.Symlink("../../dotfiles/sway.conf", link); err != nil {
		t.Fatal(err)
	}
	f.run(keepAll)
	if to, _ := os.Readlink(link); to != "../../dotfiles/sway.conf" {
		t.Errorf("the link: %q", to)
	}
	if got := f.read("dotfiles/sway.conf"); got != swayUser {
		t.Errorf("the target: %q", got)
	}
	if info, _ := os.Stat(real); info.Mode().Perm() != 0o600 {
		t.Errorf("mode %v", info.Mode())
	}
}

func TestDesktopEntriesOnlyAxioms(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	mine := f.write(".local/share/applications/axiom-settings.desktop", "[Desktop Entry]\nExec=/home/x/.local/bin/axiom open settings\n")
	f.write(".local/share/applications/axiom-foo.desktop", "[Desktop Entry]\nExec=/usr/bin/other --axiom\n")
	f.write(".local/share/applications/firefox.desktop", "[Desktop Entry]\nExec=firefox\n")
	f.write(".local/share/xdg-desktop-portal/portals/axiom.portal", "[portal]\n")
	f.write(".local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.axiom.service", "[D-BUS Service]\nExec=/home/x/.local/bin/axiom portal\n")
	f.run(keepAll)
	if _, err := os.Stat(mine); err == nil {
		t.Error("axiom's entry stayed")
	}
	for _, rel := range []string{".local/share/applications/axiom-foo.desktop", ".local/share/applications/firefox.desktop"} {
		if !f.exists(rel) {
			t.Errorf("%s was deleted", rel)
		}
	}
	// The portal files go, and the folders only they were in
	for _, rel := range []string{".local/share/xdg-desktop-portal", ".local/share/dbus-1"} {
		if f.exists(rel) {
			t.Errorf("%s stayed", rel)
		}
	}
}

func TestApprovalsGoEvenWhenConfigKept(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	f.write(".local/state/axiom/ui/takeover.json", `{"approved":["sway"]}`)
	f.write(".local/state/axiom/ui/onboarding.json", `{}`)
	f.write(".local/state/axiom/session.json", `{}`)
	f.write(".local/state/axiom/log/daemon.log", "x")
	f.write(".local/state/axiom/dev/bin", "x")
	f.write(".config/axiom/config.json", `{"version":1}`)
	f.write(".config/axiom/saved/a.json", `{}`)
	f.write(".local/share/axiom/wallpapers/a.png", "png")
	f.write(".cache/axiom/thumbs/a", "x")
	f.write(".local/state/axiom/secrets.json", `{"k":"v"}`)
	r := f.run(keepAll)
	for _, gone := range []string{".local/state/axiom/ui/takeover.json", ".local/state/axiom/session.json", ".local/state/axiom/log", ".local/state/axiom/dev", ".cache/axiom"} {
		if f.exists(gone) {
			t.Errorf("%s stayed", gone)
		}
	}
	for _, kept := range []string{".local/state/axiom/ui/onboarding.json", ".config/axiom/config.json", ".config/axiom/saved/a.json", ".local/share/axiom/wallpapers/a.png", ".local/state/axiom/secrets.json"} {
		if !f.exists(kept) {
			t.Errorf("%s was removed", kept)
		}
	}
	if len(r.Left) < 2 {
		t.Errorf("the kept folders aren't in the report: %+v", r.Left)
	}
	// Purged: all of it, the saved passwords file too
	f.run(Answers{UndoInferred: true})
	for _, gone := range []string{".config/axiom", ".local/share/axiom", ".local/state/axiom"} {
		if f.exists(gone) {
			t.Errorf("%s stayed after --purge-all", gone)
		}
	}
}

func TestPurgeKeepsSecretsFileWhenAsked(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	f.write(".local/state/axiom/secrets.json", `{"k":"v"}`)
	f.write(".local/state/axiom/ui/x.json", `{}`)
	f.run(Answers{KeepSecrets: true})
	if !f.exists(".local/state/axiom/secrets.json") || f.exists(".local/state/axiom/ui") {
		t.Error("the state purge didn't keep exactly the secrets file")
	}
}

func TestLedgerKeptWhileRowsRemain(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	l := f.o.Ledger
	own := f.write(".config/kitty/axiom.conf", "colors")
	sys := f.write(".config/sys.conf", "x")
	for _, c := range []struct {
		path   string
		system bool
	}{{own, false}, {sys, true}} {
		id, err := l.Begin(footprint.Row{Kind: footprint.KindFile, Target: c.path, System: c.system, Owner: "T"}, footprint.PriorAbsent)
		if err != nil {
			t.Fatal(err)
		}
		l.Done(id, nil)
	}
	f.write(".local/state/axiom/ui/takeover.json", "{}")
	// The system row is kept (no RestoreSystem): so is the ledger
	r := f.run(Answers{UndoInferred: true})
	if f.exists(".config/kitty/axiom.conf") {
		t.Error("the plain row wasn't undone")
	}
	if !f.exists(".config/sys.conf") {
		t.Error("the system row was undone without the switch")
	}
	if !f.exists(".local/state/axiom/footprint.json") || f.exists(".local/state/axiom/ui") {
		t.Error("the ledger must stay while it has rows, and the rest of the state go")
	}
	if rows := footprint.New(footprint.Options{Dirs: f.o.Dirs}).Rows(); len(rows) != 1 {
		t.Errorf("rows: %+v", rows)
	}
	kept := false
	for _, i := range r.Left {
		kept = kept || strings.Contains(i.Path, "sys.conf")
	}
	if !kept {
		t.Errorf("the kept row isn't reported: %+v", r.Left)
	}
	// With the switch, it's undone and the ledger goes
	f.run(Answers{UndoInferred: true, RestoreSystem: true})
	if f.exists(".config/sys.conf") || f.exists(".local/state/axiom") {
		t.Error("RestoreSystem didn't undo the row and clear the state")
	}
}

func TestBackupsListedNeverTouched(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	kitty := f.write(".config/kitty/kitty.conf", "font_size 12\n")
	bak := f.write(".config/kitty/kitty.conf.axiom-bak-20260101-000000", "old\n")
	f.write(".config/hypr/hyprland.lua", "-- mine\n")
	b1 := f.write(".config/hypr/hyprland.lua.axiom-backup-20260101-000000", "a")
	b2 := f.write(".config/hypr/user/00-previous.lua.axiom-backup-20260101-000000", "b")
	b3 := f.write(".config/hypr/user/.backups/x.lua", "c")
	b4 := f.write(".config/sway/config.bak-20260102-030405", "d")
	b5 := f.write(".config/hypr/.axiom-claimed", "previous=\nbackup=\n")
	f.write(".config/sway/config", swayUser)
	f.write(".config/sway/other.bak", "not dated")
	l := f.o.Ledger
	id, err := l.Begin(footprint.Row{Kind: footprint.KindFile, Target: filepath.Join(f.home, ".config/kitty/axiom.conf"), Owner: "T",
		Hookup: &footprint.HookupRec{Backup: bak}}, footprint.PriorAbsent)
	if err != nil {
		t.Fatal(err)
	}
	l.Done(id, nil)
	before := snapshot(t, filepath.Join(f.home, ".config"))
	r := f.run(keepAll)
	for _, b := range []string{bak, b1, b2, filepath.Dir(b3), b4, b5} {
		if !slices.Contains(r.Backups, b) {
			t.Errorf("%s isn't listed in %v", b, r.Backups)
		}
		if !exists(b) {
			t.Errorf("%s was deleted", b)
		}
	}
	if slices.Contains(r.Backups, filepath.Join(f.home, ".config/sway/other.bak")) {
		t.Error("an undated .bak is listed")
	}
	_ = kitty
	after := snapshot(t, filepath.Join(f.home, ".config"))
	for path, entry := range before {
		if strings.Contains(path, "bak") || strings.Contains(path, "backup") || strings.Contains(path, "claimed") || path == "kitty/kitty.conf" {
			if after[path] != entry {
				t.Errorf("%s changed: %q -> %q", path, entry, after[path])
			}
		}
	}
}

func TestGreeterNote(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	root := t.TempDir()
	f.o.Root = root
	if p, _ := Build(context.Background(), f.o); p.Greeter != nil {
		t.Fatalf("a note without a greeter: %+v", p.Greeter)
	}
	os.MkdirAll(filepath.Join(root, "etc/greetd"), 0o755)
	os.WriteFile(filepath.Join(root, "etc/greetd/config.toml"), []byte("[default_session]\ncommand = \"/usr/share/axiom-greeter/data/greeter/start.sh\"\n"), 0o644)
	p, _ := Build(context.Background(), f.o)
	if p.Greeter == nil || len(p.Greeter.Paths) != 1 || !strings.Contains(p.Greeter.Text, "Settings → Login screen → Uninstall") ||
		!strings.Contains(p.Greeter.Text, "axiom greeter-install uninstall") {
		t.Fatalf("%+v", p.Greeter)
	}
	// Another greetd config isn't axiom's
	os.WriteFile(filepath.Join(root, "etc/greetd/config.toml"), []byte("command = \"tuigreet\"\n"), 0o644)
	os.MkdirAll(filepath.Join(root, "usr/share/axiom-greeter"), 0o755)
	if p, _ := Build(context.Background(), f.o); p.Greeter == nil || len(p.Greeter.Paths) != 1 {
		t.Errorf("%+v", p.Greeter)
	}
	// Run reports it, and removes nothing of it
	r := f.run(keepAll)
	if r.Greeter == nil || !exists(filepath.Join(root, "usr/share/axiom-greeter")) {
		t.Error("the note or the greeter's folder")
	}
}

func TestBuildIsReadOnly(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	f.installSh()
	f.write(".config/niri/config.kdl", "// Generated by axiom\nbinds {}\n")
	f.write(".config/hypr/xdph.conf", "screencopy:custom_picker_binary = /home/x/.local/bin/axiom\n")
	f.write(".local/share/applications/axiom-settings.desktop", "[Desktop Entry]\nExec=axiom open\n")
	f.write(".local/share/xdg-desktop-portal/portals/axiom.portal", "[portal]\n")
	f.write(".local/state/axiom/ui/takeover.json", "{}")
	f.write(".config/axiom/config.json", "{}")
	f.write(".cache/axiom/x", "x")
	l := f.o.Ledger
	g := f.write(".config/g.conf", "x")
	id, _ := l.Begin(footprint.Row{Kind: footprint.KindFile, Target: g, Owner: "T"}, footprint.PriorAbsent)
	l.Done(id, nil)
	f.o.Inferred = func(context.Context) ([]footprint.Row, []footprint.Row) {
		return nil, []footprint.Row{{Kind: footprint.KindFile, Target: filepath.Join(f.home, ".config/old.conf"), Prior: footprint.Absent()}}
	}
	f.write(".config/old.conf", "x")
	before := snapshot(t, f.home)
	plan, err := Build(context.Background(), f.o)
	if err != nil {
		t.Fatal(err)
	}
	if after := snapshot(t, f.home); !mapsEqual(before, after) {
		t.Errorf("Build changed the home:\nbefore %v\nafter  %v", before, after)
	}
	steps := map[string]int{}
	for _, a := range plan.Actions {
		steps[a.Step]++
	}
	for _, want := range []string{"managed", "ledger", "lines", "files", "portal", "folders"} {
		if steps[want] == 0 {
			t.Errorf("no %s action in %+v", want, plan.Actions)
		}
	}
	if plan.Counts.Inferred != 1 || !plan.Counts.Portal {
		t.Errorf("counts %+v", plan.Counts)
	}
	// Without a ledger file nothing creates one
	f2 := newFixture(t)
	f2.installSh()
	before = snapshot(t, f2.home)
	if _, err := Build(context.Background(), f2.o); err != nil {
		t.Fatal(err)
	}
	if after := snapshot(t, f2.home); !mapsEqual(before, after) {
		t.Errorf("Build (no ledger) changed the home: %v", after)
	}
}

func mapsEqual(a, b map[string]string) bool {
	if len(a) != len(b) {
		return false
	}
	for k, v := range a {
		if b[k] != v {
			return false
		}
	}
	return true
}

func TestRefusesWhileRunning(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	cfg := f.installSh()
	before := snapshot(t, f.home)
	dir := filepath.Join(f.runtime, "axiom", "wayland-t")
	os.MkdirAll(dir, 0o700)
	lock, err := fsx.TryLock(filepath.Join(dir, "daemon.lock"))
	if err != nil {
		t.Fatal(err)
	}
	defer lock.Release()
	// (flock conflicts across open descriptions, in one process too)
	plan, err := Build(context.Background(), f.o)
	if err != nil || !slices.Equal(plan.Running, []string{"wayland-t"}) {
		t.Fatalf("running %v, %v", plan.Running, err)
	}
	_, err = Run(context.Background(), f.o, plan, keepAll)
	if axerr.KindOf(err) != axerr.Running || !strings.Contains(err.Error(), "quit it, or pass --stop") || !strings.Contains(err.Error(), "wayland-t") {
		t.Fatalf("%v", err)
	}
	if got, _ := os.ReadFile(cfg); !strings.Contains(string(got), "run") {
		t.Error("something changed")
	}
	// The daemon's own plan doesn't count itself
	f.o.ExcludeDisplay = "wayland-t"
	if plan, _ := Build(context.Background(), f.o); len(plan.Running) != 0 {
		t.Errorf("%v", plan.Running)
	}
	if after := snapshot(t, f.home); !mapsEqual(before, after) {
		t.Error("the home changed")
	}
}

func TestStopWaitsForLocks(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	dir := filepath.Join(f.runtime, "axiom", "wayland-t")
	os.MkdirAll(dir, 0o700)
	// A daemon: a socket answering daemon.shutdown, in a process of its own
	// holding both locks until it's told
	sock := filepath.Join(dir, "axiom.sock")
	ln, err := net.Listen("unix", sock)
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	held := exec.Command("sh", "-c", `exec 8>"$0/daemon.lock" 9>"$0/guard.lock"; flock -n 8 && flock -n 9 && echo held && read x`, dir)
	stdin, _ := held.StdinPipe()
	out, _ := held.StdoutPipe()
	if err := held.Start(); err != nil {
		t.Skipf("no flock(1): %v", err)
	}
	defer func() { held.Process.Kill(); held.Wait() }()
	buf := make([]byte, 5)
	if _, err := out.Read(buf); err != nil || string(buf) != "held\n" {
		t.Skipf("the helper didn't take the locks: %q %v", buf, err)
	}
	var told []string
	f.o.Shutdown = func(_ context.Context, socket string) error {
		told = append(told, socket)
		// The daemon lets go a moment after it's told
		go func() {
			time.Sleep(300 * time.Millisecond)
			stdin.Write([]byte("\n"))
		}()
		return nil
	}
	start := time.Now()
	if err := Stop(context.Background(), f.o); err != nil {
		t.Fatal(err)
	}
	if took := time.Since(start); took < 250*time.Millisecond {
		t.Errorf("Stop didn't wait for the locks: %v", took)
	}
	if !slices.Equal(told, []string{sock}) {
		t.Errorf("told %v", told)
	}
	if len(f.o.running()) != 0 {
		t.Error("still running")
	}
	// Nothing to stop: nothing asked
	told = nil
	if err := Stop(context.Background(), f.o); err != nil || len(told) != 0 {
		t.Errorf("%v %v", err, told)
	}
}

// every folder is removed through the guard, which knows the bases
func TestRemoveAllGuard(t *testing.T) {
	t.Parallel()
	refused := func(t *testing.T, o Options, what string) {
		t.Helper()
		for _, f := range o.folders() {
			if err := o.guard(f); axerr.KindOf(err) != axerr.Refused {
				t.Errorf("%s: %s (%s under %s): %v", what, f.Kind, f.Path, f.Base, err)
			}
		}
	}
	f := newFixture(t)
	for _, folder := range f.o.folders() {
		if err := f.o.guard(folder); err != nil {
			t.Errorf("%s: %v", folder.Kind, err)
		}
	}
	// a folder that isn't axiom's, or isn't under the base it names
	for name, bad := range map[string]folder{
		"home itself":      {Path: f.home, Kind: "config", Base: filepath.Dir(f.home)},
		"not axiom":        {Path: filepath.Join(f.home, ".config/kitty"), Kind: "config", Base: filepath.Join(f.home, ".config")},
		"too deep":         {Path: filepath.Join(f.home, ".config/axiom/axiom"), Kind: "config", Base: filepath.Join(f.home, ".config")},
		"another base":     {Path: filepath.Join(f.home, ".config/axiom"), Kind: "state", Base: filepath.Join(f.home, ".config")},
		"root":             {Path: "/axiom", Kind: "config", Base: "/"},
		"relative":         {Path: "axiom", Kind: "config", Base: "."},
		"dotdots":          {Path: filepath.Join(f.home, ".config/../axiom"), Kind: "config", Base: filepath.Join(f.home, ".config/..")},
		"a base not known": {Path: "/opt/axiom", Kind: "data", Base: "/opt"},
	} {
		if err := f.o.guard(bad); axerr.KindOf(err) != axerr.Refused {
			t.Errorf("%s: %v", name, err)
		}
	}
	// XDG_RUNTIME_DIR=$HOME: the runtime folder would be ~/axiom
	g := newFixture(t)
	g.env["XDG_RUNTIME_DIR"] = g.home
	os.MkdirAll(filepath.Join(g.home, "axiom"), 0o755)
	var runtime *folder
	for _, fo := range g.o.folders() {
		if fo.Kind == "runtime" {
			runtime = &fo
		}
	}
	if runtime == nil || axerr.KindOf(g.o.guard(*runtime)) != axerr.Refused {
		t.Errorf("a runtime folder that is the home: %+v", runtime)
	}
	// XDG_DATA_HOME=$HOME is no better
	h := newFixture(t)
	h.env["XDG_DATA_HOME"] = h.home
	for _, fo := range h.o.folders() {
		if fo.Kind == "data" && axerr.KindOf(h.o.guard(fo)) != axerr.Refused {
			t.Errorf("a data folder under the home: %+v", fo)
		}
	}
	// A relative HOME
	r := newFixture(t)
	r.env["HOME"] = "relative/home"
	for _, k := range []string{"XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME"} {
		delete(r.env, k)
	}
	r.o.Dirs = xdg.Resolve(r.o.Getenv)
	refused(t, r.o, "a relative HOME")
	if _, err := os.Stat(f.home); err != nil {
		t.Fatal("the home folder is gone")
	}
}

func TestRuntimeFolderRemovedOnlyWhenPrivate(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	root := filepath.Join(f.runtime, "axiom")
	os.MkdirAll(filepath.Join(root, "wayland-1"), 0o700)
	os.WriteFile(filepath.Join(root, "stray-file"), []byte("x"), 0o600)
	var rt folder
	for _, fo := range f.o.folders() {
		if fo.Kind == "runtime" {
			rt = fo
		}
	}
	os.Chmod(root, 0o755)
	if err := f.o.removeAxiomDir(rt); axerr.KindOf(err) != axerr.Refused {
		t.Errorf("a runtime folder with mode 755: %v", err)
	}
	os.Chmod(root, 0o700)
	// Display folders go; a file that isn't one keeps the folder
	if err := f.o.removeAxiomDir(rt); err == nil {
		t.Log("(the stray file kept the folder)")
	}
	if exists(filepath.Join(root, "wayland-1")) {
		t.Error("a display folder stayed")
	}
	if !exists(filepath.Join(root, "stray-file")) {
		t.Error("a file that isn't a display folder was removed")
	}
	// A link in its place is refused
	os.RemoveAll(root)
	other := t.TempDir()
	os.Symlink(other, root)
	if err := f.o.removeAxiomDir(rt); axerr.KindOf(err) != axerr.Refused {
		t.Errorf("a link: %v", err)
	}
	if !exists(other) {
		t.Fatal("the link's target is gone")
	}
}

func TestFoldersThatAreLinksAreLeft(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	target := t.TempDir()
	os.WriteFile(filepath.Join(target, "keep"), []byte("x"), 0o644)
	os.MkdirAll(filepath.Join(f.home, ".config"), 0o755)
	if err := os.Symlink(target, filepath.Join(f.home, ".config/axiom")); err != nil {
		t.Fatal(err)
	}
	r := f.run(Answers{UndoInferred: true})
	if !exists(filepath.Join(target, "keep")) || !exists(filepath.Join(f.home, ".config/axiom")) {
		t.Error("a linked config folder was followed or removed")
	}
	found := false
	for _, i := range r.Left {
		found = found || strings.Contains(i.Detail, "a link to "+target)
	}
	if !found {
		t.Errorf("not said: %+v", r.Left)
	}
}

// secret-tool prints the value it clears: none of it reaches the output,
// and the keyring is only counted by object paths
func TestSecretsNeverPrinted(t *testing.T) {
	// Not parallel: the program it writes can't be run while another test
	// forks ("text file busy")
	f := newFixture(t)
	tool := f.write("bin/secret-tool", "#!/bin/sh\necho \"$@\" > \"$0.args\"\necho SECRET-VALUE-12345\necho SECRET-VALUE-12345 >&2\n")
	os.Chmod(tool, 0o755)
	bus := dbustest.New(t)
	svc, err := dbus.Dial(context.Background(), bus.Address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { svc.Close() })
	svc.RequestName(context.Background(), "org.freedesktop.secrets", 0)
	asked := map[string]string{}
	var askedMu sync.Mutex
	svc.Export("/org/freedesktop/secrets", dbus.Interface{Name: "org.freedesktop.Secret.Service", Methods: map[string]dbus.Method{
		"SearchItems": {In: "a{ss}", Out: "aoao", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			askedMu.Lock()
			for k, v := range m.Body[0].(map[any]any) {
				asked[k.(string)] = v.(string)
			}
			askedMu.Unlock()
			return []any{[]dbus.ObjectPath{"/org/freedesktop/secrets/collection/login/1"}, []dbus.ObjectPath{"/org/freedesktop/secrets/collection/login/2", "/org/freedesktop/secrets/collection/login/3"}}, nil
		}},
	}})
	f.o.Secrets = SecretsSeam{
		Count: func(ctx context.Context) (int, error) {
			conn, err := dbus.Dial(ctx, bus.Address, dbus.Options{})
			if err != nil {
				return 0, err
			}
			defer conn.Close()
			return secrets.Count(ctx, conn)
		},
		ClearAll: func(ctx context.Context) error {
			return secrets.New(secrets.Options{StateDir: filepath.Join(f.home, ".local/state/axiom"), SecretTool: tool}).ClearAll(ctx)
		},
	}
	f.write(".local/state/axiom/secrets.json", `{"k":"SECRET-VALUE-12345"}`)
	plan, err := Build(context.Background(), f.o)
	if err != nil || plan.Counts.Secrets != 3 {
		t.Fatalf("count %d: %v", plan.Counts.Secrets, err)
	}
	askedMu.Lock()
	if asked["service"] != "axiom" || len(asked) != 1 {
		t.Errorf("asked %v", asked)
	}
	askedMu.Unlock()
	r := f.run(Answers{UndoInferred: true})
	data, _ := json.Marshal([]any{plan, r})
	if strings.Contains(string(data), "SECRET-VALUE-12345") {
		t.Error("a secret is in the plan or the report")
	}
	args, _ := os.ReadFile(tool + ".args")
	if strings.TrimSpace(string(args)) != "clear service axiom" {
		t.Errorf("secret-tool ran with %q", args)
	}
	if f.exists(".local/state/axiom/secrets.json") {
		t.Error("the file of secrets stayed")
	}
	// Kept: nothing cleared
	os.Remove(tool + ".args")
	f.write(".local/state/axiom/secrets.json", `{"k":"v"}`)
	f.run(keepAll)
	if exists(tool+".args") || !f.exists(".local/state/axiom/secrets.json") {
		t.Error("kept secrets were touched")
	}
}

func TestPortalRestartOnlyWhenAPortalThingChanged(t *testing.T) {
	t.Parallel()
	// A process of this session's runtime folder for the bus to name
	for _, c := range []struct {
		name    string
		setup   func(f *fixture)
		answers Answers
		want    bool
		note    bool
	}{
		{"portal file deleted", func(f *fixture) { f.write(".local/share/xdg-desktop-portal/portals/axiom.portal", "x") }, keepAll, true, false},
		{"xdph line removed", func(f *fixture) {
			f.write(".config/hypr/xdph.conf", "screencopy:custom_picker_binary = /usr/bin/axiom\n")
		}, keepAll, true, false},
		{"only a desktop entry", func(f *fixture) {
			f.write(".local/share/applications/axiom-a.desktop", "[Desktop Entry]\nExec=axiom\n")
		}, keepAll, false, false},
		{"a sway line", func(f *fixture) { f.installSh() }, keepAll, false, false},
		{"declined", func(f *fixture) { f.write(".local/share/xdg-desktop-portal/portals/axiom.portal", "x") },
			Answers{KeepConfig: true, KeepUserContent: true, KeepSecrets: true, UndoInferred: true}, false, true},
	} {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			f := newFixture(t)
			c.setup(f)
			sleeper := exec.Command("sleep", "30")
			sleeper.Env = []string{"XDG_RUNTIME_DIR=" + f.runtime}
			if err := sleeper.Start(); err != nil {
				t.Fatal(err)
			}
			defer func() { sleeper.Process.Kill(); sleeper.Wait() }()
			f.o.DialBus = func(context.Context) (session.Bus, func()) {
				return fakeBus{pid: uint32(sleeper.Process.Pid)}, func() {}
			}
			r := f.run(c.answers)
			signalled := slices.Contains(*f.signaled, sleeper.Process.Pid)
			if signalled != c.want {
				t.Errorf("portal signalled: %v, want %v (%v)", signalled, c.want, *f.signaled)
			}
			if got := len(r.Notes) > 0; got != c.note {
				t.Errorf("notes %v", r.Notes)
			}
		})
	}
}

// fakeBus names pid as the owner of every name but systemd's
type fakeBus struct{ pid uint32 }

func (b fakeBus) NameOwner(_ context.Context, name string) (string, error) {
	if name == "org.freedesktop.systemd1" {
		return "", nil
	}
	return ":1.1", nil
}

func (b fakeBus) ConnectionPID(context.Context, string) (uint32, error) { return b.pid, nil }

func TestManagedConfigReleasedWithoutAStartLine(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	f.write(".config/hypr/hyprland.lua", "-- Generated by axiom\nhl.config({})\n")
	f.write(".config/hypr/user/mine.lua", "-- mine\n")
	f.write(".local/state/axiom/ui/takeover.json", `{"approved":["hyprland"]}`)
	plan, _ := Build(context.Background(), f.o)
	managed := 0
	for _, a := range plan.Actions {
		if a.Step == "managed" {
			managed++
		}
	}
	if managed != 1 {
		t.Fatalf("%+v", plan.Actions)
	}
	r := f.run(keepAll)
	got := f.read(".config/hypr/hyprland.lua")
	if strings.HasPrefix(got, "-- Generated by axiom") || startsAxiom.MatchString(got) {
		t.Errorf("not given back as a plain config:\n%s", got)
	}
	if !f.exists(".config/hypr/user/mine.lua") {
		t.Error("user/ is the user's")
	}
	done := false
	for _, i := range r.Done {
		done = done || i.Step == "managed"
	}
	if !done {
		t.Errorf("%+v", r)
	}
}

func TestLinesNearMissesListedNotRemoved(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	text := "set $mod Mod4\nexec_always axiom run\nexec '/x/axiom' run --debug\n# exec axiom run\nexec axiom-foo run\nexec /x/axiom run\n"
	f.write(".config/sway/config", text)
	r := f.run(keepAll)
	if got := f.read(".config/sway/config"); got != strings.Replace(text, "exec /x/axiom run\n", "", 1) {
		t.Errorf("%q", got)
	}
	var listed []int
	for _, m := range r.Manual {
		listed = append(listed, m.Line)
	}
	if !slices.Equal(listed, []int{2, 3, 4}) {
		t.Errorf("listed lines %v: %+v", listed, r.Manual)
	}
}

// A managed config that the release couldn't give back (a link into
// dotfiles, a git repository) is axiom's still: nothing edits it
func TestBlockedManagedConfigIsNotEdited(t *testing.T) {
	t.Parallel()
	managed := "# Generated by axiom\nset $mod Mod4\nexec '/x/axiom' run\n"
	t.Run("a link", func(t *testing.T) {
		t.Parallel()
		f := newFixture(t)
		real := f.write("dotfiles/sway.conf", managed)
		link := filepath.Join(f.home, ".config/sway/config")
		os.MkdirAll(filepath.Dir(link), 0o755)
		if err := os.Symlink(real, link); err != nil {
			t.Fatal(err)
		}
		r := f.run(keepAll)
		if got, _ := os.ReadFile(real); string(got) != managed {
			t.Errorf("edited through its link:\n%s", got)
		}
		if len(r.Left) == 0 || !slices.ContainsFunc(r.Left, func(i Item) bool { return i.Step == "managed" }) {
			t.Errorf("the failed release isn't in Left: %+v", r.Left)
		}
	})
	t.Run("a git repository", func(t *testing.T) {
		t.Parallel()
		f := newFixture(t)
		path := f.write(".config/hypr/hyprland.lua", "-- Generated by axiom\nhl.config({})\nhl.on(\"hyprland.start\", function() hl.exec_cmd(\"'/x/axiom' run\") end) -- axiom\n")
		want, _ := os.ReadFile(path)
		if out, err := exec.Command("git", "-C", filepath.Dir(path), "init", "-q").CombinedOutput(); err != nil {
			t.Skipf("no git: %v %s", err, out)
		}
		r := f.run(keepAll)
		if got, _ := os.ReadFile(path); string(got) != string(want) {
			t.Errorf("edited in a git repository:\n%s", got)
		}
		if !slices.ContainsFunc(r.Left, func(i Item) bool { return i.Step == "managed" }) {
			t.Errorf("the failed release isn't in Left: %+v", r.Left)
		}
	})
}

// A ledger that can't be read is left whole, with what the state folder
// keeps of it, and said
func TestUnreadableLedgerIsKept(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	f.write(".local/state/axiom/footprint.json", "{not json")
	f.write(".local/state/axiom/footprint.json.bad-20260101-000000", "old")
	f.write(".local/state/axiom/ui/x.json", "{}")
	plan, err := Build(context.Background(), f.o)
	if err != nil || !slices.ContainsFunc(plan.Actions, func(a Action) bool { return a.Kind == "unreadable" }) {
		t.Fatalf("%v %+v", err, plan.Actions)
	}
	if got := f.read(".local/state/axiom/footprint.json"); got != "{not json" {
		t.Fatal("Build changed the ledger")
	}
	r := f.run(Answers{UndoInferred: true})
	if f.read(".local/state/axiom/footprint.json") != "{not json" || !f.exists(".local/state/axiom/footprint.json.bad-20260101-000000") {
		t.Error("an unreadable ledger or its aside copy was removed")
	}
	if f.exists(".local/state/axiom/ui") {
		t.Error("the rest of the state stayed")
	}
	kept := 0
	for _, i := range r.Left {
		if strings.Contains(i.Detail, "can't be read") || strings.Contains(i.Detail, "couldn't be read") {
			kept++
		}
	}
	if kept < 2 {
		t.Errorf("Left: %+v", r.Left)
	}
}

// Without a ledger object at all (nil) the files stay too
func TestNoLedgerKeepsItsFiles(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	f.o.Ledger = nil
	f.write(".local/state/axiom/footprint.json", `{"version":1,"rows":[]}`)
	f.run(Answers{UndoInferred: true})
	if !f.exists(".local/state/axiom/footprint.json") {
		t.Error("the ledger went with nobody to read it")
	}
}

// A secrets.json is something to ask about and to say when kept
func TestSecretsFileIsAskedAboutAndSaidWhenKept(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	f.write(".local/state/axiom/secrets.json", `{"k":"v"}`)
	plan, _ := Build(context.Background(), f.o)
	if !plan.Counts.SecretsFile {
		t.Fatalf("%+v", plan.Counts)
	}
	got, _ := Answer(Flags{}, plan.Counts, true, func(q Question, def bool) bool { return def })
	if !got.KeepSecrets {
		t.Error("the default isn't to keep")
	}
	asked := false
	Answer(Flags{}, plan.Counts, true, func(q Question, def bool) bool { asked = asked || q.Field == FieldKeepSecrets; return def })
	if !asked {
		t.Error("a secrets.json alone didn't ask the question")
	}
	r := f.run(keepAll)
	if !slices.ContainsFunc(r.Left, func(i Item) bool {
		return strings.HasSuffix(i.Path, "secrets.json") && strings.Contains(i.Detail, "kept")
	}) {
		t.Errorf("not said: %+v", r.Left)
	}
}

// Items still in the keyring after the clear are said, and a clear that
// failed with nothing left is no failure
func TestKeyringLeftoversAreSaid(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		name  string
		clear error
		left  int
		want  string
	}{
		{"all gone", nil, 0, "done"},
		{"some stayed", nil, 2, "left"},
		{"failed, items stayed", errors.New("locked"), 1, "left"},
		{"failed, nothing left", errors.New("exit 1"), 0, "done"},
	} {
		t.Run(c.name, func(t *testing.T) {
			f := newFixture(t)
			f.o.Secrets = SecretsSeam{
				Count:    func(context.Context) (int, error) { return c.left, nil },
				ClearAll: func(context.Context) error { return c.clear },
			}
			r := f.run(Answers{UndoInferred: true})
			var done, left bool
			for _, i := range r.Done {
				done = done || i.Step == "secrets"
			}
			for _, i := range r.Left {
				left = left || i.Step == "secrets"
			}
			if (c.want == "done") != done || (c.want == "left") != left {
				t.Errorf("done %v left %v: %+v", done, left, r)
			}
		})
	}
}

// Without a runtime folder, nobody can say whether axiom runs
func TestRefusesWithoutARuntimeFolder(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	delete(f.env, "XDG_RUNTIME_DIR")
	f.o.RunUserDir = t.TempDir()
	if _, err := Run(context.Background(), f.o, Plan{}, keepAll); axerr.KindOf(err) != axerr.Unavailable {
		t.Errorf("%v", err)
	}
}

// A guard.lock held (a guard still at work) counts as running
func TestGuardLockCountsAsRunning(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	dir := filepath.Join(f.runtime, "axiom", "wayland-t")
	os.MkdirAll(dir, 0o700)
	lock, err := fsx.TryLock(filepath.Join(dir, "guard.lock"))
	if err != nil {
		t.Fatal(err)
	}
	defer lock.Release()
	if got := f.o.running(); !slices.Equal(got, []string{"wayland-t"}) {
		t.Errorf("%v", got)
	}
}

func TestDesktopExecIsReadWithItsQuoting(t *testing.T) {
	t.Parallel()
	for in, want := range map[string]string{
		"[Desktop Entry]\nExec=/usr/bin/axiom open x\n": "/usr/bin/axiom",
		"Exec=\"/home/my dir/bin/axiom\" open\n":        "/home/my dir/bin/axiom",
		"Exec=\"/h/a \\\"x\\\"/axiom\" open\n":          `/h/a "x"/axiom`,
		"Exec=true %f\nExec=axiom\n":                    "true",
		"[Desktop Entry]\nName=x\n":                     "",
	} {
		if got := execBinary([]byte(in)); got != want {
			t.Errorf("%q: %q, want %q", in, got, want)
		}
	}
}
