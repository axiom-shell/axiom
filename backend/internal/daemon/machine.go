package daemon

import (
	"context"
	"fmt"
	"os/exec"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/buginfo"
	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/sysinfo"
	"github.com/axiom-shell/axiom/backend/internal/timedate"
)

// machinePushShapes are machine.go's pushes, for Contract.
func machinePushShapes() []rpc.PushShape {
	return []rpc.PushShape{pushDatetimeState.Shape()}
}

// machineParts are the machine's own settings the Settings page shows and
// changes (System info, Date & time, Account, Default apps): kept apart
// from the parts list so they read as one group.
func (d *Daemon) machineParts() []part {
	return []part{d.systemPart(), d.datetimePart()}
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

// datetimePart: Settings › System › Date & time (DateTimeManager): the
// time zone, network time and the clock, through timedated; its changes,
// made anywhere, are pushed while the daemon runs.
func (d *Daemon) datetimePart() part {
	clock := timedate.New(timedate.Options{SystemBus: d.systemBus, Log: d.opts.Log.With("part", "datetime")})
	type zoneParams struct {
		Timezone string `json:"timezone"`
	}
	type ntpParams struct {
		On bool `json:"on"`
	}
	type timeParams struct {
		// ms since the epoch, as the shell's Date.getTime()
		At int64 `json:"at"`
	}
	// Only the shell (a click in Settings) changes the clock
	shellOnly := func(c *rpc.Conn) error {
		if !fromShell(c) {
			return axerr.New(axerr.Refused, "only the shell changes the clock")
		}
		return nil
	}
	return part{
		name: "datetime",
		methods: func(reg *rpc.Registry) {
			rpc.Handle(reg, "datetime.get", func(ctx context.Context, c *rpc.Conn, _ struct{}) (timedate.State, error) {
				return clock.Get(ctx), nil
			})
			rpc.Handle(reg, "datetime.setTimezone", func(ctx context.Context, c *rpc.Conn, p zoneParams) (timedate.State, error) {
				if err := shellOnly(c); err != nil {
					return timedate.State{}, err
				}
				if err := clock.SetTimezone(ctx, p.Timezone); err != nil {
					return timedate.State{}, err
				}
				return clock.Get(ctx), nil
			})
			rpc.Handle(reg, "datetime.setNtp", func(ctx context.Context, c *rpc.Conn, p ntpParams) (timedate.State, error) {
				if err := shellOnly(c); err != nil {
					return timedate.State{}, err
				}
				if err := clock.SetNTP(ctx, p.On); err != nil {
					return timedate.State{}, err
				}
				return clock.Get(ctx), nil
			})
			rpc.Handle(reg, "datetime.setTime", func(ctx context.Context, c *rpc.Conn, p timeParams) (timedate.State, error) {
				if err := shellOnly(c); err != nil {
					return timedate.State{}, err
				}
				if err := clock.SetTime(ctx, time.UnixMilli(p.At)); err != nil {
					return timedate.State{}, err
				}
				return clock.Get(ctx), nil
			})
		},
		// Follows timedated: a lost bus or a timedated that isn't there
		// (no systemd) is tried again a while later, never an error
		run: func(ctx context.Context) error {
			for {
				err := clock.Watch(ctx, func(st timedate.State) {
					if d.server != nil {
						pushDatetimeState.Send(d.server, st, fromShell)
					}
				})
				if err != nil {
					d.opts.Log.Debug("not following timedated", "part", "datetime", "err", err)
				}
				select {
				case <-ctx.Done():
					return nil
				case <-time.After(time.Minute):
				}
			}
		},
	}
}
