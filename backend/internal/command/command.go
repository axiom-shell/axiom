// Package command runs the commands the shell asks for (CommandManager's
// run and runDetached: `exec.run`, `exec.spawn`), with the shell's
// environment and no descriptor but stdio. A run is waited on and its
// output returned; a spawn is detached for good, so what it starts (an
// app from the launcher, a bar button's command) outlives the daemon and
// is never left a zombie in it across a re-exec.
package command

import (
	"bytes"
	"context"
	"errors"
	"os/exec"
	"strings"
	"syscall"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// What a run keeps of its output: more is read and dropped, so the
// command never blocks on a full pipe, and the reply stays well under
// the protocol's 16 MiB message
const (
	maxStdout = 4 << 20
	maxStderr = 256 << 10
)

// pipeWait is how long a run that exited waits for its output to close:
// a background child it left holding stdout (`daemon &`) would keep the
// reply waiting for as long as it lives
const pipeWait = 2 * time.Second

// Result is a finished run.
type Result struct {
	ExitCode int    `json:"exitCode"` // -1: killed by a signal
	Stdout   string `json:"stdout"`
	Stderr   string `json:"stderr"`
}

// Options are what every command runs with.
type Options struct {
	// Env is the environment (nil: the daemon's own)
	Env []string
	// PipeWait replaces pipeWait (tests)
	PipeWait time.Duration
}

// Run runs argv and waits for it. Input, when not nil, is written to its
// stdin, which is then closed: how secrets reach a command (never argv,
// never logged); without it stdin is /dev/null. No timeout: a run may
// wait on the user (a terminal, a polkit prompt). When ctx ends first
// (the shell's connection closed, a re-exec) Run returns unavailable and
// the command runs on, reaped when it exits.
func Run(ctx context.Context, o Options, argv []string, input *string) (Result, error) {
	if len(argv) == 0 {
		return Result{}, axerr.New(axerr.BadRequest, "an empty command")
	}
	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.Env = o.Env
	// A group of its own: signals meant for the daemon (a terminal's ^C)
	// don't reach it
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if input != nil {
		cmd.Stdin = strings.NewReader(*input)
	}
	stdout, stderr := &capped{max: maxStdout}, &capped{max: maxStderr}
	cmd.Stdout, cmd.Stderr = stdout, stderr
	cmd.WaitDelay = pipeWait
	if o.PipeWait > 0 {
		cmd.WaitDelay = o.PipeWait
	}
	if err := cmd.Start(); err != nil {
		return Result{}, startError(argv[0], err)
	}
	done := make(chan struct{})
	// Ends when the command does, whether or not anyone still waits
	go func() {
		cmd.Wait()
		close(done)
	}()
	select {
	case <-ctx.Done():
		return Result{}, axerr.Wrap(axerr.Unavailable, ctx.Err(), "%s was still running", argv[0])
	case <-done:
	}
	return Result{ExitCode: cmd.ProcessState.ExitCode(), Stdout: stdout.String(), Stderr: stderr.String()}, nil
}

// Spawn starts argv detached and returns once it's started: through
// setsid -f, which forks it into a session of its own and exits, so it's
// never this process's child (no zombie after a re-exec, nothing tying
// it to the daemon's life) and keeps the signal handling it's given. Its
// stdio is /dev/null.
func Spawn(ctx context.Context, o Options, argv []string) error {
	if len(argv) == 0 {
		return axerr.New(axerr.BadRequest, "an empty command")
	}
	// setsid -f can't report a program that doesn't start: look first
	if _, err := exec.LookPath(argv[0]); err != nil {
		return startError(argv[0], err)
	}
	cmd := exec.CommandContext(ctx, "setsid", append([]string{"-f", "--"}, argv...)...)
	cmd.Env = o.Env
	// No pipes: the program inherits setsid's stdio, and a pipe would
	// keep this waiting for as long as the program lives
	if err := cmd.Run(); err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "starting %s", argv[0])
	}
	return nil
}

func startError(name string, err error) error {
	if errors.Is(err, exec.ErrNotFound) {
		return axerr.Wrap(axerr.NotFound, err, "%s isn't installed", name)
	}
	return axerr.Wrap(axerr.Unavailable, err, "starting %s", name)
}

// capped keeps the first max bytes written to it and drops the rest.
type capped struct {
	buf bytes.Buffer
	max int
}

func (c *capped) Write(p []byte) (int, error) {
	if room := c.max - c.buf.Len(); room > 0 {
		c.buf.Write(p[:min(len(p), room)])
	}
	return len(p), nil
}

func (c *capped) String() string { return c.buf.String() }
