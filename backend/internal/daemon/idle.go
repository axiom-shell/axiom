package daemon

import (
	"context"
	"strconv"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/idle"
	"github.com/axiom-shell/axiom/backend/internal/ipcroute"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/shellcmd"
	"github.com/axiom-shell/axiom/backend/internal/store"
)

// newIdle is the idle service (the Idle section), on the daemon's Wayland
// connection, the buses and the shell.
func (d *Daemon) newIdle() *idle.Service {
	log := d.opts.Log.With("part", "idle")
	brightness := func(ctx context.Context, function string, args ...string) error {
		_, err := d.router.Call(ctx, ipcroute.CallParams{Target: "brightness", Function: function, Args: args})
		return err
	}
	return idle.New(idle.Options{
		Notifier: d.idleNotifier,
		Actions: idle.Actions{
			Dim: func(ctx context.Context, mode string, percent int) error {
				function := "dim"
				if mode == "by" {
					function = "dimBy"
				}
				return brightness(ctx, function, strconv.Itoa(percent))
			},
			Undim: func(ctx context.Context) error { return brightness(ctx, "undim") },
			Lock:  d.locker.Lock,
			ScreenPower: func(ctx context.Context, on bool) error {
				if d.compositor == nil {
					return axerr.New(axerr.Unavailable, "no compositor to turn the screens off with")
				}
				return d.compositor.ScreenPower(ctx, on)
			},
			Command: func(line string) error { return shellcmd.Start(line, d.tasks.Go) },
		},
		SystemBus: func(ctx context.Context) (*dbus.Conn, error) {
			return dbus.Dial(ctx, dbus.SystemAddress(d.opts.Getenv), dbus.Options{Log: log})
		},
		SessionBus: func(ctx context.Context) (*dbus.Conn, error) {
			addr, err := dbus.SessionAddress(d.opts.Getenv)
			if err != nil {
				return nil, err
			}
			return dbus.Dial(ctx, addr, dbus.Options{Log: log})
		},
		Getenv:        d.opts.Getenv,
		CompositorPID: d.wayland.CompositorPID,
		OnState: func(st idle.State) {
			// Also called before there is a server
			if d.server != nil {
				pushIdleState.Send(d.server, st, subscribedTo(topicIdle))
			}
		},
		Log: log,
	})
}

// idlePart: the idle service, configured from the Idle section.
func (d *Daemon) idlePart() part {
	configure := func() {
		cfg, _ := d.store.Config()
		v, _ := config.Lookup(cfg, config.Keys("Idle"))
		section, _ := v.(*jsonx.Object)
		d.idle.Configure(idle.SettingsFrom(section))
	}
	configure()
	return part{
		name:     "idle",
		methods:  d.idleMethods,
		run:      d.idle.Run,
		onConfig: func(store.Event) { configure() },
	}
}

func (d *Daemon) idleMethods(reg *rpc.Registry) {
	rpc.Handle(reg, "idle.get", func(ctx context.Context, c *rpc.Conn, _ struct{}) (idle.State, error) {
		return d.idle.State(), nil
	})
	type caffeineParams struct {
		On bool `json:"on"`
	}
	rpc.Handle(reg, "idle.caffeine", func(ctx context.Context, c *rpc.Conn, p caffeineParams) (struct{}, error) {
		if !fromShell(c) {
			return struct{}{}, axerr.New(axerr.Refused, "only the shell has the caffeine switch")
		}
		d.idle.SetCaffeine(p.On)
		return struct{}{}, nil
	})
}
