package daemon

import (
	"context"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/theme"
)

// themePart: ThemeManager's themes generated from a wallpaper, written by
// package theme to the generated themes' folder.
func (d *Daemon) themePart() part {
	return part{name: "theme", methods: d.themeMethods}
}

// ThemeGenerateRequest is the image to generate from, an absolute path.
type ThemeGenerateRequest struct {
	Wallpaper string `json:"wallpaper"`
}

// ThemeGenerateResult lists the theme files written.
type ThemeGenerateResult struct {
	Files []string `json:"files"`
}

func (d *Daemon) themeMethods(reg *rpc.Registry) {
	rpc.Handle(reg, "theme.generate", func(ctx context.Context, c *rpc.Conn, p ThemeGenerateRequest) (ThemeGenerateResult, error) {
		files, err := theme.Generate(p.Wallpaper, d.dirs.GeneratedThemes, time.Now())
		return ThemeGenerateResult{Files: files}, err
	})
}
