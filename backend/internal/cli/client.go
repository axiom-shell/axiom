package cli

import (
	"context"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
	"github.com/axiom-shell/axiom/backend/internal/daemon"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// socketPath is the daemon to talk to: --socket, else $AXIOM_SOCKET (set
// in the shell, so what it launches finds its daemon), else the one of
// $WAYLAND_DISPLAY, else the only one running.
func socketPath(e *Env) (string, error) {
	if e.Globals.Socket != "" {
		return e.Globals.Socket, nil
	}
	if s := e.Getenv("AXIOM_SOCKET"); s != "" {
		return s, nil
	}
	if xdg.DisplayName(e.Getenv("WAYLAND_DISPLAY")) != "" {
		rt, err := xdg.ForDisplay(e.Getenv, false)
		if err != nil {
			return "", axerr.Wrap(axerr.Unavailable, err, "no axiom runs on this display")
		}
		return rt.Socket(), nil
	}
	root, err := xdg.RuntimeRoot(e.Getenv, false)
	if err != nil {
		return "", axerr.Wrap(axerr.Unavailable, err, "no axiom is running")
	}
	matches, _ := filepath.Glob(filepath.Join(root, "*", "axiom.sock"))
	switch len(matches) {
	case 0:
		return "", axerr.New(axerr.Unavailable, "no axiom is running")
	case 1:
		return matches[0], nil
	}
	return "", axerr.New(axerr.BadRequest, "axiom runs on several displays: pick one with --socket or $WAYLAND_DISPLAY")
}

// connect dials the daemon and says hello.
func connect(ctx context.Context, e *Env) (*rpc.Conn, daemon.HelloResult, error) {
	path, err := socketPath(e)
	if err != nil {
		return nil, daemon.HelloResult{}, err
	}
	dctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	c, err := rpc.Dial(dctx, path, nil, nil)
	if err != nil {
		return nil, daemon.HelloResult{}, err
	}
	var hello daemon.HelloResult
	if err := c.Call(dctx, "daemon.hello", daemon.HelloParams{Protocol: buildinfo.Protocol(), Client: "cli", PID: os.Getpid()}, &hello); err != nil {
		daemonPID := c.PeerPID()
		c.Close()
		// Another protocol: in dev mode the daemon runs a dev build, which
		// a bump leaves this installed binary behind (binds call it)
		if axerr.KindOf(err) == axerr.Incompatible && e.Exec != nil {
			if exe := devBinary(e, daemonPID); exe != "" {
				err = e.Exec(exe) // returns only when it failed
			}
		}
		return nil, daemon.HelloResult{}, err
	}
	return c, hello, nil
}

// devCLIEnv marks a command run again with the dev build: its own refusal
// is the answer.
const devCLIEnv = "AXIOM_DEV_CLI"

// procExe is the binary process pid runs ("" when unknown), also once a
// newer build replaced its file (a build the source changed under).
var procExe = func(pid int) string {
	exe, _ := os.Readlink("/proc/" + strconv.Itoa(pid) + "/exe")
	return strings.TrimSuffix(exe, " (deleted)")
}

// devBinary is dev mode's build, to run this command with when the daemon
// at pid refuses this binary's protocol: "" unless the daemon runs it (a
// dev build left from an earlier dev mode is never run), or when this is
// already the retry.
func devBinary(e *Env, pid int) string {
	if e.Getenv(devCLIEnv) != "" || pid <= 0 {
		return ""
	}
	exe := daemon.DevBinary(xdg.Resolve(e.Getenv))
	if procExe(pid) != exe {
		return ""
	}
	return exe
}

// ExecDev runs this command again with the binary at exe, in this process
// (Env.Exec in the axiom binary).
func ExecDev(exe string) error {
	err := syscall.Exec(exe, append([]string{exe}, os.Args[1:]...), append(os.Environ(), devCLIEnv+"=1"))
	return axerr.Wrap(axerr.Unavailable, err, "running the dev build %s", exe)
}

// call runs one request against the daemon.
func call(ctx context.Context, e *Env, method string, params, result any) error {
	c, _, err := connect(ctx, e)
	if err != nil {
		return err
	}
	defer c.Close()
	return c.Call(ctx, method, params, result)
}
