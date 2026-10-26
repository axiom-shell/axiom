// Package store owns config.json: it holds the writer lock, loads and
// normalizes the file, watches it for edits made outside (an editor, a
// dotfiles checkout), and is the only thing that writes it. Every change
// gets a new revision and is announced to subscribers (the daemon pushes
// it to the shell as config.changed).
//
// A file that doesn't load (bad JSON, invalid) blocks writes until it is
// fixed, so a broken hand edit is never overwritten by the shell; the last
// good config keeps running meanwhile. A file deleted while running is not
// recreated until the next write.
package store

import (
	"bytes"
	"context"
	"errors"
	"io/fs"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/share"
)

// FileName is the config's name in its folder.
const FileName = "config.json"

// Format1File keeps a format-1 config.json as it was before its conversion
// to format 2 (written once, never read by axiom)
const Format1File = "config.format1.json"

// Options configure a Store.
type Options struct {
	Dir      string // the config folder ($XDG_CONFIG_HOME/axiom)
	Pipeline config.Pipeline
	Log      *slog.Logger
	// Debounce is how long a burst of file events settles before a reload
	Debounce time.Duration
}

// State is what subscribers are told besides the config.
type State struct {
	Revision int64         `json:"revision"`
	Blocked  bool          `json:"blocked"`
	Issues   []axerr.Issue `json:"issues,omitempty"`
	Missing  bool          `json:"missing"`
	FirstRun bool          `json:"firstRun"`
}

// Event is one change: the config (nil when only the state changed).
type Event struct {
	State  State
	Config *jsonx.Object
	// FromFile: read from the file (an edit made outside, the schema
	// rebuilt), not a write through the store
	FromFile bool
}

// Store is the open config.
type Store struct {
	opts Options
	path string
	lock *fsx.Lock

	// changeMu serializes changes (writes, reloads); their events queue
	// in that order and are delivered after it is released (publish)
	changeMu sync.Mutex

	mu        sync.Mutex
	config    *jsonx.Object
	state     State
	written   []byte // what we last wrote or read, to tell our writes from others'
	takeovers [][]string
	// Running on the defaults (the file didn't load at the start): the
	// defaults with the takeover settings the file holds, which a restore
	// keeps and a write is checked against, never the defaults' own
	fileTakeovers *jsonx.Object
	// The file wasn't JSON at the start: fileTakeovers are only the
	// defaults, so the first reload that loads takes the file's own
	takeoversUnknown bool
	subs             map[int]func(Event)
	nextSub          int
	// Events not delivered yet, and whether a goroutine is delivering them
	pending  []Event
	draining bool
}

// Open takes the writer lock and loads the config (writing the defaults
// when there is no file yet: a first run).
func Open(opts Options) (*Store, error) {
	if opts.Log == nil {
		opts.Log = slog.New(slog.DiscardHandler)
	}
	if opts.Debounce == 0 {
		opts.Debounce = 150 * time.Millisecond
	}
	if err := os.MkdirAll(opts.Dir, 0o700); err != nil {
		return nil, axerr.Wrap(axerr.Unavailable, err, "making %s", opts.Dir)
	}
	lock, err := fsx.TryLock(filepath.Join(opts.Dir, FileName+".lock"))
	if err != nil {
		if axerr.KindOf(err) == axerr.Running {
			return nil, &axerr.Error{Kind: axerr.Running, Message: "another axiom is writing " + filepath.Join(opts.Dir, FileName), Err: err}
		}
		return nil, err
	}
	s := &Store{
		opts:      opts,
		path:      filepath.Join(opts.Dir, FileName),
		lock:      lock,
		subs:      map[int]func(Event){},
		takeovers: share.TakeoverPaths(opts.Pipeline.Schema()),
	}
	if err := s.loadInitial(); err != nil {
		lock.Release()
		return nil, err
	}
	return s, nil
}

// Close releases the writer lock.
func (s *Store) Close() error { return s.lock.Release() }

// Path is config.json's path.
func (s *Store) Path() string { return s.path }

// Config is the current config (the caller must not modify it) and its
// state.
func (s *Store) Config() (*jsonx.Object, State) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.config, s.state
}

// Takeovers is the config the x-takeover settings in effect are read from:
// the config, or, while it runs on the defaults because the file didn't
// load at the start, the defaults with the file's own takeover settings
// (the caller must not modify it). False when they aren't known (the file
// wasn't JSON at the start): what was applied before stays until it's
// fixed.
func (s *Store) Takeovers() (*jsonx.Object, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.takeoverBase(), !s.takeoversUnknown
}

// Subscribe calls fn after every change, until the returned func is
// called. fn runs in change order, one event at a time, holding no lock:
// it may read Config and write (its own change is delivered once it
// returns).
func (s *Store) Subscribe(fn func(Event)) func() {
	s.mu.Lock()
	id := s.nextSub
	s.nextSub++
	s.subs[id] = fn
	s.mu.Unlock()
	return func() {
		s.mu.Lock()
		delete(s.subs, id)
		s.mu.Unlock()
	}
}

// AckFirstRun clears the first-run flag (the shell has started its
// onboarding).
func (s *Store) AckFirstRun() {
	defer s.publish()
	s.changeMu.Lock()
	defer s.changeMu.Unlock()
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.state.FirstRun {
		s.state.FirstRun = false
		s.queue(Event{State: s.state})
	}
}

// SetOptions qualify a write.
type SetOptions struct {
	// Takeover allows changing x-takeover settings (only their own card
	// asks for it)
	Takeover bool
	// Restore is an explicit replacement (a saved config, an import): it
	// goes ahead while the file doesn't load, and lifts that
	Restore bool
}

// Set applies ops to the current config, validates and writes it, and
// returns the new revision. Nothing changes when any op fails, the result
// is invalid, writes are blocked, or a takeover setting would change
// without SetOptions.Takeover.
func (s *Store) Set(ops []config.Op, opts SetOptions) (int64, error) {
	return s.write(func(current *jsonx.Object) (*jsonx.Object, error) {
		next := jsonx.Clone(current).(*jsonx.Object)
		if err := config.ApplyOps(next, ops); err != nil {
			return nil, err
		}
		return next, nil
	}, opts)
}

// Replace writes cfg whole (an editor's whole config, an import),
// keeping the takeover settings as they are unless opts.Takeover.
func (s *Store) Replace(cfg *jsonx.Object, opts SetOptions) (int64, error) {
	return s.write(func(current *jsonx.Object) (*jsonx.Object, error) {
		next := jsonx.Clone(cfg).(*jsonx.Object)
		if !opts.Takeover {
			base := s.takeoverBase()
			next, _ = share.KeepTakeovers(next, base, s.takeovers).(*jsonx.Object)
			// Where cfg lacks a takeover's section (a saved look), the
			// section is made, so filling the defaults can't reset it
			for _, path := range s.takeovers {
				if v, ok := at(base, path); ok {
					if _, has := at(next, path); !has {
						putAt(next, path, jsonx.Clone(v))
					}
				}
			}
		}
		return next, nil
	}, opts)
}

// Restore replaces the config with a parsed one of any format the
// pipeline reads (an older one converted, as config.json would be), the
// takeover settings kept unless opts.Takeover. It lifts a blocked file.
func (s *Store) Restore(parsed any, opts SetOptions) (int64, error) {
	loaded, err := s.opts.Pipeline.Load(parsed)
	if err != nil {
		return 0, err
	}
	if len(loaded.Errors) > 0 {
		return 0, &axerr.Error{Kind: axerr.InvalidConfig, Message: "the config doesn't load", Issues: issues(loaded.Errors)}
	}
	opts.Restore = true
	return s.Replace(loaded.Config, opts)
}

func (s *Store) write(change func(*jsonx.Object) (*jsonx.Object, error), opts SetOptions) (int64, error) {
	defer s.publish()
	s.changeMu.Lock()
	defer s.changeMu.Unlock()
	s.mu.Lock()
	if s.state.Blocked && !opts.Restore {
		issues := s.state.Issues
		s.mu.Unlock()
		return 0, &axerr.Error{Kind: axerr.Conflict, Message: s.path + " doesn't load: fix it (or restore a saved config) before anything is saved", Issues: issues}
	}
	current := s.config
	next, err := change(current)
	if err != nil {
		s.mu.Unlock()
		return 0, err
	}
	checked, problems := s.opts.Pipeline.Check(next)
	if len(problems) > 0 {
		s.mu.Unlock()
		return 0, &axerr.Error{Kind: axerr.InvalidConfig, Message: "the change makes the config invalid", Issues: issues(problems)}
	}
	if !opts.Takeover {
		base := s.takeoverBase()
		for _, path := range s.takeovers {
			before, _ := at(base, path)
			after, _ := at(checked, path)
			if !jsonx.Equal(before, after) {
				s.mu.Unlock()
				return 0, axerr.New(axerr.TakeoverRefused, "%s takes something over on this PC: change it from its own card", joinPath(path))
			}
		}
	}
	if jsonx.Equal(checked, current) {
		rev := s.state.Revision
		s.mu.Unlock()
		return rev, nil
	}
	data := jsonx.Marshal(checked)
	if err := fsx.WriteFile(s.path, data, 0o600); err != nil {
		s.mu.Unlock()
		return 0, axerr.Wrap(axerr.Unavailable, err, "saving the config")
	}
	s.written = data
	s.config = checked
	s.fileTakeovers, s.takeoversUnknown = nil, false
	s.state.Revision++
	s.state.Missing = false
	if opts.Restore {
		s.state.Blocked, s.state.Issues = false, nil
	}
	ev := Event{State: s.state, Config: checked}
	s.queue(ev)
	s.mu.Unlock()
	return ev.State.Revision, nil
}

// Watch reloads the file whenever something else changes it, until ctx
// ends. A reload keeps every x-takeover setting as it is (holdTakeovers).
func (s *Store) Watch(ctx context.Context) error {
	w, err := fsnotify.NewWatcher()
	if err != nil {
		return err
	}
	defer w.Close()
	dirs := map[string]bool{filepath.Dir(s.path): true}
	// A config symlinked into a dotfiles repo changes in the target's folder
	if target, err := filepath.EvalSymlinks(s.path); err == nil {
		dirs[filepath.Dir(target)] = true
	}
	for d := range dirs {
		if err := w.Add(d); err != nil {
			return err
		}
	}
	var timer *time.Timer
	fire := make(chan struct{}, 1)
	for {
		select {
		case <-ctx.Done():
			return nil
		case ev, ok := <-w.Events:
			if !ok {
				return nil
			}
			if filepath.Base(ev.Name) != FileName && !isTarget(s.path, ev.Name) {
				continue
			}
			if timer == nil {
				timer = time.AfterFunc(s.opts.Debounce, func() {
					select {
					case fire <- struct{}{}:
					default: // one pending reload is enough
					}
				})
			} else {
				timer.Reset(s.opts.Debounce)
			}
		case err, ok := <-w.Errors:
			if !ok {
				return nil
			}
			s.opts.Log.Warn("watching the config", "err", err)
		case <-fire:
			s.reload()
		}
	}
}

// takeoverBase is what the takeover settings are kept from and checked
// against (s.mu held).
func (s *Store) takeoverBase() *jsonx.Object {
	if s.fileTakeovers != nil {
		return s.fileTakeovers
	}
	return s.config
}

func isTarget(path, name string) bool {
	target, err := filepath.EvalSymlinks(path)
	return err == nil && target == name
}

func (s *Store) loadInitial() error {
	data, err := os.ReadFile(s.path)
	if errors.Is(err, fs.ErrNotExist) {
		defaults := s.opts.Pipeline.Defaults()
		out := jsonx.Marshal(defaults)
		if err := fsx.WriteFile(s.path, out, 0o600); err != nil {
			return axerr.Wrap(axerr.Unavailable, err, "writing the first config")
		}
		s.config, s.written = defaults, out
		s.state = State{Revision: 1, FirstRun: true}
		s.opts.Log.Info("no config yet: wrote the defaults", "path", s.path)
		return nil
	}
	if err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "reading the config")
	}
	loaded, problems := s.load(data)
	s.state.Revision = 1
	if problems != nil {
		// Run on the defaults, writes blocked, until the file is fixed
		s.config = s.opts.Pipeline.Defaults()
		s.fileTakeovers, s.takeoversUnknown = s.config, loaded == nil
		if loaded != nil {
			s.fileTakeovers, _ = share.KeepTakeovers(s.config, loaded, s.takeovers).(*jsonx.Object)
		}
		s.state.Blocked, s.state.Issues = true, problems
		s.opts.Log.Warn("the config doesn't load: running on the defaults, saves blocked until it's fixed", "path", s.path, "issues", len(problems))
		return nil
	}
	s.config = loaded
	return nil
}

// load parses and normalizes file content: the config, or the issues
// that keep it from loading (with the config as far as it got, nil when
// it isn't JSON). A migrated file is written back.
func (s *Store) load(data []byte) (*jsonx.Object, []axerr.Issue) {
	parsed, err := jsonx.Unmarshal(bytes.TrimPrefix(data, []byte("\xef\xbb\xbf")))
	if err != nil {
		return nil, []axerr.Issue{{Path: FileName, Message: err.Error()}}
	}
	loaded, err := s.opts.Pipeline.Load(parsed)
	if err != nil {
		return nil, []axerr.Issue{{Path: FileName, Message: err.Error()}}
	}
	for _, key := range loaded.Removed {
		s.opts.Log.Warn("ignoring an unknown config key", "key", key)
	}
	for _, change := range loaded.Changes {
		s.opts.Log.Info("migrated the config", "change", change)
	}
	if len(loaded.Errors) > 0 {
		return loaded.Config, issues(loaded.Errors)
	}
	if loaded.Migrated {
		if loaded.FromFormat1 {
			// The file as it was, once, beside it: nothing is lost if the
			// conversion missed something
			backup := filepath.Join(filepath.Dir(s.path), Format1File)
			if _, err := os.Lstat(backup); errors.Is(err, fs.ErrNotExist) {
				if err := fsx.WriteFile(backup, data, 0o600); err != nil {
					s.opts.Log.Error("keeping the format-1 config failed; the file isn't rewritten", "err", err)
					return loaded.Config, nil
				}
			}
		}
		out := jsonx.Marshal(loaded.Config)
		if err := fsx.WriteFile(s.path, out, 0o600); err != nil {
			s.opts.Log.Error("writing the migrated config", "err", err)
		} else {
			s.written = out
		}
	}
	return loaded.Config, nil
}

func (s *Store) reload() {
	defer s.publish()
	s.changeMu.Lock()
	defer s.changeMu.Unlock()
	data, err := os.ReadFile(s.path)
	s.mu.Lock()
	if errors.Is(err, fs.ErrNotExist) {
		changed := !s.state.Missing
		s.state.Missing = true
		if changed {
			s.queue(Event{State: s.state, FromFile: true})
		}
		s.mu.Unlock()
		if changed {
			s.opts.Log.Warn("the config file is gone: running on the last one, until the next save writes it", "path", s.path)
		}
		return
	}
	if err != nil || bytes.Equal(data, s.written) {
		s.mu.Unlock()
		return
	}
	// Seen now: an edit back to what the store last wrote (an undo after a
	// broken edit) must still be read
	s.written = data
	s.mu.Unlock()

	loaded, problems := s.load(data)

	s.mu.Lock()
	s.state.Missing = false
	var ev Event
	if problems != nil {
		s.state.Blocked, s.state.Issues = true, problems
		ev = Event{State: s.state}
		s.opts.Log.Warn("the config was edited into one that doesn't load: keeping the last good one, saves blocked", "issues", len(problems))
	} else {
		s.state.Blocked, s.state.Issues = false, nil
		loaded = s.holdTakeovers(loaded)
		s.fileTakeovers, s.takeoversUnknown = nil, false
		if !jsonx.Equal(loaded, s.config) {
			s.config = loaded
			s.state.Revision++
			ev = Event{State: s.state, Config: loaded}
		} else {
			ev = Event{State: s.state}
		}
	}
	ev.FromFile = true
	s.queue(ev)
	s.mu.Unlock()
}

// holdTakeovers is loaded (an edit made outside) with every x-takeover
// setting as it is in effect: only its own card changes one, so a hand
// edit, a sync tool or a backup copied over the file never releases a
// managed compositor config or swaps the locker. A setting held is logged
// and written back, so the file says what is in effect and the next start
// loads the same (s.mu held). Nothing is held when no value is known (the
// file wasn't JSON at the start, or a schema rebuild added the setting),
// nor when the held values don't check (a schema rebuild reshaped one).
func (s *Store) holdTakeovers(loaded *jsonx.Object) *jsonx.Object {
	if s.takeoversUnknown {
		return loaded
	}
	base := s.takeoverBase()
	var held []string
	for _, path := range s.takeovers {
		before, known := at(base, path)
		after, _ := at(loaded, path)
		if known && !jsonx.Equal(before, after) {
			held = append(held, joinPath(path))
		}
	}
	if len(held) == 0 {
		return loaded
	}
	kept, problems := s.opts.Pipeline.Check(share.KeepTakeovers(loaded, base, s.takeovers).(*jsonx.Object))
	if len(problems) > 0 {
		s.opts.Log.Warn("the takeover settings in effect don't fit the config read: taking the file's", "keys", held)
		return loaded
	}
	for _, path := range held {
		s.opts.Log.Warn("config.json changed outside the settings: kept a setting that takes something over on this PC as it is; change it from its own card", "key", path)
	}
	out := jsonx.Marshal(kept)
	if err := fsx.WriteFile(s.path, out, 0o600); err != nil {
		s.opts.Log.Error("writing back the takeover settings kept", "err", err)
	} else {
		s.written = out
	}
	return kept
}

// queue adds ev to the events to deliver; called holding changeMu and mu,
// so the queue is in change order.
func (s *Store) queue(ev Event) { s.pending = append(s.pending, ev) }

// publish delivers the queued events, unless another call is delivering
// them (then it delivers these too, in order). Called after changeMu is
// released, so a subscriber may write: its event queues behind this one.
func (s *Store) publish() {
	s.mu.Lock()
	if s.draining {
		s.mu.Unlock()
		return
	}
	s.draining = true
	for len(s.pending) > 0 {
		ev := s.pending[0]
		s.pending = s.pending[1:]
		subs := make([]func(Event), 0, len(s.subs))
		for _, fn := range s.subs {
			subs = append(subs, fn)
		}
		s.mu.Unlock()
		for _, fn := range subs {
			fn(ev)
		}
		s.mu.Lock()
	}
	s.draining = false
	s.mu.Unlock()
}

func issues(lines []string) []axerr.Issue {
	out := make([]axerr.Issue, 0, len(lines))
	for _, l := range lines {
		path, msg, ok := cut(l)
		if !ok {
			path, msg = "", l
		}
		out = append(out, axerr.Issue{Path: path, Message: msg})
	}
	return out
}

// cut splits "path: message" (validation's form) at its first ": ".
func cut(line string) (string, string, bool) {
	for i := 0; i+1 < len(line); i++ {
		if line[i] == ':' && line[i+1] == ' ' {
			return line[:i], line[i+2:], true
		}
	}
	return "", "", false
}

func at(v any, path []string) (any, bool) {
	for _, k := range path {
		obj, ok := v.(*jsonx.Object)
		if !ok {
			return nil, false
		}
		if v, ok = obj.Get(k); !ok {
			return nil, false
		}
	}
	return v, true
}

func joinPath(path []string) string { return strings.Join(path, ".") }

// putAt sets v at path, making the objects on the way; a non-object on
// the way is left alone (validation reports it).
func putAt(o *jsonx.Object, path []string, v any) {
	for _, k := range path[:len(path)-1] {
		child, has := o.Get(k)
		if !has {
			child = jsonx.NewObject()
			o.Set(k, child)
		}
		next, ok := child.(*jsonx.Object)
		if !ok {
			return
		}
		o = next
	}
	o.Set(path[len(path)-1], v)
}

// Peek loads the config without taking the writer lock or writing
// anything (a migrated file is not written back): what `axiom config get`
// reads when no daemon runs.
func Peek(opts Options) (*jsonx.Object, State, error) {
	if opts.Log == nil {
		opts.Log = slog.New(slog.DiscardHandler)
	}
	path := filepath.Join(opts.Dir, FileName)
	data, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return opts.Pipeline.Defaults(), State{Missing: true}, nil
	}
	if err != nil {
		return nil, State{}, axerr.Wrap(axerr.Unavailable, err, "reading the config")
	}
	parsed, err := jsonx.Unmarshal(bytes.TrimPrefix(data, []byte("\xef\xbb\xbf")))
	if err != nil {
		return nil, State{Blocked: true}, &axerr.Error{Kind: axerr.InvalidConfig, Message: path + " isn't JSON", Issues: []axerr.Issue{{Path: FileName, Message: err.Error()}}}
	}
	loaded, err := opts.Pipeline.Load(parsed)
	if err != nil {
		return nil, State{}, err
	}
	if len(loaded.Errors) > 0 {
		return loaded.Config, State{Blocked: true, Issues: issues(loaded.Errors)}, nil
	}
	return loaded.Config, State{}, nil
}

// Pipeline is the one the store reads and writes through now.
func (s *Store) Pipeline() config.Pipeline {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.opts.Pipeline
}

// Reschema switches to another pipeline (the schema changed: `axiom run
// --dev` rebuilt it) and loads the file again through it.
func (s *Store) Reschema(p config.Pipeline) {
	defer s.publish()
	s.changeMu.Lock()
	defer s.changeMu.Unlock()
	s.mu.Lock()
	s.opts.Pipeline = p
	s.takeovers = share.TakeoverPaths(p.Schema())
	s.written = nil
	s.mu.Unlock()
	data, err := os.ReadFile(s.path)
	if err != nil {
		return
	}
	loaded, problems := s.load(data)
	s.mu.Lock()
	var ev Event
	if problems != nil {
		s.state.Blocked, s.state.Issues = true, problems
		ev = Event{State: s.state}
	} else {
		s.state.Blocked, s.state.Issues = false, nil
		loaded = s.holdTakeovers(loaded)
		s.config = loaded
		s.fileTakeovers, s.takeoversUnknown = nil, false
		s.state.Revision++
		ev = Event{State: s.state, Config: loaded}
	}
	ev.FromFile = true
	s.queue(ev)
	s.mu.Unlock()
}

// LockFile is the writer lock's descriptor, for a re-exec to keep it.
func (s *Store) LockFile() *os.File { return s.lock.File() }

// OpenAdopting is Open with the writer lock inherited from the image
// before a re-exec.
func OpenAdopting(opts Options, lockFile *os.File) (*Store, error) {
	if opts.Log == nil {
		opts.Log = slog.New(slog.DiscardHandler)
	}
	if opts.Debounce == 0 {
		opts.Debounce = 150 * time.Millisecond
	}
	path := filepath.Join(opts.Dir, FileName)
	lock, err := fsx.Adopt(lockFile, path+".lock")
	if err != nil {
		return nil, err
	}
	s := &Store{opts: opts, path: path, lock: lock, subs: map[int]func(Event){}, takeovers: share.TakeoverPaths(opts.Pipeline.Schema())}
	if err := s.loadInitial(); err != nil {
		lock.Release()
		return nil, err
	}
	return s, nil
}

// Freeze holds the store so nothing more is written (a re-exec follows).
func (s *Store) Freeze() { s.changeMu.Lock() }

// Thaw undoes Freeze (a re-exec that failed).
func (s *Store) Thaw() { s.changeMu.Unlock() }
