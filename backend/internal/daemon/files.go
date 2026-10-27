package daemon

import (
	"context"

	"github.com/axiom-shell/axiom/backend/internal/files"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// filesPart: the files the shell writes and watches (FileManager's write
// and watch), answered by package files.
func (d *Daemon) filesPart() part {
	return part{name: "files", methods: d.filesMethods}
}

func (d *Daemon) filesMethods(reg *rpc.Registry) {
	fileHandlers(reg, func() *files.Files { return d.files })
}

// fileHandlers are file.write, file.watch and file.unwatch on f's files
// (the greeter's axiom answers them too: its state is written through it).
func fileHandlers(reg *rpc.Registry, f func() *files.Files) {
	type writeParams struct {
		Path string `json:"path"` // absolute
		Text string `json:"text"`
	}
	type pathParams struct {
		Path string `json:"path"`
	}
	rpc.Handle(reg, "file.write", func(ctx context.Context, c *rpc.Conn, p writeParams) (struct{}, error) {
		return struct{}{}, f().Write(p.Path, p.Text)
	})
	// Changes come as file.changed pushes, to this connection only
	rpc.Handle(reg, "file.watch", func(ctx context.Context, c *rpc.Conn, p pathParams) (struct{}, error) {
		return struct{}{}, f().Watch(c, p.Path)
	})
	rpc.Handle(reg, "file.unwatch", func(ctx context.Context, c *rpc.Conn, p pathParams) (struct{}, error) {
		f().Unwatch(c, p.Path)
		return struct{}{}, nil
	})
}
