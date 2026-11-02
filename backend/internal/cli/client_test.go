package cli

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/daemon"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
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

// A daemon that refuses this binary's protocol (dev mode rebuilt it with
// a bump) runs the command again with the dev build, once, and only when
// the daemon runs it. Not parallel: it stubs procExe.
func TestProtocolRefusalRunsTheDevBuild(t *testing.T) {
	daemonExe, real := "/usr/bin/axiom", procExe
	t.Cleanup(func() { procExe = real })
	procExe = func(pid int) string {
		if pid != os.Getpid() {
			return ""
		}
		return daemonExe
	}
	dir, err := os.MkdirTemp("", "ax") // short: a sockaddr_un
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	sock := filepath.Join(dir, "s.sock")
	ln, err := rpc.Listen(sock)
	if err != nil {
		t.Fatal(err)
	}
	reg := rpc.NewRegistry()
	rpc.Handle(reg, "daemon.hello", func(context.Context, *rpc.Conn, daemon.HelloParams) (struct{}, error) {
		return struct{}{}, axerr.New(axerr.Incompatible, "this axiom speaks protocol 99")
	})
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	go (&rpc.Server{Registry: reg}).Serve(ctx, ln)

	dev := filepath.Join(dir, "state", "axiom", "dev", "axiom")
	run := func(env map[string]string) (ran string, err error) {
		e := &Env{Getenv: func(k string) string { return env[k] }}
		e.Globals.Socket = sock
		e.Exec = func(exe string) error {
			ran = exe
			return errors.New("exec'd")
		}
		_, _, err = connect(ctx, e)
		return ran, err
	}
	state := map[string]string{"XDG_STATE_HOME": filepath.Join(dir, "state")}
	// A dev build left from an earlier dev mode: the daemon runs another
	os.MkdirAll(filepath.Dir(dev), 0o700)
	if err := os.WriteFile(dev, []byte("#!/bin/sh\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	if ran, err := run(state); ran != "" || axerr.KindOf(err) != axerr.Incompatible {
		t.Errorf("the daemon runs the installed binary: ran %q, %v", ran, err)
	}
	daemonExe = dev
	if ran, err := run(state); ran != dev || err == nil {
		t.Errorf("the daemon runs the dev build: ran %q, %v", ran, err)
	}
	state[devCLIEnv] = "1"
	if ran, err := run(state); ran != "" || axerr.KindOf(err) != axerr.Incompatible {
		t.Errorf("already the dev build: ran %q, %v", ran, err)
	}
}

// A daemon restarting into a binary that speaks this protocol is greeted
// again once it's back.
func TestHelloAgainAfterTheDaemonRestarts(t *testing.T) {
	t.Parallel()
	dir, err := os.MkdirTemp("", "ax") // short: a sockaddr_un
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	sock := filepath.Join(dir, "s.sock")
	ln, err := rpc.Listen(sock)
	if err != nil {
		t.Fatal(err)
	}
	reg := rpc.NewRegistry()
	var hellos atomic.Int32
	rpc.Handle(reg, "daemon.hello", func(context.Context, *rpc.Conn, daemon.HelloParams) (daemon.HelloResult, error) {
		if hellos.Add(1) == 1 {
			return daemon.HelloResult{}, axerr.New(axerr.Unavailable, "axiom is restarting into the newer binary /x: try again")
		}
		return daemon.HelloResult{Version: "new"}, nil
	})
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	go (&rpc.Server{Registry: reg}).Serve(ctx, ln)
	e := &Env{Getenv: func(string) string { return "" }}
	e.Globals.Socket = sock
	c, hello, err := connect(ctx, e)
	if err != nil || hello.Version != "new" || hellos.Load() != 2 {
		t.Fatalf("hello %+v, %v after %d hellos", hello, err, hellos.Load())
	}
	c.Close()
}
