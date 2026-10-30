package daemon

import (
	"context"

	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/saved"
	"github.com/axiom-shell/axiom/backend/internal/share"
	"github.com/axiom-shell/axiom/backend/internal/store"
)

// sharedParams name what to apply. Shared files name monitors by place,
// which the daemon reads from its own output list (monitors).
type sharedParams struct {
	Name     string `json:"name"`
	Path     string `json:"path"`
	Snapshot string `json:"snapshot"`
	Personal bool   `json:"personal"`
	Commands bool   `json:"commands"`
	Places   bool   `json:"places"`
	// share.applyShared: the shell sets the setup's wallpaper next
	Wallpaper bool `json:"wallpaper"`
}

// monitors are this PC's outputs by place; nil while the daemon has no
// Wayland connection or hasn't heard of them yet (monitor fields are then
// left as they are)
func (d *Daemon) monitors() share.Monitors {
	return share.Monitors(d.outputs.Names())
}

// sharingPart: saved snapshots and shared configs (internal/saved), for
// the shell's settings page and the CLI.
func (d *Daemon) sharingPart() part {
	return part{
		name:     "sharing",
		methods:  d.sharingMethods,
		run:      d.savedKick.run,
		onConfig: func(store.Event) { d.savedKick.Kick() },
	}
}

func (d *Daemon) sharingMethods(reg *rpc.Registry) {
	rpc.Handle(reg, "saved.list", func(ctx context.Context, c *rpc.Conn, _ struct{}) ([]saved.Entry, error) {
		return d.saved.List()
	})
	rpc.Handle(reg, "saved.state", func(ctx context.Context, c *rpc.Conn, _ struct{}) (saved.State, error) {
		return d.saved.State(), nil
	})
	rpc.Handle(reg, "saved.save", func(ctx context.Context, c *rpc.Conn, p sharedParams) (map[string]string, error) {
		name, err := d.saved.Save(p.Name, "")
		return map[string]string{"name": name}, err
	})
	rpc.Handle(reg, "saved.restore", func(ctx context.Context, c *rpc.Conn, p sharedParams) (saved.Applied, error) {
		if err := d.writable(); err != nil {
			return saved.Applied{}, err
		}
		return d.saved.Restore(p.Name)
	})
	rpc.Handle(reg, "saved.remove", func(ctx context.Context, c *rpc.Conn, p sharedParams) (struct{}, error) {
		return struct{}{}, d.saved.Remove(p.Name)
	})
	rpc.Handle(reg, "share.examples", func(ctx context.Context, c *rpc.Conn, _ struct{}) ([]saved.Example, error) {
		return d.saved.Examples(), nil
	})
	rpc.Handle(reg, "share.open", func(ctx context.Context, c *rpc.Conn, p sharedParams) (saved.Preview, error) {
		return d.saved.Open(p.Path)
	})
	rpc.Handle(reg, "share.import", func(ctx context.Context, c *rpc.Conn, p sharedParams) (saved.Applied, error) {
		if err := d.writable(); err != nil {
			return saved.Applied{}, err
		}
		return d.saved.Import(p.Path, p.Personal, p.Commands, d.monitors())
	})
	rpc.Handle(reg, "share.example", func(ctx context.Context, c *rpc.Conn, p sharedParams) (saved.Applied, error) {
		if err := d.writable(); err != nil {
			return saved.Applied{}, err
		}
		return d.saved.ApplyExample(p.Name, d.monitors())
	})
	rpc.Handle(reg, "share.applyShared", func(ctx context.Context, c *rpc.Conn, p sharedParams) (saved.Applied, error) {
		if err := d.writable(); err != nil {
			return saved.Applied{}, err
		}
		return d.saved.ApplyShared(p.Path, p.Name, p.Snapshot, p.Wallpaper, d.monitors())
	})
	rpc.Handle(reg, "share.defaults", func(ctx context.Context, c *rpc.Conn, _ struct{}) (saved.Applied, error) {
		if err := d.writable(); err != nil {
			return saved.Applied{}, err
		}
		return d.saved.Defaults()
	})
	rpc.Handle(reg, "share.export", func(ctx context.Context, c *rpc.Conn, p sharedParams) (map[string]string, error) {
		path, err := d.saved.Export(p.Personal, p.Commands, p.Places, d.monitors())
		return map[string]string{"path": path}, err
	})
}
