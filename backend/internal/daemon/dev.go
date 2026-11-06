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
	"sync/atomic"
	"time"

	"github.com/fsnotify/fsnotify"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/devconfig"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/schema"
	"github.com/axiom-shell/axiom/backend/internal/schema/yamlsrc"
	"github.com/axiom-shell/axiom/backend/internal/store"
	"github.com/axiom-shell/axiom/backend/internal/tree"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// Dev mode runs a dev tree (a clone, `axiom dev set <path>`) on its own
// binary, built from it, and its own config ($XDG_CONFIG_HOME/axiom/dev/),
// switched while axiom runs (`axiom dev on|off`, Settings, /dev) and
// remembered across sessions in $XDG_STATE_HOME/axiom/dev.json. It's
// "active" when the dev image runs (the dev build on the dev tree and
// config); turned on, the installed image builds the dev tree (unless its
// build is fresh) and re-execs into it. While it's on:
//   - the dev tree's Go source (or a file the binary embeds) is built,
//     after an edit, into $XDG_STATE_HOME/axiom/dev/axiom, and re-exec'd
//     into, the shell restarted onto the dev tree when it ran another; a
//     build that fails leaves the daemon as it was, and one the source, the
//     tree or the choice changed under doesn't switch;
//   - the dev image rebuilds the schema within 100 ms of a YAML edit
//     (schema.changed); the installed image re-execs into the installed
//     binary when it's rebuilt;
//   - a tree whose schema isn't the binary's may write the config, unless
//     its config version is past this build's migration steps (until the
//     dev build with them re-execs: aheadReason);
//   - the daemon logs at debug level.
// Turning it off goes back to the installed binary, tree and config. Every
// build goes through one kicker (an edit, dev.rebuild, a stale build at the
// session start, dev on, a new dev tree); devstart.go is the session start.

// devChoiceFile holds the saved choice, under the state folder.
const devChoiceFile = "dev.json"

// DevState is dev mode as the shell and the CLI see it (dev.state).
type DevState struct {
	Enabled bool `json:"enabled"`
	// Options: Settings shows the developer options (dev.json, not config)
	Options bool `json:"options"`
	// Active: the dev image runs (the dev build on the dev tree and the dev
	// config); dev mode on and not active, the install runs while the dev
	// build is built
	Active bool `json:"active"`
	// Available: the dev tree has the Go source and go is installed, so it
	// can be built; Unavailable says why not
	Available   bool         `json:"available"`
	Unavailable string       `json:"unavailable,omitempty"`
	Building    bool         `json:"building"`
	LastBuild   *BuildResult `json:"lastBuild,omitempty"`
	// The image running, and the installed binary dev mode goes back to
	Binary    string `json:"binary"`
	Installed string `json:"installed"`
	// The dev tree ("" when none is set) and the install tree; the dev
	// tree's checkout: its branch, commit and whether it has changes
	Tree        string `json:"tree"`
	InstallTree string `json:"installTree"`
	Branch      string `json:"branch,omitempty"`
	Commit      string `json:"commit,omitempty"`
	Dirty       bool   `json:"dirty"`
	// Build: the dev build against the dev tree
	Build DevBuildState `json:"build"`
	// Config: the dev config
	Config DevConfigState `json:"config"`
}

// DevBuildState is the dev build against the dev tree (DevState.build), as
// last looked at (at a switch, the start, after a build: never polled).
type DevBuildState struct {
	// Fresh: built from the dev tree as it is, and new enough to run
	Fresh bool   `json:"fresh"`
	Why   string `json:"why,omitempty"` // why not
	// The build recorded for the dev tree: the commit it was built at, and
	// when
	Commit string     `json:"commit,omitempty"`
	Dirty  bool       `json:"dirty"`
	At     *time.Time `json:"at,omitempty"`
}

// DevConfigState is the dev config (DevState.config): its file and live's,
// and what readying it last did and found (the dev image's at its start;
// the install image's at its last dev.config.*, with a dev tree set).
type DevConfigState struct {
	Path     string `json:"path"`
	LivePath string `json:"livePath"`
	devconfig.Prepared
}

// DevSetParams are dev.set's: each field given changes that (tree "":
// none).
type DevSetParams struct {
	Enabled *bool   `json:"enabled,omitempty"`
	Tree    *string `json:"tree,omitempty"`
	Options *bool   `json:"options,omitempty"`
}

// BuildResult is the last dev build.
type BuildResult struct {
	OK     bool      `json:"ok"`
	At     time.Time `json:"at"`
	Output string    `json:"output,omitempty"` // the compiler's output, its tail
}

type devMode struct {
	d *Daemon

	// setMu: one dev.set at a time
	setMu sync.Mutex

	mu       sync.Mutex
	enabled  bool
	tree     string // the dev tree ("": none)
	options  bool
	building bool
	// gen counts the dev tree's changes: a build of an earlier gen never
	// switches
	gen int
	// switching: a re-exec into another image is scheduled, and no other
	// switch is taken meanwhile
	switching bool
	lastBuild *BuildResult
	git       gitState   // the dev tree's checkout
	check     buildCheck // the dev build against the dev tree
	// prepared is what readying the dev config did (the dev image)
	prepared devconfig.Prepared
	// startKick: build once the builds run (stale at the session start)
	startKick bool

	// configMu: one dev.config.* at a time; liveMu: one write to live
	// (devsync.go)
	configMu sync.Mutex
	liveMu   sync.Mutex
	// The install tree's schema and, for the install image's dev.config.*,
	// the dev tree's, built when asked (the Fns in tests)
	installCache    treeSchemaCache
	installSchemaFn func() (*schema.Schema, error)
	devCache        treeSchemaCache
	devSchemaFn     func() (*schema.Schema, error)

	changed chan struct{} // the run loop's cue to start or stop the watchers
	builds  *kicker
	// edited: the source changed since the build running started, so
	// it's stale (its kick comes once the edits settle)
	edited atomic.Bool
}

func newDevMode(d *Daemon, enabled bool) *devMode {
	m := &devMode{d: d, enabled: enabled, changed: make(chan struct{}, 1)}
	m.installCache.what, m.devCache.what = "the install tree's schema", "the dev tree's schema"
	m.builds = newKicker(m.build)
	m.setLogLevel(enabled)
	return m
}

// begin takes the saved choice's tree and options, reads the dev tree's
// checkout and build, and takes the session start's decision: a stale
// build is built once the builds run, a tripped guard is told.
func (m *devMode) begin(ctx context.Context, choice devChoice, plan startDecision) {
	var git gitState
	var check buildCheck
	if choice.Tree != "" {
		git = gitInfo(ctx, choice.Tree)
		check = buildFresh(m.d.dirs, choice.Tree)
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.tree, m.options, m.git, m.check = choice.Tree, choice.Options, git, check
	switch plan.Action {
	case startBuild:
		if m.enabled && !m.active() {
			m.d.opts.Log.Info("dev mode: building the dev tree, then switching", "tree", choice.Tree, "why", plan.Why)
			m.startKick = true
		}
	case startStayLive:
		m.d.opts.Log.Warn("dev mode: staying on the installed axiom", "why", plan.Why)
		m.lastBuild = &BuildResult{At: time.Now(), Output: plan.Why}
	}
}

func (m *devMode) part() part {
	return part{name: "dev mode", methods: m.methods, run: m.run, onConfig: m.onConfig}
}

// Enabled: dev mode is on.
func (m *devMode) Enabled() bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.enabled
}

// active: the dev image runs (on the dev config).
func (m *devMode) active() bool {
	return m.d.configDir != "" && m.d.configDir == devConfigDir(m.d.dirs)
}

// State is dev.state.
func (m *devMode) State() DevState {
	m.mu.Lock()
	defer m.mu.Unlock()
	st := DevState{
		Enabled: m.enabled, Options: m.options, Active: m.active(),
		Building: m.building, LastBuild: m.lastBuild,
		Binary: m.d.executable, Installed: m.d.installed,
		Tree: m.tree, InstallTree: m.d.installTree,
		Branch: m.git.Branch, Commit: m.git.Commit, Dirty: m.git.Dirty,
		Build: DevBuildState{Fresh: m.check.Fresh, Why: m.check.Why},
		Config: DevConfigState{
			Path:     filepath.Join(devConfigDir(m.d.dirs), store.FileName),
			LivePath: filepath.Join(m.d.dirs.Config, store.FileName),
		},
	}
	if b := m.check.Build; m.tree != "" && b.Tree == m.tree {
		at := b.At
		st.Build.Commit, st.Build.Dirty, st.Build.At = b.Commit, b.Dirty, &at
	}
	if st.Active || m.tree != "" {
		st.Config.Prepared = m.prepared
	}
	if reason := m.unavailable(m.tree); reason != "" {
		st.Unavailable = reason
	} else {
		st.Available = true
	}
	return st
}

// unavailable says why the dev tree at treeDir can't be built here ("":
// it can).
func (m *devMode) unavailable(treeDir string) string {
	if treeDir == "" {
		return "no dev tree is set: axiom dev set <clone>"
	}
	if _, err := os.Stat(filepath.Join(treeDir, "backend", "go.mod")); err != nil {
		return "the dev tree has no Go source"
	}
	if _, err := exec.LookPath(m.d.opts.Go); err != nil {
		return "go isn't installed"
	}
	return ""
}

// devChoice is what dev.json keeps: whether dev mode is on, the dev tree
// it runs (a clone's root, "" when none is set) and whether Settings shows
// the developer options. A file of before the tree (only "enabled") reads
// as no tree and no options.
type devChoice struct {
	Enabled bool   `json:"enabled"`
	Tree    string `json:"tree,omitempty"`
	Options bool   `json:"options"`
}

// loadDevChoice is the saved choice (all off when there is none, or it
// isn't JSON).
func loadDevChoice(dirs xdg.Dirs) devChoice {
	var choice devChoice
	data, err := os.ReadFile(dirs.State + devChoiceFile)
	if err != nil || json.Unmarshal(data, &choice) != nil {
		return devChoice{}
	}
	return choice
}

// saveDevChoice changes the saved choice: it reads dev.json, applies
// change and writes it back, keeping the keys it doesn't know (a dev
// build of another branch may have written more).
func saveDevChoice(dirs xdg.Dirs, change func(*devChoice)) error {
	if err := os.MkdirAll(dirs.State, 0o700); err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "making %s", dirs.State)
	}
	path := dirs.State + devChoiceFile
	raw := map[string]json.RawMessage{}
	if data, err := os.ReadFile(path); err == nil && json.Unmarshal(data, &raw) != nil {
		raw = map[string]json.RawMessage{} // not JSON: written anew
	}
	choice := loadDevChoice(dirs)
	change(&choice)
	fields, _ := json.Marshal(choice)
	var known map[string]json.RawMessage
	json.Unmarshal(fields, &known)
	delete(raw, "tree") // omitted when cleared
	for k, v := range known {
		raw[k] = v
	}
	data, _ := json.Marshal(raw)
	if err := fsx.WriteFile(path, append(data, '\n'), 0o600); err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "saving the dev mode choice")
	}
	return nil
}

// SaveDevChoice is dev.set with no axiom running (`axiom dev set` and
// `dev options` offline, as install.sh runs it before the first start):
// the tree, checked as dev.set checks it, and the options saved in
// dev.json for the next start, the saved choice returned. On and off are
// switched only while axiom runs, and a tree dev mode is on for isn't
// cleared.
func SaveDevChoice(dirs xdg.Dirs, p DevSetParams) (tree string, options bool, err error) {
	if p.Enabled != nil {
		return "", false, axerr.New(axerr.Unavailable, "no axiom is running: dev mode is switched on and off while it runs")
	}
	var newTree string
	if p.Tree != nil && *p.Tree != "" {
		if newTree, err = validDevTree(*p.Tree); err != nil {
			return "", false, err
		}
	}
	if p.Tree != nil && newTree == "" && loadDevChoice(dirs).Enabled {
		return "", false, axerr.New(axerr.Refused, "dev mode runs this tree: turn it off first (axiom dev off)")
	}
	err = saveDevChoice(dirs, func(c *devChoice) {
		if p.Tree != nil {
			c.Tree = newTree
		}
		if p.Options != nil {
			c.Options = *p.Options
		}
	})
	choice := loadDevChoice(dirs)
	return choice.Tree, choice.Options, err
}

// validDevTree is path as a dev tree (its symlinks resolved), or why it
// can't be one: an absolute path to an axiom tree with the Go source.
func validDevTree(path string) (string, error) {
	if !filepath.IsAbs(path) {
		return "", axerr.New(axerr.BadRequest, "the dev tree must be an absolute path: %s", path)
	}
	resolved, err := filepath.EvalSymlinks(path)
	if err != nil {
		return "", axerr.Wrap(axerr.NotFound, err, "the dev tree %s", path)
	}
	if !tree.IsTree(resolved) {
		return "", axerr.New(axerr.NotFound, "%s isn't an axiom tree (no qml/shell.qml and qml/config/)", resolved)
	}
	if _, err := os.Stat(filepath.Join(resolved, "backend", "go.mod")); err != nil {
		return "", axerr.New(axerr.NotFound, "%s has no Go source (backend/go.mod): a dev tree is a clone", resolved)
	}
	return resolved, nil
}

// devImage is the dev image on the dev tree at treeDir.
func (m *devMode) devImage(treeDir string) image {
	return image{Tree: treeDir, ConfigDir: devConfigDir(m.d.dirs), Dev: true}
}

// installImage is the install's image, dev mode off.
func (m *devMode) installImage() image {
	return image{Tree: m.d.installTree, ConfigDir: m.d.dirs.Config, Dev: false}
}

// Set changes dev mode (dev.set), saving the choice: the dev tree (checked;
// "" clears it), the developer options, and on or off. On builds the dev
// tree and re-execs into it (at once when its build is fresh); a new dev
// tree while on does the same; off, from the dev image, re-execs into the
// installed binary on the install tree and live config (a build running
// meanwhile finds dev mode off and doesn't switch).
func (m *devMode) Set(ctx context.Context, p DevSetParams) error {
	m.setMu.Lock()
	defer m.setMu.Unlock()
	var newTree string
	if p.Tree != nil && *p.Tree != "" {
		t, err := validDevTree(*p.Tree)
		if err != nil {
			return err
		}
		newTree = t
	}
	m.mu.Lock()
	wasOn, oldTree, switching := m.enabled, m.tree, m.switching
	m.mu.Unlock()
	if switching {
		return axerr.New(axerr.Unavailable, "dev mode is switching: try again in a moment")
	}
	on, treeDir := wasOn, oldTree
	if p.Enabled != nil {
		on = *p.Enabled
	}
	if p.Tree != nil {
		treeDir = newTree
	}
	treeChanged := treeDir != oldTree
	// Refused only when asked for dev on or a tree: `axiom run --dev` runs
	// dev mode on with no tree, and its options still change
	if on && treeDir == "" && (p.Enabled != nil || p.Tree != nil) {
		if oldTree != "" {
			return axerr.New(axerr.Refused, "dev mode runs this tree: turn it off first (axiom dev off)")
		}
		return axerr.New(axerr.Refused, "set a dev tree first: axiom dev set <clone>")
	}
	// What a switch onto the dev tree would run: its build, else a new one
	var check buildCheck
	var git gitState
	if treeDir != "" && (treeChanged || on && !wasOn) {
		check = buildFresh(m.d.dirs, treeDir)
		if on && !check.Fresh {
			if reason := m.unavailable(treeDir); reason != "" {
				return axerr.New(axerr.Unavailable, "the dev tree can't be built: %s", reason)
			}
		}
	}
	if treeChanged && treeDir != "" {
		git = gitInfo(ctx, treeDir)
	}
	if err := saveDevChoice(m.d.dirs, func(c *devChoice) {
		// Enabled only when asked: --dev's one run is never saved
		c.Tree = treeDir
		if p.Enabled != nil {
			c.Enabled = on
		}
		if p.Options != nil {
			c.Options = *p.Options
		}
	}); err != nil {
		return err
	}

	m.mu.Lock()
	m.enabled, m.tree = on, treeDir
	if p.Options != nil {
		m.options = *p.Options
	}
	if treeChanged {
		m.gen++
		m.git, m.check = git, check
		if treeDir == "" {
			m.check = buildCheck{}
		}
		if !m.active() {
			m.prepared = devconfig.Prepared{} // another tree's dev config schema
		}
	} else if treeDir != "" && on && !wasOn {
		m.check = check
	}
	// A stale build is built by the builds the watchers restart with (a
	// kick now could reach the old ones, cancelled mid-build)
	if on && (!wasOn || treeChanged) && !check.Fresh {
		m.startKick = true
	}
	m.mu.Unlock()

	if on != wasOn {
		m.d.opts.Log.Info("dev mode", "enabled", on, "tree", treeDir)
		m.setLogLevel(on)
		m.d.pushState()
	}
	if treeChanged {
		m.d.opts.Log.Info("dev mode: the dev tree", "tree", treeDir)
	}
	if on != wasOn || treeChanged {
		notify(m.changed)
	}
	m.push()
	switch {
	case !on && wasOn:
		if m.active() || m.d.executable != m.d.installed {
			m.switchSoon(m.d.installed, m.installImage())
		}
	case on && (!wasOn || treeChanged):
		if check.Fresh {
			m.switchSoon(DevBinary(m.d.dirs), m.devImage(treeDir))
		}
	}
	return nil
}

// switchSoon re-execs into exe running img once the reply is out, and
// refuses other switches meanwhile.
func (m *devMode) switchSoon(exe string, img image) {
	m.mu.Lock()
	m.switching = true
	m.mu.Unlock()
	m.d.reexecSoon(exe, img)
}

// switchFailed: the re-exec didn't happen, the daemon runs on.
func (m *devMode) switchFailed() {
	m.mu.Lock()
	was := m.switching
	m.switching = false
	m.mu.Unlock()
	if was {
		m.push()
	}
}

// shellHello: the shell said hello. In the dev image it came up, so the
// boot guard's marker goes.
func (m *devMode) shellHello() {
	if !m.active() {
		return
	}
	if err := clearBoot(m.d.dirs); err != nil {
		m.d.opts.Log.Warn("dev mode: clearing the boot guard", "err", err)
	}
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
	rpc.Handle(reg, "dev.set", func(ctx context.Context, c *rpc.Conn, p DevSetParams) (DevState, error) {
		if err := m.Set(ctx, p); err != nil {
			return DevState{}, err
		}
		return m.State(), nil
	})
	rpc.Handle(reg, "dev.rebuild", func(ctx context.Context, c *rpc.Conn, _ struct{}) (struct{}, error) {
		m.mu.Lock()
		treeDir := m.tree
		m.mu.Unlock()
		if reason := m.unavailable(treeDir); reason != "" {
			return struct{}{}, axerr.New(axerr.Unavailable, "%s", reason)
		}
		m.builds.Kick()
		return struct{}{}, nil
	})
	m.configMethods(reg)
}

// watchKey is what the watchers run for: dev mode on and its tree (the
// image, active or not, is the process's own).
type watchKey struct {
	enabled bool
	tree    string
}

func (m *devMode) watchKey() watchKey {
	m.mu.Lock()
	defer m.mu.Unlock()
	return watchKey{m.enabled, m.tree}
}

// run starts the watchers for dev mode as it is, and starts them again
// whenever it goes on or off or its tree changes, until ctx ends.
func (m *devMode) run(ctx context.Context) error {
	var stop func()
	var key watchKey
	defer func() {
		if stop != nil {
			stop()
		}
	}()
	for {
		if k := m.watchKey(); stop == nil || k != key {
			if stop != nil {
				stop()
			}
			key, stop = k, m.watch(ctx, k)
		}
		select {
		case <-ctx.Done():
			return nil
		case <-m.changed:
		}
	}
}

// watch starts the watchers for key and returns what stops them (and
// waits): the builds while a buildable dev tree is set (dev.rebuild works
// with dev mode off); while dev mode is on, the dev tree's source, and the
// schema's YAML in the dev image, else the installed binary.
func (m *devMode) watch(ctx context.Context, key watchKey) func() {
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
	if key.enabled {
		if m.active() {
			start("the schema watch", m.watchSchema)
		} else if m.d.installed != "" {
			start("the binary watch", m.watchBinary)
		}
	}
	if reason := m.unavailable(key.tree); reason == "" {
		start("the builds", m.builds.run)
		if key.enabled {
			start("the source watch", func(ctx context.Context) error { return m.watchSource(ctx, key.tree) })
			m.mu.Lock()
			kick := m.startKick
			m.startKick = false
			m.mu.Unlock()
			if kick {
				m.builds.Kick()
			}
		}
	} else if key.enabled {
		m.d.opts.Log.Info("dev mode: not building the dev tree", "why", reason)
	}
	return func() {
		cancel()
		wg.Wait()
	}
}

// watchDirs watches every folder under roots (absolute paths), and
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
		add(r)
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

// watchSchema rebuilds the schema whenever its YAML source (qml/config/
// schema/, a type folder's schema.yaml) changes.
func (m *devMode) watchSchema(ctx context.Context) error {
	qml := tree.QMLDir(m.d.opts.Tree)
	var roots []string
	for _, r := range yamlsrc.Roots(os.DirFS(qml)) {
		roots = append(roots, filepath.Join(qml, r))
	}
	isYAML := func(p string) bool { return strings.HasSuffix(p, ".yaml") }
	return m.watchDirs(ctx, roots, nil, isYAML, 100*time.Millisecond, m.d.rebuildSchema)
}

// watchSource builds a dev binary whenever a build input of the dev tree
// at treeDir changes (isBuildInput: the Go source, a file the binary
// embeds).
func (m *devMode) watchSource(ctx context.Context, treeDir string) error {
	keep := func(p string) bool {
		if isBuildInput(treeDir, p) {
			m.edited.Store(true)
			return true
		}
		return false
	}
	roots := []string{filepath.Join(treeDir, "backend"), filepath.Join(tree.QMLDir(treeDir), "config", "json")}
	return m.watchDirs(ctx, roots, buildWalkSkip(treeDir), keep, time.Second, m.builds.Kick)
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
			if err := m.d.reexecInto(installed, m.d.image()); err != nil {
				m.d.opts.Log.Error("re-exec", "err", err)
			}
		}
	}
}

// buildOutputLimit is how much of the compiler's output a failed build
// keeps (its tail: the errors).
const buildOutputLimit = 8 << 10

// build builds the dev binary from the dev tree's source, records it
// (build.json) and re-execs into the dev image, unless dev mode is off (a
// rebuild with it off only builds), its tree changed (gen), another switch
// was scheduled, or the source changed (a branch switch, then a pull: the image would be stale
// and the edits' kick would die with this process, so the next build, that
// kick's, re-execs instead). A binary older than dev trees is never run.
func (m *devMode) build(ctx context.Context) {
	m.mu.Lock()
	treeDir, gen := m.tree, m.gen
	if treeDir == "" {
		m.mu.Unlock()
		return
	}
	m.building = true
	m.mu.Unlock()
	m.edited.Store(false)
	m.push()
	fp, fpErr := fingerprint(treeDir)
	info, out, err := m.compile(ctx, treeDir)
	if ctx.Err() != nil {
		m.mu.Lock()
		m.building = false
		m.mu.Unlock()
		m.push()
		return
	}
	swapped := err == nil
	if err == nil && info.Handoff < minDevHandoff {
		err = axerr.New(axerr.Unavailable, "this tree predates dev trees: merge main")
		out = []byte(err.Error())
	}
	res := &BuildResult{OK: err == nil, At: time.Now()}
	if err != nil {
		res.Output = string(out)
		if len(res.Output) > buildOutputLimit {
			res.Output = "…" + res.Output[len(res.Output)-buildOutputLimit:]
		}
		m.d.opts.Log.Error("dev build failed: keeping this binary", "err", err, "output", res.Output)
	}
	git := gitInfo(ctx, treeDir)
	if err == nil && fpErr == nil {
		b := devBuild{Tree: treeDir, Fingerprint: fp, Commit: git.Commit, Dirty: git.Dirty, Handoff: info.Handoff, Protocol: info.Protocol, At: res.At}
		if werr := writeBuild(m.d.dirs, b); werr != nil {
			m.d.opts.Log.Warn("dev mode: recording the build", "err", werr)
		}
	} else if swapped {
		// The new binary replaced the dev one but isn't recorded (refused
		// handoff, or no fingerprint): drop the old record, so it never
		// vouches for this binary as its tree's fresh build
		if rerr := os.Remove(m.d.dirs.State + buildFile); rerr != nil && !os.IsNotExist(rerr) {
			m.d.opts.Log.Warn("dev mode: dropping the build record", "err", rerr)
		}
	}
	m.mu.Lock()
	m.building, m.lastBuild = false, res
	if m.gen == gen {
		m.git = git
		if err == nil {
			m.check = buildFresh(m.d.dirs, treeDir)
		}
	}
	m.mu.Unlock()
	m.push()
	if err != nil {
		return
	}
	if m.edited.Load() {
		m.d.opts.Log.Info("dev build done, but the source changed meanwhile: building again")
		return
	}
	m.mu.Lock()
	switchNow := m.enabled && m.gen == gen && !m.switching
	if switchNow {
		m.switching = true
	}
	m.mu.Unlock()
	if !switchNow {
		m.d.opts.Log.Info("dev build done, but dev mode is off, its tree changed or it's switching: not re-executing")
		return
	}
	target := m.binary()
	m.d.opts.Log.Info("dev build done: re-executing", "binary", target, "tree", treeDir)
	if err := m.d.reexecInto(target, m.devImage(treeDir)); err != nil {
		m.d.opts.Log.Error("re-exec", "err", err)
		m.switchFailed()
	}
}

// binary is where dev builds go.
func (m *devMode) binary() string { return DevBinary(m.d.dirs) }

// DevBinary is where dev builds go (the CLI runs it when its protocol
// isn't the daemon's).
func DevBinary(dirs xdg.Dirs) string { return dirs.State + "dev/axiom" }

// compile builds the dev binary from the tree at treeDir.
func (m *devMode) compile(ctx context.Context, treeDir string) (buildinfo.Info, []byte, error) {
	target := m.binary()
	if err := os.MkdirAll(filepath.Dir(target), 0o700); err != nil {
		return buildinfo.Info{}, nil, err
	}
	return buildAxiom(ctx, m.d.opts.Go, treeDir, target)
}

// buildAxiom builds the tree's axiom binary to target (a dev build, or
// the installed binary after a self-update): go generate, then go build
// into a file beside it, checked to run before it replaces target. It
// returns what the new binary says it is (`version --json`) and the
// tools' output.
func buildAxiom(ctx context.Context, goBin, treeDir, target string) (buildinfo.Info, []byte, error) {
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
		return buildinfo.Info{}, out.Bytes(), axerr.Wrap(axerr.Unavailable, err, "go generate")
	}
	if err := run(goBin, "build", "-o", next, "-trimpath", "./cmd/axiom"); err != nil {
		return buildinfo.Info{}, out.Bytes(), axerr.Wrap(axerr.Unavailable, err, "go build")
	}
	info, vout, err := swapIn(ctx, next, target)
	if err != nil {
		out.Write(vout)
	}
	return info, out.Bytes(), err
}

// swapIn replaces target with next, a new axiom binary beside it, once
// it's checked to run: what it says it is (`version --json`; a zero Info
// when it doesn't say, as no binary of before the field would be execed
// for dev mode) and its output.
func swapIn(ctx context.Context, next, target string) (buildinfo.Info, []byte, error) {
	var stdout, stderr bytes.Buffer
	cmd := exec.CommandContext(ctx, next, "version", "--json")
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		return buildinfo.Info{}, append(stdout.Bytes(), stderr.Bytes()...), axerr.Wrap(axerr.Unavailable, err, "the new binary doesn't run")
	}
	var info buildinfo.Info
	if json.Unmarshal(stdout.Bytes(), &info) != nil {
		info = buildinfo.Info{}
	}
	return info, stdout.Bytes(), os.Rename(next, target)
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
		if err := fsx.WriteFile(tree.SchemaPath(d.opts.Tree), data, 0o644); err != nil {
			d.opts.Log.Warn("writing the tree's schema copy", "err", err)
		}
	}
	d.setSchema(data, hash)
	d.opts.Log.Info("rebuilt the schema", "hash", hash)
	// Saving holds off while the schema is ahead of this build's steps
	d.pushState()
	pushSchemaChanged.Send(d.server, schemaChanged{Hash: hash, Path: d.runtime.File(SchemaFile)}, subscribedTo(topicConfig))
	d.store.Reschema(config.Pipeline{S: schema.New(parsed)})
}
