// Package saved keeps named snapshots of the config (saved/<name>.json in
// the config folder) and shares configs: the examples shipped in the tree,
// files imported, exports written to the home folder.
//
// A snapshot holds what share.Snapshot picks (the look, personal parts,
// commands, and the wallpaper setup), in the export format, so a saved file
// can be shared or imported as it is. Restoring applies it like an example,
// plus its wallpaper setup where the files are still there. Applying a
// shared file (an example, an import, a community setup) first saves the
// running config as "before-<name>". Nothing loaded changes a takeover
// setting (x-takeover): the store keeps them. Any format axiom reads is
// taken (an older file is converted on the way).
package saved

import (
	"encoding/json"
	"errors"
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
}

// Entry is one snapshot on disk.
type Entry struct {
	Name     string    `json:"name"`
	Title    string    `json:"title"`
	Modified time.Time `json:"modified"`
}

// Example is one of the tree's examples.
type Example struct {
	Name        string `json:"name"`
	Title       string `json:"title"`
	Description string `json:"description"`
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

// Applied says what an apply did: the snapshot of the config before it,
// and the one the result was saved as ("" for none).
type Applied struct {
	Name   string `json:"name"`
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
	s.setActive(remembered.Active, nil, "")
	return s
}

func (s *Service) savedDir() string { return filepath.Join(s.opts.Dir, "saved") }

var unsafeName = regexp.MustCompile(`[^A-Za-z0-9 _.-]`)

// Sanitize is a snapshot's file name for a name typed: letters, digits,
// space, _ . -, no leading dot.
func Sanitize(name string) string {
	return strings.TrimLeft(unsafeName.ReplaceAllString(strings.TrimSpace(name), "_"), ".")
}

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
	return s.save(name, source)
}

func (s *Service) save(name, source string) (string, error) {
	file := Sanitize(name)
	if file == "" {
		return "", axerr.New(axerr.BadRequest, "a snapshot needs a name")
	}
	cfg, _ := s.opts.Store.Config()
	sch := s.opts.Pipeline().Schema()
	out := envelope(file, "", source)
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
	s.setActive(file, cfg, source)
	s.opts.Log.Info("saved the config", "as", file)
	return file, nil
}

// envelope is a shared file's head: its format and version, and meta.
func envelope(title, description, source string) *jsonx.Object {
	meta := jsonx.Obj("title", title, "description", description)
	if source != "" {
		meta.Set("source", source)
	}
	return jsonx.Obj("format", float64(convert.Format), "version", float64(steps.Current()), "meta", meta)
}

// Restore applies the snapshot name: its parts, and its wallpaper setup
// where the files are still there; it becomes the active one.
func (s *Service) Restore(name string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	path := s.path(name)
	parsed, err := readJSON(path)
	if err != nil {
		return axerr.Wrap(axerr.NotFound, err, "%q can't be read", name)
	}
	loaded, err := s.load(parsed)
	if err != nil {
		return err
	}
	sch := s.opts.Pipeline().Schema()
	current, _ := s.opts.Store.Config()
	applied := share.Apply(sch, current, loaded, share.Everything, nil)
	var existing []string
	for _, file := range share.SnapshotFiles(sch, loaded) {
		if _, err := os.Stat(file); err == nil {
			existing = append(existing, file)
		}
	}
	applied = share.WithSnapshot(sch, applied, loaded, existing)
	if _, err := s.opts.Store.Replace(applied.(*jsonx.Object), store.SetOptions{Restore: true}); err != nil {
		return err
	}
	after, _ := s.opts.Store.Config()
	s.setActive(Sanitize(name), after, header(parsed).Source)
	s.opts.Log.Info("restored a saved config", "name", name)
	return nil
}

// Remove deletes the snapshot name.
func (s *Service) Remove(name string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := os.Remove(s.path(name)); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	if Sanitize(name) == s.state.Active {
		s.setActive("", nil, "")
	}
	return nil
}

// setActive makes name the active snapshot, baseline the config it holds
// (nil: read it from its file), remembered across restarts.
func (s *Service) setActive(name string, baseline *jsonx.Object, source string) {
	s.state.Active, s.state.ActiveSource = name, source
	s.baseline = nil
	if name != "" {
		if baseline == nil {
			if parsed, err := readJSON(s.path(name)); err == nil {
				if cfg, err := s.load(parsed); err == nil {
					baseline = cfg
				}
				if source == "" {
					s.state.ActiveSource = header(parsed).Source
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
		out = append(out, Example{Name: name, Title: title, Description: h.Description})
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
// personal, its commands with commands), after saving the running config
// as "before-<name>"; the result is saved as "import-<name>".
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
	return s.apply(preview.Name, parsed, carry, monitors, "import-"+preview.Name, preview.Name)
}

// ApplyExample applies the tree's example name (its look), after saving
// the running config as "before-<name>"; the result is saved as
// "example-<name>".
func (s *Service) ApplyExample(name string, monitors share.Monitors) (Applied, error) {
	parsed, err := readJSON(filepath.Join(s.opts.Examples, Sanitize(name)+".json"))
	if err != nil {
		return Applied{}, axerr.Wrap(axerr.NotFound, err, "the example %q", name)
	}
	return s.apply(name, parsed, nil, monitors, "example-"+Sanitize(name), name)
}

// ApplyShared applies a shared file's look (a community setup's), after
// saving the running config as "before-<name>"; the result is saved as
// snapshot ("" for none), its source the setup's name.
func (s *Service) ApplyShared(path, name, snapshot string, monitors share.Monitors) (Applied, error) {
	parsed, err := readShared(path)
	if err != nil {
		return Applied{}, err
	}
	return s.apply(name, parsed, nil, monitors, snapshot, name)
}

// Defaults applies the schema's defaults like an example (the look,
// personal parts and commands; machine settings stay), after saving the
// running config as "before-defaults".
func (s *Service) Defaults() (Applied, error) {
	return s.apply("defaults", s.opts.Pipeline().Defaults(), share.Everything, nil, "", "")
}

// apply: backup, then the file's parts in carry applied, then (snapshot
// not "") the result saved as snapshot from source.
func (s *Service) apply(name string, parsed any, carry []string, monitors share.Monitors, snapshot, source string) (Applied, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	loaded, err := s.load(parsed)
	if err != nil {
		return Applied{}, err
	}
	backup, err := s.save("before-"+name, "")
	if err != nil {
		return Applied{}, err
	}
	current, _ := s.opts.Store.Config()
	applied := share.Apply(s.opts.Pipeline().Schema(), current, loaded, carry, monitors)
	if _, err := s.opts.Store.Replace(applied.(*jsonx.Object), store.SetOptions{Restore: true}); err != nil {
		return Applied{}, err
	}
	s.setActive("", nil, "")
	result := Applied{Name: name, Backup: backup}
	if snapshot != "" {
		if result.Saved, err = s.save(snapshot, source); err != nil {
			return result, err
		}
	}
	s.opts.Log.Info("applied a shared config", "name", name, "carry", carry)
	return result, nil
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
	out := envelope(title, "", "")
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

type headerInfo struct{ Title, Description, Source string }

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
	return headerInfo{Title: str("title"), Description: str("description"), Source: str("source")}
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
	obj, ok := parsed.(*jsonx.Object)
	if !ok {
		return nil, axerr.New(axerr.InvalidConfig, "%s isn't a config", filepath.Base(path))
	}
	version, ok := obj.Value("version").(float64)
	if !ok || version < 1 || version != float64(int64(version)) {
		return nil, axerr.New(axerr.InvalidConfig, "%s has no config version, so it can't be imported", filepath.Base(path))
	}
	if format, has := obj.Get("format"); has && format != float64(convert.Format) || version > float64(steps.Current()) {
		return nil, axerr.New(axerr.InvalidConfig, "%s is from a newer axiom: update axiom to import it", filepath.Base(path))
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
