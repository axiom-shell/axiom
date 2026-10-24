package daemon

import (
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/tailscale"
	"github.com/axiom-shell/axiom/backend/internal/topics"
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
		},
	}
}

// sources are the daemon's polled topics.
func (d *Daemon) sources() []topics.Source {
	return append([]topics.Source{
		tailscale.Source(tailscale.Options{}),
	}, d.opts.topics...)
}
