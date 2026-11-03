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
	"github.com/axiom-shell/axiom/backend/internal/xdg"
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

	// The image the next one runs (reexec's img): the tree its shell runs
	// on (its own search may find no tree, or another), the folder its
	// config is in ("": the live one), and dev mode (a runtime switch
	// isn't in the arguments)
	Tree      string `json:"tree,omitempty"`
	ConfigDir string `json:"configDir,omitempty"`
	Dev       bool   `json:"dev,omitempty"`
	// The install tree (self-update's and the greeter's, whatever tree
	// the shell runs) and the installed binary, while a dev build runs
	InstallTree string `json:"installTree,omitempty"`
	Installed   string `json:"installed,omitempty"`
	// What the adopted shell runs: its QML dir (`qs -p`) and the folder
	// of the config it reads, whose writer lock ConfigLock is ("": the
	// live one). The next image adopts the lock only when it runs on the
	// same folder, and restarts the shell when either differs (an image
	// of before ShellEntry ran the old layout)
	ShellEntry    string `json:"shellEntry,omitempty"`
	ConfigLockDir string `json:"configLockDir,omitempty"`
	// When the first image started (daemon.status's uptime)
	Started int64 `json:"started,omitempty"`

	// Fresh: an exec at session start, before anything was opened (the
	// installed binary handing over to a fresh dev build): it carries the
	// instance lock (and the installed binary and install tree, which the
	// dev build can't find itself) and nothing to adopt; the next image
	// runs the dev tree on the dev config, as dev.json says
	Fresh bool `json:"fresh,omitempty"`
}

// image is what a daemon image runs: the tree the shell runs on, the
// folder of its config (dirs.Config, or devConfigDir for the dev image),
// and whether dev mode is on.
type image struct {
	Tree      string
	ConfigDir string
	Dev       bool
}

// image is the image running now (what a re-exec that changes nothing
// passes on).
func (d *Daemon) image() image {
	return image{Tree: d.opts.Tree, ConfigDir: d.configDir, Dev: d.dev.Enabled()}
}

// devConfigDir is the dev config's folder (Config/dev/), which the dev
// image runs on and the install never reads.
func devConfigDir(dirs xdg.Dirs) string { return dirs.Config + "dev/" }

// inherited reads (and clears) a handoff from the environment, its config
// folders filled in ("": the live one) and checked to be one of the two.
func inherited(getenv func(string) string, dirs xdg.Dirs) (*handoff, error) {
	raw := getenv(ReexecEnv)
	if raw == "" {
		return nil, nil
	}
	os.Unsetenv(ReexecEnv)
	var h handoff
	if err := json.Unmarshal([]byte(raw), &h); err != nil || !h.wellFormed() {
		return nil, axerr.New(axerr.Refused, "a malformed %s", ReexecEnv)
	}
	if h.Fresh {
		return &h, nil
	}
	for _, dir := range []*string{&h.ConfigDir, &h.ConfigLockDir} {
		if *dir == "" {
			*dir = dirs.Config
		}
		if *dir != dirs.Config && *dir != devConfigDir(dirs) {
			return nil, axerr.New(axerr.Refused, "a %s naming another config folder (%s)", ReexecEnv, *dir)
		}
	}
	return &h, nil
}

// wellFormed: the descriptors a handoff hands over aren't stdio's. A
// Fresh one hands over only the instance lock: nothing else to adopt, and
// no image (the next one reads dev.json).
func (h *handoff) wellFormed() bool {
	if h.Lock < 3 {
		return false
	}
	if h.Fresh {
		return h.ConfigLock == 0 && h.Listener == 0 && h.Shell == 0 && len(h.Children) == 0 &&
			h.Schema == "" && !h.Locked && h.Tree == "" && h.ConfigDir == "" && !h.Dev &&
			h.ShellEntry == "" && h.ConfigLockDir == "" && h.Started == 0
	}
	return h.Listener >= 3 && h.ConfigLock >= 3
}

// carried: h is a re-exec of a running daemon (not a session-start exec,
// which hands over only the instance lock).
func (h *handoff) carried() bool { return h != nil && !h.Fresh }

// startImage is the image a daemon starts (and its install tree): a
// re-exec's names it; a session-start exec runs the dev tree on the dev
// config (the install image, should dev.json no longer say dev on with a
// tree);
// otherwise the tree run found, on the live config, dev mode as --dev or
// the saved choice says.
func startImage(h *handoff, choice devChoice, opts Options, dirs xdg.Dirs) (img image, installTree string) {
	switch {
	case h.carried():
		img = image{Tree: h.Tree, ConfigDir: h.ConfigDir, Dev: h.Dev}
		if img.Tree == "" {
			img.Tree = opts.Tree
		}
		installTree = h.InstallTree
		if installTree == "" {
			// An image of before the field ran the install tree
			installTree = img.Tree
		}
		return img, installTree
	case h != nil && choice.Enabled && choice.Tree != "":
		installTree = h.InstallTree
		if installTree == "" {
			installTree = opts.Tree
		}
		return image{Tree: choice.Tree, ConfigDir: devConfigDir(dirs), Dev: true}, installTree
	}
	return image{Tree: opts.Tree, ConfigDir: dirs.Config, Dev: opts.Dev || choice.Enabled}, opts.Tree
}

// reexec replaces this process with the binary at exe (this one's path,
// the installed binary, or a dev build) running img, keeping the locks,
// the socket and the shell. The config's writer lock goes along only when
// img runs on the same config: otherwise the exec drops it and the next
// image opens its own. Clients are told first (daemon.closing), then see
// their connection close and reconnect. An exec that fails leaves the
// daemon as it was.
func (d *Daemon) reexec(exe string, img image) (err error) {
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
		Lock:          int(d.instance.File().Fd()),
		ConfigLock:    int(d.store.LockFile().Fd()),
		Listener:      int(listener.Fd()),
		Shell:         d.shellPID(),
		Locked:        d.locker.Held(),
		Tree:          img.Tree,
		ConfigDir:     img.ConfigDir,
		Dev:           img.Dev,
		InstallTree:   d.installTree,
		Installed:     d.installed,
		ShellEntry:    d.shellEntry,
		ConfigLockDir: d.configDir,
		Started:       d.started.UnixMilli(),
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
	d.opts.Log.Info("re-executing", "binary", exe, "shell", h.Shell, "tree", img.Tree, "config", img.ConfigDir)
	err = syscall.Exec(exe, os.Args, env)
	d.store.Thaw()
	return axerr.Wrap(axerr.Unavailable, err, "re-executing %s", exe)
}

// adopt takes the handoff's descriptors and commands over (a Fresh one's
// instance lock only: no listener).
func (d *Daemon) adopt(h *handoff) (net.Listener, error) {
	instance, err := fsx.Adopt(os.NewFile(uintptr(h.Lock), "daemon.lock"), d.runtime.Lock())
	if err != nil {
		return nil, err
	}
	d.instance = instance
	if h.Fresh {
		return nil, nil
	}
	for _, ch := range h.Children {
		d.children.Adopt(ch)
	}
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
