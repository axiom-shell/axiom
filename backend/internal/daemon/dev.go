package daemon

import (
	"bytes"
	"context"
	"encoding/json"
	"io/fs"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/schema"
	"github.com/axiom-shell/axiom/backend/internal/schema/yamlsrc"
	"github.com/axiom-shell/axiom/backend/internal/tree"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// Dev mode, switched while axiom runs (`axiom dev on|off`, the settings
// card, /dev) and remembered across sessions in $XDG_STATE_HOME/axiom/
// dev.json. While it's on:
//   - the schema is rebuilt within 100 ms of a YAML edit (schema.changed);
//   - a tree whose schema isn't the binary's may write the config;
//   - the daemon logs at debug level;
//   - an edit to the Go source (or a file the binary embeds) builds a dev
//     binary into $XDG_STATE_HOME/axiom/dev/ and re-execs into it, the
//     shell running on; a build that fails leaves the daemon as it was;
//   - a rebuilt installed binary is re-exec'd into as well.
// Turning it off goes back to the installed binary.

// devChoiceFile holds the saved choice, under the state folder.
const devChoiceFile = "dev.json"

// DevState is dev mode as the shell and the CLI see it (dev.state).
type DevState struct {
	Enabled bool `json:"enabled"`
	// Available: the tree has the Go source and go is installed, so edits
	// can be built; Unavailable says why not (the schema still follows
	// its YAML without them)
	Available   bool         `json:"available"`
	Unavailable string       `json:"unavailable,omitempty"`
	Building    bool         `json:"building"`
	LastBuild   *BuildResult `json:"lastBuild,omitempty"`
	// The image running, and the installed binary dev mode goes back to
	Binary    string `json:"binary"`
	Installed string `json:"installed"`
	// OffReadOnly: turning dev mode off would leave the config read-only
	// (the tree's schema isn't the running binary's, and it is the
	// installed one; from a dev build the installed binary decides)
	OffReadOnly bool `json:"offReadOnly"`
}

// BuildResult is the last dev build.
type BuildResult struct {
	OK     bool      `json:"ok"`
	At     time.Time `json:"at"`
	Output string    `json:"output,omitempty"` // the compiler's output, its tail
}

type devMode struct {
	d *Daemon

	mu        sync.Mutex
	enabled   bool
	building  bool
	lastBuild *BuildResult

	changed chan struct{} // the run loop's cue to start or stop the watchers
	builds  *kicker
}

func newDevMode(d *Daemon, enabled bool) *devMode {
	m := &devMode{d: d, enabled: enabled, changed: make(chan struct{}, 1)}
	m.builds = newKicker(m.build)
	m.setLogLevel(enabled)
	return m
}

func (m *devMode) part() part {
	return part{name: "dev mode", methods: m.methods, run: m.run}
}

// Enabled: dev mode is on.
func (m *devMode) Enabled() bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.enabled
}

// State is dev.state.
func (m *devMode) State() DevState {
	m.mu.Lock()
	defer m.mu.Unlock()
	st := DevState{
		Enabled: m.enabled, Building: m.building, LastBuild: m.lastBuild,
		Binary: m.d.executable, Installed: m.d.installed,
	}
	st.OffReadOnly = m.d.executable == m.d.installed && !m.d.matches()
	if reason := m.unavailable(); reason != "" {
		st.Unavailable = reason
	} else {
		st.Available = true
	}
	return st
}

// unavailable says why edits to the Go source can't be built here ("":
// they can).
func (m *devMode) unavailable() string {
	if _, err := os.Stat(filepath.Join(m.d.opts.Tree, "backend", "go.mod")); err != nil {
		return "this axiom tree has no Go source (an installed package): only the schema follows its source"
	}
	if _, err := exec.LookPath(m.d.opts.Go); err != nil {
		return "go isn't installed: only the schema follows its source"
	}
	return ""
}

// loadDevChoice is the saved choice (off when there is none).
func loadDevChoice(dirs xdg.Dirs) bool {
	data, err := os.ReadFile(dirs.State + devChoiceFile)
	if err != nil {
		return false
	}
	var choice struct {
		Enabled bool `json:"enabled"`
	}
	return json.Unmarshal(data, &choice) == nil && choice.Enabled
}

func saveDevChoice(dirs xdg.Dirs, on bool) error {
	if err := os.MkdirAll(dirs.State, 0o700); err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "making %s", dirs.State)
	}
	data, _ := json.Marshal(map[string]bool{"enabled": on})
	if err := fsx.WriteFile(dirs.State+devChoiceFile, append(data, '\n'), 0o600); err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "saving the dev mode choice")
	}
	return nil
}

// Set turns dev mode on or off, saving the choice. Off while a dev build
// runs goes back to the installed binary.
func (m *devMode) Set(on bool) error {
	if err := saveDevChoice(m.d.dirs, on); err != nil {
		return err
	}
	m.mu.Lock()
	was := m.enabled
	m.enabled = on
	m.mu.Unlock()
	if was == on {
		return nil
	}
	m.d.opts.Log.Info("dev mode", "enabled", on)
	m.setLogLevel(on)
	notify(m.changed)
	m.d.pushState()
	m.push()
	if !on && m.d.executable != m.d.installed {
		m.d.reexecSoon(m.d.installed)
	}
	return nil
}

func (m *devMode) setLogLevel(on bool) {
	if m.d.opts.LogLevel == nil {
		return
	}
	if on {
		m.d.opts.LogLevel.Set(slog.LevelDebug)
	} else {
		m.d.opts.LogLevel.Set(slog.LevelInfo)
	}
}

func (m *devMode) push() {
	if m.d.server != nil {
		pushDevState.Send(m.d.server, m.State(), subscribedTo(topicDaemon))
	}
}

func (m *devMode) methods(reg *rpc.Registry) {
	rpc.Handle(reg, "dev.get", func(ctx context.Context, c *rpc.Conn, _ struct{}) (DevState, error) {
		return m.State(), nil
	})
	rpc.Handle(reg, "dev.set", func(ctx context.Context, c *rpc.Conn, p struct {
		Enabled bool `json:"enabled"`
	}) (DevState, error) {
		if err := m.Set(p.Enabled); err != nil {
			return DevState{}, err
		}
		return m.State(), nil
	})
	rpc.Handle(reg, "dev.rebuild", func(ctx context.Context, c *rpc.Conn, _ struct{}) (struct{}, error) {
		if !m.Enabled() {
			return struct{}{}, axerr.New(axerr.Unavailable, "dev mode is off (axiom dev on)")
		}
		if reason := m.unavailable(); reason != "" {
			return struct{}{}, axerr.New(axerr.Unavailable, "%s", reason)
		}
		m.builds.Kick()
		return struct{}{}, nil
	})
}

// run starts the watchers while dev mode is on and stops them when it
// goes off, until ctx ends.
func (m *devMode) run(ctx context.Context) error {
	var stop func()
	defer func() {
		if stop != nil {
			stop()
		}
	}()
	for {
		if on := m.Enabled(); on && stop == nil {
			stop = m.watch(ctx)
		} else if !on && stop != nil {
			stop()
			stop = nil
		}
		select {
		case <-ctx.Done():
			return nil
		case <-m.changed:
		}
	}
}

// watch starts the watchers and returns what stops them (and waits).
func (m *devMode) watch(ctx context.Context) func() {
	ctx, cancel := context.WithCancel(ctx)
	var wg sync.WaitGroup
	start := func(name string, fn func(context.Context) error) {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := fn(ctx); err != nil {
				m.d.opts.Log.Warn("dev mode: "+name+" stopped", "err", err)
			}
		}()
	}
	start("the schema watch", m.watchSchema)
	if m.d.installed != "" {
		start("the binary watch", m.watchBinary)
	}
	if reason := m.unavailable(); reason == "" {
		start("the builds", m.builds.run)
		start("the source watch", m.watchSource)
	} else {
		m.d.opts.Log.Info("dev mode: not building the Go source", "why", reason)
	}
	return func() {
		cancel()
		wg.Wait()
	}
}

// watchDirs watches every folder under roots (relative to the tree), and
// the folders made later, calling fn for each event on a file keep
// accepts, debounced by delay.
func (m *devMode) watchDirs(ctx context.Context, roots []string, skip func(dir string) bool, keep func(path string) bool, delay time.Duration, fn func()) error {
	w, err := fsnotify.NewWatcher()
	if err != nil {
		return err
	}
	defer w.Close()
	add := func(root string) {
		filepath.WalkDir(root, func(p string, e fs.DirEntry, err error) error {
			if err != nil || !e.IsDir() {
				return nil
			}
			if skip != nil && skip(p) {
				return filepath.SkipDir
			}
			w.Add(p)
			return nil
		})
	}
	for _, r := range roots {
		add(filepath.Join(m.d.opts.Tree, r))
	}
	wait := newDebouncer(delay)
	defer wait.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case ev, ok := <-w.Events:
			if !ok {
				return nil
			}
			if ev.Has(fsnotify.Create) {
				if info, err := os.Stat(ev.Name); err == nil && info.IsDir() {
					add(ev.Name)
				}
			}
			if keep(ev.Name) {
				wait.Event()
			}
		case <-w.Errors:
		case <-wait.C():
			fn()
		}
	}
}

// watchSchema rebuilds the schema whenever its YAML source (config/
// schema/, a type folder's schema.yaml) changes.
func (m *devMode) watchSchema(ctx context.Context) error {
	roots := yamlsrc.Roots(os.DirFS(m.d.opts.Tree))
	isYAML := func(p string) bool { return strings.HasSuffix(p, ".yaml") }
	return m.watchDirs(ctx, roots, nil, isYAML, 100*time.Millisecond, m.d.rebuildSchema)
}

// watchSource builds a dev binary whenever the Go source, or a file the
// binary embeds, changes. Tests, editors' temporary files and the
// generated copies (which the build itself writes) are left out.
func (m *devMode) watchSource(ctx context.Context) error {
	embedded := map[string]bool{
		filepath.Join(m.d.opts.Tree, "config", "json", "backend.json"):        true,
		filepath.Join(m.d.opts.Tree, "config", "json", "theme-defaults.json"): true,
	}
	generated := filepath.Join(m.d.opts.Tree, "backend", "internal", "assets", "data")
	skip := func(dir string) bool {
		base := filepath.Base(dir)
		return dir == generated || base == "testdata" || (strings.HasPrefix(base, ".") && len(base) > 1)
	}
	keep := func(p string) bool {
		if embedded[p] {
			return true
		}
		base := filepath.Base(p)
		if strings.HasPrefix(base, ".") || strings.HasSuffix(base, "_test.go") || !strings.HasPrefix(p, filepath.Join(m.d.opts.Tree, "backend")+"/") {
			return false
		}
		switch filepath.Ext(base) {
		case ".go", ".mod", ".sum", ".js", ".json":
			return true
		}
		return false
	}
	return m.watchDirs(ctx, []string{"backend", filepath.Join("config", "json")}, skip, keep, time.Second, m.builds.Kick)
}

// watchBinary re-execs into the installed binary when it is rebuilt
// (install.sh, a self-update, `go build -o` over it).
func (m *devMode) watchBinary(ctx context.Context) error {
	installed := m.d.installed
	w, err := fsnotify.NewWatcher()
	if err != nil {
		return err
	}
	defer w.Close()
	if err := w.Add(filepath.Dir(installed)); err != nil {
		return err
	}
	before, _ := os.Stat(installed)
	wait := newDebouncer(500 * time.Millisecond)
	defer wait.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case ev, ok := <-w.Events:
			if !ok {
				return nil
			}
			if ev.Name == installed {
				wait.Event()
			}
		case <-w.Errors:
		case <-wait.C():
			now, err := os.Stat(installed)
			if err != nil || now.Mode()&0o111 == 0 || (before != nil && os.SameFile(before, now) && now.ModTime().Equal(before.ModTime())) {
				continue
			}
			if err := m.d.reexec(installed); err != nil {
				m.d.opts.Log.Error("re-exec", "err", err)
			}
		}
	}
}

// buildOutputLimit is how much of the compiler's output a failed build
// keeps (its tail: the errors).
const buildOutputLimit = 8 << 10

// build builds a dev binary from the tree's source and re-execs into it.
func (m *devMode) build(ctx context.Context) {
	m.mu.Lock()
	m.building = true
	m.mu.Unlock()
	m.push()
	out, err := m.compile(ctx)
	if ctx.Err() != nil {
		return
	}
	res := &BuildResult{OK: err == nil, At: time.Now()}
	if err != nil {
		res.Output = string(out)
		if len(res.Output) > buildOutputLimit {
			res.Output = "…" + res.Output[len(res.Output)-buildOutputLimit:]
		}
		m.d.opts.Log.Error("dev build failed: keeping this binary", "err", err, "output", res.Output)
	}
	m.mu.Lock()
	m.building, m.lastBuild = false, res
	m.mu.Unlock()
	m.push()
	if err != nil {
		return
	}
	target := m.binary()
	m.d.opts.Log.Info("dev build done: re-executing", "binary", target)
	if err := m.d.reexec(target); err != nil {
		m.d.opts.Log.Error("re-exec", "err", err)
	}
}

// binary is where dev builds go.
func (m *devMode) binary() string { return m.d.dirs.State + "dev/axiom" }

// compile builds the dev binary.
func (m *devMode) compile(ctx context.Context) ([]byte, error) {
	target := m.binary()
	if err := os.MkdirAll(filepath.Dir(target), 0o700); err != nil {
		return nil, err
	}
	return buildAxiom(ctx, m.d.opts.Go, m.d.opts.Tree, target)
}

// buildAxiom builds the tree's axiom binary to target (a dev build, or
// the installed binary after a self-update): go generate, then go build
// into a file beside it, checked to run before it replaces target. It
// returns the tools' output.
func buildAxiom(ctx context.Context, goBin, treeDir, target string) ([]byte, error) {
	src := filepath.Join(treeDir, "backend")
	next := target + ".new"
	defer os.Remove(next)
	var out bytes.Buffer
	run := func(name string, args ...string) error {
		cmd := exec.CommandContext(ctx, name, args...)
		cmd.Dir = src
		cmd.Env = append(os.Environ(), "CGO_ENABLED=0")
		cmd.Stdout, cmd.Stderr = &out, &out
		return cmd.Run()
	}
	if err := run(goBin, "generate", "./internal/assets"); err != nil {
		return out.Bytes(), axerr.Wrap(axerr.Unavailable, err, "go generate")
	}
	if err := run(goBin, "build", "-o", next, "-trimpath", "./cmd/axiom"); err != nil {
		return out.Bytes(), axerr.Wrap(axerr.Unavailable, err, "go build")
	}
	if err := run(next, "version"); err != nil {
		return out.Bytes(), axerr.Wrap(axerr.Unavailable, err, "the new binary doesn't run")
	}
	return out.Bytes(), os.Rename(next, target)
}

// rebuildSchema builds the schema from its YAML source again: written for
// the shell, schema.changed pushed so it reads it, and the config loaded
// again through it (its config.changed coming after, so the shell never
// holds a config of a shape it doesn't know).
func (d *Daemon) rebuildSchema() {
	data, err := tree.BuildSchema(d.opts.Tree)
	if err != nil {
		d.opts.Log.Error("the schema source doesn't build: keeping the last one", "err", err)
		pushSchemaError.Send(d.server, schemaError{Issues: axerr.IssuesOf(err), Message: err.Error()}, subscribedTo(topicConfig))
		return
	}
	hash := buildinfo.SchemaHash(data)
	if _, old := d.currentSchema(); hash == old {
		return
	}
	parsed, err := jsonx.Unmarshal(data)
	if err != nil {
		return
	}
	if err := fsx.WriteFile(d.runtime.File(SchemaFile), data, 0o600); err != nil {
		d.opts.Log.Error("writing the schema", "err", err)
		return
	}
	// The tree's generated copy too, for the tools and tests: only in a
	// checkout (an installed tree is read-only)
	if _, err := os.Stat(filepath.Join(d.opts.Tree, ".git")); err == nil {
		if err := fsx.WriteFile(filepath.Join(d.opts.Tree, tree.SchemaJSON), data, 0o644); err != nil {
			d.opts.Log.Warn("writing the tree's schema copy", "err", err)
		}
	}
	d.setSchema(data, hash)
	d.dev.push() // whether turning it off leaves the config read-only
	d.opts.Log.Info("rebuilt the schema", "hash", hash)
	pushSchemaChanged.Send(d.server, schemaChanged{Hash: hash, Path: d.runtime.File(SchemaFile)}, subscribedTo(topicConfig))
	d.store.Reschema(config.V2Pipeline{S: schema.New(parsed)})
}
