package daemon

import (
	"context"
	"fmt"
	"os/exec"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/buginfo"
	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/sysinfo"
)

// machineParts are the machine's own settings the Settings page shows and
// changes (System info, Date & time, Account, Default apps): kept apart
// from the parts list so they read as one group.
func (d *Daemon) machineParts() []part {
	return []part{d.systemPart()}
}

// machineMethods are machineParts' methods, for Contract.
func (d *Daemon) machineMethods() []func(*rpc.Registry) {
	var out []func(*rpc.Registry)
	for _, p := range d.machineParts() {
		out = append(out, p.methods)
	}
	return out
}

// systemBus dials the system bus, for the parts that ask polkit-guarded
// services (hostnamed, timedated, AccountsService).
func (d *Daemon) systemBus(ctx context.Context) (*dbus.Conn, error) {
	return dbus.Dial(ctx, dbus.SystemAddress(d.opts.Getenv), dbus.Options{Log: d.opts.Log.With("part", "system bus")})
}

// SystemInfo is system.info's answer: the machine as the card shows it,
// and the bug report's lines ("Copy system info", nothing personal).
type SystemInfo struct {
	Info   sysinfo.Info   `json:"info"`
	Report buginfo.Report `json:"report"`
}

// systemPart: Settings › System › System info (SystemInfoManager).
func (d *Daemon) systemPart() part {
	reader := sysinfo.New(sysinfo.Options{SystemBus: d.systemBus})
	type renameParams struct {
		Name string `json:"name"`
	}
	return part{
		name: "system",
		methods: func(reg *rpc.Registry) {
			rpc.Handle(reg, "system.info", func(ctx context.Context, c *rpc.Conn, _ struct{}) (SystemInfo, error) {
				out := SystemInfo{Info: reader.Read()}
				info := buildinfo.Get()
				out.Report.Binary = fmt.Sprintf("axiom %s (commit %s), running", info.Version, shortCommit(info.Commit))
				if d.store != nil {
					cfg, st := d.store.Config()
					out.Report.Config = buginfo.ConfigLine(cfg, st)
				}
				buginfo.Machine(ctx, buginfo.Options{
					Tree:       d.opts.Tree,
					Compositor: buginfo.CompositorFromEnv(d.opts.Getenv),
					Desktop:    d.opts.Getenv("XDG_CURRENT_DESKTOP"),
					Output: func(ctx context.Context, name string, args ...string) (string, error) {
						out, err := exec.CommandContext(ctx, name, args...).Output()
						return string(out), err
					},
					OSRelease: []string{"/etc/os-release", "/usr/lib/os-release"},
				}, &out.Report)
				return out, nil
			})
			// Only the shell (a click on Rename) renames the machine
			rpc.Handle(reg, "system.setHostname", func(ctx context.Context, c *rpc.Conn, p renameParams) (struct{}, error) {
				if !fromShell(c) {
					return struct{}{}, axerr.New(axerr.Refused, "only the shell renames the machine")
				}
				return struct{}{}, reader.Rename(ctx, p.Name)
			})
		},
	}
}

func shortCommit(commit string) string {
	if commit == "" {
		return buginfo.Unknown
	}
	return commit[:min(len(commit), 12)]
}
