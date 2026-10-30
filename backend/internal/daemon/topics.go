package daemon

import (
	"context"
	"os/user"

	"github.com/axiom-shell/axiom/backend/internal/claudeusage"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/sysmon"
	"github.com/axiom-shell/axiom/backend/internal/tailscale"
	"github.com/axiom-shell/axiom/backend/internal/topics"
	"github.com/axiom-shell/axiom/backend/internal/updates"
	"github.com/axiom-shell/axiom/backend/internal/weather"
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
		tailscale.DetailsSource(tailscale.Options{}),
		updates.Source(updates.Options{Log: d.opts.Log}),
		sysmon.Source(sysmon.Options{Home: d.opts.Getenv("HOME")}),
		claudeusage.Source(claudeusage.Options{Log: d.opts.Log, StateFile: d.dirs.State + "claude-usage.json"}),
		weather.Source(weather.Options{}),
	}, d.opts.topics...)
}

// tailscaleMethods: the popout's actions (`tailscale up` / `down`,
// `switch`, `login`, `set`, and granting operator rights), each fetching
// both Tailscale topics again after.
func (d *Daemon) tailscaleMethods(reg *rpc.Registry, o tailscale.Options) {
	handle := func(name string, act func(ctx context.Context) error) {
		rpc.Handle(reg, name, func(ctx context.Context, c *rpc.Conn, _ struct{}) (struct{}, error) {
			err := act(ctx)
			d.refreshTailscale()
			return struct{}{}, err
		})
	}
	handle("tailscale.up", func(ctx context.Context) error { return tailscale.Connect(ctx, o, true) })
	handle("tailscale.down", func(ctx context.Context) error { return tailscale.Connect(ctx, o, false) })
	handle("tailscale.login", func(ctx context.Context) error { return tailscale.Login(ctx, o) })
	handle("tailscale.grantOperator", func(ctx context.Context) error {
		u, err := user.Current()
		if err != nil {
			return err
		}
		return tailscale.GrantOperator(ctx, o, u.Username)
	})
	rpc.Handle(reg, "tailscale.switch", func(ctx context.Context, c *rpc.Conn, p struct {
		ID string `json:"id"`
	}) (struct{}, error) {
		err := tailscale.Switch(ctx, o, p.ID)
		d.refreshTailscale()
		return struct{}{}, err
	})
	rpc.Handle(reg, "tailscale.set", func(ctx context.Context, c *rpc.Conn, p tailscale.SetRequest) (struct{}, error) {
		err := tailscale.Set(ctx, o, p)
		d.refreshTailscale()
		return struct{}{}, err
	})
}

func (d *Daemon) refreshTailscale() {
	d.topics.Refresh("tailscale")
	d.topics.Refresh("tailscaledetails")
}
