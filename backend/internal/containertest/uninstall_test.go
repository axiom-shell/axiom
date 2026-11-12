//go:build container

package containertest

import (
	"crypto/sha256"
	"encoding/json"
	"errors"
	"flag"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// The uninstall's round trip (docs/dev/backend/uninstall.md): install.sh as a
// user would run it (the clone, the binary built from it, desktop entries,
// the portal's files, the autostart lines), axiom run from that install with
// everything applied, then `install.sh --uninstall --yes --purge-all
// --restore-system`, and the home compared with what it was.

var updateGolden = flag.Bool("update", false, "rewrite testdata/uninstall-plan.golden.json")

// uninstallSnapshotSkips are what the harness itself puts in the home (the
// bin of its fake programs, glib's keyfile settings, the keyring it starts). Everything else is
// compared, axiom's own folders and the cache included.
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
	for key := range schemaHookups(t, s) {
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
	text = regexp.MustCompile(`"`+regexp.QuoteMeta(display)+`"`).ReplaceAllString(text, `"$DISPLAY"`)
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

	beforePlan := s.snapshotSkipping(uninstallSnapshotSkips)
	plan := s.normalize(s.Axiom("--json", "uninstall", "--dry-run"))
	var pretty any
	if err := json.Unmarshal([]byte(plan), &pretty); err != nil {
		t.Fatalf("the plan isn't JSON: %v\n%s", err, plan)
	}
	data, _ := json.MarshalIndent(pretty, "", "  ")
	golden := "testdata/uninstall-plan.golden.json"
	if *updateGolden || os.Getenv("AXIOM_CTR_UPDATE") == "1" {
		os.WriteFile(golden, append(data, '\n'), 0o644)
		os.WriteFile(filepath.Join(os.Getenv("AXIOM_CTR_OUT"), "uninstall-plan.golden.json"), append(data, '\n'), 0o644)
	} else if want, err := os.ReadFile(golden); err != nil {
		t.Fatalf("%v (container-test.sh -update writes it into the logs folder)", err)
	} else if strings.TrimSpace(string(want)) != strings.TrimSpace(string(data)) {
		os.WriteFile(filepath.Join(s.Out, "uninstall-plan.got.json"), data, 0o644)
		t.Errorf("the plan differs from %s (got it in the logs: uninstall-plan.got.json):\n%s", golden, data)
	}
	// (the daemon's own folders and the claim's user/ folder change meanwhile)
	var changedByPlan []string
	for _, line := range Diff(beforePlan, s.snapshotSkipping(uninstallSnapshotSkips)) {
		path := strings.TrimLeft(strings.TrimPrefix(strings.TrimPrefix(line, "+ "), "~ "), " ")
		if !strings.HasPrefix(path, ".config/axiom") && !strings.HasPrefix(path, ".local/state/axiom") && !strings.HasPrefix(path, ".config/sway/user") {
			changedByPlan = append(changedByPlan, line)
		}
	}
	if d := changedByPlan; len(d) > 0 {
		t.Errorf("--dry-run changed the home:\n%s", strings.Join(d, "\n"))
	}

	for _, r := range s.footprintRows() {
		if strings.Contains(r.Target, "cava") {
			t.Logf("row before: %s %s state=%s status=%s wrote=%s hookup=%+v", r.Kind, r.Target, r.State, r.Status, r.Wrote, r.Hookup)
		}
	}
	cava, _ := os.ReadFile(filepath.Join(s.Config, "cava/config"))
	t.Logf("cava/config before (sha %x):\n%s", sha256.Sum256(cava), cava)
	out, err := s.RunInstallSh(repo, "--uninstall", "--purge-all", "--restore-system")
	if err != nil {
		t.Fatalf("install.sh --uninstall: %v\n%s", err, out)
	}
	t.Logf("uninstall:\n%s", out)
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
	t.Logf("allowlist used: %v; backups listed: %v", allowed, reportedBackups(out))
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
	setupInstalled(t, s, false)
	if _, err := os.Stat(filepath.Join(s.State, "axiom/ui/takeover.json")); err != nil {
		t.Fatalf("no approval to remove: %v", err)
	}

	out, err := s.RunInstallSh(repo, "--uninstall")
	if err != nil {
		t.Fatalf("install.sh --uninstall: %v\n%s", err, out)
	}
	for _, rel := range []string{".config/axiom/config.json", ".local/share/axiom"} {
		if _, err := os.Stat(filepath.Join(s.Home, rel)); err != nil && rel != ".local/share/axiom" {
			t.Errorf("%s was removed: %v", rel, err)
		}
	}
	if _, err := os.Stat(filepath.Join(s.State, "axiom/ui/takeover.json")); err == nil {
		t.Error("the approval stayed")
	}
	b := s.snapshotSkipping(uninstallSnapshotSkips)
	rest, _ := s.withoutListed(Diff(a, b), reportedBackups(out))
	var left []string
	for _, line := range rest {
		path := strings.TrimPrefix(strings.TrimPrefix(line, "+ "), "~ ")
		// What the defaults keep: the settings, the content, the state of
		// the rest of axiom
		if slices.Contains(allowed, line) || goConfig(line) || strings.HasPrefix(path, ".config/axiom") || strings.HasPrefix(path, ".local/share/axiom") || strings.HasPrefix(path, ".local/state/axiom") {
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
	if d := Diff(before, s.snapshotSkipping(uninstallSnapshotSkips)); len(d) > 0 {
		t.Errorf("something changed:\n%s", strings.Join(d, "\n"))
	}
}
