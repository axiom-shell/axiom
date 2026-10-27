package daemon

import (
	"context"
	"encoding/json"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/theme"
)

// themePart: ThemeManager's themes generated from a wallpaper, written by
// package theme to the generated themes' folder, and its theme
// integrations, each writing its app's own axiom.* file.
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
	d.themeIntegrateMethods(reg)
	rpc.Handle(reg, "theme.generate", func(ctx context.Context, c *rpc.Conn, p ThemeGenerateRequest) (ThemeGenerateResult, error) {
		files, err := theme.Generate(p.Wallpaper, d.dirs.GeneratedThemes, time.Now())
		return ThemeGenerateResult{Files: files}, err
	})
}

// ThemeIntegrateRequest is the theme file to theme the apps with, and the
// integrations (ThemeIntegrations keys) to run.
type ThemeIntegrateRequest struct {
	Theme string   `json:"theme"`
	Keys  []string `json:"keys"`
}

// ThemeIntegrateResult is each integration's run (none while another run
// takes the request over).
type ThemeIntegrateResult struct {
	Results []theme.IntegrationResult `json:"results"`
}

func (d *Daemon) themeIntegrateMethods(reg *rpc.Registry) {
	in := theme.NewIntegrator(theme.IntegrateOptions{
		Getenv:   d.opts.Getenv,
		Profiles: d.integrationProfiles,
		Live:     true,
		Log:      d.opts.Log.With("part", "theme"),
	})
	rpc.Handle(reg, "theme.integrate", func(ctx context.Context, c *rpc.Conn, p ThemeIntegrateRequest) (ThemeIntegrateResult, error) {
		results, err := in.Run(ctx, p.Theme, p.Keys)
		return ThemeIntegrateResult{Results: results}, err
	})
}

// integrationProfiles is a ThemeIntegrations switch's x-profiles, from the
// schema the shell runs with.
func (d *Daemon) integrationProfiles(key string) []string {
	var s struct {
		Properties struct {
			ThemeIntegrations struct {
				Properties map[string]struct {
					Profiles []string `json:"x-profiles"`
				} `json:"properties"`
			} `json:"ThemeIntegrations"`
		} `json:"properties"`
	}
	built, _ := d.currentSchema()
	if err := json.Unmarshal(built, &s); err != nil {
		return nil
	}
	return s.Properties.ThemeIntegrations.Properties[key].Profiles
}
