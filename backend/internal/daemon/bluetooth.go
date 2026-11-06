package daemon

import (
	"context"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/bluez"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// newBluetooth is BlueZ on the system bus (BluetoothManager): the default
// adapter and its devices, and what the shell does with them.
func (d *Daemon) newBluetooth() {
	log := d.opts.Log.With("part", "bluetooth")
	d.bluetooth = bluez.New(bluez.Options{
		SystemBus: func(ctx context.Context) (*dbus.Conn, error) {
			return dbus.Dial(ctx, dbus.SystemAddress(d.opts.Getenv), dbus.Options{Log: log})
		},
		OnChange: func(st bluez.State) {
			if d.server != nil {
				pushBluetoothState.Send(d.server, st, subscribedTo(topicBluetooth))
			}
		},
		Log: log,
	})
}

// bluetoothPart: Bluetooth, followed while the daemon runs.
func (d *Daemon) bluetoothPart() part {
	return part{
		name:    "bluetooth",
		methods: d.bluetoothMethods,
		run:     d.bluetooth.Run,
	}
}

func (d *Daemon) bluetoothMethods(reg *rpc.Registry) {
	type onParams struct {
		On bool `json:"on"`
	}
	type addressParams struct {
		Address string `json:"address"`
	}
	// Only the shell changes Bluetooth: it's the one showing it
	refused := func() error { return axerr.New(axerr.Refused, "only the shell changes Bluetooth") }
	rpc.Handle(reg, "bluetooth.get", func(ctx context.Context, c *rpc.Conn, _ struct{}) (bluez.State, error) {
		return d.bluetooth.State(), nil
	})
	rpc.Handle(reg, "bluetooth.setPowered", func(ctx context.Context, c *rpc.Conn, p onParams) (struct{}, error) {
		if !fromShell(c) {
			return struct{}{}, refused()
		}
		return struct{}{}, d.bluetooth.SetPowered(ctx, p.On)
	})
	rpc.Handle(reg, "bluetooth.discovery", func(ctx context.Context, c *rpc.Conn, p onParams) (struct{}, error) {
		if !fromShell(c) {
			return struct{}{}, refused()
		}
		return struct{}{}, d.bluetooth.Discovery(ctx, p.On)
	})
	// Each runs until BlueZ answers (a pair or connect can take many
	// seconds): the call's own goroutine waits, nothing else does
	device := func(name string, fn func(context.Context, string) error) {
		rpc.Handle(reg, name, func(ctx context.Context, c *rpc.Conn, p addressParams) (struct{}, error) {
			if !fromShell(c) {
				return struct{}{}, refused()
			}
			return struct{}{}, fn(ctx, p.Address)
		})
	}
	device("bluetooth.connect", d.bluetooth.Connect)
	device("bluetooth.disconnect", d.bluetooth.Disconnect)
	device("bluetooth.pair", d.bluetooth.Pair)
	device("bluetooth.cancelPair", d.bluetooth.CancelPair)
	device("bluetooth.forget", d.bluetooth.Forget)
}
