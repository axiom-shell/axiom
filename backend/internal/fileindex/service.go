// Package fileindex keeps the launcher's file index (filesearch) filled
// and current: a crawl child process (`axiom index-crawl`, at SCHED_IDLE
// and idle disk priority) walks the roots and streams each folder to the
// daemon, which only applies them, a folder at a time under a write lock
// held for microseconds; inotify watches folders up to a budget, and a
// stat pass in the same child checks the rest; the index is cached on
// disk and loaded at start. It also answers searches, folder listings and
// the recent files. Docs: docs/dev/features/file-search.md.
package fileindex

import (
	"context"
	"encoding/binary"
	"hash/fnv"
	"log/slog"
	"maps"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/axiom-shell/axiom/backend/internal/filesearch"
)

// Settings are what shapes the index (Launcher.providers.files).
type Settings struct {
	Enabled  bool
	Roots    []string // absolute
	Excludes []string
	Hidden   bool // hidden files and folders are indexed too
}

// Phases of the index
const (
	PhaseOff      = "off"      // file search is off
	PhaseWaiting  = "waiting"  // on, nothing built or loaded yet (the first search starts it)
	PhaseLoading  = "loading"  // reading the cache
	PhaseCrawling = "crawling" // building it: results grow as it goes
	PhaseReady    = "ready"
)

// State is the index as the shell shows it (filesearch.state).
type State struct {
	Phase   string `json:"phase"`
	Entries int    `json:"entries"`
	// Watched folders follow changes at once; Unwatched ones (past the
	// watch budget) are checked by a stat pass
	Watched    int    `json:"watched"`
	Unwatched  int    `json:"unwatched"`
	Unreadable int    `json:"unreadable"` // folders the crawl couldn't read
	Truncated  bool   `json:"truncated"`  // the cap left entries out
	Error      string `json:"error"`
}

// The cap on entries: MaxEntries' default and its hard limit
const (
	DefaultMaxEntries = 500_000
	HardMaxEntries    = 2_000_000
)

// Options configure a Service.
type Options struct {
	// Exe is the binary run as the crawl child (default /proc/self/exe:
	// the image running, whatever is on disk now)
	Exe string
	// CacheFile is the index's cache (~/.cache/axiom/fileindex.bin)
	CacheFile string
	// HistoryFile is the launcher's own file history
	// (~/.local/state/axiom/launcher-files.json)
	HistoryFile string
	// XBEL is recently-used.xbel (~/.local/share/recently-used.xbel)
	XBEL string
	// DataDirs are where shared-mime-info's files are ($XDG_DATA_HOME
	// first, then $XDG_DATA_DIRS)
	DataDirs []string
	// Skip are folders never indexed ($XDG_RUNTIME_DIR, the thumbnails)
	Skip []string
	// MaxEntries caps the index (default DefaultMaxEntries)
	MaxEntries int
	// WatchBudget is how many folders to watch (0: a quarter of the
	// kernel's max_user_watches, at most 64k; -1: none)
	WatchBudget int
	// LoadDelay: an existing cache loads this long after start (20 s),
	// unless a search asks first
	LoadDelay time.Duration
	// StatEvery: the unwatched folders are checked this often (10 min)
	StatEvery time.Duration
	// QuietSpell: a search after this long without a stat pass starts
	// one (1 min)
	QuietSpell time.Duration
	// SaveEvery: the cache is written at most this often while its
	// entries change (30 min), and when Run ends
	SaveEvery time.Duration
	// Pause is the crawl's sleep every 128 folders (10 ms; -1: none)
	Pause time.Duration
	// PushEvery: the state is pushed at most this often while it
	// changes (500 ms)
	PushEvery time.Duration
	// Debounce: a watched folder is read again once its events stop
	// this long (50 ms), or after ten times that at the most
	Debounce time.Duration
	// Tick is the housekeeping's period: saves, stat passes, compaction
	// (1 min)
	Tick    time.Duration
	Now     func() time.Time
	OnState func(State)
	Log     *slog.Logger
}

func (o *Options) defaults() {
	if o.Exe == "" {
		o.Exe = "/proc/self/exe"
	}
	if o.MaxEntries <= 0 {
		o.MaxEntries = DefaultMaxEntries
	}
	o.MaxEntries = min(o.MaxEntries, HardMaxEntries)
	if o.WatchBudget == 0 {
		o.WatchBudget = watchBudget()
	}
	set := func(d *time.Duration, v time.Duration) {
		if *d == 0 {
			*d = v
		}
	}
	set(&o.LoadDelay, 20*time.Second)
	set(&o.StatEvery, 10*time.Minute)
	set(&o.QuietSpell, time.Minute)
	set(&o.SaveEvery, 30*time.Minute)
	set(&o.Pause, 10*time.Millisecond)
	set(&o.PushEvery, 500*time.Millisecond)
	set(&o.Debounce, 50*time.Millisecond)
	set(&o.Tick, time.Minute)
	if o.Now == nil {
		o.Now = time.Now
	}
	if o.OnState == nil {
		o.OnState = func(State) {}
	}
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
}

// Service is the index and what keeps it current. Searches read it under
// mu's read lock; the loop (Run) is its only writer.
type Service struct {
	o    Options
	mu   sync.RWMutex
	ix   *filesearch.Index // nil: none
	hist *history
	meta *meta

	stateMu sync.Mutex
	state   State

	// bonus is the use bonus by entry, resolved from the history at most
	// every bonusEvery for an index (and again when the history changes)
	bonusMu sync.Mutex
	bonus   bonusCache

	setMu    sync.Mutex
	settings Settings
	cfgCh    chan struct{}
	demandCh chan struct{}
	freshCh  chan struct{}
}

// New is a service with file search off until Configure.
func New(o Options) *Service {
	o.defaults()
	return &Service{
		o:        o,
		hist:     &history{path: o.HistoryFile, now: o.Now},
		meta:     newMeta(o.DataDirs),
		state:    State{Phase: PhaseOff},
		cfgCh:    make(chan struct{}, 1),
		demandCh: make(chan struct{}, 1),
		freshCh:  make(chan struct{}, 1),
	}
}

func signal(ch chan struct{}) {
	select {
	case ch <- struct{}{}:
	default:
	}
}

// Configure sets the settings (applied by Run's loop).
func (s *Service) Configure(st Settings) {
	s.setMu.Lock()
	s.settings = st
	s.setMu.Unlock()
	signal(s.cfgCh)
}

func (s *Service) currentSettings() Settings {
	s.setMu.Lock()
	defer s.setMu.Unlock()
	return s.settings
}

// State is the index's state now.
func (s *Service) State() State {
	s.stateMu.Lock()
	defer s.stateMu.Unlock()
	return s.state
}

// Query is one search.
type Query struct {
	Text  string
	Dir   string // only below this folder ("": every root)
	Limit int
	// Stale says a newer query replaced this one
	Stale func() bool
}

// Result is a search's answer.
type Result struct {
	Items []Item
	// Stale: a newer query replaced it before it finished
	Stale bool
	// Indexed: the search ran on the index (false while there's none
	// yet, or for a folder it doesn't hold)
	Indexed bool
}

// Query searches the index, starting it when it waits for a first
// search, and a stat pass after a quiet spell.
func (s *Service) Query(q Query) Result {
	signal(s.demandCh)
	signal(s.freshCh)
	out := Result{Items: []Item{}}
	s.mu.RLock()
	ix := s.ix
	if ix == nil {
		s.mu.RUnlock()
		return out
	}
	under := filesearch.NoEntry
	if q.Dir != "" {
		var ok bool
		if under, ok = ix.Lookup(filepath.Clean(q.Dir)); !ok {
			s.mu.RUnlock()
			return out
		}
	}
	now := s.o.Now()
	bonus := s.useBonus(ix, now)
	hits, stale := ix.Search(filesearch.Query{
		Pattern: filesearch.ParsePattern(q.Text), Under: under, Limit: q.Limit,
		Now: now.UnixNano(), Bonus: bonus, Stale: q.Stale, Shards: runtime.GOMAXPROCS(0),
	})
	paths := make([]string, len(hits))
	for k, h := range hits {
		paths[k] = ix.Path(h.Entry)
	}
	s.mu.RUnlock()
	out.Indexed, out.Stale = true, stale
	for _, p := range paths {
		if it, ok := s.meta.item(p); ok {
			out.Items = append(out.Items, it)
		}
	}
	return out
}

// How long a resolved use bonus is kept
const bonusEvery = 2 * time.Second

type bonusCache struct {
	ix      *filesearch.Index
	version int
	at      time.Time
	byEntry map[uint32]float64
}

// useBonus is the history's use bonus by entry of ix (read-locked by the
// caller): resolving a path is a lookup, so it's done again only every
// bonusEvery, for another index (compacted, rebuilt) or a new use.
func (s *Service) useBonus(ix *filesearch.Index, now time.Time) map[uint32]float64 {
	uses, version := s.hist.snapshot()
	s.bonusMu.Lock()
	defer s.bonusMu.Unlock()
	b := &s.bonus
	if b.ix == ix && b.version == version && now.Sub(b.at) < bonusEvery {
		return b.byEntry
	}
	byEntry := make(map[uint32]float64, len(uses))
	for p, i := range ix.FindAll(slices.Collect(maps.Keys(uses))) {
		byEntry[i] = filesearch.UseBonus(filesearch.Frecency(uses[p], now.UnixMilli()))
	}
	*b = bonusCache{ix: ix, version: version, at: now, byEntry: byEntry}
	return byEntry
}

// Recent are the recently used files that still exist, newest first:
// recently-used.xbel's and the launcher's own.
func (s *Service) Recent(limit int) []Item {
	out := []Item{}
	uses, _ := s.hist.snapshot()
	for _, r := range recent(s.o.XBEL, uses) {
		if len(out) >= limit {
			break
		}
		// A name that isn't UTF-8: JSON would carry another path
		if !utf8.ValidString(r.Path) {
			continue
		}
		if it, ok := s.meta.item(r.Path); ok {
			out = append(out, it)
		}
	}
	return out
}

// Used records that the launcher opened path.
func (s *Service) Used(path string) error {
	return s.hist.used(filepath.Clean(path))
}

// settingsKey names the settings a cache was made for.
func settingsKey(st Settings, max int) uint64 {
	h := fnv.New64a()
	write := func(list []string) {
		h.Write(binary.AppendUvarint(nil, uint64(len(list))))
		for _, s := range list {
			h.Write(binary.AppendUvarint(nil, uint64(len(s))))
			h.Write([]byte(s))
		}
	}
	write(st.Roots)
	write(st.Excludes)
	if st.Hidden {
		h.Write([]byte{1})
	}
	h.Write(binary.AppendUvarint(nil, uint64(max)))
	return h.Sum64()
}

// Run keeps the index until ctx ends.
func (s *Service) Run(ctx context.Context) error {
	l := &loop{s: s, changed: map[string]bool{}, written: map[string]bool{}}
	defer l.shutdown()
	tick := time.NewTicker(s.o.Tick)
	defer tick.Stop()
	l.configure(s.currentSettings())
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-s.cfgCh:
			l.configure(s.currentSettings())
		case <-s.demandCh:
			l.demand()
		case <-s.freshCh:
			l.freshen()
		case <-timerC(l.loadTimer):
			l.loadTimer = nil
			l.load()
		case m := <-l.childC():
			l.childMsg(m)
		case evs := <-l.eventsC():
			l.watchEvents(evs)
		case <-timerC(l.debounce):
			l.debounce = nil
			l.flush()
		case <-timerC(l.pushTimer):
			l.pushTimer = nil
			l.publish(true)
		case <-tick.C:
			l.housekeep()
		}
	}
}

func timerC(t *time.Timer) <-chan time.Time {
	if t == nil {
		return nil
	}
	return t.C
}

// loop is Run's state: only its goroutine touches it.
type loop struct {
	s      *Service
	cur    Settings
	key    uint64
	active bool // on, with roots
	f      *filter
	phase  string
	w      *watcher
	child  *child
	// Work waiting for the child: folders to crawl, stat passes
	pendingStart  []string
	statAll       bool
	statUnwatched bool
	// watchLoaded: a loaded index's folders are watched once nothing is
	// left for the child (watchAll)
	watchLoaded bool
	// Watched folders to read again, files written
	changed    map[string]bool
	written    map[string]bool
	debounce   *time.Timer
	firstEvent time.Time
	loadTimer  *time.Timer
	lastStat   time.Time
	lastSave   time.Time
	// dirty: entries were added or removed since the cache was written
	// (a time alone doesn't count: a loaded cache's stat pass reads a
	// folder whose time differs again anyway)
	dirty      bool
	truncated  bool
	unreadable int
	errText    string
	pushTimer  *time.Timer
	lastPush   time.Time
	pushed     State // the state last pushed
	wg         sync.WaitGroup
}

func (l *loop) shutdown() {
	l.stopChild()
	// A stopped stat pass leaves the index whole (each folder it read is
	// in); a stopped crawl leaves the phase Crawling, and nothing saved
	l.save()
	if l.w != nil {
		l.w.close()
		l.w = nil
	}
	l.wg.Wait()
}

func (l *loop) ix() *filesearch.Index { return l.s.ix }

// setIndex swaps the index, dropping the use bonus resolved for the old
// one (which would keep it, tens of MB, alive: off, compacted, rebuilt).
func (l *loop) setIndex(ix *filesearch.Index) {
	l.s.mu.Lock()
	l.s.ix = ix
	l.s.mu.Unlock()
	l.s.bonusMu.Lock()
	l.s.bonus = bonusCache{}
	l.s.bonusMu.Unlock()
}

// configure applies the settings: a change of what's indexed drops the
// index (and its cache) and waits for the next search to build it again;
// off drops everything.
func (l *loop) configure(st Settings) {
	st.Roots = cleanRoots(st.Roots)
	key := settingsKey(st, l.s.o.MaxEntries)
	active := st.Enabled && len(st.Roots) > 0
	started := l.phase != ""
	if started && active == l.active && (!active || key == l.key) {
		return
	}
	l.reset()
	l.cur, l.key, l.active = st, key, active
	if !active {
		// Off: the index goes, its cache with it (also one an earlier
		// run left)
		l.phase = PhaseOff
		os.Remove(l.s.o.CacheFile)
		l.publish(true)
		return
	}
	l.f = newFilter(st.Roots, st.Excludes, l.s.o.Skip, st.Hidden)
	l.phase = PhaseWaiting
	if started {
		// Other roots or excludes: the cache is another index's
		os.Remove(l.s.o.CacheFile)
	} else if _, err := os.Stat(l.s.o.CacheFile); err == nil {
		l.loadTimer = time.NewTimer(l.s.o.LoadDelay)
	}
	l.publish(true)
}

// reset drops the index and everything following it.
func (l *loop) reset() {
	l.stopChild()
	if l.w != nil {
		l.w.close()
		l.w = nil
	}
	for _, t := range []**time.Timer{&l.loadTimer, &l.debounce} {
		if *t != nil {
			(*t).Stop()
			*t = nil
		}
	}
	l.setIndex(nil)
	l.pendingStart, l.statAll, l.statUnwatched, l.watchLoaded = nil, false, false, false
	clear(l.changed)
	clear(l.written)
	l.dirty, l.truncated, l.unreadable, l.errText = false, false, 0, ""
	l.lastSave, l.lastStat = time.Time{}, time.Time{}
}

// demand: a search came; a waiting index loads its cache or is built.
func (l *loop) demand() {
	if l.phase != PhaseWaiting {
		return
	}
	if l.loadTimer != nil {
		l.loadTimer.Stop()
		l.loadTimer = nil
	}
	if _, err := os.Stat(l.s.o.CacheFile); err == nil {
		l.load()
		return
	}
	l.build()
}

// freshen: a search after a quiet spell checks the unwatched folders.
func (l *loop) freshen() {
	if l.phase != PhaseReady || l.s.o.Now().Sub(l.lastStat) < l.s.o.QuietSpell {
		return
	}
	l.statUnwatched = true
	l.next()
}

// newWatcher starts watching (none when inotify is unavailable or the
// budget is none: every folder is then the stat pass's).
func (l *loop) newWatcher() {
	if l.s.o.WatchBudget < 0 {
		return
	}
	w, err := newWatcher(l.s.o.WatchBudget)
	if err != nil {
		l.s.o.Log.Warn("file search: inotify is unavailable: changes are found by the stat pass", "err", err)
		return
	}
	l.w = w
	l.wg.Go(w.read)
}

// build crawls the roots into a new index.
func (l *loop) build() {
	ix := filesearch.New()
	// Every root, one missing too: the stat pass reads it once it's there
	for _, r := range l.cur.Roots {
		ix.AddRoot(r)
	}
	l.setIndex(ix)
	l.newWatcher()
	l.phase = PhaseCrawling
	l.truncated, l.unreadable = false, 0
	l.pendingStart = slices.Clone(l.cur.Roots)
	l.publish(true)
	l.next()
}

// load reads the cache; a cache that won't do is removed and the index
// built. A loaded index is watched and checked by a stat pass over every
// folder (they may have changed while nothing watched).
func (l *loop) load() {
	if l.phase != PhaseWaiting {
		return
	}
	l.phase = PhaseLoading
	l.publish(true)
	data, err := os.ReadFile(l.s.o.CacheFile)
	var ix *filesearch.Index
	if err == nil {
		ix, err = filesearch.Decode(data, l.key)
	}
	data = nil
	if err != nil {
		l.s.o.Log.Info("file search: building the index again", "reason", err)
		os.Remove(l.s.o.CacheFile)
		l.phase = PhaseWaiting
		l.build()
		return
	}
	l.setIndex(ix)
	l.newWatcher()
	l.lastSave = l.s.o.Now()
	l.phase = PhaseReady
	l.s.o.Log.Info("file search: loaded the index", "entries", ix.Len())
	l.statAll = true
	l.watchLoaded = true
	l.publish(true)
	l.next()
}

// watchAll watches a loaded index's folders, within the budget, once the
// stat pass has run: adding a watch looks its path up, which on a cold
// cache (a login) reads the disk, and the idle child's pass has read
// those folders by then. A folder that changed since the index's time
// for it is read again (the watch came after the change). Folders never
// read (left out at the cap) aren't watched, as a crawl leaves them.
func (l *loop) watchAll() {
	ix := l.ix()
	if l.w == nil || ix == nil {
		return
	}
	type dir struct {
		d    uint32
		path string
	}
	var watched []dir
	ix.EachDir(func(d uint32) {
		mtime := ix.Mtime(d)
		if ix.Watched(d) || mtime == 0 || len(l.w.byPath) >= l.w.budget {
			return
		}
		path := ix.Path(d)
		if !l.watch(path) {
			return
		}
		watched = append(watched, dir{d, path})
		if st, err := os.Lstat(path); err == nil && st.ModTime().UnixNano() != mtime {
			l.changedDir(path)
		}
	})
	l.s.mu.Lock()
	for _, w := range watched {
		// Unless a later one took its watch (a root linked into another)
		if _, ok := l.w.byPath[w.path]; ok {
			ix.SetWatched(w.d, true)
		}
	}
	l.s.mu.Unlock()
	l.publish(false)
}

// next starts the child's next job when none runs: folders to crawl,
// then a stat pass; with nothing to do, saves the cache when due.
func (l *loop) next() {
	if l.child != nil || !l.active || l.ix() == nil {
		return
	}
	ix := l.ix()
	req := CrawlRequest{Roots: l.cur.Roots, Excludes: l.cur.Excludes, Skip: l.s.o.Skip, Hidden: l.cur.Hidden,
		Max: max(1, l.s.o.MaxEntries-ix.Len()), Pause: int(l.s.o.Pause / time.Millisecond)}
	if len(l.pendingStart) > 0 && ix.Len() >= l.s.o.MaxEntries {
		l.pendingStart = nil
		l.truncated = true
		// Nothing left to crawl: built (saved below as a crawl's end is)
		if l.phase == PhaseCrawling {
			l.phase = PhaseReady
			l.publish(true)
		}
	}
	switch {
	case len(l.pendingStart) > 0:
		req.Start, l.pendingStart = l.pendingStart, nil
		l.startChild(req)
	case l.statAll || l.statUnwatched:
		all := l.statAll
		l.statAll, l.statUnwatched = false, false
		ix.EachDir(func(d uint32) {
			if all || !ix.Watched(d) {
				req.Stat = append(req.Stat, StatDir{Path: ix.Path(d), Mtime: ix.Mtime(d)})
			}
		})
		l.lastStat = l.s.o.Now()
		if len(req.Stat) > 0 {
			l.startChild(req)
		}
	default:
		if l.watchLoaded {
			l.watchLoaded = false
			l.watchAll()
		}
		l.maybeSave()
	}
}

// maybeSave writes the cache when its entries changed and the last write
// is SaveEvery old (a built index's first at once).
func (l *loop) maybeSave() {
	if !l.lastSave.IsZero() && l.s.o.Now().Sub(l.lastSave) < l.s.o.SaveEvery {
		return
	}
	l.save()
}

// save writes the cache when its entries changed and nothing crawls or
// runs a stat pass: streamed to the file under the read lock (searches
// go on; the loop, the only writer, is busy meanwhile: ~30 ms a million
// entries), never fsynced.
func (l *loop) save() {
	ix := l.ix()
	if !l.dirty || l.child != nil || ix == nil || l.phase != PhaseReady {
		return
	}
	if err := os.MkdirAll(filepath.Dir(l.s.o.CacheFile), 0o700); err != nil {
		l.s.o.Log.Warn("file search: the cache can't be written", "err", err)
		return
	}
	l.s.mu.RLock()
	err := writeCache(l.s.o.CacheFile, ix, l.key)
	l.s.mu.RUnlock()
	if err != nil {
		l.s.o.Log.Warn("file search: the cache can't be written", "err", err)
		return
	}
	l.dirty = false
	l.lastSave = l.s.o.Now()
}

// housekeep: compaction, the periodic stat pass, a due save.
func (l *loop) housekeep() {
	if !l.active || l.ix() == nil {
		return
	}
	l.compact()
	if l.phase == PhaseReady && l.s.o.Now().Sub(l.lastStat) >= l.s.o.StatEvery {
		l.statUnwatched = true
	}
	l.next()
}

// compact swaps in a compacted copy once removals pass a quarter: built
// without the lock (searches go on in the old one), swapped under it.
func (l *loop) compact() {
	if ix := l.ix(); ix != nil && ix.NeedsCompact() {
		l.setIndex(ix.Compact())
	}
}

// applyDir sets a folder's contents as read; with crawlNew (a stat pass
// or a watch, not the crawl that will read them), its new folders are
// queued for a crawl. The folder is watched within the budget; if it
// changed since it was read, it's read again.
func (l *loop) applyDir(path string, mtime int64, kids []filesearch.Child, crawlNew bool) {
	ix := l.ix()
	d, ok := ix.Lookup(path)
	if !ok {
		return
	}
	watch := l.w != nil && !ix.Watched(d) && l.watch(path)
	l.s.mu.Lock()
	ch := ix.ReplaceDir(d, path, mtime, kids, l.s.o.MaxEntries)
	if watch {
		ix.SetWatched(d, true)
	}
	l.s.mu.Unlock()
	for _, g := range ch.GoneWatched {
		if l.w != nil {
			l.w.remove(ix.Path(g))
		}
	}
	if crawlNew {
		for _, nd := range ch.NewDirs {
			l.pendingStart = append(l.pendingStart, ix.Path(nd))
		}
	}
	l.truncated = l.truncated || ch.Truncated
	if ch.Added > 0 || ch.Removed > 0 {
		l.dirty = true
	}
	if watch {
		// Changed between the read and the watch: the watch missed it
		if st, err := os.Lstat(path); err == nil && st.ModTime().UnixNano() != mtime {
			l.changedDir(path)
		}
	}
}

// watch adds a watch on path within the budget; the path it was watched
// under until now is no longer marked watched (left to the stat pass).
func (l *loop) watch(path string) bool {
	ok, stolen := l.w.add(path, slices.Contains(l.cur.Roots, path))
	if ix := l.ix(); stolen != "" && ix != nil {
		if d, found := ix.Lookup(stolen); found {
			l.s.mu.Lock()
			ix.SetWatched(d, false)
			l.s.mu.Unlock()
		}
	}
	return ok
}

// changedDir queues a folder to read again, debounced.
func (l *loop) changedDir(path string) {
	l.changed[path] = true
	l.arm()
}

func (l *loop) arm() {
	now := l.s.o.Now()
	if l.debounce == nil {
		l.firstEvent = now
		l.debounce = time.NewTimer(l.s.o.Debounce)
		return
	}
	// Events that never stop are read every ten debounces at least
	if now.Sub(l.firstEvent) < 10*l.s.o.Debounce {
		l.debounce.Reset(l.s.o.Debounce)
	}
}

// flush reads the changed folders again (in the daemon: one folder each,
// small) and updates the written files' times.
func (l *loop) flush() {
	ix := l.ix()
	if ix == nil || !l.active {
		clear(l.changed)
		clear(l.written)
		return
	}
	// Folders read again: their files' times are set
	reread := map[string]bool{}
	for len(l.changed) > 0 {
		paths := make([]string, 0, len(l.changed))
		for p := range l.changed {
			paths = append(paths, p)
		}
		clear(l.changed)
		slices.SortFunc(paths, func(a, b string) int { return len(a) - len(b) })
		for _, p := range paths {
			root := l.f.rootOf(p)
			if root == "" {
				continue
			}
			if _, ok := ix.Lookup(p); !ok {
				continue
			}
			fo, err := l.f.read(root, p)
			switch {
			case err == nil:
				l.applyDir(p, fo.mtime, fo.kids, true)
				reread[p] = true
			case p == root:
				l.applyDir(p, 0, nil, false)
			default:
				// Gone: its folder drops it
				l.changed[filepath.Dir(p)] = true
			}
		}
	}
	var written []string
	for p := range l.written {
		if !reread[filepath.Dir(p)] {
			written = append(written, p)
		}
	}
	for p, i := range ix.FindAll(written) {
		if ix.IsDir(i) {
			continue
		}
		if st, err := os.Lstat(p); err == nil {
			l.s.mu.Lock()
			ix.SetMtime(i, st.ModTime().UnixNano())
			l.s.mu.Unlock()
		}
	}
	clear(l.written)
	l.compact()
	l.publish(false)
	l.next()
}

func (l *loop) eventsC() <-chan []event {
	if l.w == nil {
		return nil
	}
	return l.w.events
}
