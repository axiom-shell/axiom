package daemon

import (
	"context"

	"github.com/axiom-shell/axiom/backend/internal/brightness"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// brightnessPart: the monitors' brightness (BrightnessManager), its
// logind connection closed when the daemon stops.
func (d *Daemon) brightnessPart() part {
	log := d.opts.Log.With("part", "brightness")
	svc := brightness.New(brightness.Options{
		SystemBus: func(ctx context.Context) (*dbus.Conn, error) {
			return dbus.Dial(ctx, dbus.SystemAddress(d.opts.Getenv), dbus.Options{Log: log})
		},
		Getenv: d.opts.Getenv,
	})
	type setParams struct {
		brightness.Target
		Value int `json:"value"`
	}
	return part{
		name: "brightness",
		methods: func(reg *rpc.Registry) {
			rpc.Handle(reg, "brightness.detect", func(ctx context.Context, c *rpc.Conn, _ struct{}) (brightness.Found, error) {
				return svc.Detect(ctx), nil
			})
			rpc.Handle(reg, "brightness.get", func(ctx context.Context, c *rpc.Conn, p brightness.Target) (brightness.Level, error) {
				return svc.Get(ctx, p)
			})
			rpc.Handle(reg, "brightness.set", func(ctx context.Context, c *rpc.Conn, p setParams) (struct{}, error) {
				return struct{}{}, svc.Set(ctx, p.Target, p.Value)
			})
		},
		run: func(ctx context.Context) error {
			<-ctx.Done()
			svc.Close()
			return nil
		},
	}
}
