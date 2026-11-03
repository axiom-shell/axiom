package daemon

import (
	"context"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/devconfig"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/migrate/convert"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/schema"
	"github.com/axiom-shell/axiom/backend/internal/schema/yamlsrc"
	"github.com/axiom-shell/axiom/backend/internal/share"
	"github.com/axiom-shell/axiom/backend/internal/store"
	"github.com/axiom-shell/axiom/backend/internal/tree"
)

// The dev config and live, while the dev image runs (package devconfig):
// dev.config.diff lists every setting they disagree on, three ways against
// the base; dev.config.copy copies chosen ones either way (to live only
// what the install's schema knows, written to live's raw JSON, never
// migrated); dev.config.pull brings live's changes since the base over
// (merge) or makes dev live's copy (replace). A takeover setting changed in
// dev is written to live too (one per machine), and a snapshot the
// installed axiom can restore is never written over.

// Where a copy goes
const (
	copyToLive = "live"
	copyToDev  = "dev"
)

// How a pull brings live over
const (
	pullMerge   = "merge"
	pullReplace = "replace"
)

// DevConfigDiff is dev.config.diff's: every setting dev and live disagree
// on, and whether live changed since the base.
type DevConfigDiff struct {
	Rows        []devconfig.Row `json:"rows"`
	LiveChanged bool            `json:"liveChanged"`
}

// DevConfigCopyParams are dev.config.copy's: the settings (a path copies
// every differing setting under it; a key after a list is an item's id)
// and where they go, "live" or "dev".
type DevConfigCopyParams struct {
	Paths []config.Path `json:"paths"`
	To    string        `json:"to"`
}

// DevConfigCopied is what a copy did: the settings copied, and the diff
// after it.
type DevConfigCopied struct {
	Copied []config.Path `json:"copied"`
	Diff   DevConfigDiff `json:"diff"`
}

// DevConfigPullParams are dev.config.pull's: "merge" (live's changes since
// the base where dev left the setting alone) or "replace" (dev becomes
// live's copy).
type DevConfigPullParams struct {
	Mode string `json:"mode"`
}

// DevConfigPulled is what a pull did: the settings merged, those changed
// on both sides and kept as dev's (merge), and the diff after it.
type DevConfigPulled struct {
	Merged    []config.Path `json:"merged"`
	Conflicts []config.Path `json:"conflicts"`
	Diff      DevConfigDiff `json:"diff"`
}

// installSchemaCache is the install tree's schema, built from its YAML
// source, built again when a source file's time or the files change.
type installSchemaCache struct {
	mu     sync.Mutex
	key    string
	schema *schema.Schema
}

// get is the install tree's schema at treeDir.
func (c *installSchemaCache) get(treeDir string) (*schema.Schema, error) {
	key := schemaSourceKey(treeDir)
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.schema != nil && key != "" && key == c.key {
		return c.schema, nil
	}
	data, err := tree.BuildSchema(treeDir)
	if err != nil {
		return nil, axerr.Wrap(axerr.KindOf(err), err, "the install tree's schema")
	}
	parsed, err := jsonx.Unmarshal(data)
	if err != nil {
		return nil, axerr.Wrap(axerr.Internal, err, "the install tree's schema")
	}
	c.key, c.schema = key, schema.New(parsed)
	return c.schema, nil
}

// schemaSourceKey tells the tree's schema source apart from an earlier
// one: its YAML files' count and newest time ("" when it can't be read).
func schemaSourceKey(treeDir string) string {
	qml := tree.QMLDir(treeDir)
	var count int
	var newest int64
	for _, root := range yamlsrc.Roots(os.DirFS(qml)) {
		filepath.WalkDir(filepath.Join(qml, root), func(p string, e fs.DirEntry, err error) error {
			if err != nil || e.IsDir() || !strings.HasSuffix(p, ".yaml") {
				return nil
			}
			if info, err := e.Info(); err == nil {
				count++
				newest = max(newest, info.ModTime().UnixNano())
			}
			return nil
		})
	}
	if count == 0 {
		return ""
	}
	return fmt.Sprintf("%d:%d", count, newest)
}

// installSchema is the install tree's schema: what live is checked
// against, and what tells dev-only settings.
func (m *devMode) installSchema() (*schema.Schema, error) {
	if m.installSchemaFn != nil {
		return m.installSchemaFn()
	}
	return m.installCache.get(m.d.installTree)
}

// installVersion is the config version the installed axiom migrates to
// (the install schema's version default).
func (m *devMode) installVersion() (float64, error) {
	s, err := m.installSchema()
	if err != nil {
		return 0, err
	}
	v, ok := schema.Get(schema.Get(schema.Get(s.Root(), "properties"), "version"), "default").(float64)
	if !ok {
		return 0, axerr.New(axerr.Internal, "the install tree's schema has no config version")
	}
	return v, nil
}

// liveRestores says whether the installed axiom can restore a snapshot
// (its file's head), so dev mode never writes over it: asked only while
// the dev image runs. One of another format is no one's; one whose version
// can't be told is taken to be live's.
func (m *devMode) liveRestores(snapshot *jsonx.Object) bool {
	if !m.active() {
		return false
	}
	if format, has := snapshot.Get("format"); has && format != float64(convert.Format) {
		return false
	}
	version, ok := snapshot.Value("version").(float64)
	installed, err := m.installVersion()
	if !ok || err != nil {
		return true
	}
	return version <= installed
}

// configMethods are dev.config.*, only while the dev image runs.
func (m *devMode) configMethods(reg *rpc.Registry) {
	rpc.Handle(reg, "dev.config.diff", func(ctx context.Context, c *rpc.Conn, _ struct{}) (DevConfigDiff, error) {
		m.configMu.Lock()
		defer m.configMu.Unlock()
		return m.configDiff()
	})
	rpc.Handle(reg, "dev.config.copy", func(ctx context.Context, c *rpc.Conn, p DevConfigCopyParams) (DevConfigCopied, error) {
		return m.configCopy(p)
	})
	rpc.Handle(reg, "dev.config.pull", func(ctx context.Context, c *rpc.Conn, p DevConfigPullParams) (DevConfigPulled, error) {
		return m.configPull(p)
	})
}

// configOpen refuses the dev config's methods outside the dev image.
func (m *devMode) configOpen() error {
	if !m.active() {
		return axerr.New(axerr.Unavailable, "the dev config is open only while dev mode runs the dev tree (axiom dev on)")
	}
	return nil
}

// devSides is the three configs in dev's shape (base nil when there is
// none, or it doesn't load), live's bytes as read, and the dev pipeline.
type devSides struct {
	base, live, dev *jsonx.Object
	liveRaw         []byte
	pipe            config.Pipeline
}

// sides reads live and the base and takes dev from the store.
func (m *devMode) sides() (devSides, error) {
	f := m.d.devConfigFiles()
	pipe := m.d.store.Pipeline()
	liveRaw, err := devconfig.ReadOptional(f.Live)
	if err != nil {
		return devSides{}, err
	}
	if liveRaw == nil {
		return devSides{}, axerr.New(axerr.NotFound, "there is no live config at %s", f.Live)
	}
	live, err := devconfig.InShape(pipe, liveRaw)
	if err != nil {
		return devSides{}, axerr.Wrap(axerr.KindOf(err), err, "the live config")
	}
	s := devSides{live: live, liveRaw: liveRaw, pipe: pipe}
	if baseRaw, err := devconfig.ReadOptional(f.Base); err == nil && baseRaw != nil {
		s.base, _ = devconfig.InShape(pipe, baseRaw)
	}
	s.dev, _ = m.d.store.Config()
	return s, nil
}

// configDiff is dev.config.diff (configMu held).
func (m *devMode) configDiff() (DevConfigDiff, error) {
	if err := m.configOpen(); err != nil {
		return DevConfigDiff{}, err
	}
	install, err := m.installSchema()
	if err != nil {
		return DevConfigDiff{}, err
	}
	s, err := m.sides()
	if err != nil {
		return DevConfigDiff{}, err
	}
	rows := devconfig.Rows(s.base, s.live, s.dev, install)
	if rows == nil {
		rows = []devconfig.Row{}
	}
	return DevConfigDiff{Rows: rows, LiveChanged: m.liveChangedNow()}, nil
}

// configCopy is dev.config.copy: the rows under the paths given copied to
// dev (through the store, as an edit of dev's) or to live (on its raw
// JSON, checked against the install's schema; a dev-only setting can't
// go).
func (m *devMode) configCopy(p DevConfigCopyParams) (DevConfigCopied, error) {
	if p.To != copyToLive && p.To != copyToDev {
		return DevConfigCopied{}, axerr.New(axerr.BadRequest, "copy to %q: live or dev", p.To)
	}
	if len(p.Paths) == 0 {
		return DevConfigCopied{}, axerr.New(axerr.BadRequest, "no settings to copy")
	}
	m.configMu.Lock()
	defer m.configMu.Unlock()
	diff, err := m.configDiff()
	if err != nil {
		return DevConfigCopied{}, err
	}
	dev, _ := m.d.store.Config()
	var picked []devconfig.Row
	seen := map[string]bool{}
	for _, want := range p.Paths {
		want = config.Resolve(dev, want)
		found := false
		for _, r := range diff.Rows {
			if hasPrefix(r.Path, want) {
				found = true
				if !seen[r.Path.String()] {
					seen[r.Path.String()] = true
					picked = append(picked, r)
				}
			}
		}
		if !found {
			return DevConfigCopied{}, axerr.New(axerr.NotFound, "dev and live don't differ at %s", want)
		}
	}
	var ops []config.Op
	var copied []config.Path
	for _, r := range picked {
		copied = append(copied, r.Path)
		if p.To == copyToLive {
			if r.DevOnly {
				return DevConfigCopied{}, axerr.New(axerr.Refused, "%s is dev only: the installed axiom has no such setting", r.Path)
			}
			if r.HasDev {
				ops = append(ops, config.SetValue(r.Path, jsonx.Clone(r.Dev)))
			} else {
				ops = append(ops, config.Op{Op: "delete", Path: r.Path})
			}
			continue
		}
		op := config.Op{Op: "delete", Path: r.Path}
		if r.HasLive {
			op = config.SetValue(r.Path, jsonx.Clone(r.Live))
		}
		if r.HasDev {
			op = op.WithBase(jsonx.Clone(r.Dev))
		}
		ops = append(ops, op)
	}
	if p.To == copyToLive {
		install, err := m.installSchema()
		if err != nil {
			return DevConfigCopied{}, err
		}
		if err := m.writeLive(ops, install); err != nil {
			return DevConfigCopied{}, err
		}
		m.d.opts.Log.Info("dev config: copied to live", "paths", pathStrings(copied))
	} else {
		takeover := touchesTakeover(ops, m.d.store.Pipeline())
		if _, err := m.d.store.Set(ops, store.SetOptions{Takeover: takeover}); err != nil {
			return DevConfigCopied{}, err
		}
		m.d.opts.Log.Info("dev config: copied from live", "paths", pathStrings(copied))
	}
	after, err := m.configDiff()
	m.push()
	return DevConfigCopied{Copied: copied, Diff: after}, err
}

// configPull is dev.config.pull: live's changes since the base merged
// into dev where dev left the setting as the base had it, or dev made
// live's copy; either way the base is live after it, so live changed no
// more.
func (m *devMode) configPull(p DevConfigPullParams) (DevConfigPulled, error) {
	if p.Mode != pullMerge && p.Mode != pullReplace {
		return DevConfigPulled{}, axerr.New(axerr.BadRequest, "pull mode %q: merge or replace", p.Mode)
	}
	m.configMu.Lock()
	defer m.configMu.Unlock()
	if err := m.configOpen(); err != nil {
		return DevConfigPulled{}, err
	}
	s, err := m.sides()
	if err != nil {
		return DevConfigPulled{}, err
	}
	var out DevConfigPulled
	if p.Mode == pullReplace {
		if _, err := m.d.store.Replace(s.live, store.SetOptions{Restore: true, Takeover: true}); err != nil {
			return DevConfigPulled{}, err
		}
		m.d.opts.Log.Info("dev config: replaced with live")
	} else {
		ops := devconfig.Merge(s.base, s.live, s.dev)
		if len(ops) > 0 {
			if _, err := m.d.store.Set(ops, store.SetOptions{Takeover: touchesTakeover(ops, s.pipe)}); err != nil {
				return DevConfigPulled{}, err
			}
		}
		for _, op := range ops {
			out.Merged = append(out.Merged, op.Path)
		}
		if s.base != nil {
			for _, r := range devconfig.Rows(s.base, s.live, s.dev, s.pipe.Schema()) {
				if r.Side == devconfig.SideBoth {
					out.Conflicts = append(out.Conflicts, r.Path)
				}
			}
		}
		m.d.opts.Log.Info("dev config: brought live's changes over", "merged", pathStrings(out.Merged), "kept", pathStrings(out.Conflicts))
	}
	if err := devconfig.SyncBase(m.d.devConfigFiles(), s.liveRaw); err != nil {
		return out, err
	}
	out.Diff, err = m.configDiff()
	m.push()
	return out, err
}

// liveChangedNow reads again whether live changed since the base, kept
// for dev.state (pushed when it changed).
func (m *devMode) liveChangedNow() bool {
	changed, err := devconfig.LiveChanged(m.d.devConfigFiles(), m.d.store.Pipeline())
	m.mu.Lock()
	if err != nil {
		changed = m.prepared.LiveChanged
		m.d.opts.Log.Warn("dev config: comparing live with the base", "err", err)
	}
	was := m.prepared.LiveChanged
	m.prepared.LiveChanged = changed
	m.mu.Unlock()
	if was != changed {
		m.push()
	}
	return changed
}

// writeLive applies ops to live (devconfig.WriteLive), one write at a
// time: its lock is the file's, which a second taker in this process
// would find held.
func (m *devMode) writeLive(ops []config.Op, install *schema.Schema) error {
	m.liveMu.Lock()
	defer m.liveMu.Unlock()
	f := m.d.devConfigFiles()
	return devconfig.WriteLive(f.Live, f.Base, ops, install)
}

// onConfig mirrors a takeover setting changed in dev to live (one per
// machine): only the dev image's own writes, not a file read. It runs on
// the store's delivery, inside a write a copy or pull may make holding
// configMu, so it takes only liveMu.
func (m *devMode) onConfig(ev store.Event) {
	if !m.active() || ev.FromFile || ev.Config == nil || len(ev.Changes) == 0 {
		return
	}
	var ops []config.Op
	for _, tp := range share.TakeoverPaths(m.d.store.Pipeline().Schema()) {
		path := config.Keys(tp...)
		touched := false
		for _, ch := range ev.Changes {
			if hasPrefix(ch.Path, path) || hasPrefix(path, ch.Path) {
				touched = true
				break
			}
		}
		if !touched {
			continue
		}
		if v, ok := config.Lookup(ev.Config, path); ok {
			ops = append(ops, config.SetValue(path, jsonx.Clone(v)))
		} else {
			ops = append(ops, config.Op{Op: "delete", Path: path})
		}
	}
	if len(ops) == 0 {
		return
	}
	install, err := m.installSchema()
	if err == nil {
		err = m.writeLive(ops, install)
	}
	if err != nil {
		m.d.opts.Log.Warn("dev config: a takeover setting changed, but live didn't take it", "paths", opPaths(ops), "err", err)
		return
	}
	m.d.opts.Log.Info("dev config: a takeover setting changed: written to live too", "paths", opPaths(ops))
}

// touchesTakeover says whether ops change a takeover setting (or a
// section holding one).
func touchesTakeover(ops []config.Op, pipe config.Pipeline) bool {
	for _, tp := range share.TakeoverPaths(pipe.Schema()) {
		path := config.Keys(tp...)
		for _, op := range ops {
			if hasPrefix(op.Path, path) || hasPrefix(path, op.Path) {
				return true
			}
		}
	}
	return false
}

// hasPrefix says path is prefix or under it.
func hasPrefix(path, prefix config.Path) bool {
	if len(prefix) > len(path) {
		return false
	}
	for i, s := range prefix {
		if path[i] != s {
			return false
		}
	}
	return true
}

func pathStrings(paths []config.Path) []string {
	out := make([]string, len(paths))
	for i, p := range paths {
		out[i] = p.String()
	}
	return out
}

func opPaths(ops []config.Op) []string {
	out := make([]string, len(ops))
	for i, op := range ops {
		out[i] = op.Path.String()
	}
	return out
}
