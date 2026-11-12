package session

import (
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/wayland/wire"
)

// Files of the guard in the display's runtime folder
const (
	RuntimeFile = "session.json"
	GuardLock   = "guard.lock"
)

// PidfdFD is the descriptor the daemon's pidfd is passed as.
const PidfdFD = 3

// StartGuard is what the daemon runs: `axiom guard --stage1` (exe), with
// the daemon's own pidfd as descriptor 3. Stage 1 starts stage 2 in a
// session of its own and exits at once, so the daemon (which waits for
// stage 1 here) never has a zombie, and stage 2 is no child of it.
func StartGuard(exe string) error {
	fd, err := unix.PidfdOpen(os.Getpid(), 0)
	if err != nil {
		return err
	}
	pidfd := os.NewFile(uintptr(fd), "pidfd")
	defer pidfd.Close()
	// os/exec holds the fork lock, so the lock descriptors can't leak
	cmd := exec.Command(exe, "guard", "--stage1")
	cmd.ExtraFiles = []*os.File{pidfd}
	return cmd.Run()
}

// Stage1 is `axiom guard --stage1`: it starts stage 2 and returns.
func Stage1(exe, display string, pidfd *os.File) error {
	cmd := exec.Command(exe, "guard", "--display", display)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	cmd.ExtraFiles = []*os.File{pidfd}
	if err := cmd.Start(); err != nil {
		return err
	}
	return cmd.Process.Release()
}

// GuardOptions configure RunGuard.
type GuardOptions struct {
	Dir           string // the display's runtime folder
	Pidfd         int    // the daemon's pidfd
	WaylandSocket string
	// Base has the teardown's seams, scope, state record and portal env;
	// the guard fills in the rest
	Base TeardownOptions
	// DialBus connects to the session bus (nil result: none)
	DialBus func(ctx context.Context) (Bus, func())
	// Alive says whether the compositor answers (default: its socket
	// accepts a connection)
	Alive func() bool
	Log   Logf
}

func (o GuardOptions) alive() bool {
	if o.Alive != nil {
		return o.Alive()
	}
	conn, err := net.DialTimeout("unix", o.WaylandSocket, 2*time.Second)
	if err != nil {
		return false
	}
	conn.Close()
	return true
}

// RestartPortalFunc is a teardown's RestartPortal: the frontend, through
// bus, in scope, with seams.
func RestartPortalFunc(bus Bus, scope Scope, s Seams, log Logf) func(ctx context.Context) error {
	s = s.WithDefaults()
	return func(ctx context.Context) error {
		if bus == nil {
			return nil
		}
		return RestartPortal(ctx, bus, scope, s.Systemctl, s.Signal, nil, log)
	}
}

// RunGuard is stage 2: it holds guard.lock, and waits for the daemon to
// exit (its pidfd), the compositor to go (its socket), or a signal. When
// the daemon exits without having cleaned up it runs the teardown; when
// the compositor goes it only undoes what files and processes hold. A
// SIGTERM (a logout) ends it without one: the daemon tears down itself.
func RunGuard(ctx context.Context, o GuardOptions) error {
	lock, err := fsx.TryLock(filepath.Join(o.Dir, GuardLock))
	if err != nil {
		if axerr.KindOf(err) == axerr.Running {
			return nil
		}
		return err
	}
	defer lock.Release()
	path := filepath.Join(o.Dir, RuntimeFile)
	rec := ReadRuntime(path, o.Log)
	if rec == nil {
		o.Log.log("guard: no session record: nothing to guard")
		return nil
	}
	if err := checkPidfd(o.Pidfd, rec.DaemonPID); err != nil {
		o.Log.log("guard: refusing: %v", err)
		return err
	}
	rec.GuardPID = os.Getpid()
	if err := rec.Write(path); err != nil {
		return err
	}
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	events := make(chan string, 3)
	go func() {
		exited, err := waitPidfd(ctx, o.Pidfd)
		switch {
		case err != nil:
			o.Log.log("guard: the daemon's pidfd: %v", err)
		case exited:
			events <- "daemon"
		}
	}()
	go func() {
		if err := wire.Watch(ctx, o.WaylandSocket); ctx.Err() == nil && err != nil {
			events <- "compositor"
		}
	}()
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGTERM, syscall.SIGINT)
	defer signal.Stop(sigs)
	o.Log.log("guard: watching daemon %d", rec.DaemonPID)
	var event string
	select {
	case event = <-events:
	case <-sigs:
		o.Log.log("guard: told to stop: leaving the teardown to the daemon")
		return nil
	case <-ctx.Done():
		return nil
	}
	cur := ReadRuntime(path, o.Log)
	if cur == nil {
		o.Log.log("guard: the session record is gone or of another version: leaving it")
		return nil
	}
	if cur.Clean || cur.DaemonPID != rec.DaemonPID {
		o.Log.log("guard: done (the record is clean or another daemon's)")
		return nil
	}
	to := o.Base
	to.Runtime, to.RuntimePath = cur, path
	to.SameInstance = true
	switch event {
	case "daemon":
		to.Compositor = true
		to.CompositorAlive = o.alive()
	case "compositor":
		to.Compositor = false
		to.CompositorAlive = false
		cur.Stopped = nil
	}
	o.Log.log("guard: the %s is gone: tearing down (compositor reachable: %v)", event, to.CompositorAlive)
	if o.DialBus != nil && to.CompositorAlive {
		bus, closeBus := o.DialBus(ctx)
		if closeBus != nil {
			defer closeBus()
		}
		to.Bus = bus
	}
	to.RestartPortal = RestartPortalFunc(to.Bus, to.Scope, to.Seams, o.Log)
	if err := Teardown(context.WithoutCancel(ctx), to); err != nil {
		o.Log.log("guard: %v", err)
	}
	o.Log.log("guard: done")
	return nil
}

// checkPidfd: fd is a pidfd of the daemon (pid): what stage 1 hands down as
// descriptor 3, and nothing else may be taken for it.
func checkPidfd(fd, pid int) error {
	link, err := os.Readlink("/proc/self/fd/" + strconv.Itoa(fd))
	if err != nil || link != "anon_inode:[pidfd]" {
		return fmt.Errorf("descriptor %d isn't a pidfd (%q)", fd, link)
	}
	info, err := os.ReadFile("/proc/self/fdinfo/" + strconv.Itoa(fd))
	if err != nil {
		return err
	}
	for _, line := range strings.Split(string(info), "\n") {
		if v, ok := strings.CutPrefix(line, "Pid:"); ok {
			// -1: it exited already (a valid pidfd, readable at once)
			if got, _ := strconv.Atoi(strings.TrimSpace(v)); got != pid && got != -1 {
				return fmt.Errorf("the pidfd is of process %d, not the daemon %d", got, pid)
			}
			return nil
		}
	}
	return fmt.Errorf("no Pid in the pidfd's info")
}

// waitPidfd waits until the pidfd is readable (the process exited); false
// when ctx ended first. An invalid descriptor or a poll error is an error,
// never "exited".
func waitPidfd(ctx context.Context, fd int) (bool, error) {
	for ctx.Err() == nil {
		fds := []unix.PollFd{{Fd: int32(fd), Events: unix.POLLIN}}
		n, err := unix.Poll(fds, 250)
		if err != nil && !errors.Is(err, unix.EINTR) {
			return false, err
		}
		if n > 0 {
			if fds[0].Revents&(unix.POLLNVAL|unix.POLLERR) != 0 {
				return false, fmt.Errorf("poll revents %#x", fds[0].Revents)
			}
			if fds[0].Revents&unix.POLLIN != 0 {
				return true, nil
			}
		}
	}
	return false, nil
}
