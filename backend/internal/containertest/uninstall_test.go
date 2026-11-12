//go:build container

package containertest

import (
	"encoding/json"
	"errors"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// The uninstall's round trip (docs/dev/backend/uninstall.md): install.sh as a
// user would run it (the clone, the binary built from it, desktop entries,
// the portal's files, the autostart lines), axiom run from that install with
// everything applied, then `install.sh --uninstall --yes --purge-all
// --restore-system`, and the home compared with what it was.

// uninstallSnapshotSkips are what the harness itself puts in the home (the
// bin of its fake programs, glib's keyfile settings, the keyring it starts).
// Everything else is compared, axiom's own folders and the cache included.
var uninstallSnapshotSkips = []string{"bin", ".config/glib-2.0", ".local/share/keyrings"}

// sudoStub refuses: nothing here escalates (the image has every package
// install.sh would ask for)
const sudoStub = "echo \"sudo refused: no escalation in the container tests\" >&2; exit 1"

// installRepo is a bare clone of the snapshot's tree, with its one commit:
// what install.sh clones (AXIOM_REPO). The generated files, ignored by git,
// are built by install.sh itself.
func installRepo(t *testing.T) string {
	t.Helper()
	src := os.Getenv("AXIOM_SRC")
	work := filepath.Join(t.TempDir(), "work")
	run := func(dir string, args ...string) {
		cmd := exec.Command(args[0], args[1:]...)
		cmd.Dir = dir
		cmd.Env = append(os.Environ(), "GIT_CONFIG_GLOBAL=/dev/null", "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@t", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@t")
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("%v: %v\n%s", args, err, out)
		}
	}
	run("", "cp", "-a", src, work)
	run(work, "git", "init", "-q", "-b", "main")
	run(work, "git", "add", "-A")
	run(work, "git", "commit", "-q", "-m", "snapshot")
	bare := filepath.Join(t.TempDir(), "axiom.git")
	run("", "git", "clone", "-q", "--bare", work, bare)
	return bare
}

// RunInstallSh runs the snapshot's install.sh as the session's user, with
// --yes and --compositor sway and args: its clone is of the snapshot, the
// official builds are out of reach (so it builds from source with go), and
// sudo refuses.
func (s *Session) RunInstallSh(repo string, args ...string) (string, error) {
	s.t.Helper()
	script := filepath.Join(os.Getenv("AXIOM_SRC"), "install.sh")
	cmd := exec.Command("bash", append([]string{script, "--yes", "--compositor", "sway"}, args...)...)
	cmd.Env = s.env("AXIOM_REPO=file://"+repo, "AXIOM_RELEASES=http://127.0.0.1:9/none",
		"GOMODCACHE="+os.Getenv("GOMODCACHE"), "GOCACHE="+filepath.Join(filepath.Dir(os.Getenv("GOMODCACHE")), "go-build"), "GOTOOLCHAIN=local")
	out, err := cmd.CombinedOutput()
	if werr := os.WriteFile(filepath.Join(s.Out, "install.sh.out"), out, 0o644); werr != nil {
		s.t.Log(werr)
	}
	return string(out), err
}

// UseInstalled makes the session run (and ask) the axiom install.sh built,
// from the tree it cloned.
func (s *Session) UseInstalled() {
	s.t.Helper()
	s.bin = filepath.Join(s.Home, ".local/bin/axiom")
	s.tree = filepath.Join(s.Data, "axiom-shell")
	if _, err := os.Stat(s.bin); err != nil {
		s.t.Fatalf("install.sh built no axiom: %v", err)
	}
}

// uninstallSession is a seeded home with the three compositors' configs of
// the user's, sway running. install.sh adds its lines to all three (--yes
// takes every offer).
func uninstallSession(t *testing.T) *Session {
	t.Helper()
	s := NewSessionWith(t, "GSETTINGS_BACKEND=keyfile", "SHELL=/bin/bash")
	s.SeedHome("testdata/home-seed")
	s.WriteFile(".config/hypr/hyprland.lua", "-- my hyprland\nhl.config({})\n")
	s.WriteFile(".config/niri/config.kdl", "// my niri\nbinds {}\n")
	os.MkdirAll(filepath.Join(s.Home, ".local/bin"), 0o755)
	s.FakeProgram("bat", "exit 0")
	s.FakeProgram("sudo", sudoStub)
	return s
}

// startInstalled starts the installed axiom on the running sway.
func (s *Session) startInstalled() *Proc {
	s.t.Helper()
	s.UseInstalled()
	return s.StartAxiom("sway")
}

// decoyRunning is a process whose command line is `axiom run`, so that
// install.sh finds axiom running and doesn't start the real one (with the
// real quickshell) after installing.
func (s *Session) decoyRunning() {
	s.t.Helper()
	s.run("decoy.log", exec.Command("bash", "-c", `exec -a "axiom run" sleep 3000`))
}

// keyring starts a Secret Service on the session bus, or says why it can't
func (s *Session) keyring() bool {
	s.t.Helper()
	if _, err := exec.LookPath("gnome-keyring-daemon"); err != nil {
		return false
	}
	cmd := exec.Command("gnome-keyring-daemon", "--unlock", "--components=secrets")
	cmd.Env = s.env()
	cmd.Stdin = strings.NewReader("pw\n")
	if out, err := cmd.CombinedOutput(); err != nil {
		s.t.Logf("no keyring: %v %s", err, out)
		return false
	}
	return testkit.Eventually(func() bool {
		cmd := exec.Command("busctl", "--user", "list")
		cmd.Env = s.env()
		out, err := cmd.Output()
		return err == nil && strings.Contains(string(out), "org.freedesktop.secrets")
	})
}

// secretFound: the keyring holds an item of axiom's
func (s *Session) secretFound() bool {
	cmd := exec.Command("secret-tool", "search", "service", "axiom")
	cmd.Env = s.env()
	out, _ := cmd.CombinedOutput()
	return strings.Contains(string(out), "attribute.service = axiom")
}

// setupInstalled is what the settings do over the install: everything
// applied (as in the footprint round trip), a keyring secret when there is a
// keyring, and Compositor.mode managed with the takeover approved, so a
// claim happens and the merge marks lines. system: the default app too.
func setupInstalled(t *testing.T, s *Session, system bool) (secret bool) {
	t.Helper()
	if system {
		applyEverything(t, s)
	} else {
		applyWithoutSystem(t, s)
	}
	if s.keyring() {
		if _, err := s.ShellCall("secrets.set", map[string]any{"scope": "provider", "id": "ctr", "label": "ctr", "value": "not-a-real-key"}); err == nil {
			secret = s.secretFound()
		}
	}
	if _, err := s.ShellCall("config.set", map[string]any{"ops": []config.Op{config.SetValue(config.Keys("Compositor", "mode"), "managed")}, "takeover": true}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.ShellCall("compositor.allowTakeover", nil); err != nil {
		t.Fatal(err)
	}
	if !testkit.Eventually(func() bool {
		data, _ := os.ReadFile(filepath.Join(s.Config, "sway/config"))
		return strings.HasPrefix(string(data), "# Generated by axiom")
	}) {
		t.Fatalf("sway's config wasn't taken over; daemon log:\n%s", s.Tail(daemonLog, 40))
	}
	return secret
}

// applyWithoutSystem is applyEverything but for the system's own choice (the
// default app), which a plain --yes keeps
func applyWithoutSystem(t *testing.T, s *Session) {
	t.Helper()
	keys := integrationKeys()
	s.integrate(keys)
	for _, key := range slices.Sorted(maps.Keys(schemaHookups(t, s))) {
		if _, err := s.ShellCall("hookup.apply", map[string]any{"key": key, "owner": "ThemeIntegrations." + key}); err != nil {
			t.Fatalf("hookup.apply %s: %v", key, err)
		}
	}
	s.integrate(keys)
	if _, err := s.ShellCall("cursor.theme", map[string]any{"theme": "whiteglass", "size": 24, "owner": "Input.cursor.enabled"}); err != nil {
		t.Fatal(err)
	}
}

// normalize makes a plan or a report comparable: the session's folders and
// display by name, dates as <stamp>
func (s *Session) normalize(text string) string {
	display := s.vars["WAYLAND_DISPLAY"]
	text = strings.ReplaceAll(text, s.Runtime, "$RUNTIME")
	text = strings.ReplaceAll(text, s.Home, "$HOME")
	text = strings.ReplaceAll(text, "/"+display, "/$DISPLAY")
	text = strings.ReplaceAll(text, `"`+display+`"`, `"$DISPLAY"`)
	return regexp.MustCompile(`\d{8}-\d{6}`).ReplaceAllString(text, "<stamp>")
}

// reportedBackups are the paths under "Backups kept:" of the text report
func reportedBackups(out string) []string {
	var paths []string
	_, rest, ok := strings.Cut(out, "Backups kept:\n")
	if !ok {
		return nil
	}
	for _, line := range strings.Split(rest, "\n") {
		if !strings.HasPrefix(line, "  /") {
			break
		}
		path, _, _ := strings.Cut(strings.TrimSpace(line), " (")
		paths = append(paths, path)
	}
	return paths
}

// withoutListed takes out of a diff the paths the report lists as backups
// (and what's in a listed folder), returning what's left and what it took.
func (s *Session) withoutListed(diff, listed []string) (rest, taken []string) {
	for _, line := range diff {
		path := strings.TrimPrefix(strings.TrimPrefix(line, "+ "), "~ ")
		abs := filepath.Join(s.Home, strings.SplitN(path, ":", 2)[0])
		ok := false
		for _, l := range listed {
			if abs == l || strings.HasPrefix(abs, l+"/") {
				ok = true
			}
		}
		if ok {
			taken = append(taken, line)
		} else {
			rest = append(rest, line)
		}
	}
	return rest, taken
}

// allowed is the allowlist the round trip needs beyond the listed backups:
// the empty user/ folder a takeover made in sway's config folder (it is the
// user's, and stays), and the shell history a bash leaves.
var allowed = []string{"+ .config/sway/user", "+ .bash_history"}

// goConfig is the go tool's own (install.sh builds axiom with it: telemetry
// counters in ~/.config/go)
func goConfig(line string) bool {
	path := strings.TrimPrefix(line, "+ ")
	return path == ".config/go" || strings.HasPrefix(path, ".config/go/")
}

// diffPath is the path a Diff line is about (a plus or a tilde line: added
// or changed; others come back as they are)
func diffPath(line string) string {
	path := strings.TrimPrefix(strings.TrimPrefix(line, "+ "), "~ ")
	return strings.SplitN(path, ":", 2)[0]
}

// under: path is x or inside it
func under(path, x string) bool { return path == x || strings.HasPrefix(path, x+"/") }

// checkPlan runs `axiom --json uninstall --dry-run args…` and compares its
// plan with testdata/<name> (container-test.sh -update writes it, into the
// logs folder).
func (s *Session) checkPlan(t *testing.T, name string, args ...string) {
	t.Helper()
	plan := s.normalize(s.Axiom(append([]string{"--json", "uninstall", "--dry-run"}, args...)...))
	var pretty any
	if err := json.Unmarshal([]byte(plan), &pretty); err != nil {
		t.Fatalf("the plan isn't JSON: %v\n%s", err, plan)
	}
	// Two backups made in different seconds are one name once the stamp is
	// <stamp>: which it is depends on timing, so each is listed once
	if m, ok := pretty.(map[string]any); ok {
		if p, ok := m["plan"].(map[string]any); ok {
			if list, ok := p["backups"].([]any); ok {
				p["backups"] = slices.Compact(list)
			}
		}
	}
	data, _ := json.MarshalIndent(pretty, "", "  ")
	golden := filepath.Join("testdata", name)
	if os.Getenv("AXIOM_CTR_UPDATE") == "1" {
		os.WriteFile(golden, append(data, '\n'), 0o644)
		os.WriteFile(filepath.Join(os.Getenv("AXIOM_CTR_OUT"), name), append(data, '\n'), 0o644)
	} else if want, err := os.ReadFile(golden); err != nil {
		t.Fatalf("%v (container-test.sh -update writes it into the logs folder)", err)
	} else if strings.TrimSpace(string(want)) != strings.TrimSpace(string(data)) {
		os.WriteFile(filepath.Join(s.Out, name+".got"), data, 0o644)
		t.Errorf("the plan differs from %s (got it in the logs: %s.got):\n%s", golden, name, data)
	}
}

func (s *Session) noAxiomProcesses() []ProcInfo {
	return Procs(func(p ProcInfo) bool {
		return filepath.Base(p.Argv[0]) == "axiom" && p.HasEnv("XDG_RUNTIME_DIR="+s.Runtime)
	})
}

func TestContainerUninstallRoundTrip(t *testing.T) {
	repo := installRepo(t)
	s := uninstallSession(t)
	userSway := swayMinimal + "bindsym $mod+Return exec true\n"
	// sway runs the user's config first: install.sh's autostart line then
	// starts nothing (a reload runs no `exec`), and the harness starts axiom
	s.StartSway(userSway)
	s.decoyRunning()
	a := s.snapshotSkipping(uninstallSnapshotSkips)

	if out, err := s.RunInstallSh(repo); err != nil {
		t.Fatalf("install.sh: %v\n%s", err, out)
	}
	for _, rel := range []string{".local/bin/axiom", ".local/share/axiom-shell/qml/shell.qml", ".local/share/xdg-desktop-portal/portals/axiom.portal"} {
		if _, err := os.Stat(filepath.Join(s.Home, rel)); err != nil {
			t.Errorf("install.sh left no %s", rel)
		}
	}
	if got, _ := os.ReadFile(filepath.Join(s.Config, "sway/config")); !strings.Contains(string(got), "' run") {
		t.Fatalf("install.sh added no line to sway's config:\n%s", got)
	}
	s.startInstalled()
	secret := setupInstalled(t, s, true)

	// The daemon is still saving what the setup changed: wait until the home
	// holds still, so that a change after this is the plan's
	beforePlan := s.snapshotSkipping(uninstallSnapshotSkips)
	testkit.Eventually(func() bool {
		time.Sleep(300 * time.Millisecond)
		next := s.snapshotSkipping(uninstallSnapshotSkips)
		still := len(Diff(beforePlan, next)) == 0
		beforePlan = next
		return still
	})
	s.checkPlan(t, "uninstall-plan.golden.json")
	s.checkPlan(t, "uninstall-plan-purge.golden.json", "--purge-all", "--restore-system")
	// Axiom's own folders are compared too: only the running daemon's log
	// changes meanwhile, and the claim's user/ folder is sway's
	var changedByPlan []string
	for _, line := range Diff(beforePlan, s.snapshotSkipping(uninstallSnapshotSkips)) {
		path := diffPath(line)
		if !under(path, ".local/state/axiom/log") && !under(path, ".config/sway/user") {
			changedByPlan = append(changedByPlan, line)
		}
	}
	if d := changedByPlan; len(d) > 0 {
		t.Errorf("--dry-run changed the home:\n%s", strings.Join(d, "\n"))
	}

	out, err := s.RunInstallSh(repo, "--uninstall", "--purge-all", "--restore-system")
	if err != nil {
		t.Fatalf("install.sh --uninstall: %v\n%s", err, out)
	}
	b := s.snapshotSkipping(uninstallSnapshotSkips)
	rest, taken := s.withoutListed(Diff(a, b), reportedBackups(out))
	var left []string
	for _, line := range rest {
		if !slices.Contains(allowed, line) && !goConfig(line) {
			left = append(left, line)
		}
	}
	if len(left) > 0 {
		t.Errorf("the home isn't as it was:\n%s", strings.Join(left, "\n"))
	}
	if len(taken) == 0 {
		t.Error("no backups were kept and listed")
	}
	if got, _ := os.ReadFile(filepath.Join(s.Config, "sway/config")); string(got) != userSway {
		t.Errorf("sway's config isn't the user's:\n%s", got)
	}
	if procs := s.noAxiomProcesses(); len(procs) > 0 {
		t.Errorf("axiom still runs: %+v", procs)
	}
	if _, err := os.Stat(filepath.Join(s.Runtime, "axiom")); err == nil {
		t.Error("the runtime folder stayed")
	}
	if secret && s.secretFound() {
		t.Error("the keyring item stayed")
	}
}

func TestContainerUninstallDefaultsKeepConfig(t *testing.T) {
	repo := installRepo(t)
	s := uninstallSession(t)
	userSway := swayMinimal + "bindsym $mod+Return exec true\n"
	s.StartSway(userSway)
	s.decoyRunning()
	a := s.snapshotSkipping(uninstallSnapshotSkips)
	if out, err := s.RunInstallSh(repo); err != nil {
		t.Fatalf("install.sh: %v\n%s", err, out)
	}
	s.startInstalled()
	// With the system's own choice recorded too (a System row): the defaults
	// keep it, and the ledger with it
	secret := setupInstalled(t, s, true)
	if _, err := os.Stat(filepath.Join(s.State, "axiom/ui/takeover.json")); err != nil {
		t.Fatalf("no approval to remove: %v", err)
	}
	// Something of the user's in the data folder
	todo := filepath.Join(s.Data, "axiom/todo.json")
	os.MkdirAll(filepath.Dir(todo), 0o755)
	os.WriteFile(todo, []byte("[]\n"), 0o644)
	mimeapps := filepath.Join(s.Config, "mimeapps.list")
	mimeBefore, _ := os.ReadFile(mimeapps)

	out, err := s.RunInstallSh(repo, "--uninstall")
	if err != nil {
		t.Fatalf("install.sh --uninstall: %v\n%s", err, out)
	}
	// Each thing kept
	for _, p := range []string{filepath.Join(s.Config, "axiom/config.json"), todo, filepath.Join(s.State, "axiom/footprint.json")} {
		if _, err := os.Stat(p); err != nil {
			t.Errorf("%s was removed: %v", p, err)
		}
	}
	if got, _ := os.ReadFile(mimeapps); string(got) != string(mimeBefore) {
		t.Errorf("the default apps were put back without being asked:\n%s\n->\n%s", mimeBefore, got)
	}
	if secret && !s.secretFound() {
		t.Error("the keyring item went though the defaults keep it")
	}
	if _, err := os.Stat(filepath.Join(s.State, "axiom/ui/takeover.json")); err == nil {
		t.Error("the approval stayed")
	}
	b := s.snapshotSkipping(uninstallSnapshotSkips)
	rest, _ := s.withoutListed(Diff(a, b), reportedBackups(out))
	var left []string
	for _, line := range rest {
		path := diffPath(line)
		// What the defaults keep: the settings, the content, the state of
		// the rest of axiom, and the system's default apps
		if slices.Contains(allowed, line) || goConfig(line) || path == ".config/mimeapps.list" ||
			under(path, ".config/axiom") || under(path, ".local/share/axiom") || under(path, ".local/state/axiom") {
			continue
		}
		left = append(left, line)
	}
	if len(left) > 0 {
		t.Errorf("the home isn't as it was, but for what's kept:\n%s", strings.Join(left, "\n"))
	}
	if got, _ := os.ReadFile(filepath.Join(s.Config, "sway/config")); string(got) != userSway {
		t.Errorf("sway's config isn't the user's:\n%s", got)
	}
}

func TestContainerUninstallRefusesWhileRunning(t *testing.T) {
	repo := installRepo(t)
	s := uninstallSession(t)
	s.StartSway(swayMinimal)
	s.decoyRunning()
	if out, err := s.RunInstallSh(repo); err != nil {
		t.Fatalf("install.sh: %v\n%s", err, out)
	}
	s.startInstalled()
	before := s.snapshotSkipping(uninstallSnapshotSkips)
	out, err := s.AxiomTry("uninstall", "--yes")
	var exit *exec.ExitError
	if !errors.As(err, &exit) || exit.ExitCode() != axerr.ExitCode(axerr.New(axerr.Running, "")) {
		t.Fatalf("exit: %v\n%s", err, out)
	}
	if !strings.Contains(out, "quit it, or pass --stop") {
		t.Errorf("%s", out)
	}
	// Nothing outside axiom's own folders (which the running daemon writes
	// to) changed, and what an uninstall would touch is all still there
	for _, line := range Diff(before, s.snapshotSkipping(uninstallSnapshotSkips)) {
		path := diffPath(line)
		if !under(path, ".config/axiom") && !under(path, ".local/state/axiom") && !under(path, ".local/share/axiom") && !under(path, ".cache/axiom") {
			t.Errorf("something changed: %s", line)
		}
	}
	for _, rel := range []string{".local/bin/axiom", ".local/share/axiom-shell/qml/shell.qml", ".local/share/xdg-desktop-portal/portals/axiom.portal", ".config/sway/config", ".config/axiom/config.json"} {
		if _, err := os.Stat(filepath.Join(s.Home, rel)); err != nil {
			t.Errorf("%s: %v", rel, err)
		}
	}
	if got, _ := os.ReadFile(filepath.Join(s.Config, "sway/config")); !strings.Contains(string(got), "' run") {
		t.Errorf("sway's config lost install.sh's line:\n%s", got)
	}
}
