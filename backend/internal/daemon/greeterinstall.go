package daemon

import (
	"context"
	"os/user"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/greeterinstall"
	"github.com/axiom-shell/axiom/backend/internal/greeterinstall/rules"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// greeterInstallPart: GreeterManager's setup of the login screen (package
// greeterinstall): its status, and installing, updating or removing its
// copy as root through pkexec.
func (d *Daemon) greeterInstallPart() part {
	return part{name: "greeter-install", methods: d.greeterInstallMethods}
}

// GreeterStatusRequest names where the copy's code comes from: source
// "git" | "local" | "package", and git's channel.
type GreeterStatusRequest struct {
	Source  string `json:"source"`
	Channel string `json:"channel"`
}

// GreeterApplyRequest is an install, update or uninstall: its source and
// channel, and the bundle the shell just staged for the snapshot.
type GreeterApplyRequest struct {
	Action  string `json:"action"`
	Source  string `json:"source"`
	Channel string `json:"channel"`
	Staged  string `json:"staged"`
}

func (d *Daemon) greeterInstallMethods(reg *rpc.Registry) {
	in := greeterinstall.New(greeterinstall.Options{})
	rpc.Handle(reg, "greeter.status", func(ctx context.Context, c *rpc.Conn, p GreeterStatusRequest) (greeterinstall.Report, error) {
		return in.Status(ctx, d.opts.Tree, p.Source, p.Channel)
	})
	// Only the shell (a user's click) runs anything as root
	rpc.Handle(reg, "greeter.apply", func(ctx context.Context, c *rpc.Conn, p GreeterApplyRequest) (greeterinstall.Elevated, error) {
		if !fromShell(c) {
			return greeterinstall.Elevated{}, axerr.New(axerr.Refused, "only the shell sets up the login screen")
		}
		switch p.Action {
		case rules.ActionInstall, rules.ActionUpdate, rules.ActionUninstall:
		default:
			return greeterinstall.Elevated{}, axerr.New(axerr.BadRequest, "unknown action: %s", p.Action)
		}
		me, err := user.Current()
		if err != nil {
			return greeterinstall.Elevated{}, err
		}
		// A local copy reuses the binary built last: the one running
		req := rules.Request{Action: p.Action, Repo: d.opts.Tree, User: me.Username, Staged: p.Staged,
			Source: p.Source, Channel: p.Channel, Binary: d.executable}
		return in.Elevate(ctx, req)
	})
}
