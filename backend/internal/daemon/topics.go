package daemon

import (
	"context"

	"github.com/axiom-shell/axiom/backend/internal/claudeusage"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/sysmon"
	"github.com/axiom-shell/axiom/backend/internal/tailscale"
	"github.com/axiom-shell/axiom/backend/internal/topics"
	"github.com/axiom-shell/axiom/backend/internal/updates"
)

// topicsPart: the polled topics (internal/topics), each source from the
// package that owns its side effect. A connection subscribes to one with
// `<name>.subscribe` (the shell through BackendManager.acquire), never
// through its hello, and its requests go when it closes.
func (d *Daemon) topicsPart() part {
	return part{
		name: "topics",
		methods: func(reg *rpc.Registry) {
			for _, src := range d.sources() {
				topics.Register(reg, d.topics, src)
			}
			d.tailscaleMethods(reg, tailscale.Options{})
		},
	}
}

// sources are the daemon's polled topics.
func (d *Daemon) sources() []topics.Source {
	return append([]topics.Source{
		tailscale.Source(tailscale.Options{}),
		updates.Source(updates.Options{Log: d.opts.Log}),
		sysmon.Source(sysmon.Options{Home: d.opts.Getenv("HOME")}),
		claudeusage.Source(claudeusage.Options{Log: d.opts.Log, StateFile: d.dirs.State + "claude-usage.json"}),
	}, d.opts.topics...)
}

// tailscaleMethods: `tailscale.up` / `tailscale.down`, the popout's
// Connect and Disconnect, each fetching the topic again after.
func (d *Daemon) tailscaleMethods(reg *rpc.Registry, o tailscale.Options) {
	connect := func(up bool) func(ctx context.Context, c *rpc.Conn, _ struct{}) (struct{}, error) {
		return func(ctx context.Context, c *rpc.Conn, _ struct{}) (struct{}, error) {
			err := tailscale.Connect(ctx, o, up)
			d.topics.Refresh("tailscale")
			return struct{}{}, err
		}
	}
	rpc.Handle(reg, "tailscale.up", connect(true))
	rpc.Handle(reg, "tailscale.down", connect(false))
}
