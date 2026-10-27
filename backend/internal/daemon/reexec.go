package daemon

import (
	"encoding/json"
	"net"
	"os"
	"strings"
	"syscall"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/command"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
)

// reexecEnv carries a handoff from the image before a re-exec (an updated
// binary taking over) to the one after: the descriptors it keeps open and
// the shell it supervises and the commands it runs (still this process's
// children: execve keeps the pid). The handoff is trusted only when its
// instance-lock descriptor really is the held lock of this display, which
// only the previous holder could pass on.
const reexecEnv = "AXIOM_REEXEC"

type handoff struct {
	Lock       int `json:"lock"`
	ConfigLock int `json:"configLock"`
	Listener   int `json:"listener"`
	Shell      int `json:"shell"`
	// The commands running, for the next image to drain and reap
	Children []command.Child `json:"children,omitempty"`
	// The schema the shell read, and whether it held the session lock: a
	// new image whose tree builds another schema (an update) restarts the
	// shell, locked first when it was
	Schema string `json:"schema,omitempty"`
	Locked bool   `json:"locked,omitempty"`
	// Dev mode as it was (a runtime switch isn't in the arguments), and
	// the installed binary while a dev build runs
	Dev       bool   `json:"dev,omitempty"`
	Installed string `json:"installed,omitempty"`
	// When the first image started (daemon.status's uptime)
	Started int64 `json:"started,omitempty"`
}

// inherited reads (and clears) a handoff from the environment.
func inherited(getenv func(string) string) (*handoff, error) {
	raw := getenv(reexecEnv)
	if raw == "" {
		return nil, nil
	}
	os.Unsetenv(reexecEnv)
	var h handoff
	if err := json.Unmarshal([]byte(raw), &h); err != nil || h.Lock < 3 || h.Listener < 3 || h.ConfigLock < 3 {
		return nil, axerr.New(axerr.Refused, "a malformed %s", reexecEnv)
	}
	return &h, nil
}

// reexec replaces this process with the binary at exe (this one's path,
// the installed binary, or a dev build), keeping the locks, the socket and
// the shell. Clients are told first (daemon.closing), then see their
// connection close and reconnect. An exec
// that fails leaves the daemon as it was.
func (d *Daemon) reexec(exe string) (err error) {
	if _, err := os.Stat(exe); err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "the binary to re-exec")
	}
	lf, ok := d.listener.(*net.UnixListener)
	if !ok {
		return axerr.New(axerr.Internal, "the socket can't be handed over")
	}
	listener, err := lf.File() // a duplicate, without close-on-exec once cleared
	if err != nil {
		return axerr.Wrap(axerr.Internal, err, "the socket to hand over")
	}
	defer listener.Close() // only reached when the exec failed
	h := handoff{
		Lock:       int(d.instance.File().Fd()),
		ConfigLock: int(d.store.LockFile().Fd()),
		Listener:   int(listener.Fd()),
		Shell:      d.shellPID(),
		Locked:     d.locker.State().Locked,
		Dev:        d.dev.Enabled(),
		Installed:  d.installed,
		Started:    d.started.UnixMilli(),
	}
	_, h.Schema = d.currentSchema()
	// The clients close their side first, so the exec's close is no
	// error to them
	announceClosing(d.server, true, closingWait)
	// No child may start while the descriptors lose close-on-exec (it
	// would inherit the locks): every fork takes ForkLock first
	syscall.ForkLock.Lock()
	defer syscall.ForkLock.Unlock()
	fds := []int{h.Lock, h.ConfigLock, h.Listener}
	h.Children = d.children.Handoff()
	for _, ch := range h.Children {
		fds = append(fds, ch.Output...)
	}
	defer func() {
		if err != nil {
			d.children.Resume()
			for _, fd := range fds {
				unix.FcntlInt(uintptr(fd), unix.F_SETFD, unix.FD_CLOEXEC)
			}
		}
	}()
	for _, fd := range fds {
		if _, err := unix.FcntlInt(uintptr(fd), unix.F_SETFD, 0); err != nil {
			return axerr.Wrap(axerr.Internal, err, "keeping a descriptor across the re-exec")
		}
	}
	data, _ := json.Marshal(h)
	env := []string{reexecEnv + "=" + string(data)}
	for _, kv := range os.Environ() {
		if !strings.HasPrefix(kv, reexecEnv+"=") {
			env = append(env, kv)
		}
	}
	// No config write may be cut in half: hold the store until the exec
	d.store.Freeze()
	d.opts.Log.Info("re-executing", "binary", exe, "shell", h.Shell)
	err = syscall.Exec(exe, os.Args, env)
	d.store.Thaw()
	return axerr.Wrap(axerr.Unavailable, err, "re-executing %s", exe)
}

// adopt takes the handoff's descriptors and commands over.
func (d *Daemon) adopt(h *handoff) (net.Listener, error) {
	for _, ch := range h.Children {
		command.Adopt(ch)
	}
	instance, err := fsx.Adopt(os.NewFile(uintptr(h.Lock), "daemon.lock"), d.runtime.Lock())
	if err != nil {
		return nil, err
	}
	d.instance = instance
	inherited := os.NewFile(uintptr(h.Listener), "axiom.sock")
	ln, err := net.FileListener(inherited)
	// FileListener works on a duplicate (close-on-exec): the inherited
	// descriptor, without it, mustn't stay open for children to inherit
	inherited.Close()
	if err != nil {
		return nil, axerr.Wrap(axerr.Refused, err, "the inherited socket")
	}
	if ul, ok := ln.(*net.UnixListener); ok {
		ul.SetUnlinkOnClose(true)
	}
	return ln, nil
}
