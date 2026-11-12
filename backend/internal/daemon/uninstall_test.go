package daemon

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"github.com/axiom-shell/axiom/backend/internal/uninstall"
)

// The plan the shell asks for leaves the daemon that makes it out of the
// displays that run: it quits itself, as the uninstall's --stop says.
func TestUninstallPlanRPCExcludesItself(t *testing.T) {
	t.Parallel()
	td := newTestDaemon(t)
	td.start(t, asShell)
	shell, err := td.connect(t, "shell", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	// another daemon's display, held by a lock (a child holds it)
	other := filepath.Join(td.env["XDG_RUNTIME_DIR"], "axiom", "wayland-other")
	os.MkdirAll(other, 0o700)
	lock, err := fsx.TryLock(filepath.Join(other, "daemon.lock"))
	if err != nil {
		t.Fatal(err)
	}
	defer lock.Release()
	var res UninstallPlanResult
	if err := shell.Call(context.Background(), "uninstall.plan", struct{}{}, &res); err != nil {
		t.Fatal(err)
	}
	if len(res.Plan.Running) != 1 || res.Plan.Running[0] != "wayland-other" {
		t.Errorf("running %v: the daemon counted itself, or missed another", res.Plan.Running)
	}
	if res.Log != filepath.Join(td.env["XDG_RUNTIME_DIR"], "axiom-uninstall.log") || res.Packaged {
		t.Errorf("%+v", res)
	}
	// The same plan from the outside counts both
	plan, err := uninstall.Build(context.Background(), uninstall.Options{Dirs: td.dirs, Getenv: td.getenv})
	if err != nil || len(plan.Running) != 2 {
		t.Errorf("without the exclusion: %v %v", plan.Running, err)
	}
	// Only the shell asks
	cli, err := td.connect(t, "cli", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	if err := cli.Call(context.Background(), "uninstall.plan", struct{}{}, nil); axerr.KindOf(err) != axerr.Refused {
		t.Errorf("a non-shell: %v", err)
	}
}

func TestUninstallStartSpawnsDetached(t *testing.T) {
	t.Parallel()
	td := newTestDaemon(t)
	fx := &effects{proc: t.TempDir()}
	td.session = &sessionTest{Seams: fx.seams(nil), ProcRoot: fx.proc}
	td.start(t, asShell)
	shell, err := td.connect(t, "shell", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	answers := uninstall.Answers{KeepConfig: true, UndoInferred: true, RestoreSystem: true}
	var res UninstallStartResult
	if err := shell.Call(context.Background(), "uninstall.start", UninstallStartRequest{Answers: answers}, &res); err != nil {
		t.Fatal(err)
	}
	rt := td.env["XDG_RUNTIME_DIR"]
	if res.Log != filepath.Join(rt, "axiom-uninstall.log") {
		t.Errorf("log %q", res.Log)
	}
	spawn := ""
	testkit.Eventually(func() bool {
		for _, l := range strings.Split(fx.got(), "\n") {
			if strings.HasPrefix(l, "spawn bash ") {
				spawn = l
			}
		}
		return spawn != ""
	})
	// Output to the log, then the command (the tree has its install.sh: it
	// runs it), with the answers in a file
	for _, want := range []string{" >" + res.Log, "install.sh --uninstall --yes --answers " + rt + "/axiom-uninstall-answers-"} {
		if !strings.Contains(spawn, want) {
			t.Errorf("spawn %q lacks %q", spawn, want)
		}
	}
	files, _ := filepath.Glob(filepath.Join(rt, "axiom-uninstall-answers-*.json"))
	if len(files) != 1 {
		t.Fatalf("answers files %v", files)
	}
	if info, _ := os.Stat(files[0]); info.Mode().Perm() != 0o600 {
		t.Errorf("mode %v", info.Mode())
	}
	var got uninstall.Answers
	data, _ := os.ReadFile(files[0])
	if err := json.Unmarshal(data, &got); err != nil || got != answers {
		t.Errorf("answers %+v %v", got, err)
	}
	// One at a time
	if err := shell.Call(context.Background(), "uninstall.start", UninstallStartRequest{Answers: answers}, nil); axerr.KindOf(err) != axerr.Conflict {
		t.Errorf("a second start: %v", err)
	}
	// Only the shell starts one
	cli, err := td.connect(t, "cli", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	if err := cli.Call(context.Background(), "uninstall.start", UninstallStartRequest{Answers: answers}, nil); axerr.KindOf(err) != axerr.Refused {
		t.Errorf("a non-shell: %v", err)
	}
}

// With the install's script beside its tree (not a package), the script
// does it: it takes the install and the binary away too
func TestUninstallStartRunsTheInstallScript(t *testing.T) {
	t.Parallel()
	sd := newSessionDaemon(t, false)
	tree := t.TempDir()
	os.WriteFile(filepath.Join(tree, "install.sh"), []byte("#!/bin/bash\n"), 0o755)
	sd.d.installTree = tree
	if _, err := sd.d.startUninstall(context.Background(), uninstall.Answers{}); err != nil {
		t.Fatal(err)
	}
	if got := sd.fx.got(); !strings.Contains(got, "spawn bash "+filepath.Join(tree, "install.sh")+" --uninstall --yes --answers ") {
		t.Errorf("%q", got)
	}
	// A package: the binary's own uninstall (the package manager removes it)
	os.WriteFile(filepath.Join(tree, ".packaged"), []byte("1.0\n"), 0o644)
	sd.fx.list = nil
	sd.d.uninstalling.Store(false)
	sd.d.installed = "/bin/sh"
	if _, err := sd.d.startUninstall(context.Background(), uninstall.Answers{}); err != nil {
		t.Fatal(err)
	}
	if got := sd.fx.got(); strings.Contains(got, "install.sh") || !strings.Contains(got, "spawn /bin/sh uninstall --stop --yes --answers ") {
		t.Errorf("%q", got)
	}
}

// The backfill without a shell: the targets come from the built schema's
// x-hookup (the repo's tree here), the writers' include and autostart
// lines, and the screen-share picker's shapes
func TestOfflineInferredFromSchemaAndWriters(t *testing.T) {
	t.Parallel()
	td := newTestDaemon(t)
	cfg := td.env["XDG_CONFIG_HOME"]
	write := func(path, text string) {
		os.MkdirAll(filepath.Dir(path), 0o755)
		if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	// kitty's hookup from an earlier axiom (a line and its backup)
	write(filepath.Join(cfg, "kitty", "kitty.conf"), "font_size 12\n\ninclude axiom.conf\n")
	write(filepath.Join(cfg, "kitty", "kitty.conf.axiom-bak-20260101-000000"), "font_size 12\n")
	write(filepath.Join(cfg, "kitty", "axiom.conf"), "# colors\n")
	// install.sh's autostart line (as the compositor card writes it), and the
	// xdpw chooser the Screen sharing card added
	bin := "/home/u/.local/bin/axiom"
	write(filepath.Join(cfg, "sway", "config"), "set $mod Mod4\nexec '"+bin+"' run\n")
	write(filepath.Join(cfg, "xdg-desktop-portal-wlr", "config"), "[screencast]\nchooser_type = dmenu\nchooser_cmd = '"+bin+"' screenshare-pick --for xdpw\n")
	// the user's own, with no trace of axiom
	write(filepath.Join(cfg, "alacritty", "alacritty.toml"), "[general]\n")
	hooks, files := OfflineInferred(context.Background(), td.getenv, testkit.RepoRoot(), bin)
	rows := append(hooks, files...)
	got := map[string]string{}
	for _, r := range rows {
		got[r.Kind+" "+strings.TrimPrefix(r.Target, cfg+"/")] = r.Owner
	}
	for key, owner := range map[string]string{
		"hookup kitty/kitty.conf":              "ThemeIntegrations.kitty",
		"hookup sway/config":                   "",
		"hookup xdg-desktop-portal-wlr/config": "ScreenSharing.enabled",
		"file kitty/axiom.conf":                "ThemeIntegrations.kitty",
	} {
		if o, ok := got[key]; !ok || o != owner {
			t.Errorf("%q: owner %q, found %v (rows %v)", key, o, ok, got)
		}
	}
	if _, ok := got["hookup alacritty/alacritty.toml"]; ok {
		t.Error("a file with no trace of axiom is inferred")
	}
	// Nothing was written
	if _, err := os.Stat(filepath.Join(td.dirs.State, "footprint.json")); err == nil {
		t.Error("the ledger was written")
	}
}
