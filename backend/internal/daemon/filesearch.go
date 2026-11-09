package daemon

import (
	"context"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/fileindex"
	"github.com/axiom-shell/axiom/backend/internal/filesearch"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/mimeapps"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/store"
	"github.com/axiom-shell/axiom/backend/internal/thumbnail"
)

// The launcher's file search (Launcher.providers.files): the index, kept
// by fileindex, and what the file rows ask (FileSearchManager).
type fileSearch struct {
	index  *fileindex.Service
	thumbs *thumbnail.Service
	// latest guards each connection's newest query id (queryKey)
	latest sync.Mutex
}

// queryKey holds a connection's newest query id (an *atomic.Int64): a
// query whose id is older answers stale. It goes with the connection.
type queryKey struct{}

// Limits on what a call returns
const (
	defaultFileLimit = 50
	maxFileLimit     = 200
	maxBrowseLimit   = 1000
	// How long ShowItems may take before the folder opens instead
	revealTimeout = 5 * time.Second
)

// newFileSearch is the index on the user's folders, and the thumbnails.
func (d *Daemon) newFileSearch() {
	env := mimeapps.FromEnv(d.opts.Getenv)
	cacheHome := strings.TrimSuffix(d.dirs.Cache, "/axiom/")
	skip := []string{filepath.Join(cacheHome, "thumbnails")}
	if rt := d.opts.Getenv("XDG_RUNTIME_DIR"); filepath.IsAbs(rt) {
		skip = append(skip, filepath.Clean(rt))
	}
	o := fileindex.Options{
		CacheFile:   filepath.Join(d.dirs.Cache, "fileindex.bin"),
		HistoryFile: filepath.Join(d.dirs.State, "launcher-files.json"),
		XBEL:        filepath.Join(env.DataHome, "recently-used.xbel"),
		DataDirs:    append([]string{env.DataHome}, env.DataDirs...),
		Skip:        skip,
		OnState: func(st fileindex.State) {
			if d.server != nil {
				pushFileSearchState.Send(d.server, st, subscribedTo(topicFileSearch))
			}
		},
		Log: d.opts.Log.With("part", "filesearch"),
	}
	if d.opts.fileSearchOptions != nil {
		d.opts.fileSearchOptions(&o)
	}
	d.fileSearch = &fileSearch{
		index:  fileindex.New(o),
		thumbs: thumbnail.New(thumbnail.Options{CacheHome: cacheHome, Go: d.tasks.Go}),
	}
}

// fileSearchSettings reads Launcher.providers.files (a ~ in a root is
// $HOME).
func (d *Daemon) fileSearchSettings() fileindex.Settings {
	if d.opts.fileSearch != nil {
		return *d.opts.fileSearch
	}
	cfg, _ := d.store.Config()
	v, _ := config.Lookup(cfg, config.Keys("Launcher", "providers", "files"))
	o, _ := v.(*jsonx.Object)
	if o == nil {
		return fileindex.Settings{}
	}
	strs := func(v any) []string {
		a, _ := v.(*jsonx.Array)
		var out []string
		if a != nil {
			for _, item := range a.Items {
				if s, ok := item.(string); ok && strings.TrimSpace(s) != "" {
					out = append(out, s)
				}
			}
		}
		return out
	}
	home := d.opts.Getenv("HOME")
	var roots []string
	// reads: Launcher.providers.files.enabled, Launcher.providers.files.roots, Launcher.providers.files.excludes, Launcher.providers.files.showHidden
	for _, r := range strs(o.Value("roots")) {
		if r == "~" || strings.HasPrefix(r, "~/") {
			if home == "" {
				continue
			}
			r = home + r[1:]
		}
		roots = append(roots, r)
	}
	return fileindex.Settings{
		Enabled:  jsonx.Truthy(o.Value("enabled")),
		Roots:    roots,
		Excludes: strs(o.Value("excludes")),
		Hidden:   jsonx.Truthy(o.Value("showHidden")),
	}
}

// fileSearchPart: the index, following its settings.
func (d *Daemon) fileSearchPart() part {
	configure := func() { d.fileSearch.index.Configure(d.fileSearchSettings()) }
	configure()
	return part{
		name:     "filesearch",
		methods:  d.fileSearchMethods,
		run:      d.fileSearch.index.Run,
		onConfig: func(store.Event) { configure() },
	}
}

// fileQueryParams is filesearch.query's: id orders a connection's
// queries (a newer id makes an older query answer stale), dir keeps the
// results below a folder.
type fileQueryParams struct {
	ID    int64  `json:"id"`
	Query string `json:"query"`
	Dir   string `json:"dir,omitempty"`
	Limit int    `json:"limit"`
}

// fileQueryResult: the query's id, its results best first, stale when a
// newer query replaced it (no results then), indexed false while there's
// no index yet or the folder isn't in it.
type fileQueryResult struct {
	ID      int64            `json:"id"`
	Items   []fileindex.Item `json:"items"`
	Stale   bool             `json:"stale"`
	Indexed bool             `json:"indexed"`
}

// newest is a connection's newest query id, kept (with stale's
// semantics) by the queries themselves.
func (d *Daemon) newest(c *rpc.Conn) *atomic.Int64 {
	d.fileSearch.latest.Lock()
	defer d.fileSearch.latest.Unlock()
	if v, ok := c.Value(queryKey{}); ok {
		return v.(*atomic.Int64)
	}
	n := &atomic.Int64{}
	c.SetValue(queryKey{}, n)
	return n
}

func clampLimit(n, def, most int) int {
	if n <= 0 {
		return def
	}
	return min(n, most)
}

func (d *Daemon) fileSearchMethods(reg *rpc.Registry) {
	// The user's files: only the shell asks
	shellOnly := func(c *rpc.Conn) error {
		if !fromShell(c) {
			return axerr.New(axerr.Refused, "only the shell searches the files")
		}
		return nil
	}
	rpc.Handle(reg, "filesearch.get", func(ctx context.Context, c *rpc.Conn, _ struct{}) (fileindex.State, error) {
		if err := shellOnly(c); err != nil {
			return fileindex.State{}, err
		}
		return d.fileSearch.index.State(), nil
	})
	// Newest wins: there's no cancel, so each query carries an id, and
	// one older than its connection's newest stops within ~16k entries
	rpc.Handle(reg, "filesearch.query", func(ctx context.Context, c *rpc.Conn, p fileQueryParams) (fileQueryResult, error) {
		if err := shellOnly(c); err != nil {
			return fileQueryResult{}, err
		}
		if p.Dir != "" && !filepath.IsAbs(p.Dir) {
			return fileQueryResult{}, axerr.New(axerr.BadRequest, "search below an absolute path")
		}
		latest := d.newest(c)
		for {
			cur := latest.Load()
			if p.ID < cur {
				return fileQueryResult{ID: p.ID, Items: []fileindex.Item{}, Stale: true}, nil
			}
			if latest.CompareAndSwap(cur, p.ID) {
				break
			}
		}
		stale := func() bool { return latest.Load() != p.ID || ctx.Err() != nil }
		res := d.fileSearch.index.Query(fileindex.Query{Text: p.Query, Dir: p.Dir, Limit: clampLimit(p.Limit, defaultFileLimit, maxFileLimit),
			Stale: stale})
		if res.Stale {
			res.Items = []fileindex.Item{}
		}
		return fileQueryResult{ID: p.ID, Items: res.Items, Stale: res.Stale, Indexed: res.Indexed}, nil
	})
	type browseParams struct {
		Path   string `json:"path"` // absolute
		Query  string `json:"query,omitempty"`
		Limit  int    `json:"limit"`
		Hidden bool   `json:"hidden,omitempty"`
	}
	// A folder's listing from the disk (works while the index builds,
	// and outside the roots)
	rpc.Handle(reg, "filesearch.browse", func(ctx context.Context, c *rpc.Conn, p browseParams) (fileindex.BrowseResult, error) {
		if err := shellOnly(c); err != nil {
			return fileindex.BrowseResult{}, err
		}
		return d.fileSearch.index.Browse(p.Path, p.Query, clampLimit(p.Limit, maxFileLimit, maxBrowseLimit), p.Hidden)
	})
	type recentParams struct {
		Limit int `json:"limit"`
	}
	type itemsResult struct {
		Items []fileindex.Item `json:"items"`
	}
	// The recently used files: recently-used.xbel's and the launcher's
	rpc.Handle(reg, "filesearch.recent", func(ctx context.Context, c *rpc.Conn, p recentParams) (itemsResult, error) {
		if err := shellOnly(c); err != nil {
			return itemsResult{}, err
		}
		return itemsResult{Items: d.fileSearch.index.Recent(clampLimit(p.Limit, defaultFileLimit, maxFileLimit))}, nil
	})
	type pathParams struct {
		Path string `json:"path"` // absolute
	}
	// The launcher opened a file: its rank and the recent files remember
	rpc.Handle(reg, "filesearch.used", func(ctx context.Context, c *rpc.Conn, p pathParams) (struct{}, error) {
		if err := shellOnly(c); err != nil {
			return struct{}{}, err
		}
		if !filepath.IsAbs(p.Path) {
			return struct{}{}, axerr.New(axerr.BadRequest, "an absolute path")
		}
		return struct{}{}, d.fileSearch.index.Used(p.Path)
	})
	type thumbnailParams struct {
		Path string `json:"path"` // absolute
		Size string `json:"size"` // "normal" (128 px) or "large" (256 px)
	}
	// A file's thumbnail (the freedesktop spec's cache; made for images)
	rpc.Handle(reg, "filesearch.thumbnail", func(ctx context.Context, c *rpc.Conn, p thumbnailParams) (thumbnail.Result, error) {
		if err := shellOnly(c); err != nil {
			return thumbnail.Result{}, err
		}
		return d.fileSearch.thumbs.Get(ctx, p.Path, p.Size)
	})
	type revealResult struct {
		// How: "showItems" (the file manager selected it), or "folder"
		// (none answered: its folder was opened)
		Via string `json:"via"`
	}
	// Shows a file in its folder
	rpc.Handle(reg, "filesearch.reveal", func(ctx context.Context, c *rpc.Conn, p pathParams) (revealResult, error) {
		if err := shellOnly(c); err != nil {
			return revealResult{}, err
		}
		via, err := d.reveal(ctx, p.Path)
		return revealResult{Via: via}, err
	})
}

// reveal asks the file manager to show path selected
// (org.freedesktop.FileManager1.ShowItems: Nautilus, Dolphin, Thunar,
// Nemo); with none answering, it opens the folder holding it.
func (d *Daemon) reveal(ctx context.Context, path string) (string, error) {
	if !filepath.IsAbs(path) {
		return "", axerr.New(axerr.BadRequest, "reveal an absolute path")
	}
	path = filepath.Clean(path)
	if conn, err := d.sessionBus(ctx); err == nil {
		cctx, cancel := context.WithTimeout(ctx, revealTimeout)
		_, err = conn.Call(cctx, "org.freedesktop.FileManager1", "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1",
			"ShowItems", "ass", []string{filesearch.FileURI(path)}, "")
		cancel()
		conn.Close()
		if err == nil {
			return "showItems", nil
		}
	}
	_, err := d.openTarget(ctx, filepath.Dir(path), nil)
	return "folder", err
}
