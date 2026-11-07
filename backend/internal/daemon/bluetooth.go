package daemon

import (
	"context"
	"slices"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/bluez"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/store"
)

// bluetoothAgentDone is bluetooth.agentDone: a pairing agent's request
// BlueZ, the user or the pairing's end ended, to hide.
type bluetoothAgentDone struct {
	ID string `json:"id"`
}

// newBluetooth is BlueZ on the system bus (BluetoothManager): the default
// adapter and its devices, what the shell does with them, and the
// pairing agent asking the shell for PINs, passkeys and confirmations.
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
		// Only the shell answers: it's the one showing the prompt
		OnAgentRequest: func(req bluez.AgentRequest) bool {
			if d.server == nil || !slices.ContainsFunc(d.server.Conns(), shellIn(subscribedTo(topicBluetooth))) {
				return false
			}
			pushBluetoothAgentRequest.Send(d.server, req, shellIn(subscribedTo(topicBluetooth)))
			return true
		},
		OnAgentDone: func(id string) {
			if d.server != nil {
				pushBluetoothAgentDone.Send(d.server, bluetoothAgentDone{ID: id}, subscribedTo(topicBluetooth))
			}
		},
		// Devices connecting or disconnecting, for the OSD's card
		OnEvent: func(e bluez.Event) {
			if d.server != nil {
				pushBluetoothEvent.Send(d.server, e, subscribedTo(topicBluetooth))
			}
		},
		Log: log,
	})
}

// bluetoothPart: Bluetooth, followed while the daemon runs; the pairing
// agent registered while Bluetooth.pairingAgent is on.
func (d *Daemon) bluetoothPart() part {
	configure := func() {
		cfg, _ := d.store.Config()
		// reads: Bluetooth.pairingAgent
		v, _ := config.Lookup(cfg, config.Keys("Bluetooth", "pairingAgent"))
		d.bluetooth.SetAgent(jsonx.Truthy(v))
	}
	configure()
	return part{
		name:     "bluetooth",
		methods:  d.bluetoothMethods,
		run:      d.bluetooth.Run,
		onConfig: func(store.Event) { configure() },
	}
}

// lastShellGone stops the scan when c was the last shell: it's the
// daemon's BlueZ session, which BlueZ doesn't end as a shell goes, and a
// shell that exited cleanly isn't started again to turn it off. One that
// comes back asks for it again after its hello.
func (d *Daemon) lastShellGone(c *rpc.Conn) {
	if slices.ContainsFunc(d.server.Conns(), func(o *rpc.Conn) bool { return o != c && fromShell(o) }) {
		return
	}
	d.tasks.Go(func(ctx context.Context) {
		if err := d.bluetooth.Discovery(ctx, false); err != nil {
			d.opts.Log.Debug("bluetooth: stopping the scan of a shell gone", "err", err)
		}
	})
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
		// Not cancelled with the call: a scan BlueZ started for a shell
		// gone mid-call is still recorded, so the off that follows ends it
		return struct{}{}, d.bluetooth.Discovery(context.WithoutCancel(ctx), p.On)
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
	type aliasParams struct {
		Address string `json:"address"`
		Name    string `json:"name"`
	}
	rpc.Handle(reg, "bluetooth.setAlias", func(ctx context.Context, c *rpc.Conn, p aliasParams) (struct{}, error) {
		if !fromShell(c) {
			return struct{}{}, refused()
		}
		return struct{}{}, d.bluetooth.SetAlias(ctx, p.Address, p.Name)
	})
	type deviceOnParams struct {
		Address string `json:"address"`
		On      bool   `json:"on"`
	}
	deviceOn := func(name string, fn func(context.Context, string, bool) error) {
		rpc.Handle(reg, name, func(ctx context.Context, c *rpc.Conn, p deviceOnParams) (struct{}, error) {
			if !fromShell(c) {
				return struct{}{}, refused()
			}
			return struct{}{}, fn(ctx, p.Address, p.On)
		})
	}
	deviceOn("bluetooth.setTrusted", d.bluetooth.SetTrusted)
	deviceOn("bluetooth.setBlocked", d.bluetooth.SetBlocked)
	rpc.Handle(reg, "bluetooth.setDiscoverable", func(ctx context.Context, c *rpc.Conn, p onParams) (struct{}, error) {
		if !fromShell(c) {
			return struct{}{}, refused()
		}
		return struct{}{}, d.bluetooth.SetDiscoverable(ctx, p.On)
	})
	// The rfkill soft block of every Bluetooth radio, not BlueZ's
	rpc.Handle(reg, "bluetooth.unblock", func(ctx context.Context, c *rpc.Conn, _ struct{}) (struct{}, error) {
		if !fromShell(c) {
			return struct{}{}, refused()
		}
		return struct{}{}, d.bluetooth.Unblock()
	})
	type agentReplyParams struct {
		ID     string `json:"id"`
		Accept bool   `json:"accept"`
		Value  string `json:"value"`
	}
	rpc.Handle(reg, "bluetooth.agentReply", func(ctx context.Context, c *rpc.Conn, p agentReplyParams) (struct{}, error) {
		if !fromShell(c) {
			return struct{}{}, axerr.New(axerr.Refused, "only the shell answers the pairing agent")
		}
		return struct{}{}, d.bluetooth.AgentReply(p.ID, p.Accept, p.Value)
	})
}
