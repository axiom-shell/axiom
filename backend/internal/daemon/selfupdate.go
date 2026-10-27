package daemon

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/selfupdate"
)

// selfUpdatePart: SelfUpdateManager's updates of the tree the shell runs
// from (package selfupdate), and after one the axiom binary rebuilt from
// it and re-exec'd into, so the daemon's embedded schema is the tree's.
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
	u := selfupdate.New(selfupdate.Options{Dir: d.opts.Tree, Environ: func() []string {
		// The shell's environment (its ssh agent), as when it ran git itself
		if d.shell != nil {
			return d.shell.Environ()
		}
		return os.Environ()
	}})
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
		r.Rebuilt, r.BuildError = d.rebuildInstalled(context.WithoutCancel(ctx))
		if r.Rebuilt {
			// The new image takes the daemon over once this reply is out;
			// when the update changed the schema it restarts the shell
			d.opts.Log.Info("self-update: rebuilt the binary, re-executing", "binary", d.installed)
			d.reexecSoon(d.installed)
		}
		return r, nil
	})
}

// rebuildInstalled builds the installed binary again from the updated
// tree, when this user may replace it (install.sh's in ~/.local/bin, not
// a package's): whether it did, or why that failed ("" when it wasn't
// tried).
func (d *Daemon) rebuildInstalled(ctx context.Context) (bool, string) {
	bin := d.installed
	if bin == "" || unix.Access(bin, unix.W_OK) != nil || unix.Access(filepath.Dir(bin), unix.W_OK) != nil {
		return false, ""
	}
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
