package daemon

import (
	"context"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/nmnet"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// netPart: what the Wi-Fi menu asks NetworkManager beyond
// Quickshell.Networking (NetworkingManager): a device's details, joining
// a network its form describes, the saved networks' autoconnect.
func (d *Daemon) netPart() part {
	return part{name: "net", methods: d.netMethods}
}

func (d *Daemon) netMethods(reg *rpc.Registry) {
	type deviceParams struct {
		Device string `json:"device"`
	}
	rpc.Handle(reg, "net.details", func(ctx context.Context, c *rpc.Conn, p deviceParams) (nmnet.Details, error) {
		return d.net.Details(ctx, p.Device)
	})
	// Carries a password: only from the shell, as vpn.secret
	rpc.Handle(reg, "net.join", func(ctx context.Context, c *rpc.Conn, p nmnet.JoinRequest) (struct{}, error) {
		if !fromShell(c) {
			return struct{}{}, axerr.New(axerr.Refused, "only the shell joins networks")
		}
		return struct{}{}, d.net.Join(ctx, p)
	})
	type savedResult struct {
		Networks []nmnet.SavedNetwork `json:"networks"`
	}
	rpc.Handle(reg, "net.savedWifi", func(ctx context.Context, c *rpc.Conn, _ struct{}) (savedResult, error) {
		list, err := d.net.SavedWifi(ctx)
		return savedResult{Networks: list}, err
	})
	type autoconnectParams struct {
		UUID string `json:"uuid"`
		On   bool   `json:"on"`
	}
	rpc.Handle(reg, "net.setAutoconnect", func(ctx context.Context, c *rpc.Conn, p autoconnectParams) (struct{}, error) {
		return struct{}{}, d.net.SetAutoconnect(ctx, p.UUID, p.On)
	})
}
