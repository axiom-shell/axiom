package daemon

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/compositor/binds"
	"github.com/axiom-shell/axiom/backend/internal/compositor/manager"
	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/store"
)

// newCompositor is the compositor's config layer (internal/compositor/
// manager) for the compositor this daemon runs under: nil when the tree's
// tables can't be read (logged), and inert under a compositor without
// config modes.
func (d *Daemon) newCompositor() *manager.Manager {
	tables, err := render.ParseTables(func(p string) (string, error) {
		data, err := os.ReadFile(filepath.Join(d.opts.Tree, p))
		return string(data), err
	})
	if err != nil {
		d.opts.Log.Error("compositor: reading the tree's tables", "err", err)
		return nil
	}
	actions, err := binds.LoadActions(d.opts.Tree)
	if err != nil {
		d.opts.Log.Error("compositor: reading the bind actions", "err", err)
		return nil
	}
	setting := func(path ...string) any {
		cfg, _ := d.store.Config()
		v, _ := config.Lookup(cfg, config.Keys(path...))
		return v
	}
	return manager.New(manager.Options{
		Getenv:      d.opts.Getenv,
		StateDir:    d.dirs.State,
		RuntimeFile: d.runtime.File("compositor.json"),
		Tables:      tables,
		Actions:     actions,
		Schema:      func() any { return d.store.Pipeline().Schema().Root() },
		Mode:        func() string { s, _ := setting("Compositor", "mode").(string); return s },
		Binds:       func() any { return setting("Keybinds", "binds") },
		CommitBinds: func(b *jsonx.Array) error {
			if err := d.writable(); err != nil {
				return err
			}
			_, err := d.store.Set([]config.Op{config.SetValue(config.Keys("Keybinds", "binds"), b)}, store.SetOptions{})
			return err
		},
		Push: func(method string, params any) {
			raw := json.RawMessage(jsonx.MarshalCompact(params))
			if method == "compositor.state" {
				// A state: only the newest unsent one matters
				d.server.BroadcastLatest(method, raw, subscribedTo(topicCompositor))
				return
			}
			d.server.Broadcast(method, raw, subscribedTo(topicCompositor))
		},
		// This image, even once the file it came from is replaced
		Bin:  "/proc/self/exe",
		Tree: d.opts.Tree,
		Log:  d.opts.Log.With("part", "compositor"),
	})
}

// compositorPart: the compositor's config. The shell sends what the layer
// is made of (compositor.inputs, its readers' values); the daemon writes
// the files, takes the config over and gives it back, moves the user's
// binds in and applies the runtime layer, and pushes what the Compositor
// settings show (compositor.state).
func (d *Daemon) compositorPart() part {
	m := d.compositor
	if m == nil {
		return part{name: "compositor"}
	}
	return part{
		name:     "compositor",
		methods:  func(reg *rpc.Registry) { d.compositorMethods(reg, m) },
		run:      m.Run,
		onConfig: func(store.Event) { m.ConfigChanged() },
	}
}

func (d *Daemon) compositorMethods(reg *rpc.Registry, m *manager.Manager) {
	// Only the shell drives it: its inputs, and every action that changes
	// the user's compositor config
	shellOnly := func(c *rpc.Conn) error {
		if !fromShell(c) {
			return axerr.New(axerr.Refused, "only the shell drives the compositor's config")
		}
		return nil
	}
	rpc.Handle(reg, "compositor.inputs", func(ctx context.Context, c *rpc.Conn, p json.RawMessage) (struct{}, error) {
		if err := shellOnly(c); err != nil {
			return struct{}{}, err
		}
		v, err := jsonx.Unmarshal(p)
		in, ok := v.(*jsonx.Object)
		if err != nil || !ok {
			return struct{}{}, axerr.New(axerr.BadRequest, "inputs must be an object")
		}
		m.SetInputs(in)
		return struct{}{}, nil
	})
	rpc.Handle(reg, "compositor.state", func(ctx context.Context, c *rpc.Conn, _ struct{}) (json.RawMessage, error) {
		return jsonx.MarshalCompact(m.State(ctx)), nil
	})
	rpc.Handle(reg, "compositor.checkManaged", func(ctx context.Context, c *rpc.Conn, _ struct{}) (map[string]string, error) {
		if err := shellOnly(c); err != nil {
			return nil, err
		}
		return map[string]string{"check": m.CheckManaged(ctx)}, nil
	})
	rpc.Handle(reg, "compositor.entries", func(ctx context.Context, c *rpc.Conn, _ struct{}) (json.RawMessage, error) {
		return jsonx.MarshalCompact(m.Entries(ctx)), nil
	})
	action := func(name string, run func(p struct {
		Only string `json:"only"`
	})) {
		rpc.Handle(reg, name, func(ctx context.Context, c *rpc.Conn, p struct {
			Only string `json:"only"`
		}) (struct{}, error) {
			if err := shellOnly(c); err != nil {
				return struct{}{}, err
			}
			run(p)
			return struct{}{}, nil
		})
	}
	action("compositor.allowTakeover", func(struct {
		Only string `json:"only"`
	}) {
		m.AllowTakeover()
	})
	action("compositor.merge", func(p struct {
		Only string `json:"only"`
	}) {
		m.Merge(p.Only)
	})
	action("compositor.previewMerge", func(struct {
		Only string `json:"only"`
	}) {
		m.PreviewMerge()
	})
	action("compositor.reload", func(struct {
		Only string `json:"only"`
	}) {
		m.Reload()
	})
}
