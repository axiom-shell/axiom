package cli

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// The daemon to talk to: --socket, else $AXIOM_SOCKET, else the display's,
// else the only one running (several is a question, none Unavailable)
func TestSocketPath(t *testing.T) {
	t.Parallel()
	rt, err := os.MkdirTemp("", "ax") // short: a sockaddr_un
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(rt) })
	if err := os.Chmod(rt, 0o700); err != nil {
		t.Fatal(err)
	}
	running := func(displays ...string) {
		for _, d := range displays {
			dir := filepath.Join(rt, "axiom", d)
			if err := os.MkdirAll(dir, 0o700); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(dir, "axiom.sock"), nil, 0o600); err != nil {
				t.Fatal(err)
			}
		}
	}
	resolve := func(socket string, env map[string]string) (string, error) {
		e := &Env{Getenv: func(k string) string { return env[k] }}
		e.Globals.Socket = socket
		return socketPath(e)
	}
	sock := func(d string) string { return filepath.Join(rt, "axiom", d, "axiom.sock") }

	if _, err := resolve("", map[string]string{"XDG_RUNTIME_DIR": rt}); axerr.KindOf(err) != axerr.Unavailable {
		t.Errorf("none running: %v, want Unavailable", err)
	}
	running("wayland-1")
	only := map[string]string{"XDG_RUNTIME_DIR": rt}
	for _, c := range []struct {
		name, socket string
		env          map[string]string
		want         string
	}{
		{"--socket first", "/s/flag.sock", map[string]string{"AXIOM_SOCKET": "/s/env.sock", "XDG_RUNTIME_DIR": rt}, "/s/flag.sock"},
		{"then $AXIOM_SOCKET", "", map[string]string{"AXIOM_SOCKET": "/s/env.sock", "WAYLAND_DISPLAY": "wayland-1", "XDG_RUNTIME_DIR": rt}, "/s/env.sock"},
		{"then the display's", "", map[string]string{"WAYLAND_DISPLAY": "wayland-1", "XDG_RUNTIME_DIR": rt}, sock("wayland-1")},
		{"then the only one", "", only, sock("wayland-1")},
	} {
		if got, err := resolve(c.socket, c.env); err != nil || got != c.want {
			t.Errorf("%s: %q, %v, want %q", c.name, got, err, c.want)
		}
	}
	running("wayland-2")
	if _, err := resolve("", only); axerr.KindOf(err) != axerr.BadRequest || !strings.Contains(err.Error(), "several") {
		t.Errorf("several running: %v, want BadRequest", err)
	}
	if _, err := resolve("", map[string]string{}); axerr.KindOf(err) != axerr.Unavailable {
		t.Errorf("no $XDG_RUNTIME_DIR: %v, want Unavailable", err)
	}
}

// Offline, config set / get / reset work on the file, read as the
// setting's type, and a takeover setting needs --takeover
func TestConfigOffline(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	config := func(args ...string) (int, string, string) {
		return run(t, Root(), append([]string{"--offline", "--config-dir", dir, "config"}, args...)...)
	}
	steps := []struct {
		args []string
		code int
		out  string
	}{
		{[]string{"get", "General.language"}, 0, "en\n"},
		{[]string{"set", "General.language", "de"}, 0, ""},
		{[]string{"get", "General.language"}, 0, "de\n"},
		{[]string{"reset", "General.language"}, 0, ""},
		{[]string{"get", "General.language"}, 0, "en\n"},
		{[]string{"get", "General.nothing"}, -1, ""},
		{[]string{"set", "Idle.enabled", "on"}, -1, ""},
		{[]string{"get", "Idle.enabled"}, 0, "false\n"},
		{[]string{"set", "--takeover", "Idle.enabled", "on"}, 0, ""},
		{[]string{"get", "Idle.enabled"}, 0, "true\n"},
	}
	for _, s := range steps {
		code, out, errOut := config(s.args...)
		if (s.code < 0 && code == 0) || (s.code == 0 && code != 0) {
			t.Fatalf("%v: exit %d (%s)", s.args, code, errOut)
		}
		if s.code == 0 && strings.HasPrefix(s.args[0], "get") && out != s.out {
			t.Errorf("%v printed %q, want %q", s.args, out, s.out)
		}
	}
	if _, err := os.Stat(filepath.Join(dir, "config.json")); err != nil {
		t.Errorf("no config.json written: %v", err)
	}
}
