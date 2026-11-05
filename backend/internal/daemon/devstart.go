package daemon

import (
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"syscall"
	"time"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/store"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// The session start in dev mode: at login the installed axiom starts
// first. With dev mode on and a dev tree set, a fresh dev build is exec'd
// into at once, before the schema, the store or the shell, with a Fresh
// handoff (the instance lock only); a missing or stale one leaves the live
// shell on the live config running while it builds, then switches.
//
// The boot guard: before every exec into the dev image (that one, and a
// runtime switch's re-exec: reexecInto) State/dev/boot.json is written
// naming the build; the dev image's shell clears it with its hello. A
// marker still there for the same build at the next session start (the
// dev image or its shell never came up) keeps the session live, with a
// notification, until the build changes. A dev image that fails before it
// serves execs back into the installed binary at once (fallBackLive): a
// session start's with no handoff, a runtime switch's with the handoff it
// carried, onto the install tree and live config; either finds the marker
// and stays live, told why.

// bootFile is the boot guard's marker, under the state folder.
const bootFile = "dev/boot.json"

// startAction is what a session start does about dev mode.
type startAction int

const (
	// startAsIs: run the image started (no dev tree to run, a re-exec, a
	// tree given on the command line)
	startAsIs startAction = iota
	// startExec: exec into the fresh dev build now
	startExec
	// startBuild: live now, the dev build built in the background, then
	// switched to
	startBuild
	// startStayLive: live, and the user told why (the boot guard tripped,
	// the dev tree is gone)
	startStayLive
)

// startDecision is a session start's action, and why (logged; for
// startStayLive, the notification's text).
type startDecision struct {
	Action startAction
	Why    string
}

// startPlan decides a session start: dev mode's choice, its build's check
// (looked at only when dev mode is on with a tree), the handoff (nil: a
// session start), and whether the tree was given (--tree, $AXIOM_TREE),
// which wins over dev mode's. A carried re-exec of the installed axiom
// with dev mode on (a rebuilt installed binary, a self-update) builds a
// stale dev build again: the one building died with the exec, and stays
// live, told why, when the guard tripped (a dev image fell back to it).
// live is the live config's folder. Pure.
func startPlan(choice devChoice, build buildCheck, h *handoff, override bool, live string) startDecision {
	waiting := installImageWaiting(choice, h, override, live)
	switch {
	case waiting && !build.Fresh && !build.Gone:
		return startDecision{startBuild, build.Why}
	case waiting && build.Fresh && build.Guarded:
		return startDecision{startStayLive, guardTripped}
	case h != nil:
		return startDecision{startAsIs, "a re-exec runs the image it was handed"}
	case !choice.Enabled || choice.Tree == "":
		return startDecision{startAsIs, "dev mode runs no tree"}
	case override:
		return startDecision{startAsIs, "the tree was given: dev mode's isn't run at the start"}
	case build.Gone:
		return startDecision{startStayLive, build.Why}
	case !build.Fresh:
		return startDecision{startBuild, build.Why}
	case build.Guarded:
		return startDecision{startStayLive, guardTripped}
	}
	return startDecision{startExec, "the dev build is fresh"}
}

// guardTripped is a tripped boot guard's notification.
const guardTripped = "the dev build didn't come up last time: staying on the installed axiom until it's built again (axiom dev rebuild)"

// installImageWaiting: h is a carried re-exec of the install image (the
// live config, live: inherited fills the folder in) in dev mode, a dev
// tree chosen and not given over.
func installImageWaiting(choice devChoice, h *handoff, override bool, live string) bool {
	return h.carried() && h.Dev && h.ConfigDir == live && choice.Enabled && choice.Tree != "" && !override
}

// bootMarker is boot.json: the build last exec'd into.
type bootMarker struct {
	Tree        string    `json:"tree"`
	Fingerprint string    `json:"fingerprint"`
	Built       time.Time `json:"built"`
	At          time.Time `json:"at"`
}

func (m bootMarker) of(b devBuild) bool {
	return m.Tree == b.Tree && m.Fingerprint == b.Fingerprint && m.Built.Equal(b.At)
}

// guarded: a marker for build b is there (its exec never came up).
func guarded(dirs xdg.Dirs, b devBuild) bool {
	data, err := os.ReadFile(dirs.State + bootFile)
	var m bootMarker
	return err == nil && json.Unmarshal(data, &m) == nil && m.of(b)
}

func writeBoot(dirs xdg.Dirs, b devBuild) error {
	if err := os.MkdirAll(dirs.State+"dev", 0o700); err != nil {
		return err
	}
	data, _ := json.Marshal(bootMarker{Tree: b.Tree, Fingerprint: b.Fingerprint, Built: b.At, At: time.Now()})
	return fsx.WriteFile(dirs.State+bootFile, append(data, '\n'), 0o600)
}

// clearBoot removes the marker (the dev image's shell said hello).
func clearBoot(dirs xdg.Dirs) error {
	if err := os.Remove(dirs.State + bootFile); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

// sessionStart decides what a session start does about dev mode, and on
// startExec execs into the dev build: it returns only when it didn't (the
// decision then startBuild, so the live image builds it again).
func (d *Daemon) sessionStart(h *handoff, choice devChoice) startDecision {
	var check buildCheck
	if (h == nil || installImageWaiting(choice, h, d.opts.TreeOverride, d.dirs.Config)) && choice.Enabled && choice.Tree != "" && !d.opts.TreeOverride {
		check = buildFresh(d.dirs, choice.Tree)
		check.Guarded = check.Fresh && guarded(d.dirs, check.Build)
	}
	plan := startPlan(choice, check, h, d.opts.TreeOverride, d.dirs.Config)
	if plan.Action != startExec {
		return plan
	}
	if err := d.execFresh(check.Build); err != nil {
		d.opts.Log.Error("dev mode: the exec into the dev build failed: building it again", "err", err)
		return startDecision{startBuild, "the exec into the dev build failed"}
	}
	return plan // a test's exec that returned
}

// execFresh execs into the dev build b at session start: the boot guard
// first, then a Fresh handoff carrying the instance lock, the installed
// binary and the install tree (opts.Tree: the dev image reads its own tree
// from dev.json). A failed exec leaves no marker and the lock as it was.
func (d *Daemon) execFresh(b devBuild) (err error) {
	if err := writeBoot(d.dirs, b); err != nil {
		return err
	}
	defer func() {
		if err != nil {
			clearBoot(d.dirs)
		}
	}()
	h := handoff{Lock: int(d.instance.File().Fd()), Fresh: true, Installed: d.installed, InstallTree: d.opts.Tree}
	env := h.environ()
	syscall.ForkLock.Lock()
	defer syscall.ForkLock.Unlock()
	if _, err := unix.FcntlInt(uintptr(h.Lock), unix.F_SETFD, 0); err != nil {
		return err
	}
	defer unix.CloseOnExec(h.Lock) // only reached when the exec failed
	d.opts.Log.Info("dev mode: executing the dev build", "binary", DevBinary(d.dirs), "tree", b.Tree)
	return d.execProcess(DevBinary(d.dirs), os.Args, env)
}

// fallsBack: an image started from h falls back to the installed binary
// when it fails before it serves: a dev image (a session start's exec, a
// runtime switch's re-exec) the installed binary handed over to.
func (d *Daemon) fallsBack(h *handoff) bool {
	return h != nil && h.Installed != "" && (h.Fresh || h.ConfigDir == devConfigDir(d.dirs))
}

// fallBackLive is the dev image's way out when it fails before it serves
// (listener: the socket it adopted, for a carried h), and the store
// closed: it execs back into the installed binary, which finds the boot
// marker and stays live. From a session start's exec there's no handoff
// (the instance lock dropped at the exec, which it takes again); from a
// runtime switch the carried one goes on, onto the install tree and live
// config (fallBackCarried). It returns only when it couldn't.
func (d *Daemon) fallBackLive(h *handoff, listener net.Listener, cause error) {
	if !d.fallsBack(h) {
		return
	}
	d.opts.Log.Error("the dev image didn't start: back to the installed axiom", "err", cause)
	var err error
	if h.Fresh {
		d.instance.Release()
		err = d.execProcess(h.Installed, os.Args, os.Environ())
	} else {
		err = d.fallBackCarried(h, listener)
	}
	if err != nil {
		d.opts.Log.Error("re-executing the installed axiom", "err", err)
	}
}

// fallBackCarried re-execs the installed binary with the handoff h
// carried, as reexec would from the install image: the instance lock,
// the socket, the shell and the commands go on; the config's writer lock
// is the live config's, taken again (the store let go of the one it
// had). The shell restarts when it ran the dev image's tree or config
// (needsShellRestart: h's entry and config).
func (d *Daemon) fallBackCarried(h *handoff, listener net.Listener) error {
	lf, ok := listener.(*net.UnixListener)
	if !ok || h.InstallTree == "" {
		return axerr.New(axerr.Internal, "nothing to hand the installed axiom")
	}
	ln, err := lf.File()
	if err != nil {
		return axerr.Wrap(axerr.Internal, err, "the socket to hand over")
	}
	defer ln.Close() // only reached when the exec failed
	// A child of this process may still hold the copy of the lock the
	// store just closed, for the moment between its fork and its exec
	var lock *fsx.Lock
	for try := 0; ; try++ {
		lock, err = fsx.TryLock(filepath.Join(d.dirs.Config, store.FileName+".lock"))
		if axerr.KindOf(err) != axerr.Running || try == 20 {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	if err != nil {
		return err
	}
	defer lock.Release()
	next := *h
	next.Lock, next.ConfigLock, next.Listener = int(d.instance.File().Fd()), int(lock.File().Fd()), int(ln.Fd())
	next.Tree, next.ConfigDir, next.Dev = h.InstallTree, d.dirs.Config, h.Dev
	syscall.ForkLock.Lock()
	defer syscall.ForkLock.Unlock()
	next.Children = d.children.Handoff()
	defer d.children.Resume()
	fds := []int{next.Lock, next.ConfigLock, next.Listener}
	for _, ch := range next.Children {
		fds = append(fds, ch.Output...)
	}
	defer func() {
		for _, fd := range fds {
			unix.CloseOnExec(fd)
		}
	}()
	for _, fd := range fds {
		if _, err := unix.FcntlInt(uintptr(fd), unix.F_SETFD, 0); err != nil {
			return axerr.Wrap(axerr.Internal, err, "keeping a descriptor across the re-exec")
		}
	}
	return d.execProcess(h.Installed, os.Args, next.environ())
}

// execProcess replaces the process (Options.exec in tests).
func (d *Daemon) execProcess(exe string, argv, env []string) error {
	if d.opts.exec != nil {
		return d.opts.exec(exe, argv, env)
	}
	return syscall.Exec(exe, argv, env)
}
