package daemon

import (
	"context"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/deps"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/tz"
)

// zoneinfo is the time zone directory: $TZDIR (NixOS has no
// /usr/share/zoneinfo), else the usual one
func (d *Daemon) zoneinfo() string {
	if dir := d.opts.Getenv("TZDIR"); dir != "" {
		return dir
	}
	return tz.DefaultDir
}

// toolsPart: one-off lookups the shell asks for, each answered from the
// package owning it.
func (d *Daemon) toolsPart() part {
	return part{name: "tools", methods: d.toolsMethods}
}

func (d *Daemon) toolsMethods(reg *rpc.Registry) {
	type checkParams struct {
		Commands []string `json:"commands"`
	}
	type checkResult struct {
		Found []string `json:"found"`
	}
	type zonesResult struct {
		Zones []string `json:"zones"`
	}
	rpc.Handle(reg, "tz.zones", func(ctx context.Context, c *rpc.Conn, _ struct{}) (zonesResult, error) {
		return zonesResult{Zones: append([]string{}, tz.Zones(d.zoneinfo())...)}, nil
	})
	type offsetsParams struct {
		Zones []string `json:"zones"`
	}
	type offsetsResult struct {
		Offsets map[string]int `json:"offsets"` // minutes east of UTC
	}
	rpc.Handle(reg, "tz.offsets", func(ctx context.Context, c *rpc.Conn, p offsetsParams) (offsetsResult, error) {
		return offsetsResult{Offsets: tz.Offsets(d.zoneinfo(), p.Zones, time.Now())}, nil
	})
	rpc.Handle(reg, "deps.check", func(ctx context.Context, c *rpc.Conn, p checkParams) (checkResult, error) {
		return checkResult{Found: append([]string{}, deps.Check(ctx, p.Commands, deps.Options{})...)}, nil
	})
}
