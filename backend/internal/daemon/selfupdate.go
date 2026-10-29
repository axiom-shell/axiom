package daemon

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/release/fetch"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/selfupdate"
)

// selfUpdatePart: SelfUpdateManager's updates of the tree the shell runs
// from (package selfupdate), and after one the axiom binary replaced to
// match it and re-exec'd into, so the daemon's embedded schema is the
// tree's: the official build of the commit checked out when there is one
// (maintainer, 2026-10-27: "Download, build fallback (Recommended)"),
// else built from the tree.
func (d *Daemon) selfUpdatePart() part {
	return part{name: "self-update", methods: d.selfUpdateMethods}
}

// SelfUpdateRequest names the channel; Apply also the update to apply
// (the Latest a check reported).
type SelfUpdateRequest struct {
	Channel string `json:"channel"`
	Target  string `json:"target,omitempty"`
}

func (d *Daemon) selfUpdateMethods(reg *rpc.Registry) {
	releases := fetch.New(fetch.Options{Base: d.opts.releases})
	u := selfupdate.New(selfupdate.Options{Dir: d.opts.Tree, Environ: func() []string {
		// The shell's environment (its ssh agent), as when it ran git itself
		if d.shell != nil {
			return d.shell.Environ()
		}
		return os.Environ()
	}, EdgeCommit: releases.EdgeCommit})
	rpc.Handle(reg, "selfupdate.status", func(ctx context.Context, c *rpc.Conn, p SelfUpdateRequest) (selfupdate.Report, error) {
		return u.Status(ctx, p.Channel)
	})
	rpc.Handle(reg, "selfupdate.check", func(ctx context.Context, c *rpc.Conn, p SelfUpdateRequest) (selfupdate.Report, error) {
		return u.Check(ctx, p.Channel)
	})
	// Only the shell (a user's click, or SelfUpdate.mode auto) updates
	rpc.Handle(reg, "selfupdate.apply", func(ctx context.Context, c *rpc.Conn, p SelfUpdateRequest) (selfupdate.Report, error) {
		if !fromShell(c) {
			return selfupdate.Report{}, axerr.New(axerr.Refused, "only the shell applies a self-update")
		}
		r, err := u.Apply(ctx, p.Channel, p.Target)
		if err != nil || r.Error != "" {
			return r, err
		}
		ctx = context.WithoutCancel(ctx)
		r.Rebuilt, r.BinarySource, r.BuildError = d.replaceInstalled(ctx, releases, p.Channel, r.Latest, u.Head(ctx))
		if r.Rebuilt {
			// The new image takes the daemon over once this reply is out;
			// when the update changed the schema it restarts the shell
			d.opts.Log.Info("self-update: replaced the binary, re-executing", "binary", d.installed, "from", r.BinarySource)
			d.reexecSoon(d.installed)
		}
		return r, nil
	})
}

// replaceInstalled replaces the installed binary to match the updated
// tree, when this user may replace it (install.sh's in ~/.local/bin, not
// a package's): with the official build of the commit checked out, the
// tag's release (tags) or main's newest build when it's head's (main),
// checked against its SHA256SUMS; else built from the tree. It says
// whether it did, from where, or why that failed ("" when it wasn't
// tried).
func (d *Daemon) replaceInstalled(ctx context.Context, releases *fetch.Fetcher, channel, tag, head string) (bool, string, string) {
	bin := d.installed
	if bin == "" || unix.Access(bin, unix.W_OK) != nil || unix.Access(filepath.Dir(bin), unix.W_OK) != nil {
		return false, "", ""
	}
	var data []byte
	var err error
	source := "release"
	if channel == selfupdate.ChannelMain {
		source = "edge"
		var commit string
		if commit, data, err = releases.Edge(ctx, runtime.GOARCH); err == nil && commit != head {
			data, err = nil, fmt.Errorf("main's newest build is %.12s, not %.12s: %w", commit, head, fetch.ErrMissing)
		}
	} else {
		data, err = releases.Binary(ctx, tag, runtime.GOARCH)
	}
	if err == nil {
		if err = installBinary(ctx, data, bin); err == nil {
			return true, source, ""
		}
	}
	if errors.Is(err, fetch.ErrMissing) {
		d.opts.Log.Info("self-update: no official build to download, building", "reason", err)
	} else {
		d.opts.Log.Warn("self-update: the official build wasn't taken, building", "err", err)
	}
	rebuilt, reason := d.rebuildInstalled(ctx)
	if rebuilt {
		return true, "built", ""
	}
	return false, "", reason
}

// rebuildInstalled builds the installed binary again from the updated
// tree: whether it did, or why that failed.
func (d *Daemon) rebuildInstalled(ctx context.Context) (bool, string) {
	bin := d.installed
	if _, err := exec.LookPath(d.opts.Go); err != nil {
		return false, "go isn't installed"
	}
	out, err := buildAxiom(ctx, d.opts.Go, d.opts.Tree, bin)
	if err == nil {
		return true, ""
	}
	d.opts.Log.Error("self-update: the binary didn't build", "err", err, "output", string(out))
	// The compiler's first line says why, else the step that failed
	for _, line := range strings.Split(string(out), "\n") {
		if line = strings.TrimSpace(line); line != "" {
			return false, line
		}
	}
	return false, err.Error()
}

// installBinary puts a downloaded binary in target's place: written
// beside it, checked to run, then swapped in.
func installBinary(ctx context.Context, data []byte, target string) error {
	next := target + ".new"
	defer os.Remove(next)
	// Written with forks held off (os/exec forks under ForkLock's write
	// lock): a child forked meanwhile holds the file open for writing
	// until it execs, and running it then (swapIn) fails with ETXTBSY
	syscall.ForkLock.RLock()
	err := os.WriteFile(next, data, 0o755)
	syscall.ForkLock.RUnlock()
	if err != nil {
		return err
	}
	_, err = swapIn(ctx, next, target)
	return err
}
