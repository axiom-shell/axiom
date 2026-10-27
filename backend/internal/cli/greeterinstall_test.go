package cli

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/greeterinstall/rules"
)

// asAxiom makes this test binary the axiom binary when it's run with it
// set: the shim's update runs it as the installed copy's bin/axiom.
const asAxiom = "AXIOM_CLI_TEST_AS_AXIOM"

func TestMain(m *testing.M) {
	if os.Getenv(asAxiom) == "1" {
		os.Exit(Main(os.Args[1:], &Env{Stdin: os.Stdin, Stdout: os.Stdout, Stderr: os.Stderr, Getenv: os.Getenv}))
	}
	os.Exit(m.Run())
}

// greeterRoot is a scratch root with greetd, agreety and sway.
func greeterRoot(t *testing.T, greeter string) string {
	t.Helper()
	root := filepath.Join(t.TempDir(), "root")
	files := map[string]string{
		"etc/greetd/config.toml": "[default_session]\ncommand = \"agreety --cmd /bin/sh\"\nuser = \"" + greeter + "\"\n",
		"usr/bin/greetd":         "#!/bin/sh\n", "usr/bin/agreety": "#!/bin/sh\n", "usr/bin/sway": "#!/bin/sh\n",
	}
	for name, text := range files {
		writeTestFile(t, filepath.Join(root, name), text, 0o755)
	}
	return root
}

func writeTestFile(t *testing.T, path, text string, mode os.FileMode) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), mode); err != nil {
		t.Fatal(err)
	}
}

// greeter-install runs as root: Main hands it over before opening
// anything of the user's (their XDG folders, a log file, the daemon's
// socket), and it answers in JSON whatever happens.
func TestGreeterInstallTouchesNothingOfTheUsers(t *testing.T) {
	t.Parallel()
	me, err := user.Current()
	if err != nil {
		t.Skip(err)
	}
	root := greeterRoot(t, me.Username)
	home := t.TempDir()
	env := map[string]string{"HOME": home, "XDG_RUNTIME_DIR": filepath.Join(home, "run"), "XDG_STATE_HOME": filepath.Join(home, "state"),
		"XDG_CONFIG_HOME": filepath.Join(home, "config"), "XDG_CACHE_HOME": filepath.Join(home, "cache"), "AXIOM_GREETER_ROOT": root}
	for _, tc := range []struct {
		args []string
		ok   bool
		want string
	}{
		{[]string{"greeter-install", "uninstall", home, me.Username}, true, ""},
		{[]string{"greeter-install", "bogus"}, false, "usage"},
		{[]string{"greeter-install", "install", home, me.Username, "", "svn"}, false, "unknown source"},
		{[]string{"greeter-install", "install", filepath.Join(home, "missing"), me.Username}, false, "no repo"},
	} {
		var out bytes.Buffer
		code := Main(tc.args, &Env{Stdout: &out, Stderr: &out, Getenv: func(k string) string { return env[k] }})
		var r rules.Result
		if err := json.Unmarshal(out.Bytes(), &r); err != nil {
			t.Fatalf("%v: not one JSON object: %q", tc.args, out.String())
		}
		if r.OK != tc.ok || (code == 0) != tc.ok || !strings.Contains(r.Error, tc.want) || r.Changed == nil {
			t.Errorf("%v: exit %d, %+v", tc.args, code, r)
		}
	}
	if entries, _ := os.ReadDir(home); len(entries) != 0 {
		t.Errorf("made %v in the user's home", entries)
	}
}

// oldInstaller is the bash greeter_install.sh from git history: the last
// version before the port, which every existing install has as root's
// helper.
func oldInstaller(t *testing.T) string {
	t.Helper()
	top, err := exec.Command("git", "rev-parse", "--show-toplevel").Output()
	if err != nil {
		t.Skip("not in a clone:", err)
	}
	dir := strings.TrimSpace(string(top))
	const path = "scripts/greeter/greeter_install.sh"
	commits, err := exec.Command("git", "-C", dir, "rev-list", "HEAD", "--", path).Output()
	if err != nil {
		t.Skip("no history:", err)
	}
	for _, commit := range strings.Fields(string(commits)) {
		text, err := exec.Command("git", "-C", dir, "show", commit+":"+path).Output()
		if err == nil && bytes.Contains(text, []byte("command -v jq")) {
			return string(text)
		}
	}
	t.Skip("the bash installer isn't in this clone's history (shallow?)")
	return ""
}

// An install made by the bash installer updates to the shim through its
// own update (it copies the new tree and its binary), and the next update
// runs `axiom greeter-install` through that shim: no marker needed.
func TestOldInstallerUpdatesToTheShim(t *testing.T) {
	t.Parallel()
	for _, tool := range []string{"bash", "jq", "awk", "git", "tar", "sha256sum"} {
		if _, err := exec.LookPath(tool); err != nil {
			t.Skip(tool, "isn't installed")
		}
	}
	old := oldInstaller(t)
	shim, err := os.ReadFile("../../../scripts/greeter/greeter_install.sh")
	if err != nil {
		t.Fatal(err)
	}
	policy, err := os.ReadFile("../../../scripts/greeter/org.axiom.greeter.policy")
	if err != nil {
		t.Fatal(err)
	}
	binary, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	me, err := user.Current()
	if err != nil {
		t.Skip(err)
	}
	tmp := t.TempDir()
	root := greeterRoot(t, me.Username)
	env := append(os.Environ(), "AXIOM_GREETER_ROOT="+root, asAxiom+"=1", "HOME="+tmp, "GIT_CONFIG_NOSYSTEM=1",
		"GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@t", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@t")
	run := func(dir string, name string, args ...string) string {
		t.Helper()
		cmd := exec.Command(name, args...)
		cmd.Dir, cmd.Env = dir, env
		out, err := cmd.Output()
		if err != nil {
			t.Fatalf("%s %v: %v\n%s", name, args, err, out)
		}
		return string(out)
	}
	repo := filepath.Join(tmp, "repo")
	for name, text := range map[string]string{"greeter.qml": "greeter", "scripts/greeter/greeter-session.sh": "session",
		"scripts/greeter/org.axiom.greeter.policy": string(policy), "scripts/greeter/greeter_install.sh": old} {
		writeTestFile(t, filepath.Join(repo, name), text, 0o755)
	}
	run(tmp, "git", "init", "-q", "-b", "main", repo)
	run(repo, "git", "add", ".")
	run(repo, "git", "commit", "-qm", "before the port")
	update := func(helper string) {
		t.Helper()
		var r rules.Result
		if err := json.Unmarshal([]byte(run(repo, helper, "update", repo, me.Username, "", "local", "tags", binary)), &r); err != nil || !r.OK {
			t.Fatalf("%s's update: %+v, %v", helper, r, err)
		}
	}
	// An install from before the port: root's helper is the bash one
	helper := filepath.Join(root, "usr/share/axiom-greeter/scripts/greeter/greeter_install.sh")
	update(filepath.Join(repo, "scripts/greeter/greeter_install.sh"))
	// The port lands: the old helper's update installs the shim and binary
	writeTestFile(t, filepath.Join(repo, "scripts/greeter/greeter_install.sh"), string(shim), 0o755)
	writeTestFile(t, filepath.Join(repo, "greeter.qml"), "after the port", 0o644)
	run(repo, "git", "commit", "-qam", "the port")
	update(helper)
	if text, _ := os.ReadFile(helper); !bytes.Equal(text, shim) {
		t.Fatal("the old helper's update didn't install the shim")
	}
	// The next update runs axiom greeter-install through the shim
	writeTestFile(t, filepath.Join(repo, "greeter.qml"), "through the shim", 0o644)
	update(helper)
	copied, _ := os.ReadFile(filepath.Join(root, "usr/share/axiom-greeter/greeter.qml"))
	source, _ := os.ReadFile(filepath.Join(root, "usr/share/axiom-greeter/.greeter-source"))
	if string(copied) != "through the shim" || string(source) != "local\n" {
		t.Errorf("after the shim's update: greeter.qml %q, source %q", copied, source)
	}
}
