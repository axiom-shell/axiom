package daemon

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
	"github.com/axiom-shell/axiom/backend/internal/command"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/tree"
)

// ReexecEnv carries a handoff from the image before a re-exec (an updated
// binary taking over) to the one after: the descriptors it keeps open and
// the shell it supervises and the commands it runs (still this process's
// children: execve keeps the pid). The handoff is trusted only when its
// instance-lock descriptor really is the held lock of this display, which
// only the previous holder could pass on.
const ReexecEnv = "AXIOM_REEXEC"

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
	// The tree the shell runs on: the next image runs the same one (its
	// own search may find no tree, or another), and restarts the shell
	// when it doesn't (an image of before this field ran the old layout)
	Tree string `json:"tree,omitempty"`
	// Dev mode as it was (a runtime switch isn't in the arguments), and
	// the installed binary while a dev build runs
	Dev       bool   `json:"dev,omitempty"`
	Installed string `json:"installed,omitempty"`
	// When the first image started (daemon.status's uptime)
	Started int64 `json:"started,omitempty"`
}

// inherited reads (and clears) a handoff from the environment.
func inherited(getenv func(string) string) (*handoff, error) {
	raw := getenv(ReexecEnv)
	if raw == "" {
		return nil, nil
	}
	os.Unsetenv(ReexecEnv)
	var h handoff
	if err := json.Unmarshal([]byte(raw), &h); err != nil || h.Lock < 3 || h.Listener < 3 || h.ConfigLock < 3 {
		return nil, axerr.New(axerr.Refused, "a malformed %s", ReexecEnv)
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
		Tree:       d.opts.Tree,
		Locked:     d.locker.Held(),
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
	env := []string{ReexecEnv + "=" + string(data)}
	for _, kv := range os.Environ() {
		if !strings.HasPrefix(kv, ReexecEnv+"=") {
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
		d.children.Adopt(ch)
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

// upgradeTarget is the binary to re-exec into for a client speaking
// protocol want, newer than this image's: the dev build (in dev mode),
// else the installed one, the first that speaks it, and only when the
// tree's files do too (a stray newer CLI never strands the shell). ""
// when none does; each binary is tried once. Once one is found, every
// newer hello until the exec gets it too (start: only the first, which
// re-execs), so one said meanwhile isn't refused.
func (d *Daemon) upgradeTarget(ctx context.Context, want int) (exe string, start bool) {
	if want <= buildinfo.Protocol() || protocolIn(filepath.Join(tree.QMLDir(d.opts.Tree), "config", "json", "backend.json")) != want {
		return "", false
	}
	d.upgradeMu.Lock()
	defer d.upgradeMu.Unlock()
	if d.upgrading != "" {
		return d.upgrading, false
	}
	candidates := []string{d.installed}
	if d.dev.Enabled() {
		candidates = []string{DevBinary(d.dirs), d.installed}
	}
	for _, exe := range candidates {
		info, err := os.Stat(exe)
		if err != nil {
			continue
		}
		var inode uint64
		if st, ok := info.Sys().(*syscall.Stat_t); ok {
			inode = st.Ino
		}
		key := fmt.Sprint(exe, inode, info.ModTime().UnixNano())
		if d.upgradesTried == nil {
			d.upgradesTried = map[string]bool{}
		}
		if d.upgradesTried[key] {
			continue
		}
		d.upgradesTried[key] = true
		if binaryProtocol(ctx, exe) == want {
			d.upgrading = exe
			return exe, true
		}
	}
	return "", false
}

// binaryProtocol is the protocol the axiom binary at exe speaks (0: it
// didn't say). A hello dropped meanwhile doesn't cut it short: the
// answer is remembered (upgradesTried) for every later hello.
func binaryProtocol(ctx context.Context, exe string) int {
	ctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 2*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, exe, "version", "--json").Output()
	var info struct {
		Protocol int `json:"protocol"`
	}
	if err != nil || json.Unmarshal(out, &info) != nil {
		return 0
	}
	return info.Protocol
}

// protocolIn is the protocol a backend.json names (0: unreadable).
func protocolIn(path string) int {
	data, err := os.ReadFile(path)
	var file struct {
		Protocol int `json:"protocol"`
	}
	if err != nil || json.Unmarshal(data, &file) != nil {
		return 0
	}
	return file.Protocol
}
