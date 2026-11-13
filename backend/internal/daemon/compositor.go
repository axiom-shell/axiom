package daemon

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/compositor/actions"
	"github.com/axiom-shell/axiom/backend/internal/compositor/manager"
	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/schema"
	"github.com/axiom-shell/axiom/backend/internal/store"
)

// newCompositor is the compositor's config layer (internal/compositor/
// manager) for the compositor this daemon runs under: nil when the tree's
// tables can't be read (logged), and inert under a compositor without
// config modes.
func (d *Daemon) newCompositor(carried bool) *manager.Manager {
	tables, err := render.ParseTables(func(p string) (string, error) {
		data, err := os.ReadFile(filepath.Join(d.opts.Tree, p))
		return string(data), err
	})
	if err != nil {
		d.opts.Log.Error("compositor: reading the tree's tables", "err", err)
		return nil
	}
	setting := func(path ...string) any {
		cfg, _ := d.store.Config()
		v, _ := config.Lookup(cfg, config.Keys(path...))
		return v
	}
	return manager.New(manager.Options{
		Getenv:      d.opts.Getenv,
		Carried:     carried,
		StateDir:    d.dirs.State,
		RuntimeFile: d.runtime.File("compositor.json"),
		Tables:      tables,
		Schema:      func() any { return d.store.Pipeline().Schema().Root() },
		// The takeover settings in effect (the store's: the file's, or the
		// ones it kept, while it runs on the defaults), "" while unknown
		Mode: func() string {
			cfg, known := d.store.Takeovers()
			if !known {
				return ""
			}
			v, _ := config.Lookup(cfg, config.Keys("Compositor", "mode"))
			s, _ := v.(string)
			return s
		},
		Config: func() *jsonx.Object {
			cfg, _ := d.store.Config()
			return cfg
		},
		Binds: func() any { return setting("Keybinds", "binds") },
		CommitBinds: func(b *jsonx.Array) error {
			if err := d.writable(); err != nil {
				return err
			}
			_, err := d.store.Set([]config.Op{config.SetValue(config.Keys("Keybinds", "binds"), b)}, store.SetOptions{})
			return err
		},
		Push: func(method string, params any) {
			p, ok := compositorPushes[method]
			if !ok {
				d.opts.Log.Error("compositor: no such push", "method", method)
				return
			}
			p.Send(d.server, json.RawMessage(jsonx.MarshalCompact(params)), subscribedTo(topicCompositor))
		},
		OnSteps: d.sess.setSteps,
		// This image, even once the file it came from is replaced
		Bin: "/proc/self/exe",
		Log: d.opts.Log.With("part", "compositor"),
	})
}

// compositorPart: the compositor's config. The layer is made of the config
// and what only the shell knows (compositor.inputs); the daemon writes
// the files, takes the config over and gives it back, moves the user's
// binds in and applies the runtime layer, and pushes what the Compositor
// settings show (compositor.state).
func (d *Daemon) compositorPart() part {
	m := d.compositor
	if m == nil {
		return part{name: "compositor", methods: bindActionsMethod}
	}
	return part{
		name:     "compositor",
		methods:  func(reg *rpc.Registry) { d.compositorMethods(reg, m) },
		run:      m.Run,
		onConfig: func(ev store.Event) { m.ConfigChanged(ev.FromFile) },
	}
}

// bindActionsMethod: what each bind action is (actions.JSON), which the
// shell names and files binds by (BindActions), with or without a layer
func bindActionsMethod(reg *rpc.Registry) {
	rpc.Handle(reg, "compositor.bindActions", func(ctx context.Context, c *rpc.Conn, _ struct{}) (json.RawMessage, error) {
		return actions.JSON, nil
	})
}

// fillWindowRules is a draft WindowRules section with the schema's defaults
// filled (a new rule's `enabled` is true only after that)
func fillWindowRules(s *schema.Schema, section json.RawMessage) (any, error) {
	v, err := jsonx.Unmarshal(section)
	if err != nil {
		return nil, axerr.New(axerr.BadRequest, "the section isn't JSON: %v", err)
	}
	filled, _ := config.ApplyDefaults(s, v, true, schema.Get(schema.Get(s.Root(), "properties"), "WindowRules"))
	return filled, nil
}

func (d *Daemon) compositorMethods(reg *rpc.Registry, m *manager.Manager) {
	bindActionsMethod(reg)
	// Only the shell drives it: its inputs, and every action that changes
	// the user's compositor config
	shellOnly := func(c *rpc.Conn) error {
		if !fromShell(c) {
			return axerr.New(axerr.Refused, "only the shell drives the compositor's config")
		}
		return nil
	}
	rpc.Handle(reg, "compositor.inputs", func(ctx context.Context, c *rpc.Conn, p manager.Facts) (struct{}, error) {
		if err := shellOnly(c); err != nil {
			return struct{}{}, err
		}
		m.SetFacts(p)
		// The engine reads the same capabilities (ruleXwayland)
		if d.windowRules != nil {
			d.windowRules.SetSupports(p.Supports)
		}
		return struct{}{}, nil
	})
	rpc.Handle(reg, "compositor.layerRules", func(ctx context.Context, c *rpc.Conn, _ struct{}) (struct{}, error) {
		if err := shellOnly(c); err != nil {
			return struct{}{}, err
		}
		return struct{}{}, m.AddLayerRules(ctx)
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
	// The editor's draft of WindowRules, checked as compositor.state's
	// windowRules reports the saved one
	type checkRulesParams struct {
		Section json.RawMessage `json:"section"`
	}
	rpc.Handle(reg, "compositor.checkRules", func(ctx context.Context, c *rpc.Conn, p checkRulesParams) (json.RawMessage, error) {
		filled, err := fillWindowRules(d.store.Pipeline().Schema(), p.Section)
		if err != nil {
			return nil, err
		}
		return jsonx.MarshalCompact(m.CheckRules(ctx, filled)), nil
	})
	type onlyParams struct {
		Only string `json:"only"`
	}
	action := func(name string, run func(only string)) {
		rpc.Handle(reg, name, func(ctx context.Context, c *rpc.Conn, p onlyParams) (struct{}, error) {
			if err := shellOnly(c); err != nil {
				return struct{}{}, err
			}
			run(p.Only)
			return struct{}{}, nil
		})
	}
	action("compositor.allowTakeover", func(string) { m.AllowTakeover() })
	action("compositor.merge", m.Merge)
	action("compositor.previewMerge", func(string) { m.PreviewMerge() })
	action("compositor.reload", func(string) { m.Reload() })
}
