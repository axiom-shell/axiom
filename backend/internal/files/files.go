// Package files is how the shell writes and watches its own files
// (FileManager's write and watch: file.write, file.watch, file.unwatch):
// StateManager's state, notes, the todo list, notification history and
// chats; and lists a folder's files of some kinds (file.list: the
// wallpapers, the notes browser). A write is atomic (fsx) and makes the
// folders it needs; a watch pushes a path's change (a folder's: an
// entry's) to every connection watching it, a moment after a burst of
// events settles, but not one this package's own write made.
package files

import (
	"context"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
)

// Changed is the push: a watched path changed (or went).
type Changed struct {
	Path string `json:"path"`
}

// Subscriber is where changes go: an *rpc.Conn.
type Subscriber interface {
	Notify(method string, params any) error
}

// Options configure Files; the zero Debounce is 50 ms, the zero Go runs a
// plain goroutine, the zero Log discards.
type Options struct {
	Method string // the push's method
	Log    *slog.Logger
	// Context bounds the watcher's loop; Go runs it on a goroutine its
	// owner waits for
	Context  context.Context
	Go       func(func(ctx context.Context))
	Debounce time.Duration
}

// Files holds the watched paths and who watches them.
type Files struct {
	o       Options
	mu      sync.Mutex
	watcher *fsnotify.Watcher // made by the first watch
	// Each subscriber's paths, cleaned, to the path as it asked (what its
	// pushes name)
	subs map[Subscriber]map[string]string
	// Each watched folder's count of watched paths in it
	dirs map[string]int
	// A watched path's file as this package last wrote it
	written map[string]os.FileInfo
	timers  map[string]*time.Timer
	due     map[string]bool
	kick    chan struct{}
}

// New returns Files with nothing watched.
func New(o Options) *Files {
	if o.Context == nil {
		o.Context = context.Background()
	}
	if o.Go == nil {
		o.Go = func(fn func(context.Context)) { go fn(o.Context) }
	}
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	if o.Debounce == 0 {
		o.Debounce = 50 * time.Millisecond
	}
	return &Files{
		o: o, subs: map[Subscriber]map[string]string{}, dirs: map[string]int{},
		written: map[string]os.FileInfo{}, timers: map[string]*time.Timer{}, due: map[string]bool{},
		kick: make(chan struct{}, 1),
	}
}

// clean is path cleaned, or an error when it isn't absolute.
func clean(path string) (string, error) {
	if !filepath.IsAbs(path) {
		return "", axerr.New(axerr.BadRequest, "%q isn't an absolute path", path)
	}
	return filepath.Clean(path), nil
}

// Write replaces path's content with text atomically (a new file is 0644,
// as the shell's own writes were), making its missing folders 0700 first.
func (f *Files) Write(path, text string) error {
	path, err := clean(path)
	if err != nil {
		return err
	}
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "making %s", dir)
	}
	// Held across the write: the rename's event can't settle and push
	// before the file is recorded as this package's (a slow fsync after it)
	f.mu.Lock()
	defer f.mu.Unlock()
	if err := fsx.WriteFile(path, []byte(text), 0o644); err != nil {
		return err
	}
	if f.watched(path) {
		if info, err := os.Stat(path); err == nil {
			f.written[path] = info
		}
		// The folder may be new: watch it now
		f.addDir(dir)
	}
	return nil
}

// Watch adds path to s's watched paths. A path asked for with a trailing
// "/" is a folder, changed when an entry in it is (the notes browser).
func (f *Files) Watch(s Subscriber, asked string) error {
	path, err := clean(asked)
	if err != nil {
		return err
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.watcher == nil {
		w, err := fsnotify.NewWatcher()
		if err != nil {
			return axerr.Wrap(axerr.Unavailable, err, "watching files")
		}
		f.watcher = w
		f.o.Go(f.loop)
	}
	if _, ok := f.subs[s][path]; ok {
		return nil
	}
	if f.subs[s] == nil {
		f.subs[s] = map[string]string{}
	}
	f.subs[s][path] = asked
	dir := watchedDir(path, asked)
	f.dirs[dir]++
	if f.dirs[dir] == 1 {
		f.addDir(dir)
	}
	return nil
}

// Unwatch drops path from s's watched paths.
func (f *Files) Unwatch(s Subscriber, path string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.drop(s, filepath.Clean(path))
}

// Forget drops every watch of s (a connection that closed).
func (f *Files) Forget(s Subscriber) {
	f.mu.Lock()
	defer f.mu.Unlock()
	for path := range f.subs[s] {
		f.drop(s, path)
	}
}

func (f *Files) drop(s Subscriber, path string) {
	asked, ok := f.subs[s][path]
	if !ok {
		return
	}
	delete(f.subs[s], path)
	if len(f.subs[s]) == 0 {
		delete(f.subs, s)
	}
	if !f.watched(path) {
		delete(f.written, path)
	}
	dir := watchedDir(path, asked)
	if f.dirs[dir]--; f.dirs[dir] == 0 {
		delete(f.dirs, dir)
		_ = f.watcher.Remove(dir)
	}
}

// watchedDir is the folder watched for path: path itself for a folder
// (asked with a trailing "/"), else the one holding it.
func watchedDir(path, asked string) string {
	if strings.HasSuffix(asked, "/") {
		return path
	}
	return filepath.Dir(path)
}

// folderOf is the watched folder an entry's change belongs to, or "".
func (f *Files) folderOf(entry string) string {
	dir := filepath.Dir(entry)
	for _, paths := range f.subs {
		if asked, ok := paths[dir]; ok && strings.HasSuffix(asked, "/") {
			return dir
		}
	}
	return ""
}

func (f *Files) watched(path string) bool {
	for _, paths := range f.subs {
		if _, ok := paths[path]; ok {
			return true
		}
	}
	return false
}

// addDir watches a folder; one that doesn't exist yet is watched once a
// write makes it.
func (f *Files) addDir(dir string) {
	if f.dirs[dir] == 0 || f.watcher == nil {
		return
	}
	if err := f.watcher.Add(dir); err != nil && !os.IsNotExist(err) {
		f.o.Log.Warn("can't watch a folder", "dir", dir, "err", err)
	}
}

// loop turns the watcher's events into debounced changes, until ctx ends.
func (f *Files) loop(ctx context.Context) {
	f.mu.Lock()
	w := f.watcher
	f.mu.Unlock()
	defer w.Close()
	for {
		select {
		case <-ctx.Done():
			return
		case ev, ok := <-w.Events:
			if !ok {
				return
			}
			f.event(ev.Name)
		case err, ok := <-w.Errors:
			if !ok {
				return
			}
			f.o.Log.Warn("watching files", "err", err)
		case <-f.kick:
			f.fire()
		}
	}
}

// event (re)starts the settle timer of a watched path, and of the
// watched folder holding it (an open note's folder in the browser).
func (f *Files) event(path string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.watched(path) {
		f.settle(path)
	}
	if dir := f.folderOf(path); dir != "" {
		f.settle(dir)
	}
}

// settle (re)starts path's settle timer; f.mu is held.
func (f *Files) settle(path string) {
	if t := f.timers[path]; t != nil {
		t.Reset(f.o.Debounce)
		return
	}
	f.timers[path] = time.AfterFunc(f.o.Debounce, func() {
		f.mu.Lock()
		delete(f.timers, path)
		f.due[path] = true
		f.mu.Unlock()
		select {
		case f.kick <- struct{}{}:
		default:
		}
	})
}

// fire pushes every settled change, but not a path still holding the
// file this package last wrote there.
func (f *Files) fire() {
	type push struct {
		to   Subscriber
		path string
	}
	var pushes []push
	f.mu.Lock()
	for path := range f.due {
		delete(f.due, path)
		info, err := os.Stat(path)
		if last := f.written[path]; err == nil && last != nil && os.SameFile(info, last) && info.ModTime().Equal(last.ModTime()) && info.Size() == last.Size() {
			continue
		}
		for s, paths := range f.subs {
			if asked, ok := paths[path]; ok {
				pushes = append(pushes, push{s, asked})
			}
		}
	}
	f.mu.Unlock()
	for _, p := range pushes {
		_ = p.to.Notify(f.o.Method, Changed{Path: p.path})
	}
}
