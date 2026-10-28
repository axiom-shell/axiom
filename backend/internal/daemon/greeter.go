package daemon

import (
	"context"
	"io"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
	"github.com/axiom-shell/axiom/backend/internal/command"
	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/files"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/topics"
	"github.com/axiom-shell/axiom/backend/internal/weather"
)

// GreeterOptions configure the greeter's axiom (`axiom greeter`).
type GreeterOptions struct {
	Command []string // qs -p <tree>/greeter.qml
	Environ []string // its environment, without AXIOM_SOCKET (added here)
	// Dir is the greeter's private runtime folder (xdg.PrivateDir): its
	// socket
	Dir        string
	SchemaHash string // the schema written for it, which its hello names
	Schema     any    // that schema, parsed (input.apply reads its Input)
	Tree       string
	Getenv     func(string) string
	Output     io.Writer // quickshell's stdout and stderr
	Log        *slog.Logger
}

// greeterSocket is the greeter's socket in its runtime folder.
const greeterSocket = "axiom.sock"

// RunGreeter runs the login screen's quickshell as its parent, until it
// exits (an error when it failed, so greeter-session.sh tries the
// fallback) or ctx ends (it is stopped). Unlike Run, it owns no config,
// lock screen, compositor layer or Wayland connection: it answers only
// what the greeter asks, its commands (exec.*, watched ones pushed as
// exec.outputs), lookups (tz.*, net.addresses), the weather topic (its
// Weather module) and the compositor's socket (hypr.request, niri.*), and
// only to that quickshell. Greeter mode reads its
// config once and writes nothing (docs/dev/features/greeter-runtime.md).
func RunGreeter(ctx context.Context, o GreeterOptions) error {
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	socket := filepath.Join(o.Dir, greeterSocket)
	ln, err := rpc.Listen(socket)
	if err != nil {
		return err
	}
	var shellPID atomic.Int64
	isShell := func(pid int) bool { return pid > 0 && int64(pid) == shellPID.Load() }
	env := append(append([]string{}, o.Environ...), "AXIOM_SOCKET="+socket)
	serveCtx, stopServing := context.WithCancel(context.Background())
	watches := command.NewWatches(command.WatchOptions{
		Method:  pushExecOutputs.Method,
		Options: func() command.Options { return command.Options{Env: env} },
		Context: serveCtx,
		Log:     o.Log,
	})
	hub := topics.New(topics.Options{Log: o.Log, Context: serveCtx})
	written := files.New(files.Options{Method: pushFileChanged.Method, Log: o.Log, Context: serveCtx})
	// niri's event stream, for NiriManager when the greeter is looked at
	// from a niri session (the login screen's own compositor is sway or
	// Hyprland); its streams end with serveCtx and are waited for
	var streams sync.WaitGroup
	niri := niriStreams(o.Getenv, o.Log, serveCtx, func(fn func(context.Context)) {
		streams.Go(func() { fn(serveCtx) })
	})
	server := &rpc.Server{Registry: greeterRegistry(o, env, isShell, watches, hub, written, niri), Log: o.Log, OnClose: func(c *rpc.Conn) {
		watches.Forget(c)
		written.Forget(c)
		hub.Forget(c)
		if niri != nil {
			niri.Forget(c)
		}
	}}
	served := make(chan error, 1)
	go func() { served <- server.Serve(serveCtx, ln) }()
	defer func() {
		stopServing()
		<-served
		streams.Wait()
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
	if err := cmd.Wait(); err != nil && ctx.Err() == nil {
		return axerr.Wrap(axerr.Internal, err, "the greeter's quickshell failed")
	}
	return nil
}

// greeterRegistry is what the greeter's axiom answers: a hello from its
// quickshell alone, then that quickshell's commands (watched ones too), run with its own
// environment, its files (its state), lookups, the weather and the
// compositor's socket (Hyprland's requests, niri's requests and event
// stream on niriStreams, nil when not under niri). Anything else is unavailable, as it was with
// no axiom at all, so the shell's callers stay quiet about it.
func greeterRegistry(o GreeterOptions, env []string, isShell func(int) bool, watches *command.Watches, hub *topics.Hub, written *files.Files, niriStreams *ipc.NiriStreams) *rpc.Registry {
	reg := rpc.NewRegistry()
	reg.Before = func(c *rpc.Conn, method string) error {
		if method != "daemon.hello" && sessionOf(c) == nil {
			return axerr.New(axerr.BadRequest, "say daemon.hello first")
		}
		if _, _, ok := reg.Types(method); !ok {
			return axerr.New(axerr.Unavailable, "the greeter's axiom has no %s", method)
		}
		return nil
	}
	rpc.Handle(reg, "daemon.hello", func(ctx context.Context, c *rpc.Conn, p HelloParams) (HelloResult, error) {
		if err := p.compatible(o.SchemaHash); err != nil {
			return HelloResult{}, err
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
	execHandlers(reg, func() command.Options { return command.Options{Env: env} }, func() *command.Watches { return watches })
	fileHandlers(reg, func() *files.Files { return written })
	lookupMethods(reg, o.Getenv)
	hyprHandlers(reg, ipc.HyprFromEnv(o.Getenv))
	niriHandlers(reg, ipc.NiriFromEnv(o.Getenv), niriStreams)
	outputHandlers(reg, o.Getenv)
	greeterOnlyMethods(reg, o.Getenv, func() any { return o.Schema })
	topics.Register(reg, hub, weather.Source(weather.Options{}))
	return reg
}
