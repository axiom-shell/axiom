// Package saved keeps named snapshots of the config (saved/<name>.json in
// the config folder) and shares configs: the examples shipped in the tree,
// files imported, exports written to the home folder.
//
// A snapshot holds what share.Snapshot picks (the look, personal parts,
// commands, and the wallpaper setup), in the export format, so a saved file
// can be shared or imported as it is. Restoring applies it like an example,
// plus its wallpaper setup where the files are still there. Restoring one
// or applying a shared file (an example, an import, a community setup)
// first keeps the running config: edits go into the active snapshot, and
// with none active it's saved as "unsaved" (one file, replaced each time).
// An applied file becomes the active snapshot at once; untouched, it goes
// once another replaces it, as that file applies it again. Nothing loaded
// changes a takeover setting (x-takeover): the store keeps them. Any format
// axiom reads is taken (an older file is converted on the way).
package saved

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/migrate/convert"
	"github.com/axiom-shell/axiom/backend/internal/migrate/legacy"
	"github.com/axiom-shell/axiom/backend/internal/migrate/steps"
	"github.com/axiom-shell/axiom/backend/internal/share"
	"github.com/axiom-shell/axiom/backend/internal/store"
)

// Options configure a Service.
type Options struct {
	Dir      string // the config folder: snapshots in saved/
	Examples string // the tree's examples/
	Home     string // where exports go
	UIState  string // the file remembering the active snapshot
	Store    *store.Store
	// Pipeline is the store's (it changes when the schema is rebuilt)
	Pipeline func() config.Pipeline
	Now      func() time.Time
	Log      *slog.Logger
	// OnState is told whenever State changes (pushed as saved.state); it
	// must not call back into the service
	OnState func(State)
}

// State is what the settings page shows of the snapshots.
type State struct {
	// The snapshot the running config was last saved as or restored from,
	// "" for none (or once its file is gone)
	Active string `json:"active"`
	// The shared setup it was saved from, unchanged since ("" for one the
	// user saved)
	ActiveSource string `json:"activeSource"`
	// The running config's snapshot parts differ from the active one's
	Modified bool `json:"modified"`
	// What an apply or restore does with the running config first (plan)
	Keep KeepPlan `json:"keep"`
	// The same for one that changes the wallpaper setup too (a community
	// setup with its wallpaper)
	KeepWallpaper KeepPlan `json:"keepWallpaper"`
}

// KeepPlan is where the running config goes before something replaces it.
type KeepPlan struct {
	// The snapshot it's saved into: the active one (its edits), the
	// kindUnsaved backup, or "" (it's on disk already)
	Into string `json:"into"`
	// Into is the kindUnsaved backup: there's no active snapshot to hold it
	Backup bool `json:"backup"`
	// The backup there is gets replaced, losing what it holds
	Replaces bool `json:"replaces"`
}

// Entry is one snapshot on disk.
type Entry struct {
	Name     string    `json:"name"`
	Title    string    `json:"title"`
	Modified time.Time `json:"modified"`
}

// Example is one of the tree's examples, with what a preview draws of it:
// its theme, the screen border, and its shown bars and docks.
type Example struct {
	Name         string        `json:"name"`
	Title        string        `json:"title"`
	Description  string        `json:"description"`
	Theme        string        `json:"theme"`
	ScreenBorder bool          `json:"screenBorder"`
	Bars         []ExampleBar  `json:"bars"`
	Docks        []ExampleDock `json:"docks"`
}

// ExampleBar is an example's bar: its edge and background style.
type ExampleBar struct {
	Location   string `json:"location"`
	Background string `json:"background"`
}

// ExampleDock is an example's dock: its edge.
type ExampleDock struct {
	Edge string `json:"edge"`
}

// Preview is a shared file read for the settings page to confirm.
type Preview struct {
	Name        string `json:"name"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Path        string `json:"path"`
	// It holds preferences, keybinds or apps (personal), or commands
	HasPersonal bool `json:"hasPersonal"`
	HasCommands bool `json:"hasCommands"`
}

// Applied says what an apply or restore did: the snapshot the config
// before it was saved as ("" when it was already on disk), and the one the
// result is ("" for none).
type Applied struct {
	Name string `json:"name"`
	// The active snapshot the running config's edits were saved into
	Kept   string `json:"kept"`
	Backup string `json:"backup"`
	Saved  string `json:"saved"`
}

// Service is the snapshots and sharing, over one store.
type Service struct {
	opts Options

	mu sync.Mutex // one change at a time: a backup, then its apply
	// the active snapshot's parts as it loads, for Modified
	baseline *jsonx.Object
	state    State
	// the active snapshot's meta.kind: kindCopy, kindUnsaved or "" (the
	// user's)
	activeKind string
}

// New returns a service, its active snapshot read back.
func New(opts Options) *Service {
	if opts.Now == nil {
		opts.Now = time.Now
	}
	if opts.Log == nil {
		opts.Log = slog.New(slog.DiscardHandler)
	}
	s := &Service{opts: opts}
	// Made up front: the shell's file list watches it from the start
	if opts.Dir != "" {
		_ = os.MkdirAll(s.savedDir(), 0o700)
	}
	var remembered struct {
		Active string `json:"active"`
	}
	if data, err := os.ReadFile(opts.UIState); err == nil {
		_ = json.Unmarshal(data, &remembered)
	}
	s.setActive(remembered.Active, nil, "", "")
	return s
}

func (s *Service) savedDir() string { return filepath.Join(s.opts.Dir, "saved") }

var unsafeName = regexp.MustCompile(`[^A-Za-z0-9 _.-]`)

// Sanitize is a snapshot's file name for a name typed: letters, digits,
// space, _ . -, no leading dot.
func Sanitize(name string) string {
	return strings.TrimLeft(unsafeName.ReplaceAllString(strings.TrimSpace(name), "_"), ".")
}

// What a snapshot is for, in its meta.kind: a decision about a snapshot
// reads this, never its name. None (every file saved before kinds) is the
// user's: never replaced or deleted unasked.
const (
	// The copy an applied file (an example, a community setup) was saved
	// as: deleted once something else replaces it, as that file applies it
	// again
	kindCopy = "copy"
	// The running config, kept before something replaced it when it wasn't
	// on disk: one file, replaced each time
	kindUnsaved = "unsaved"
)

// unsaved is the name the kindUnsaved snapshot is saved under, when no
// snapshot of the user's has it.
const unsaved = "unsaved"

func (s *Service) path(name string) string {
	return filepath.Join(s.savedDir(), Sanitize(name)+".json")
}

// List is every snapshot, newest first.
func (s *Service) List() ([]Entry, error) {
	entries, err := os.ReadDir(s.savedDir())
	if errors.Is(err, fs.ErrNotExist) {
		return []Entry{}, nil
	}
	if err != nil {
		return nil, err
	}
	out := []Entry{}
	for _, e := range entries {
		name, ok := strings.CutSuffix(e.Name(), ".json")
		if !ok || !e.Type().IsRegular() {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		title := name
		if parsed, err := readJSON(filepath.Join(s.savedDir(), e.Name())); err == nil {
			if t := header(parsed).Title; t != "" {
				title = t
			}
		}
		out = append(out, Entry{Name: name, Title: title, Modified: info.ModTime()})
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].Modified.After(out[j].Modified) })
	return out, nil
}

// State is the active snapshot and whether the config has changed since.
func (s *Service) State() State {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.state
}

// Changed recomputes Modified after the config changed, telling OnState.
// The store's change events come while an apply may hold the service, so
// they call it on a goroutine of their own.
func (s *Service) Changed() {
	s.mu.Lock()
	before := s.state
	s.state.Modified = s.modified()
	s.state.Keep, s.state.KeepWallpaper = s.plan(false), s.plan(true)
	after := s.state
	s.mu.Unlock()
	if after != before && s.opts.OnState != nil {
		s.opts.OnState(after)
	}
}

func (s *Service) modified() bool {
	if s.state.Active == "" || s.baseline == nil {
		return false
	}
	cfg, _ := s.opts.Store.Config()
	return !jsonx.Equal(share.Snapshot(s.opts.Pipeline().Schema(), cfg), s.baseline)
}

// Save writes the running config's snapshot parts as name (replacing one
// of that name), and makes it the active one. source: the shared setup it
// holds as applied. It returns the name it was saved as.
func (s *Service) Save(name, source string) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.save(name, source, "")
}

func (s *Service) save(name, source, kind string) (string, error) {
	file := Sanitize(name)
	if file == "" {
		return "", axerr.New(axerr.BadRequest, "a snapshot needs a name")
	}
	cfg, _ := s.opts.Store.Config()
	sch := s.opts.Pipeline().Schema()
	out := envelope(file, "", source, kind)
	body := share.Sparse(sch, share.Snapshot(sch, cfg)).(*jsonx.Object)
	for _, k := range body.Keys() {
		out.Set(k, body.Value(k))
	}
	if err := os.MkdirAll(s.savedDir(), 0o700); err != nil {
		return "", err
	}
	if err := fsx.WriteFile(s.path(file), jsonx.Marshal(out), 0o600); err != nil {
		return "", axerr.Wrap(axerr.Unavailable, err, "saving %s", file)
	}
	s.setActive(file, cfg, source, kind)
	s.opts.Log.Info("saved the config", "as", file)
	return file, nil
}

// envelope is a shared file's head: its format and version, and meta.
func envelope(title, description, source, kind string) *jsonx.Object {
	meta := jsonx.Obj("title", title, "description", description)
	if source != "" {
		meta.Set("source", source)
	}
	if kind != "" {
		meta.Set("kind", kind)
	}
	return jsonx.Obj("format", float64(convert.Format), "version", float64(steps.Current()), "meta", meta)
}

// Restore applies the snapshot name: its parts, and its wallpaper setup
// where the files are still there; it becomes the active one, after the
// running config is kept (keep).
func (s *Service) Restore(name string) (Applied, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	path := s.path(name)
	parsed, err := readJSON(path)
	if err != nil {
		return Applied{}, axerr.Wrap(axerr.NotFound, err, "%q can't be read", name)
	}
	loaded, err := s.load(parsed)
	if err != nil {
		return Applied{}, err
	}
	result := Applied{Name: Sanitize(name), Saved: Sanitize(name)}
	h := header(parsed)
	sch := s.opts.Pipeline().Schema()
	var existing []string
	for _, file := range share.SnapshotFiles(sch, loaded) {
		if _, err := os.Stat(file); err == nil {
			existing = append(existing, file)
		}
	}
	current, _ := s.opts.Store.Config()
	applied := share.Apply(sch, current, loaded, share.Everything, nil)
	applied = share.WithSnapshot(sch, applied, loaded, existing)
	// Restoring the active one itself discards its edits (Revert), and the
	// backup with none active takes its file as it was: keeping the running
	// config there would replace what's being restored
	plan := s.plan(share.SnapshotChanged(sch, current, applied))
	// The confirm said what plan(false) does (keepHint): with the look at
	// the defaults, the backup isn't replaced for a wallpaper setup alone
	if plan.Replaces && s.plan(false).Into == "" {
		plan = KeepPlan{}
	}
	if result.Name != s.state.Active && !(plan.Backup && plan.Into == result.Name) {
		if err := s.keep(plan, &result); err != nil {
			return Applied{}, err
		}
	}
	previous, copied := s.state.Active, s.activeKind == kindCopy
	if _, err := s.opts.Store.Replace(applied.(*jsonx.Object), store.SetOptions{Restore: true}); err != nil {
		return result, err
	}
	after, _ := s.opts.Store.Config()
	s.setActive(result.Name, after, h.Source, h.Kind)
	if copied {
		s.drop(previous, result.Name)
	}
	s.opts.Log.Info("restored a saved config", "name", name, "kept", result.Kept, "backup", result.Backup)
	return result, nil
}

// Remove deletes the snapshot name.
func (s *Service) Remove(name string) error {
	s.mu.Lock()
	err := s.remove(name)
	s.mu.Unlock()
	// Deleting the backup changes what an apply would do with it (plan)
	s.Changed()
	return err
}

func (s *Service) remove(name string) error {
	if err := os.Remove(s.path(name)); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	if Sanitize(name) == s.state.Active {
		s.setActive("", nil, "", "")
	}
	return nil
}

// keep carries out plan, the running config saved where it says, naming
// it in result (Kept or Backup).
func (s *Service) keep(plan KeepPlan, result *Applied) error {
	if plan.Into == "" {
		return nil
	}
	// Saved into, a kindCopy one is the user's; the backup stays the backup
	kind := ""
	if plan.Backup || s.activeKind == kindUnsaved {
		kind = kindUnsaved
	}
	if _, err := s.save(plan.Into, "", kind); err != nil {
		return err
	}
	if plan.Backup {
		result.Backup = plan.Into
	} else {
		result.Kept = plan.Into
	}
	return nil
}

// plan says where the running config goes before something replaces it.
// With an active snapshot (loaded, its file there): its edits go into it,
// and an unchanged one is on disk, except a kindCopy one when wallpaper
// (what replaces it changes the wallpaper setup too, which the file it
// came from doesn't hold): saved into, it stays. With none, the schema's
// defaults are on disk (Restore defaults applies them again; not with
// wallpaper: they leave machine settings as they are), and anything else
// is saved as the kindUnsaved backup.
func (s *Service) plan(wallpaper bool) KeepPlan {
	if s.state.Active != "" && s.baseline != nil {
		if _, err := os.Stat(s.path(s.state.Active)); err == nil {
			if s.modified() || wallpaper && s.activeKind == kindCopy {
				return KeepPlan{Into: s.state.Active}
			}
			return KeepPlan{}
		}
	}
	if s.state.Active == "" && !wallpaper {
		sch := s.opts.Pipeline().Schema()
		cfg, _ := s.opts.Store.Config()
		if jsonx.Equal(share.Pick(sch, cfg, share.Everything, nil), share.Pick(sch, s.opts.Pipeline().Defaults(), share.Everything, nil)) {
			return KeepPlan{}
		}
	}
	name, exists := s.unsavedName()
	return KeepPlan{Into: name, Backup: true, Replaces: exists}
}

// unsavedName is the kindUnsaved snapshot's name and whether it exists: the
// one there is, else a free name from "unsaved".
func (s *Service) unsavedName() (string, bool) {
	entries, _ := os.ReadDir(s.savedDir())
	for _, e := range entries {
		name, ok := strings.CutSuffix(e.Name(), ".json")
		if !ok || !e.Type().IsRegular() {
			continue
		}
		if parsed, err := readJSON(filepath.Join(s.savedDir(), e.Name())); err == nil && header(parsed).Kind == kindUnsaved {
			return name, true
		}
	}
	return s.freeName(unsaved), false
}

// freeName is base, or "base <n>" past the snapshots that have it.
func (s *Service) freeName(base string) string {
	name := base
	// Any error but "it's there" counts as free: save then says what's wrong
	for n := 2; ; n++ {
		if _, err := os.Stat(s.path(name)); err != nil {
			return name
		}
		name = fmt.Sprintf("%s %d", base, n)
	}
}

// copyOrFree is the name to save an applied file's result as: snapshot,
// unless one of the user's has it (an applied copy saved into, say), then
// a free name.
func (s *Service) copyOrFree(snapshot string) string {
	parsed, err := readJSON(s.path(snapshot))
	if err != nil || header(parsed).Kind == kindCopy {
		return snapshot
	}
	return s.freeName(Sanitize(snapshot))
}

// drop deletes previous, the copy an applied file was saved as (active,
// unchanged since, when it was replaced), unless it's still the one in
// use: the file it came from applies it again.
func (s *Service) drop(previous, current string) {
	if previous == "" || previous == current {
		return
	}
	if err := s.remove(previous); err != nil {
		s.opts.Log.Warn("could not delete an applied copy", "name", previous, "err", err)
	}
}

// setActive makes name the active snapshot, baseline the config it holds
// (nil: read it, its source and kind from its file), remembered across
// restarts.
func (s *Service) setActive(name string, baseline *jsonx.Object, source, kind string) {
	s.state.Active, s.state.ActiveSource, s.activeKind = name, source, kind
	s.baseline = nil
	if name != "" {
		if baseline == nil {
			if parsed, err := readJSON(s.path(name)); err == nil {
				if cfg, err := s.load(parsed); err == nil {
					baseline = cfg
				}
				if source == "" && kind == "" {
					h := header(parsed)
					s.state.ActiveSource, s.activeKind = h.Source, h.Kind
				}
			} else {
				s.state.Active = ""
			}
		}
		if baseline != nil {
			s.baseline = share.Snapshot(s.opts.Pipeline().Schema(), baseline)
		}
	}
	if s.opts.UIState != "" {
		data, _ := json.Marshal(map[string]string{"active": s.state.Active})
		if err := os.MkdirAll(filepath.Dir(s.opts.UIState), 0o700); err == nil {
			_ = fsx.WriteFile(s.opts.UIState, data, 0o600)
		}
	}
	s.state.Modified = s.modified()
	s.state.Keep, s.state.KeepWallpaper = s.plan(false), s.plan(true)
	if s.opts.OnState != nil {
		s.opts.OnState(s.state)
	}
}

// Examples are the tree's examples, by name.
func (s *Service) Examples() []Example {
	entries, _ := os.ReadDir(s.opts.Examples)
	out := []Example{}
	for _, e := range entries {
		name, ok := strings.CutSuffix(e.Name(), ".json")
		if !ok {
			continue
		}
		parsed, err := readJSON(filepath.Join(s.opts.Examples, e.Name()))
		if err != nil {
			continue
		}
		h := header(parsed)
		title := h.Title
		if title == "" {
			title = name
		}
		example := Example{Name: name, Title: title, Description: h.Description, Bars: []ExampleBar{}, Docks: []ExampleDock{}}
		if loaded, err := s.load(parsed); err == nil {
			summarize(&example, loaded)
		}
		out = append(out, example)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

// Open reads a shared file (an export, an example, a whole config.json of
// any version) for the settings page to confirm: what it holds.
func (s *Service) Open(path string) (Preview, error) {
	parsed, err := readShared(path)
	if err != nil {
		return Preview{}, err
	}
	return s.preview(path, parsed)
}

// preview is Open's answer for a file already read.
func (s *Service) preview(path string, parsed any) (Preview, error) {
	if _, err := s.load(parsed); err != nil {
		return Preview{}, err
	}
	h := header(parsed)
	title := h.Title
	if title == "" {
		title = strings.TrimSuffix(filepath.Base(path), ".json")
	}
	name := Sanitize(title)
	if name == "" {
		name = "import"
	}
	// What the file holds, read converted but not filled: a file without
	// personal parts would otherwise bring their defaults
	held := s.held(parsed)
	sch := s.opts.Pipeline().Schema()
	look := share.Pick(sch, held, nil, nil)
	personal := share.Pick(sch, held, []string{"personal"}, nil)
	withCommands := share.Pick(sch, held, share.Everything, nil)
	return Preview{
		Name:        name,
		Title:       title,
		Description: h.Description,
		Path:        path,
		HasPersonal: !jsonx.Equal(personal, look),
		HasCommands: !jsonx.Equal(withCommands, personal),
	}, nil
}

// Import applies the shared file at path (its personal parts too with
// personal, its commands with commands), after keeping the running config
// (keep); the result is saved as "import-<name>", kept like one the user
// saved (the file may not be there to apply it again).
func (s *Service) Import(path string, personal, commands bool, monitors share.Monitors) (Applied, error) {
	// Read once: what's applied is what the preview judged, even if the
	// file changes meanwhile
	parsed, err := readShared(path)
	if err != nil {
		return Applied{}, err
	}
	preview, err := s.preview(path, parsed)
	if err != nil {
		return Applied{}, err
	}
	var carry []string
	if personal && preview.HasPersonal {
		carry = append(carry, "personal")
	}
	if commands && preview.HasCommands {
		carry = append(carry, "commands")
	}
	// No source: its file may be gone, so its copy is the user's to keep
	return s.apply(preview.Name, parsed, carry, monitors, "import-"+preview.Name, "", "")
}

// summarize fills in what a preview of the example draws, from it loaded
// (converted and filled, as applying it would take it).
func summarize(e *Example, cfg *jsonx.Object) {
	at := func(path string) any {
		p, _ := config.ParsePath(path)
		v, _ := config.Lookup(cfg, p)
		return v
	}
	str := func(o *jsonx.Object, k string) string { v, _ := o.Value(k).(string); return v }
	shown := func(o *jsonx.Object) bool { v, ok := o.Value("enabled").(bool); return !ok || v }
	e.Theme, _ = at("Appearance.theme.name").(string)
	e.ScreenBorder, _ = at("Appearance.shape.screenBorder").(bool)
	if bars, ok := at("Bars.items").(*jsonx.Array); ok {
		for _, item := range bars.Items {
			if bar, ok := item.(*jsonx.Object); ok && shown(bar) {
				e.Bars = append(e.Bars, ExampleBar{Location: str(bar, "location"), Background: str(bar, "background")})
			}
		}
	}
	if docks, ok := at("Dock.items").(*jsonx.Array); ok {
		for _, item := range docks.Items {
			if dock, ok := item.(*jsonx.Object); ok && shown(dock) {
				e.Docks = append(e.Docks, ExampleDock{Edge: str(dock, "edge")})
			}
		}
	}
}

// ApplyExample applies the tree's example name (its look), after keeping
// the running config (keep); the result is saved as "example-<name>".
func (s *Service) ApplyExample(name string, monitors share.Monitors) (Applied, error) {
	parsed, err := readJSON(filepath.Join(s.opts.Examples, Sanitize(name)+".json"))
	if err != nil {
		return Applied{}, axerr.Wrap(axerr.NotFound, err, "the example %q", name)
	}
	return s.apply(name, parsed, nil, monitors, "example-"+Sanitize(name), name, "")
}

// ApplyShared applies a shared file's look (a community setup's), after
// keeping the running config (keep); the result is saved as snapshot (""
// for none), its source the setup's name. wallpaper: a file:// URL set as
// the fixed wallpaper on every monitor ("" for none).
func (s *Service) ApplyShared(path, name, snapshot, wallpaper string, monitors share.Monitors) (Applied, error) {
	parsed, err := readShared(path)
	if err != nil {
		return Applied{}, err
	}
	return s.apply(name, parsed, nil, monitors, snapshot, name, wallpaper)
}

// Defaults applies the schema's defaults like an example (the look,
// personal parts and commands; machine settings stay), after keeping the
// running config (keep).
func (s *Service) Defaults() (Applied, error) {
	return s.apply("defaults", s.opts.Pipeline().Defaults(), share.Everything, nil, "", "", "")
}

// apply: the running config kept, then the file's parts in carry applied,
// then (wallpaper not "") that wallpaper set, then (snapshot not "") the
// result saved as snapshot from source (a kindCopy one with a source: its
// file applies it again; copyOrFree), and the untouched copy the last
// applied file was saved as dropped.
func (s *Service) apply(name string, parsed any, carry []string, monitors share.Monitors, snapshot, source, wallpaper string) (Applied, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	loaded, err := s.load(parsed)
	if err != nil {
		return Applied{}, err
	}
	result := Applied{Name: name}
	if err := s.keep(s.plan(wallpaper != ""), &result); err != nil {
		return Applied{}, err
	}
	previous, copied := s.state.Active, s.activeKind == kindCopy
	current, _ := s.opts.Store.Config()
	applied := share.Apply(s.opts.Pipeline().Schema(), current, loaded, carry, monitors).(*jsonx.Object)
	if wallpaper != "" {
		setWallpaper(applied, wallpaper, monitors)
	}
	if _, err := s.opts.Store.Replace(applied, store.SetOptions{Restore: true}); err != nil {
		return Applied{}, err
	}
	s.setActive("", nil, "", "")
	if snapshot != "" {
		kind := ""
		if source != "" {
			kind = kindCopy
		}
		if result.Saved, err = s.save(s.copyOrFree(snapshot), source, kind); err != nil {
			return result, err
		}
	}
	if copied {
		s.drop(previous, result.Saved)
	}
	s.opts.Log.Info("applied a shared config", "name", name, "carry", carry, "kept", result.Kept, "backup", result.Backup)
	return result, nil
}

// setWallpaper makes url cfg's fixed wallpaper, on every monitor.
func setWallpaper(cfg *jsonx.Object, url string, monitors share.Monitors) {
	appearance, _ := cfg.Value("Appearance").(*jsonx.Object)
	if appearance == nil {
		appearance = jsonx.NewObject()
		cfg.Set("Appearance", appearance)
	}
	wallpaper, _ := appearance.Value("wallpaper").(*jsonx.Object)
	if wallpaper == nil {
		wallpaper = jsonx.NewObject()
		appearance.Set("wallpaper", wallpaper)
	}
	wallpaper.Set("mode", "fixed")
	wallpaper.Set("file", url)
	perScreen, _ := wallpaper.Value("perScreen").(*jsonx.Object)
	if perScreen == nil {
		perScreen = jsonx.NewObject()
		wallpaper.Set("perScreen", perScreen)
	}
	for _, output := range monitors {
		perScreen.Set(output, url)
	}
}

// Export writes the running config's look (its personal parts with
// personal, commands with commands) to ~/axiom-<active>-<date>-<time>.json,
// only what differs from the defaults. places: monitors are named by their
// place (monitors, left to right), so the file applies on another PC.
func (s *Service) Export(personal, commands, places bool, monitors share.Monitors) (string, error) {
	var carry []string
	if personal {
		carry = append(carry, "personal")
	}
	if commands {
		carry = append(carry, "commands")
	}
	if !places {
		monitors = nil
	}
	state := s.State()
	cfg, _ := s.opts.Store.Config()
	sch := s.opts.Pipeline().Schema()
	title := state.Active
	if title == "" {
		title = "axiom"
	}
	out := envelope(title, "", "", "")
	body := share.Sparse(sch, share.Pick(sch, cfg, carry, monitors)).(*jsonx.Object)
	for _, k := range body.Keys() {
		out.Set(k, body.Value(k))
	}
	named := ""
	if state.Active != "" {
		named = strings.ReplaceAll(Sanitize(state.Active), " ", "-") + "-"
	}
	path := filepath.Join(s.opts.Home, "axiom-"+named+s.opts.Now().Format("2006-01-02-150405")+".json")
	if err := fsx.WriteFile(path, jsonx.Marshal(out), 0o644); err != nil {
		return "", axerr.Wrap(axerr.Unavailable, err, "exporting")
	}
	return path, nil
}

// load is a shared or saved file as it applies: loaded as config.json is
// (an older format converted), keeping what an older file never held
// (share.KeepMovedKeys).
func (s *Service) load(parsed any) (*jsonx.Object, error) {
	loaded, err := s.opts.Pipeline().Load(withoutHeader(parsed))
	if err != nil {
		return nil, err
	}
	if len(loaded.Errors) > 0 {
		return nil, &axerr.Error{Kind: axerr.InvalidConfig, Message: "it isn't a valid config", Issues: issuesOf(loaded.Errors)}
	}
	cfg := loaded.Config
	if loaded.FromFormat1 {
		obj, _ := parsed.(*jsonx.Object)
		current, _ := s.opts.Store.Config()
		kept, _ := share.KeepMovedKeys(cfg, s.held(parsed), current, obj.Value("version")).(*jsonx.Object)
		cfg = kept
	}
	return cfg, nil
}

// held is a shared file migrated (and converted) but not filled: what it
// holds itself.
func (s *Service) held(parsed any) *jsonx.Object {
	obj, _ := withoutHeader(parsed).(*jsonx.Object)
	if obj == nil {
		return jsonx.NewObject()
	}
	if _, ok := obj.Get("format"); ok {
		return obj
	}
	migrated, err := legacy.Migrate(obj)
	if err != nil {
		return jsonx.NewObject()
	}
	return convert.ToV2(migrated.Config).Config
}

// withoutHeader drops a shared file's own keys (meta, format 1's
// _example), which the pipeline would prune anyway.
func withoutHeader(parsed any) any {
	obj, ok := parsed.(*jsonx.Object)
	if !ok {
		return parsed
	}
	out := jsonx.Clone(obj).(*jsonx.Object)
	out.Delete("meta")
	out.Delete("_example")
	return out
}

type headerInfo struct{ Title, Description, Source, Kind string }

// header is a shared file's meta (format 1: _example).
func header(parsed any) headerInfo {
	obj, _ := parsed.(*jsonx.Object)
	if obj == nil {
		return headerInfo{}
	}
	meta, _ := obj.Value("meta").(*jsonx.Object)
	if meta == nil {
		meta, _ = obj.Value("_example").(*jsonx.Object)
	}
	if meta == nil {
		return headerInfo{}
	}
	str := func(k string) string { v, _ := meta.Value(k).(string); return v }
	return headerInfo{Title: str("title"), Description: str("description"), Source: str("source"), Kind: str("kind")}
}

func readJSON(path string) (any, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return jsonx.Unmarshal(data)
}

// readShared reads a file to apply: an object with a version (a file
// without one would be taken for version 1), not from a newer axiom.
func readShared(path string) (any, error) {
	parsed, err := readJSON(path)
	if err != nil {
		return nil, axerr.Wrap(axerr.InvalidConfig, err, "%s", filepath.Base(path))
	}
	obj, err := versioned(parsed, filepath.Base(path))
	if err != nil {
		return nil, err
	}
	version := obj.Value("version").(float64)
	if format, has := obj.Get("format"); has && format != float64(convert.Format) || version > float64(steps.Current()) {
		return nil, axerr.New(axerr.InvalidConfig, "%s is from a newer axiom: update axiom to import it", filepath.Base(path))
	}
	return obj, nil
}

// versioned is parsed (the file name) when it's an object with a version:
// a file without one would be taken for version 1.
func versioned(parsed any, name string) (*jsonx.Object, error) {
	obj, ok := parsed.(*jsonx.Object)
	if !ok {
		return nil, axerr.New(axerr.InvalidConfig, "%s isn't a config", name)
	}
	version, ok := obj.Value("version").(float64)
	if !ok || version < 1 || version != float64(int64(version)) {
		return nil, axerr.New(axerr.InvalidConfig, "%s has no config version, so it can't be imported", name)
	}
	return obj, nil
}

func issuesOf(errs []string) []axerr.Issue {
	out := make([]axerr.Issue, 0, len(errs))
	for _, e := range errs {
		path, msg, ok := strings.Cut(e, ": ")
		if !ok {
			path, msg = "", e
		}
		out = append(out, axerr.Issue{Path: path, Message: msg})
	}
	return out
}
