package daemon

import (
	"context"
	"os/user"

	"github.com/axiom-shell/axiom/backend/internal/claudeusage"
	"github.com/axiom-shell/axiom/backend/internal/lockkeys"
	"github.com/axiom-shell/axiom/backend/internal/markets"
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
			d.marketsMethods(reg)
			// The graphed metrics whose history is kept from launch
			// (SystemManager, from config): sampled in the daemon, pushed
			// only with a graph's subscription
			rpc.Handle(reg, "system.keep", func(ctx context.Context, c *rpc.Conn, p struct {
				Metrics []string `json:"metrics"`
			}) (struct{}, error) {
				return struct{}{}, d.sysmon.Keep(c, p.Metrics)
			})
		},
		run: func(ctx context.Context) error { return d.sysmon.Run(ctx) },
	}
}

// newSysmon is the `system` topic's monitor, kept for the daemon's
// lifetime: its history outlives the topic's subscribers.
func (d *Daemon) newSysmon() *sysmon.Monitor {
	return sysmon.New(sysmon.Options{Home: d.opts.Getenv("HOME"), Log: d.opts.Log.With("part", "sysmon")})
}

// sources are the daemon's polled topics.
func (d *Daemon) sources() []topics.Source {
	return append([]topics.Source{
		tailscale.Source(tailscale.Options{}),
		tailscale.DetailsSource(tailscale.Options{}),
		updates.Source(updates.Options{Log: d.opts.Log}),
		d.sysmon.Source(),
		claudeusage.Source(claudeusage.Options{Log: d.opts.Log, StateFile: d.dirs.State + "claude-usage.json"}),
		weather.Source(weather.Options{Log: d.opts.Log}),
		d.marketsService().Source(),
		lockkeys.Source(lockkeys.Options{}),
		// (nil in BuildContract: only its shapes are read)
		d.inputMethod.Source(),
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

// marketsService is the `markets` topic's fetcher, made once: the search
// and the history share its hosts' backoff.
func (d *Daemon) marketsService() *markets.Markets {
	if d.markets == nil {
		d.markets = markets.New(markets.Options{Log: d.opts.Log.With("part", "markets"), StateFile: d.dirs.State + "markets.json"})
	}
	return d.markets
}

// marketsMethods: the watchlist card's symbol search and the detail
// chart's history (MarketsManager.search / history), and the prices for
// a request at once (`axiom markets list`), from the topic's cache: only
// what's due is fetched.
func (d *Daemon) marketsMethods(reg *rpc.Registry) {
	l := d.marketsService().Lookup()
	rpc.Handle(reg, "markets.quotes", func(ctx context.Context, c *rpc.Conn, p markets.Request) (*markets.State, error) {
		return d.marketsService().State(ctx, p)
	})
	rpc.Handle(reg, "markets.search", func(ctx context.Context, c *rpc.Conn, p markets.SearchRequest) (markets.SearchResult, error) {
		return l.Search(ctx, p)
	})
	rpc.Handle(reg, "markets.history", func(ctx context.Context, c *rpc.Conn, p markets.HistoryRequest) (*markets.History, error) {
		return l.History(ctx, p)
	})
}
