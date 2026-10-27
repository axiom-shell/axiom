// Package supervise runs the shell (quickshell) as the daemon's child:
// starting it, restarting it after a crash with a growing delay, giving up
// on one that keeps crashing, and stopping it. A pid file in the runtime
// directory names the running child, so a daemon that died without
// stopping it (SIGKILL) has its orphan stopped by the next one rather
// than a second shell starting beside it.
//
// The child gets the daemon's environment (apps the shell launches inherit
// it, so it can't be cut down) with the AXIOM_* variables the daemon sets
// replacing any inherited ones.
//
// With NoTHP the child runs with transparent huge pages off: freed heap
// held in huge pages is never returned, and qs frees in small pieces. The
// flag (PR_SET_THP_DISABLE) belongs to a process and its children, and
// os/exec runs nothing between fork and exec, so the child is the running
// axiom image (/proc/self/exe) with NoTHPArg, which sets it on itself and
// execs the command (ExecNoTHP): the daemon, and what it launches, keep
// huge pages.
package supervise

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/fsx"
)

// Options describe the child.
type Options struct {
	Command []string          // argv: qs -p <tree>
	NoTHP   bool              // run Command with transparent huge pages off (ExecNoTHP)
	Env     map[string]string // AXIOM_* (and any other) values set over the inherited environment
	// EnvFunc, when set, is read at each start for values set over Env:
	// what may change while the daemon runs (whether its config is writable)
	EnvFunc func() map[string]string
	Environ []string  // the environment to start from (default os.Environ())
	PIDFile string    // where the child's pid is kept
	Output  io.Writer // the child's stdout and stderr (nil: discarded)
	Log     *slog.Logger

	// Restart delays: Backoff doubles from the first up to the last; a
	// child that ran for Stable resets it. GiveUp crashes within Window
	// stop the restarts.
	Backoff []time.Duration
	Stable  time.Duration
	GiveUp  int
	Window  time.Duration
	// StopGrace is how long a child has to exit after SIGTERM before SIGKILL
	StopGrace time.Duration

	// AdoptPID is a shell already running as this process's child (after a
	// re-exec): supervised instead of starting one
	AdoptPID int

	// OnStart sees each run start, OnExit each run that ended on its own
	// (with whether it crashed), OnStop each one the supervisor stopped
	// (a restart, or ctx ending)
	OnStart func(pid int)
	OnExit  func(pid int, crashed bool)
	OnStop  func(pid int)
}

// Status is what the supervisor is doing.
type Status struct {
	Running  bool   `json:"running"`
	PID      int    `json:"pid"`
	Restarts int    `json:"restarts"`
	GaveUp   bool   `json:"gaveUp"`
	LastExit string `json:"lastExit,omitempty"`
}

// Supervisor runs one child at a time.
type Supervisor struct {
	opts Options

	mu       sync.Mutex
	proc     *os.Process
	status   Status
	crashes  []time.Time
	restart  chan restartRequest
	extraEnv map[string]string // for the next start only (lock-on-start)
}

type restartRequest struct {
	env  map[string]string
	done chan struct{}
}

// New returns a supervisor; Run starts it.
func New(opts Options) *Supervisor {
	if opts.Log == nil {
		opts.Log = slog.New(slog.DiscardHandler)
	}
	if opts.Backoff == nil {
		opts.Backoff = []time.Duration{time.Second, 8 * time.Second}
	}
	if opts.Stable == 0 {
		opts.Stable = 30 * time.Second
	}
	if opts.GiveUp == 0 {
		opts.GiveUp = 5
	}
	if opts.Window == 0 {
		opts.Window = time.Minute
	}
	if opts.StopGrace == 0 {
		opts.StopGrace = 3 * time.Second
	}
	if opts.Environ == nil {
		opts.Environ = os.Environ()
	}
	return &Supervisor{opts: opts, restart: make(chan restartRequest)}
}

// Status is the current status.
func (s *Supervisor) Status() Status {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.status
}

// Restart stops the child (if running) and starts it again at once, with
// env added for that start only. It also starts a child the supervisor
// gave up on.
func (s *Supervisor) Restart(ctx context.Context, env map[string]string) error {
	req := restartRequest{env: env, done: make(chan struct{})}
	select {
	case s.restart <- req:
	case <-ctx.Done():
		return ctx.Err()
	}
	select {
	case <-req.done:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

// Run supervises until ctx ends, then stops the child.
func (s *Supervisor) Run(ctx context.Context) error {
	if len(s.opts.Command) == 0 {
		return ErrNoCommand
	}
	adopt := s.opts.AdoptPID
	// The pid file names an adopted shell too: it's ours, not an orphan
	if adopt == 0 {
		s.stopOrphan()
	}
	step := 0
	for {
		started := time.Now()
		var exited <-chan exitResult
		if adopt > 0 {
			exited, adopt = s.adopt(adopt), 0
		} else {
			exited = s.start()
		}
		select {
		case <-ctx.Done():
			s.stop(exited)
			return nil
		case req := <-s.restart:
			s.stop(exited)
			s.accept(req)
			step = 0
			continue
		case result := <-exited:
			if !s.exited(result) {
				// A clean exit is the shell quitting on purpose: it starts
				// again only when asked (axiom restart)
				if !s.waitRestart(ctx) {
					return nil
				}
				step = 0
				continue
			}
			if time.Since(started) >= s.opts.Stable {
				step = 0
			}
			if s.gaveUp() {
				s.opts.Log.Error("the shell keeps crashing: not restarting it until asked (axiom restart)", "crashes", s.opts.GiveUp, "window", s.opts.Window)
				if !s.waitRestart(ctx) {
					return nil
				}
				step = 0
				continue
			}
			wait := s.backoff(step)
			step++
			s.opts.Log.Warn("the shell crashed; restarting", "after", wait, "exit", result.String())
			select {
			case <-ctx.Done():
				return nil
			case <-time.After(wait):
			case req := <-s.restart:
				s.accept(req)
				step = 0
			}
		}
	}
}

// backoff is the wait before the step'th restart in a row: the first
// delay doubled per step, capped at the last.
func (s *Supervisor) backoff(step int) time.Duration {
	first, last := s.opts.Backoff[0], s.opts.Backoff[len(s.opts.Backoff)-1]
	if step > 30 {
		return last
	}
	return min(first<<step, last)
}

// accept takes a restart request: its env for the next start, the
// give-up reset.
func (s *Supervisor) accept(req restartRequest) {
	s.mu.Lock()
	s.extraEnv = req.env
	s.status.GaveUp = false
	s.crashes = nil
	s.mu.Unlock()
	close(req.done)
}

// waitRestart waits for a Restart, false when ctx ends first.
func (s *Supervisor) waitRestart(ctx context.Context) bool {
	select {
	case <-ctx.Done():
		return false
	case req := <-s.restart:
		s.accept(req)
		return true
	}
}

type exitResult struct {
	err error
}

func (r exitResult) String() string {
	if r.err == nil {
		return "exit 0"
	}
	return r.err.Error()
}

// start starts the child; the channel gets its exit (at once, when it
// can't start, which then counts as a crash).
func (s *Supervisor) start() <-chan exitResult {
	s.mu.Lock()
	extra := s.extraEnv
	s.extraEnv = nil
	s.mu.Unlock()

	argv := s.opts.Command
	if s.opts.NoTHP {
		// The image running, not the path it came from: an update may
		// have replaced that with a binary of another version
		argv = append([]string{"/proc/self/exe", NoTHPArg}, argv...)
	}
	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.Env = s.environ(extra)
	cmd.Stdout, cmd.Stderr = s.opts.Output, s.opts.Output
	// Its own process group, so a stop reaches what it started but the
	// terminal's ^C doesn't reach it ahead of the daemon
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	done := make(chan exitResult, 1)
	if err := cmd.Start(); err != nil {
		s.opts.Log.Error("starting the shell", "command", s.opts.Command[0], "err", err)
		done <- exitResult{err: err}
		return done
	}
	pid := cmd.Process.Pid
	s.writePID(pid)
	s.mu.Lock()
	s.proc = cmd.Process
	s.status.Running, s.status.PID = true, pid
	s.mu.Unlock()
	s.opts.Log.Info("started the shell", "pid", pid)
	if s.opts.OnStart != nil {
		s.opts.OnStart(pid)
	}
	go func() { done <- exitResult{err: cmd.Wait()} }()
	return done
}

// adopt supervises a child this process already has (its pid survived a
// re-exec): waiting on it works as for one it started.
func (s *Supervisor) adopt(pid int) <-chan exitResult {
	done := make(chan exitResult, 1)
	proc, err := os.FindProcess(pid)
	if err != nil {
		done <- exitResult{err: err}
		return done
	}
	s.mu.Lock()
	s.proc = proc
	s.status.Running, s.status.PID = true, pid
	s.mu.Unlock()
	s.opts.Log.Info("supervising the shell started before the re-exec", "pid", pid)
	go func() {
		state, err := proc.Wait()
		if err == nil && !state.Success() {
			err = errors.New(state.String())
		}
		done <- exitResult{err: err}
	}()
	return done
}

// Environ is the environment the shell starts with now, which the
// commands it asks the daemon to run (exec.*) get too.
func (s *Supervisor) Environ() []string { return s.environ(nil) }

func (s *Supervisor) environ(extra map[string]string) []string {
	set := map[string]string{}
	for k, v := range s.opts.Env {
		set[k] = v
	}
	if s.opts.EnvFunc != nil {
		for k, v := range s.opts.EnvFunc() {
			set[k] = v
		}
	}
	for k, v := range extra {
		set[k] = v
	}
	var env []string
	for _, kv := range s.opts.Environ {
		name, _, _ := strings.Cut(kv, "=")
		// Inherited AXIOM_* values never reach the child: only the daemon's
		if strings.HasPrefix(name, "AXIOM_") {
			continue
		}
		if _, overridden := set[name]; overridden {
			continue
		}
		env = append(env, kv)
	}
	for k, v := range set {
		env = append(env, k+"="+v)
	}
	return env
}

// exited records a run's end, reporting whether it was a crash.
func (s *Supervisor) exited(r exitResult) bool {
	crashed := r.err != nil
	s.mu.Lock()
	pid := s.status.PID
	s.proc = nil
	s.status.Running, s.status.PID, s.status.LastExit = false, 0, r.String()
	if crashed {
		s.status.Restarts++
		s.crashes = append(s.crashes, time.Now())
	}
	s.mu.Unlock()
	s.removePID()
	if s.opts.OnExit != nil {
		s.opts.OnExit(pid, crashed)
	}
	return crashed
}

func (s *Supervisor) gaveUp() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	cutoff := time.Now().Add(-s.opts.Window)
	recent := s.crashes[:0]
	for _, t := range s.crashes {
		if t.After(cutoff) {
			recent = append(recent, t)
		}
	}
	s.crashes = recent
	if len(recent) >= s.opts.GiveUp {
		s.status.GaveUp = true
		return true
	}
	return false
}

// stop ends the running child: SIGTERM to its group, SIGKILL after the
// grace period.
func (s *Supervisor) stop(exited <-chan exitResult) {
	s.mu.Lock()
	proc := s.proc
	s.mu.Unlock()
	if proc == nil {
		return
	}
	pgid := proc.Pid
	syscall.Kill(-pgid, syscall.SIGTERM)
	select {
	case r := <-exited:
		s.exitedQuietly(r)
	case <-time.After(s.opts.StopGrace):
		s.opts.Log.Warn("the shell didn't stop in time: killing it", "pid", pgid)
		syscall.Kill(-pgid, syscall.SIGKILL)
		s.exitedQuietly(<-exited)
	}
}

func (s *Supervisor) exitedQuietly(r exitResult) {
	s.mu.Lock()
	pid := s.status.PID
	s.proc = nil
	s.status.Running, s.status.PID, s.status.LastExit = false, 0, r.String()
	s.mu.Unlock()
	s.removePID()
	if s.opts.OnStop != nil {
		s.opts.OnStop(pid)
	}
}

func (s *Supervisor) writePID(pid int) {
	if s.opts.PIDFile == "" {
		return
	}
	if err := fsx.WriteFile(s.opts.PIDFile, []byte(strconv.Itoa(pid)+"\n"), 0o600); err != nil {
		s.opts.Log.Warn("writing the shell's pid file", "err", err)
	}
}

func (s *Supervisor) removePID() {
	if s.opts.PIDFile != "" {
		os.Remove(s.opts.PIDFile)
	}
}

// stopOrphan stops a child an earlier daemon left running, if the pid
// file names a live process running the same command (pids get reused:
// a pid alone proves nothing).
func (s *Supervisor) stopOrphan() {
	if s.opts.PIDFile == "" {
		return
	}
	data, err := os.ReadFile(s.opts.PIDFile)
	if err != nil {
		return
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(data)))
	if err != nil || pid <= 1 {
		os.Remove(s.opts.PIDFile)
		return
	}
	if !s.isOurChild(pid) {
		os.Remove(s.opts.PIDFile)
		return
	}
	s.opts.Log.Warn("stopping the shell an earlier daemon left running", "pid", pid)
	// Its group, as stop does: it was started as a group leader, and what
	// it launched goes with it (the pid alone if it leads none)
	signal := func(sig syscall.Signal) {
		if syscall.Kill(-pid, sig) != nil {
			syscall.Kill(pid, sig)
		}
	}
	signal(syscall.SIGTERM)
	for i := 0; i < int(s.opts.StopGrace/(50*time.Millisecond)); i++ {
		if syscall.Kill(pid, 0) != nil {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	if syscall.Kill(pid, 0) == nil {
		signal(syscall.SIGKILL)
	}
	os.Remove(s.opts.PIDFile)
}

func (s *Supervisor) isOurChild(pid int) bool {
	cmdline, err := os.ReadFile(filepath.Join("/proc", strconv.Itoa(pid), "cmdline"))
	if err != nil {
		return false
	}
	// Exactly: a prefix would take `qs -p /x/axiom` for `qs -p /x/axiom-old`
	want := strings.Join(s.opts.Command, "\x00") + "\x00"
	return bytes.Equal(cmdline, []byte(want))
}

// NoTHPArg is the first argument that makes the axiom binary run
// ExecNoTHP on the rest (cli.Main): a contract only with the image
// itself, never another version.
const NoTHPArg = "exec-no-thp"

// ExecNoTHP turns transparent huge pages off for this process and what it
// runs, then execs argv in its place (looked up in $PATH), keeping its
// pid, process group and environment. It returns only when the exec
// failed; a kernel refusing the flag leaves huge pages on rather than the
// shell not starting.
func ExecNoTHP(argv []string, stderr io.Writer) error {
	if len(argv) == 0 {
		return ErrNoCommand
	}
	path, err := exec.LookPath(argv[0])
	if err != nil {
		return err
	}
	if err := unix.Prctl(unix.PR_SET_THP_DISABLE, 1, 0, 0, 0); err != nil {
		fmt.Fprintln(stderr, "axiom: transparent huge pages stay on:", err)
	}
	return syscall.Exec(path, argv, os.Environ())
}

// ErrNoCommand is returned for an empty command.
var ErrNoCommand = errors.New("supervise: no command")
