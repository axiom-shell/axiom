package theme

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/assets"
	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/theme/integrations"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// IntegrateOptions configure an Integrator.
type IntegrateOptions struct {
	Getenv   func(string) string
	LookPath func(string) (string, error)
	// Profiles are the profiles.ini files an integration's x-profiles
	// lists (with {home} and {config}), for one written per profile
	Profiles func(key string) []string
	// Live tells the running apps (signals, sockets, D-Bus, gsettings,
	// bat's cache); tests leave it off, so they never reach the session
	Live bool
	Log  *slog.Logger
}

// Integrator runs the theme integrations (ThemeManager.themeIntegrations):
// each writes its app's own axiom.* file and tells the app.
type Integrator struct {
	opts IntegrateOptions

	mu      sync.Mutex
	running bool
	pending map[string]string // key: the theme file it's wanted for
}

// NewIntegrator makes an Integrator.
func NewIntegrator(opts IntegrateOptions) *Integrator {
	if opts.Log == nil {
		opts.Log = slog.New(slog.DiscardHandler)
	}
	if opts.LookPath == nil {
		opts.LookPath = exec.LookPath
	}
	if opts.Profiles == nil {
		opts.Profiles = func(string) []string { return nil }
	}
	return &Integrator{opts: opts, pending: map[string]string{}}
}

// IntegrationResult is how one integration's run went.
type IntegrationResult struct {
	Key string `json:"key"`
	// Files are the paths written
	Files    []string `json:"files"`
	Warnings []string `json:"warnings"`
	// Error is why it wrote nothing
	Error string `json:"error,omitempty"`
}

// Run themes the integrations keys name for the theme file at themePath.
// While a run is going, a call only queues its keys for it (each runs for
// the latest theme asked) and returns no results: a quick light-dark-light
// never ends on the middle one. An unknown key is axerr.BadRequest.
func (in *Integrator) Run(ctx context.Context, themePath string, keys []string) ([]IntegrationResult, error) {
	for _, k := range keys {
		if _, ok := integrations.Table[k]; !ok {
			return nil, axerr.New(axerr.BadRequest, "no theme integration %q", k)
		}
	}
	// The shell may go (a reload) while the apps are told: finish anyway
	ctx = context.WithoutCancel(ctx)
	in.mu.Lock()
	for _, k := range keys {
		in.pending[k] = themePath
	}
	if in.running {
		in.mu.Unlock()
		return nil, nil
	}
	in.running = true
	var results []IntegrationResult
	for len(in.pending) > 0 {
		batch := in.pending
		in.pending = map[string]string{}
		in.mu.Unlock()
		for _, k := range slices.Sorted(maps.Keys(batch)) {
			results = append(results, in.one(ctx, k, batch[k]))
		}
		in.mu.Lock()
	}
	in.running = false
	in.mu.Unlock()
	return results, nil
}

// run is one integration's run in progress.
type run struct {
	*Integrator
	ctx    context.Context
	key    string
	dirs   integrations.Dirs
	theme  *integrations.Theme
	files  map[string][]byte // path: what was written
	result *IntegrationResult
}

func (r *run) warn(format string, args ...any) {
	r.result.Warnings = append(r.result.Warnings, fmt.Sprintf(format, args...))
}

func (r *run) has(cmd string) bool { _, err := r.opts.LookPath(cmd); return err == nil }

func (in *Integrator) one(ctx context.Context, key, themePath string) IntegrationResult {
	result := IntegrationResult{Key: key, Files: []string{}, Warnings: []string{}}
	b := xdg.ResolveBases(in.opts.Getenv)
	r := &run{Integrator: in, ctx: ctx, key: key, result: &result, files: map[string][]byte{},
		dirs: integrations.Dirs{Home: b.Home, Config: b.Config, State: b.State, Data: b.Data}}
	if err := r.write(themePath); err != nil {
		result.Error = err.Error()
		return result
	}
	if fx, ok := effects[key]; ok && fx.after != nil {
		fx.after(r)
	}
	return result
}

// write renders and writes the integration's files.
func (r *run) write(themePath string) error {
	data, err := os.ReadFile(themePath)
	if err != nil {
		return axerr.Wrap(axerr.NotFound, err, "can't read the theme")
	}
	defaults, err := assets.Read("config/json/theme-defaults.json")
	if err != nil {
		return axerr.Wrap(axerr.Internal, err, "theme defaults")
	}
	if r.theme, err = integrations.Parse(data, defaults, strings.TrimSuffix(filepath.Base(themePath), ".json")); err != nil {
		return err
	}
	integ := integrations.Table[r.key]
	places := []string{""}
	if integ.Each != nil || integ.Profiles {
		if places = r.places(integ); len(places) == 0 {
			return axerr.New(axerr.NotFound, "%s", integ.Missing)
		}
	}
	for _, each := range places {
		d := r.dirs
		d.Each = each
		for _, f := range integ.Files {
			if strings.HasPrefix(f.Path, "{each}") != (each != "") {
				continue
			}
			if f.Requires != "" && !r.has(f.Requires) {
				continue
			}
			path := d.Expand(f.Path)
			if _, err := os.Lstat(path); f.IfMissing && !errors.Is(err, fs.ErrNotExist) {
				continue // there (a link to a theme's too): the user's
			}
			out, err := f.Render(r.theme, d)
			if err != nil {
				return err
			}
			if fx, ok := effects[r.key]; ok && fx.adjust != nil {
				out = fx.adjust(r, out)
			}
			if err := writeFile(path, out); err != nil {
				return err
			}
			r.files[path] = out
			r.result.Files = append(r.result.Files, path)
		}
	}
	return nil
}

func writeFile(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "can't make %s", filepath.Dir(path))
	}
	return fsx.WriteFile(path, data, 0o644)
}

// places are the folders an Each or Profiles integration writes into.
func (r *run) places(integ integrations.Integration) []string {
	var out []string
	if integ.Profiles {
		for _, ini := range r.opts.Profiles(r.key) {
			out = append(out, profileDirs(r.dirs.Expand(ini))...)
		}
	}
	for _, dir := range integ.Each {
		out = append(out, r.dirs.Expand(dir))
	}
	slices.Sort(out)
	return slices.DeleteFunc(slices.Compact(out), func(dir string) bool {
		info, err := os.Stat(dir)
		return err != nil || !info.IsDir()
	})
}

// profileDirs are the profile folders a browser's profiles.ini lists.
func profileDirs(ini string) []string {
	data, err := os.ReadFile(ini)
	if err != nil {
		return nil
	}
	var out []string
	add := func(section map[string]string) {
		if section["path"] == "" {
			return
		}
		dir := section["path"]
		if section["isrelative"] != "0" {
			dir = filepath.Join(filepath.Dir(ini), dir)
		}
		out = append(out, dir)
	}
	var section map[string]string
	sc := bufio.NewScanner(bytes.NewReader(data))
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if name, ok := strings.CutPrefix(line, "["); ok {
			if section != nil {
				add(section)
			}
			section = nil
			if strings.HasPrefix(name, "Profile") {
				section = map[string]string{}
			}
		} else if k, v, ok := strings.Cut(line, "="); ok && section != nil {
			section[strings.ToLower(strings.TrimSpace(k))] = strings.TrimSpace(v)
		}
	}
	if section != nil {
		add(section)
	}
	return out
}

// output runs a command with a timeout, for what it prints.
func (r *run) output(name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(r.ctx, 5*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, name, args...).Output()
	return string(out), err
}
