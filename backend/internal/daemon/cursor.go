package daemon

import (
	"context"
	"os/exec"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/cursortheme"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// cursorPart: CursorThemeManager's cursor theme as XCursor readers get it
// (package cursortheme: the companion theme filling in standard names, and
// GTK's cursor settings).
func (d *Daemon) cursorPart() part {
	return part{name: "cursor", methods: d.cursorMethods}
}

// CursorThemeRequest is the theme set (Input's cursor) and its size.
type CursorThemeRequest struct {
	Theme string `json:"theme"`
	Size  int    `json:"size"`
}

func (d *Daemon) cursorMethods(reg *rpc.Registry) {
	r := cursortheme.New(cursortheme.Options{Getenv: d.opts.Getenv, GSettings: gsettings})
	rpc.Handle(reg, "cursor.theme", func(ctx context.Context, c *rpc.Conn, p CursorThemeRequest) (cursortheme.Result, error) {
		return r.Resolve(ctx, p.Theme, p.Size)
	})
}

// gsettings runs gsettings (an error where it isn't installed).
func gsettings(ctx context.Context, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "gsettings", args...).Output()
	return string(out), err
}
