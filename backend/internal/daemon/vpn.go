package daemon

import (
	"context"
	"slices"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/nmvpn"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// vpnSecretDone is vpn.secretDone: a secret request NetworkManager or
// the user ended, to hide.
type vpnSecretDone struct {
	ID string `json:"id"`
}

// newVPN is NetworkManager's VPNs on the system bus (VpnManager), and the
// secret agent asking the shell for their passwords.
func (d *Daemon) newVPN() {
	log := d.opts.Log.With("part", "vpn")
	d.vpn = nmvpn.New(nmvpn.Options{
		SystemBus: func(ctx context.Context) (*dbus.Conn, error) {
			return dbus.Dial(ctx, dbus.SystemAddress(d.opts.Getenv), dbus.Options{Log: log})
		},
		OnChange: func(st nmvpn.State) {
			if d.server != nil {
				pushVPNState.Send(d.server, st, subscribedTo(topicVPN))
			}
		},
		// A password goes only to the shell, which is the one to ask
		OnSecret: func(req nmvpn.SecretRequest) bool {
			if d.server == nil || !slices.ContainsFunc(d.server.Conns(), shellIn(subscribedTo(topicVPN))) {
				return false
			}
			pushVPNSecretRequest.Send(d.server, req, shellIn(subscribedTo(topicVPN)))
			return true
		},
		OnSecretDone: func(id string) {
			if d.server != nil {
				pushVPNSecretDone.Send(d.server, vpnSecretDone{ID: id}, subscribedTo(topicVPN))
			}
		},
		Log: log,
	})
}

// shellIn keeps the shell's connections among those keep keeps.
func shellIn(keep func(*rpc.Conn) bool) func(*rpc.Conn) bool {
	return func(c *rpc.Conn) bool { return fromShell(c) && keep(c) }
}

// vpnPart: the VPNs, followed while the daemon runs.
func (d *Daemon) vpnPart() part {
	return part{
		name:    "vpn",
		methods: d.vpnMethods,
		run:     d.vpn.Run,
	}
}

func (d *Daemon) vpnMethods(reg *rpc.Registry) {
	type uuidParams struct {
		UUID string `json:"uuid"`
	}
	type secretParams struct {
		ID      string            `json:"id"`
		Secrets map[string]string `json:"secrets"`
		Cancel  bool              `json:"cancel"`
	}
	rpc.Handle(reg, "vpn.get", func(ctx context.Context, c *rpc.Conn, _ struct{}) (nmvpn.State, error) {
		return d.vpn.State(), nil
	})
	rpc.Handle(reg, "vpn.up", func(ctx context.Context, c *rpc.Conn, p uuidParams) (struct{}, error) {
		return struct{}{}, d.vpn.Up(ctx, p.UUID)
	})
	rpc.Handle(reg, "vpn.down", func(ctx context.Context, c *rpc.Conn, p uuidParams) (struct{}, error) {
		return struct{}{}, d.vpn.Down(ctx, p.UUID)
	})
	rpc.Handle(reg, "vpn.secret", func(ctx context.Context, c *rpc.Conn, p secretParams) (struct{}, error) {
		if !fromShell(c) {
			return struct{}{}, axerr.New(axerr.Refused, "only the shell answers for VPN secrets")
		}
		return struct{}{}, d.vpn.Answer(p.ID, p.Secrets, p.Cancel)
	})
}
