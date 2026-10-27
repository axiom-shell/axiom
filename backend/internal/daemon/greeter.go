package daemon

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
	"github.com/axiom-shell/axiom/backend/internal/command"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// GreeterOptions configure the greeter's axiom (`axiom greeter`).
type GreeterOptions struct {
	Command []string // qs -p <tree>/greeter.qml
	Environ []string // its environment, without AXIOM_SOCKET (added here)
	// Dir is the greeter's private runtime folder (xdg.PrivateDir): its
	// socket and lock
	Dir        string
	SchemaHash string // the schema written for it, which its hello names
	Tree       string
	Getenv     func(string) string
	Output     io.Writer // quickshell's stdout and stderr
	Log        *slog.Logger

	// isShell replaces the check that a peer is the greeter (tests)
	isShell func(pid int) bool
}

// greeterSocket is the greeter's socket in its runtime folder.
const greeterSocket = "axiom.sock"

// RunGreeter runs the login screen's quickshell as its parent, until it
// exits (an error when it failed, so greeter-session.sh tries the
// fallback) or ctx ends (it is stopped). Unlike Run, it owns no config,
// lock screen, compositor layer or Wayland connection: it answers only
// what the greeter asks, its commands (exec.*) and lookups (tz.*,
// net.addresses), and only to that quickshell. Greeter mode reads its
// config once and writes nothing (docs/dev/features/greeter-runtime.md).
func RunGreeter(ctx context.Context, o GreeterOptions) error {
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	lock, err := fsx.TryLock(filepath.Join(o.Dir, "greeter.lock"))
	if err != nil {
		return err
	}
	defer lock.Release()
	socket := filepath.Join(o.Dir, greeterSocket)
	ln, err := rpc.Listen(socket)
	if err != nil {
		return err
	}
	var shellPID atomic.Int64
	isShell := o.isShell
	if isShell == nil {
		isShell = func(pid int) bool { return pid > 0 && int64(pid) == shellPID.Load() }
	}
	env := append(append([]string{}, o.Environ...), "AXIOM_SOCKET="+socket)
	server := &rpc.Server{Registry: greeterRegistry(o, env, isShell), Log: o.Log}
	serveCtx, stopServing := context.WithCancel(context.Background())
	served := make(chan error, 1)
	go func() { served <- server.Serve(serveCtx, ln) }()
	defer func() {
		stopServing()
		<-served
	}()

	cmd := exec.CommandContext(ctx, o.Command[0], o.Command[1:]...)
	cmd.Env = env
	cmd.Stdout, cmd.Stderr = o.Output, o.Output
	// Stopped as the shell is: SIGTERM, then SIGKILL after a grace
	cmd.Cancel = func() error { return cmd.Process.Signal(syscall.SIGTERM) }
	cmd.WaitDelay = 3 * time.Second
	if err := cmd.Start(); err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "starting %s", o.Command[0])
	}
	shellPID.Store(int64(cmd.Process.Pid))
	err = cmd.Wait()
	if ctx.Err() != nil {
		return nil
	}
	var exit *exec.ExitError
	if errors.As(err, &exit) {
		return axerr.Wrap(axerr.Internal, err, "the greeter's quickshell failed")
	}
	if err != nil {
		return axerr.Wrap(axerr.Internal, err, "waiting for the greeter's quickshell")
	}
	return nil
}

// greeterRegistry is what the greeter's axiom answers: a hello from its
// quickshell alone, then that quickshell's commands, run with its own
// environment, and lookups.
func greeterRegistry(o GreeterOptions, env []string, isShell func(int) bool) *rpc.Registry {
	reg := rpc.NewRegistry()
	reg.Before = func(c *rpc.Conn, method string) error {
		if method != "daemon.hello" && sessionOf(c) == nil {
			return axerr.New(axerr.BadRequest, "say daemon.hello first")
		}
		return nil
	}
	rpc.Handle(reg, "daemon.hello", func(ctx context.Context, c *rpc.Conn, p HelloParams) (HelloResult, error) {
		if p.Protocol != buildinfo.Protocol() {
			return HelloResult{}, axerr.New(axerr.Incompatible, "this axiom speaks protocol %d, the client %d: the shell's files and the binary are from different versions", buildinfo.Protocol(), p.Protocol)
		}
		if p.SchemaHash != "" && p.SchemaHash != o.SchemaHash {
			return HelloResult{}, axerr.New(axerr.Incompatible, "the client read another schema than the greeter was given")
		}
		if p.Client != "shell" || !isShell(c.PeerPID()) {
			return HelloResult{}, axerr.New(axerr.Refused, "only the greeter's quickshell may connect to the greeter's axiom")
		}
		c.SetValue(sessionKey{}, &session{Client: p.Client, PID: p.PID})
		info := buildinfo.Get()
		return HelloResult{
			Protocol: info.Protocol, Version: info.Version, Commit: info.Commit,
			SchemaHash: o.SchemaHash, PID: os.Getpid(), Tree: o.Tree, Compatible: true,
		}, nil
	})
	execHandlers(reg, func() command.Options { return command.Options{Env: env} })
	lookupMethods(reg, o.Getenv)
	return reg
}
