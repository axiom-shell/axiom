package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/uninstall"
)

// uninstallHome is a scratch home with a sway config install.sh changed.
// Its session bus is nowhere: a keyring is never reached from these tests.
func uninstallHome(t *testing.T) (env map[string]string, config string) {
	t.Helper()
	home := t.TempDir()
	rt, err := os.MkdirTemp("", "uxr")
	if err != nil {
		t.Fatal(err)
	}
	os.Chmod(rt, 0o700)
	t.Cleanup(func() { os.RemoveAll(rt) })
	env = map[string]string{"HOME": home, "XDG_CONFIG_HOME": filepath.Join(home, "config"), "XDG_STATE_HOME": filepath.Join(home, "state"),
		"XDG_DATA_HOME": filepath.Join(home, "data"), "XDG_CACHE_HOME": filepath.Join(home, "cache"), "XDG_RUNTIME_DIR": rt,
		"DBUS_SESSION_BUS_ADDRESS": "unix:path=" + filepath.Join(rt, "no-bus")}
	config = filepath.Join(home, "config", "sway", "config")
	os.MkdirAll(filepath.Dir(config), 0o755)
	if err := os.WriteFile(config, []byte("set $mod Mod4\nexec '/x/axiom' run\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	os.MkdirAll(filepath.Join(home, "config", "axiom"), 0o755)
	os.WriteFile(filepath.Join(home, "config", "axiom", "config.json"), []byte("{}"), 0o644)
	os.MkdirAll(filepath.Join(home, "cache", "axiom"), 0o755)
	return env, config
}

func runUninstall(t *testing.T, env map[string]string, args ...string) (int, string, string) {
	t.Helper()
	var out, errOut bytes.Buffer
	e := &Env{Stdin: strings.NewReader(""), Stdout: &out, Stderr: &errOut, Getenv: func(k string) string { return env[k] }}
	code := Run(context.Background(), Root(), append([]string{"--offline", "uninstall"}, args...), e)
	return code, out.String(), errOut.String()
}

func TestUninstallDryRunJSON(t *testing.T) {
	t.Parallel()
	env, config := uninstallHome(t)
	before, _ := os.ReadFile(config)
	code, out, errOut := runUninstall(t, env, "--dry-run", "--json")
	if code != 0 {
		t.Fatalf("%d %s %s", code, out, errOut)
	}
	var got struct {
		Plan    uninstall.Plan    `json:"plan"`
		Answers uninstall.Answers `json:"answers"`
	}
	if err := json.Unmarshal([]byte(out), &got); err != nil {
		t.Fatalf("%v: %s", err, out)
	}
	lines := 0
	for _, a := range got.Plan.Actions {
		if a.Step == "lines" && a.Path == config {
			lines++
		}
	}
	if lines != 1 {
		t.Errorf("plan: %+v", got.Plan.Actions)
	}
	if !got.Answers.KeepConfig || !got.Answers.KeepUserContent || !got.Answers.KeepSecrets || got.Answers.RestoreSystem {
		t.Errorf("answers %+v", got.Answers)
	}
	if after, _ := os.ReadFile(config); string(after) != string(before) {
		t.Error("--dry-run changed the config")
	}
	if _, err := os.Stat(filepath.Join(env["XDG_CACHE_HOME"], "axiom")); err != nil {
		t.Error("--dry-run removed the cache")
	}
	// The text form says it too, with the defaults
	if code, out, _ := runUninstall(t, env, "--dry-run"); code != 0 || !strings.Contains(out, "axiom would:") || !strings.Contains(out, "keep settings") {
		t.Errorf("%d %s", code, out)
	}
}

func TestUninstallNoTTYRefuses(t *testing.T) {
	t.Parallel()
	env, config := uninstallHome(t)
	before, _ := os.ReadFile(config)
	code, _, errOut := runUninstall(t, env)
	if code != axerr.ExitCode(axerr.New(axerr.BadRequest, "")) || !strings.Contains(errOut, "run with --yes to take the defaults, or --dry-run to see the plan") {
		t.Errorf("%d %s", code, errOut)
	}
	if after, _ := os.ReadFile(config); string(after) != string(before) {
		t.Error("it changed the config")
	}
	// --yes goes on: the defaults keep the settings, the line is gone
	if code, out, errOut := runUninstall(t, env, "--yes"); code != 0 {
		t.Fatalf("%d %s %s", code, out, errOut)
	}
	if got, _ := os.ReadFile(config); string(got) != "set $mod Mod4\n" {
		t.Errorf("%q", got)
	}
	if _, err := os.Stat(filepath.Join(env["XDG_CONFIG_HOME"], "axiom", "config.json")); err != nil {
		t.Error("the defaults didn't keep the settings")
	}
	if _, err := os.Stat(filepath.Join(env["XDG_CACHE_HOME"], "axiom")); err == nil {
		t.Error("the cache stayed")
	}
}

func TestUninstallAnswersFile(t *testing.T) {
	t.Parallel()
	env, _ := uninstallHome(t)
	file := filepath.Join(env["XDG_RUNTIME_DIR"], "axiom-uninstall-answers-1.json")
	data, _ := json.Marshal(uninstall.Answers{UndoInferred: true, KeepSecrets: true})
	if err := os.WriteFile(file, data, 0o600); err != nil {
		t.Fatal(err)
	}
	// No --yes and no terminal: the file stands in for the questions
	if code, out, errOut := runUninstall(t, env, "--answers", file, "--json"); code != 0 {
		t.Fatalf("%d %s %s", code, out, errOut)
	}
	if _, err := os.Stat(filepath.Join(env["XDG_CONFIG_HOME"], "axiom")); err == nil {
		t.Error("the answers said not to keep the settings")
	}
	if _, err := os.Stat(file); err == nil {
		t.Error("the answers file stayed")
	}
	// A broken one is a bad request
	bad := filepath.Join(t.TempDir(), "a.json")
	os.WriteFile(bad, []byte("{"), 0o600)
	if code, _, _ := runUninstall(t, env, "--answers", bad); code != 2 {
		t.Errorf("exit %d", code)
	}
	// The flag isn't in the help
	var help bytes.Buffer
	writeHelp(&help, uninstallCommand(), []string{"axiom", "uninstall"})
	if strings.Contains(help.String(), "--answers") || !strings.Contains(help.String(), "--purge-all") {
		t.Errorf("help:\n%s", help.String())
	}
}

func TestUninstallAnswersAreStrict(t *testing.T) {
	t.Parallel()
	env, config := uninstallHome(t)
	before, _ := os.ReadFile(config)
	dir := t.TempDir()
	write := func(name, text string) string {
		p := filepath.Join(dir, name)
		os.WriteFile(p, []byte(text), 0o600)
		return p
	}
	full := `{"keepConfig":true,"keepUserContent":true,"keepSecrets":true,"undoInferred":true,"restoreSystem":false,"restartPortal":true`
	for name, c := range map[string]struct {
		args []string
		file string
	}{
		"a missing key":         {file: `{"keepConfig":false}`},
		"an unknown key":        {file: full + `,"deleteEverything":true}`},
		"not JSON":              {file: `{`},
		"a null answer":         {file: `{"keepConfig":null,"keepUserContent":true,"keepSecrets":true,"undoInferred":true,"restoreSystem":false,"restartPortal":true}`},
		"a non-boolean answer":  {file: `{"keepConfig":"yes","keepUserContent":true,"keepSecrets":true,"undoInferred":true,"restoreSystem":false,"restartPortal":true}`},
		"with --purge-all":      {file: full + `}`, args: []string{"--purge-all"}},
		"with --restore-system": {file: full + `}`, args: []string{"--restore-system"}},
	} {
		code, _, errOut := runUninstall(t, env, append([]string{"--answers", write("a.json", c.file)}, c.args...)...)
		if code != 2 {
			t.Errorf("%s: exit %d: %s", name, code, errOut)
		}
	}
	if after, _ := os.ReadFile(config); string(after) != string(before) {
		t.Error("a refused answers file changed the config")
	}
	if code, out, errOut := runUninstall(t, env, "--answers", write("ok.json", full+`}`)); code != 0 {
		t.Errorf("a whole file: %d %s %s", code, out, errOut)
	}
}

// axiom running is said before any question; the questions go to stderr
func TestUninstallRunningIsSaidBeforeQuestions(t *testing.T) {
	t.Parallel()
	env, config := uninstallHome(t)
	before, _ := os.ReadFile(config)
	dir := filepath.Join(env["XDG_RUNTIME_DIR"], "axiom", "wayland-t")
	os.MkdirAll(dir, 0o700)
	lock, err := fsx.TryLock(filepath.Join(dir, "daemon.lock"))
	if err != nil {
		t.Fatal(err)
	}
	defer lock.Release()
	var out, errOut bytes.Buffer
	e := &Env{Stdin: strings.NewReader("n\nn\nn\n"), Stdout: &out, Stderr: &errOut, Getenv: func(k string) string { return env[k] }, TTY: func() bool { return true }}
	code := Run(context.Background(), Root(), []string{"--offline", "uninstall"}, e)
	if code != 3 || strings.Contains(errOut.String(), "[Y/n]") || !strings.Contains(errOut.String(), "quit it, or pass --stop") {
		t.Errorf("exit %d: %s", code, errOut.String())
	}
	if after, _ := os.ReadFile(config); string(after) != string(before) {
		t.Error("it changed the config")
	}
}

func TestUninstallQuestionsGoToStderrWithTheListFirst(t *testing.T) {
	t.Parallel()
	env, _ := uninstallHome(t)
	var out, errOut bytes.Buffer
	e := &Env{Stdin: strings.NewReader("\n\n\n"), Stdout: &out, Stderr: &errOut, Getenv: func(k string) string { return env[k] }}
	plan := uninstall.Plan{Actions: []uninstall.Action{{Step: "ledger", What: "Delete the file axiom made", Path: "/h/x", Asks: uninstall.FieldUndoInferred}}}
	ask := asker(e, uninstall.Options{}, plan)
	ask(uninstall.Question{Field: uninstall.FieldUndoInferred, N: 1}, true)
	ask(uninstall.Question{Field: uninstall.FieldKeepUserContent}, true)
	got := errOut.String()
	list, question := strings.Index(got, "Delete the file axiom made /h/x"), strings.Index(got, "Also undo 1 changes")
	if list < 0 || question < list || out.Len() != 0 {
		t.Errorf("stdout %q, stderr %q", out.String(), got)
	}
	if !strings.Contains(got, "notes, to-dos, themes, downloaded wallpapers and calendars") {
		t.Errorf("the data question doesn't say what it holds: %q", got)
	}
}

func TestReadAnswersFalseStaysFalse(t *testing.T) {
	t.Parallel()
	p := filepath.Join(t.TempDir(), "a.json")
	os.WriteFile(p, []byte(`{"keepConfig":false,"keepUserContent":false,"keepSecrets":false,"undoInferred":false,"restoreSystem":false,"restartPortal":false}`), 0o600)
	a, err := readAnswers(p)
	if err != nil {
		t.Fatal(err)
	}
	if a != (uninstall.Answers{}) {
		t.Errorf("answers %+v", a)
	}
}
