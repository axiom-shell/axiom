package fileindex

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/filesearch"
	"github.com/axiom-shell/axiom/backend/internal/procprio"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"golang.org/x/sys/unix"
)

// The test binary is its own crawl child: `<test binary> index-crawl`
func TestMain(m *testing.M) {
	if len(os.Args) > 1 && os.Args[1] == ChildCommand {
		if err := RunChild(context.Background(), os.Stdin, os.Stdout); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		os.Exit(0)
	}
	os.Exit(m.Run())
}

// tree makes files (a trailing "/" an empty folder) under a new folder.
func tree(t testing.TB, paths ...string) string {
	t.Helper()
	root := t.TempDir()
	for _, p := range paths {
		full := filepath.Join(root, p)
		if strings.HasSuffix(p, "/") {
			if err := os.MkdirAll(full, 0o755); err != nil {
				t.Fatal(err)
			}
			continue
		}
		os.MkdirAll(filepath.Dir(full), 0o755)
		if err := os.WriteFile(full, []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

// serve runs the child's side in this process (unlowered) and returns
// what it sent: each folder's names, and the other messages' kinds.
func serve(t *testing.T, req CrawlRequest) (map[string][]string, string) {
	t.Helper()
	data, _ := json.Marshal(req)
	var out bytes.Buffer
	if err := Serve(context.Background(), bytes.NewReader(data), &out); err != nil {
		t.Fatal(err)
	}
	dirs, kinds := map[string][]string{}, ""
	r := &frameReader{r: bufio.NewReader(&out)}
	for {
		kind, payload, err := r.next()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		m, ok := decodeMsg(kind, payload)
		if !ok {
			t.Fatalf("bad %c", kind)
		}
		kinds += string(kind)
		if kind == msgDir {
			var names []string
			for _, k := range m.kids {
				n := string(k.Name)
				if k.Dir {
					n += "/"
				} else if k.Link {
					n += "@"
				}
				names = append(names, n)
			}
			slices.Sort(names)
			dirs[m.path] = names
		}
	}
	return dirs, kinds
}

func TestCrawl(t *testing.T) {
	t.Parallel()
	outside := tree(t, "secret/key.txt")
	root := tree(t, "a/b/c.txt", "a/.hidden/x", ".dot", "node_modules/m.js", "keep/x.pyc", "keep/x.py", "e/")
	os.Symlink(outside, filepath.Join(root, "a", "escape"))
	os.Symlink(filepath.Join(root, "a", "b"), filepath.Join(root, "inner"))
	base := CrawlRequest{Roots: []string{root}, Start: []string{root}, Excludes: []string{"node_modules", "*.pyc"}}
	for _, c := range []struct {
		name  string
		req   func(CrawlRequest) CrawlRequest
		want  map[string][]string
		kinds string
	}{
		{"excludes, hidden and links", func(r CrawlRequest) CrawlRequest { return r }, map[string][]string{
			root:           {"a/", "e/", "inner@", "keep/"},
			root + "/a":    {"b/", "escape@"},
			root + "/a/b":  {"c.txt"},
			root + "/e":    nil,
			root + "/keep": {"x.py"},
		}, "DDDDDE"},
		{"hidden too", func(r CrawlRequest) CrawlRequest { r.Hidden = true; return r }, map[string][]string{
			root:                {".dot", "a/", "e/", "inner@", "keep/"},
			root + "/a":         {".hidden/", "b/", "escape@"},
			root + "/a/b":       {"c.txt"},
			root + "/a/.hidden": {"x"},
			root + "/e":         nil,
			root + "/keep":      {"x.py"},
		}, "DDDDDDE"},
		{"skipped", func(r CrawlRequest) CrawlRequest { r.Skip = []string{root + "/a"}; return r }, map[string][]string{
			root:           {"e/", "inner@", "keep/"},
			root + "/e":    nil,
			root + "/keep": {"x.py"},
		}, "DDDE"},
		{"the cap", func(r CrawlRequest) CrawlRequest { r.Max = 3; return r }, map[string][]string{
			root: {"a/", "e/", "inner@", "keep/"},
		}, "DTE"},
	} {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			got, kinds := serve(t, c.req(base))
			if len(got) != len(c.want) || kinds != c.kinds {
				t.Fatalf("got %v (%s), want %v (%s)", got, kinds, c.want, c.kinds)
			}
			for dir, names := range c.want {
				if !slices.Equal(got[dir], names) {
					t.Errorf("%s: %q, want %q", dir, got[dir], names)
				}
			}
		})
	}
}

// The stat pass reads a folder whose time changed, and says one is gone;
// the cap is a crawl's (an index at its cap still has its folders checked)
func TestStatPass(t *testing.T) {
	t.Parallel()
	root := tree(t, "a/x", "b/y", "c/")
	st, _ := os.Lstat(filepath.Join(root, "b"))
	got, kinds := serve(t, CrawlRequest{Roots: []string{root}, Max: 1, Stat: []StatDir{
		{Path: root + "/a", Mtime: 1},
		{Path: root + "/b", Mtime: st.ModTime().UnixNano()},
		{Path: root + "/gone", Mtime: 1},
	}})
	if kinds != "DGE" || !slices.Equal(got[root+"/a"], []string{"x"}) {
		t.Errorf("%v %s", got, kinds)
	}
}

// The crawl child runs every thread at SCHED_IDLE in the idle I/O class
func TestChildRunsIdle(t *testing.T) {
	t.Parallel()
	var paths []string
	for i := range 400 {
		paths = append(paths, fmt.Sprintf("d%d/f", i))
	}
	root := tree(t, paths...)
	req, _ := json.Marshal(CrawlRequest{Roots: []string{root}, Start: []string{root}, Pause: 60_000})
	cmd := exec.Command(os.Args[0], ChildCommand)
	cmd.Env = []string{"GOMAXPROCS=1", "GOGC=20"}
	cmd.Stdin = bytes.NewReader(req)
	stdout, _ := cmd.StdoutPipe()
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	defer cmd.Wait()
	defer cmd.Process.Kill()
	// Its first folder: it lowered itself before reading anything
	if _, _, err := (&frameReader{r: bufio.NewReader(stdout)}).next(); err != nil {
		t.Fatal(err)
	}
	tids, err := procprio.Threads(cmd.Process.Pid)
	if err != nil || len(tids) == 0 {
		t.Fatal(tids, err)
	}
	for _, tid := range tids {
		if p, err := procprio.Policy(cmd.Process.Pid, tid); err != nil || p != 5 {
			t.Errorf("thread %d: policy %d (%v), want SCHED_IDLE (5)", tid, p, err)
		}
		if class, _, err := procprio.IOPrio(tid); err != nil || class != procprio.ClassIdle {
			t.Errorf("thread %d: I/O class %d (%v), want idle", tid, class, err)
		}
	}
}

// running is a service on scratch folders, run until the test ends.
type running struct {
	*Service
	dir    string
	states chan State
}

func start(t *testing.T, o Options, st Settings) *running {
	t.Helper()
	dir := t.TempDir()
	r := &running{dir: dir, states: make(chan State, 1024)}
	o.Exe = os.Args[0]
	if o.CacheFile == "" {
		o.CacheFile = filepath.Join(dir, "cache", "fileindex.bin")
	}
	o.HistoryFile = filepath.Join(dir, "state", "launcher-files.json")
	o.XBEL = filepath.Join(dir, "recently-used.xbel")
	if o.Pause == 0 {
		o.Pause = -1
	}
	o.Debounce = 5 * time.Millisecond
	o.OnState = func(s State) {
		select {
		case r.states <- s:
		default:
		}
	}
	r.Service = New(o)
	r.Configure(st)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		r.Run(ctx)
		close(done)
	}()
	t.Cleanup(func() {
		cancel()
		select {
		case <-done:
		case <-time.After(testkit.Bound(10 * time.Second)):
			t.Error("the service didn't stop")
		}
	})
	return r
}

// finds: a query for text has path among its results, eventually
func (r *running) finds(t *testing.T, text, path string, want bool) {
	t.Helper()
	ok := testkit.Eventually(func() bool {
		res := r.Query(Query{Text: text, Limit: 50})
		has := slices.ContainsFunc(res.Items, func(it Item) bool { return it.Path == path })
		return has == want && r.State().Phase == PhaseReady
	})
	if !ok {
		t.Fatalf("%q: finding %s is not %v (state %+v, items %v)", text, path, want, r.State(), r.Query(Query{Text: text, Limit: 50}).Items)
	}
}

func TestBuildAndWatch(t *testing.T) {
	t.Parallel()
	root := tree(t, "docs/report.pdf", "docs/old/notes.txt", "music/")
	r := start(t, Options{WatchBudget: 100}, Settings{Enabled: true, Roots: []string{root}})
	r.finds(t, "report", root+"/docs/report.pdf", true)
	if st := r.State(); st.Entries != 6 || st.Watched != 4 || st.Unwatched != 0 {
		t.Errorf("state %+v", st)
	}
	// Made, removed, renamed, a folder moved in with files
	os.WriteFile(root+"/music/song.mp3", nil, 0o644)
	r.finds(t, "song", root+"/music/song.mp3", true)
	os.Remove(root + "/docs/report.pdf")
	r.finds(t, "report", root+"/docs/report.pdf", false)
	os.Rename(root+"/docs/old", root+"/music/older")
	r.finds(t, "notes", root+"/music/older/notes.txt", true)
	r.finds(t, "notes", root+"/docs/old/notes.txt", false)
	elsewhere := tree(t, "deep/inside/thing.txt")
	os.Rename(elsewhere+"/deep", root+"/deep")
	r.finds(t, "thing", root+"/deep/inside/thing.txt", true)
	// Its meta
	res := r.Query(Query{Text: "song.mp3", Limit: 1})
	if len(res.Items) != 1 || res.Items[0].Dir || res.Items[0].Mtime == 0 || !res.Indexed {
		t.Errorf("item %+v", res)
	}
	// Under a folder; under one it doesn't hold
	if res := r.Query(Query{Text: "thing", Dir: root + "/music", Limit: 5}); len(res.Items) != 0 || !res.Indexed {
		t.Errorf("under music: %+v", res)
	}
	if res := r.Query(Query{Text: "thing", Dir: "/nowhere", Limit: 5}); res.Indexed {
		t.Errorf("under an unknown folder: %+v", res)
	}
}

// Past the watch budget, the stat pass still finds a change
func TestBudgetLeavesFoldersToTheStatPass(t *testing.T) {
	t.Parallel()
	root := tree(t, "a/x", "b/y", "c/z", "d/w")
	r := start(t, Options{WatchBudget: 2, QuietSpell: time.Nanosecond}, Settings{Enabled: true, Roots: []string{root}})
	r.finds(t, "x", root+"/a/x", true)
	if st := r.State(); st.Watched != 2 || st.Unwatched != 3 {
		t.Fatalf("state %+v", st)
	}
	// Whichever folders went unwatched, every one changes
	for _, d := range []string{"a", "b", "c", "d"} {
		os.WriteFile(filepath.Join(root, d, "new-"+d), nil, 0o644)
	}
	for _, d := range []string{"a", "b", "c", "d"} {
		r.finds(t, "new-"+d, filepath.Join(root, d, "new-"+d), true)
	}
}

// A root missing when the index is built is read once it's there
func TestRootMadeLater(t *testing.T) {
	t.Parallel()
	root := tree(t, "a/x")
	later := filepath.Join(t.TempDir(), "later")
	r := start(t, Options{WatchBudget: 100, QuietSpell: time.Nanosecond}, Settings{Enabled: true, Roots: []string{root, later}})
	r.finds(t, "x", root+"/a/x", true)
	if err := os.MkdirAll(later+"/inside", 0o755); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(later+"/inside/thing.txt", nil, 0o644)
	r.finds(t, "thing", later+"/inside/thing.txt", true)
}

// A cache loads at the next start, and a stat pass catches what changed
// meanwhile; turning file search off removes it
func TestCache(t *testing.T) {
	t.Parallel()
	root := tree(t, "a/x.txt", "b/y.txt")
	cache := filepath.Join(t.TempDir(), "axiom", "fileindex.bin")
	st := Settings{Enabled: true, Roots: []string{root}}
	r := start(t, Options{CacheFile: cache, WatchBudget: 100}, st)
	r.finds(t, "x.txt", root+"/a/x.txt", true)
	if !testkit.Eventually(func() bool { _, err := os.Stat(cache); return err == nil }) {
		t.Fatal("no cache")
	}
	if info, _ := os.Stat(cache); info.Mode().Perm() != 0o600 {
		t.Errorf("cache mode %v", info.Mode())
	}
	if info, _ := os.Stat(filepath.Dir(cache)); info.Mode().Perm() != 0o700 {
		t.Errorf("cache folder mode %v", info.Mode())
	}
	// Changed while nothing ran (the second service has its own watches)
	os.WriteFile(root+"/b/z.txt", nil, 0o644)
	r2 := start(t, Options{CacheFile: cache, WatchBudget: 100, LoadDelay: time.Hour}, st)
	if !testkit.Eventually(func() bool { return r2.State().Phase == PhaseWaiting }) {
		t.Errorf("before a search: %+v", r2.State())
	}
	r2.finds(t, "z.txt", root+"/b/z.txt", true)
	// Its folders are watched once the stat pass ran
	if !testkit.Eventually(func() bool { return r2.State().Watched == 3 }) {
		t.Errorf("after the stat pass: %+v", r2.State())
	}
	os.WriteFile(root+"/a/w.txt", nil, 0o644)
	r2.finds(t, "w.txt", root+"/a/w.txt", true)
	r2.Configure(Settings{})
	if !testkit.Eventually(func() bool { _, err := os.Stat(cache); return os.IsNotExist(err) && r2.State().Phase == PhaseOff }) {
		t.Error("off kept the cache")
	}
	if res := r2.Query(Query{Text: "x", Limit: 5}); len(res.Items) != 0 {
		t.Errorf("off still answers %v", res.Items)
	}
}

func TestCapTruncates(t *testing.T) {
	t.Parallel()
	var paths []string
	for i := range 50 {
		paths = append(paths, fmt.Sprintf("f%02d", i))
	}
	root := tree(t, paths...)
	r := start(t, Options{MaxEntries: 20, WatchBudget: 10}, Settings{Enabled: true, Roots: []string{root}})
	r.Query(Query{Text: "f", Limit: 1})
	if !testkit.Eventually(func() bool { s := r.State(); return s.Phase == PhaseReady && s.Truncated && s.Entries <= 20 }) {
		t.Errorf("state %+v", r.State())
	}
}

func TestRecentAndUsed(t *testing.T) {
	t.Parallel()
	// caf\xe9.txt: a name that isn't UTF-8 is left out (JSON would carry
	// another path)
	root := tree(t, "a.txt", "b.txt", "c.txt", "caf\xe9.txt")
	r := start(t, Options{WatchBudget: -1}, Settings{})
	xbel := `<xbel version="1.0"><bookmark href="file://` + root + `/a.txt" modified="2026-01-02T10:00:00Z"/>` +
		`<bookmark href="file://` + root + `/gone.txt" modified="2026-01-03T10:00:00Z"/>` +
		`<bookmark href="file://` + root + `/caf%E9.txt" modified="2026-01-04T10:00:00Z"/></xbel>`
	os.WriteFile(r.o.XBEL, []byte(xbel), 0o644)
	if err := r.Used(root + "/b.txt"); err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, it := range r.Recent(10) {
		got = append(got, filepath.Base(it.Path))
	}
	if !slices.Equal(got, []string{"b.txt", "a.txt"}) {
		t.Errorf("recent %q", got)
	}
	if info, err := os.Stat(r.o.HistoryFile); err != nil || info.Mode().Perm() != 0o600 {
		t.Errorf("history %v %v", info, err)
	}
	if info, _ := os.Stat(filepath.Dir(r.o.HistoryFile)); info.Mode().Perm() != 0o700 {
		t.Errorf("history folder %v", info.Mode())
	}
}

func TestBrowse(t *testing.T) {
	t.Parallel()
	root := tree(t, "Zeta.txt", "alpha.txt", "beta/", ".hid", "report.pdf", "not-utf8-\xff")
	os.Symlink(root+"/beta", root+"/link")
	s := New(Options{})
	for _, c := range []struct {
		query  string
		hidden bool
		want   []string
	}{
		{"", false, []string{"beta", "link", "alpha.txt", "report.pdf", "Zeta.txt"}},
		{"", true, []string{"beta", "link", ".hid", "alpha.txt", "report.pdf", "Zeta.txt"}},
		{"rep", false, []string{"report.pdf"}},
		{".h", false, []string{".hid"}},
	} {
		res, err := s.Browse(root, c.query, 10, c.hidden)
		if err != nil {
			t.Fatal(err)
		}
		var got []string
		for _, it := range res.Items {
			got = append(got, it.Name)
		}
		if !slices.Equal(got, c.want) {
			t.Errorf("%q %v: %q", c.query, c.hidden, got)
		}
	}
	res, _ := s.Browse(root, "", 2, false)
	if len(res.Items) != 2 || res.Total != 5 || !res.Items[1].Dir || res.Items[1].Name != "link" {
		t.Errorf("limit: %+v", res)
	}
	if _, err := s.Browse("relative", "", 2, false); err == nil {
		t.Error("a relative path")
	}
}

// loopOn is a loop over root's index, read by hand, ready, its clock now
func loopOn(t *testing.T, root string, now *time.Time) *loop {
	t.Helper()
	o := Options{CacheFile: filepath.Join(t.TempDir(), "fileindex.bin"), Now: func() time.Time { return *now }}
	s := New(o)
	st := Settings{Enabled: true, Roots: []string{root}}
	l := &loop{s: s, changed: map[string]bool{}, written: map[string]bool{}, cur: st, active: true, phase: PhaseReady,
		f: newFilter(st.Roots, nil, nil, false)}
	ix := filesearch.New()
	ix.AddRoot(root)
	l.setIndex(ix)
	l.readDir(t, root)
	return l
}

// readDir reads a folder into the index as a watch would
func (l *loop) readDir(t *testing.T, path string) {
	t.Helper()
	fo, err := l.f.read(path, path)
	if err != nil {
		t.Fatal(err)
	}
	l.applyDir(path, fo.mtime, fo.kids, false)
}

func saved(l *loop) bool {
	_, err := os.Stat(l.s.o.CacheFile)
	return err == nil
}

// Only a change of the entries makes the cache dirty: a file's or a
// folder's time alone doesn't
func TestCacheDirtiesOnEntries(t *testing.T) {
	t.Parallel()
	root := tree(t, "a.txt")
	now := time.Now()
	l := loopOn(t, root, &now)
	if !l.dirty {
		t.Fatal("the first read isn't dirty")
	}
	l.dirty = false
	later := time.Now().Add(time.Hour)
	os.Chtimes(root+"/a.txt", later, later)
	os.Chtimes(root, later, later)
	l.readDir(t, root)
	l.written[root+"/a.txt"] = true
	l.flush()
	if l.dirty {
		t.Error("a time alone made it dirty")
	}
	os.WriteFile(root+"/b.txt", nil, 0o644)
	l.readDir(t, root)
	if !l.dirty {
		t.Error("an added file didn't make it dirty")
	}
}

// A dirty cache is written at most every SaveEvery, never while the child
// runs, and when Run ends
func TestCacheSaves(t *testing.T) {
	t.Parallel()
	root := tree(t, "a.txt")
	now := time.Now()
	l := loopOn(t, root, &now)
	l.lastSave = now
	l.maybeSave()
	now = now.Add(l.s.o.SaveEvery - time.Second)
	l.maybeSave()
	if saved(l) {
		t.Fatal("saved before the interval")
	}
	now = now.Add(time.Second)
	l.child = &child{}
	l.maybeSave()
	if saved(l) {
		t.Fatal("saved while the child ran")
	}
	l.child = nil
	l.maybeSave()
	if !saved(l) || l.dirty {
		t.Fatal("not saved at the interval")
	}
	// At the end of Run, before the interval
	os.Remove(l.s.o.CacheFile)
	os.WriteFile(root+"/b.txt", nil, 0o644)
	l.readDir(t, root)
	l.shutdown()
	data, err := os.ReadFile(l.s.o.CacheFile)
	if err != nil {
		t.Fatal("not saved at shutdown")
	}
	ix, err := filesearch.Decode(data, l.key)
	if err != nil || ix.Len() != 3 {
		t.Errorf("the saved cache: %v", err)
	}
	if info, _ := os.Stat(l.s.o.CacheFile); info.Mode().Perm() != 0o600 {
		t.Errorf("cache mode %v", info.Mode())
	}
}

// The cap reached with folders still queued (a watch's, during the
// build) ends the build: it's ready, so it saves and runs stat passes
func TestCapWithFoldersQueued(t *testing.T) {
	t.Parallel()
	root := tree(t, "a.txt", "b.txt", "sub/c.txt")
	now := time.Now()
	cache := filepath.Join(t.TempDir(), "c.bin")
	s := New(Options{CacheFile: cache, MaxEntries: 4, Now: func() time.Time { return now }})
	st := Settings{Enabled: true, Roots: []string{root}}
	l := &loop{s: s, changed: map[string]bool{}, written: map[string]bool{}, cur: st, active: true, phase: PhaseCrawling,
		f: newFilter(st.Roots, nil, nil, false)}
	ix := filesearch.New()
	ix.AddRoot(root)
	l.setIndex(ix)
	l.readDir(t, root)
	l.pendingStart = []string{root + "/sub"}
	l.child = &child{cmd: &exec.Cmd{}, msgs: make(chan childMsg), stop: make(chan struct{}), build: true}
	l.childMsg(childMsg{done: true})
	if l.phase != PhaseReady || !l.truncated || l.child != nil {
		t.Errorf("phase %s, truncated %v, a child %v", l.phase, l.truncated, l.child != nil)
	}
	// Saved at once, as a crawl that ends is
	if _, err := os.Stat(cache); err != nil {
		t.Errorf("no cache: %v", err)
	}
}

// Only a failed build is the state's error ("couldn't be built"): a
// failed stat pass over a built index is only logged
func TestOnlyABuildFailsTheState(t *testing.T) {
	t.Parallel()
	root := tree(t, "a.txt")
	now := time.Now()
	l := loopOn(t, root, &now)
	l.child = &child{cmd: &exec.Cmd{}, msgs: make(chan childMsg), stop: make(chan struct{}), stat: true}
	l.childMsg(childMsg{done: true, err: errors.New("killed")})
	if l.errText != "" {
		t.Errorf("a stat pass's error: %q", l.errText)
	}
	l.phase = PhaseCrawling
	l.child = &child{cmd: &exec.Cmd{}, msgs: make(chan childMsg), stop: make(chan struct{}), build: true}
	l.childMsg(childMsg{done: true, err: errors.New("killed")})
	if l.errText == "" {
		t.Error("a build's error is missing")
	}
}

// A change held for the push timer is pushed when it fires
func TestHeldStateIsPushed(t *testing.T) {
	t.Parallel()
	now := time.Now()
	var pushed []State
	s := New(Options{PushEvery: time.Hour, Now: func() time.Time { return now }, OnState: func(st State) { pushed = append(pushed, st) }})
	l := &loop{s: s, phase: PhaseReady}
	l.publish(true)
	l.unreadable = 5
	l.publish(false)
	if l.pushTimer == nil || len(pushed) != 1 {
		t.Fatalf("held: timer %v, pushes %d", l.pushTimer != nil, len(pushed))
	}
	l.pushTimer.Stop()
	l.pushTimer = nil
	l.publish(true) // the timer fired (Run)
	if len(pushed) != 2 || pushed[1].Unreadable != 5 {
		t.Errorf("pushes %+v", pushed)
	}
}

// A root linked into another reaches the same folders: the one whose
// watch the other took is left to the stat pass, and still follows
func TestLinkedRoots(t *testing.T) {
	t.Parallel()
	target := tree(t, "sub/a.txt")
	link := filepath.Join(t.TempDir(), "link")
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}
	r := start(t, Options{WatchBudget: 100, QuietSpell: time.Nanosecond}, Settings{Enabled: true, Roots: []string{target, link}})
	r.finds(t, "a.txt", target+"/sub/a.txt", true)
	r.finds(t, "a.txt", link+"/sub/a.txt", true)
	os.WriteFile(target+"/sub/b.txt", nil, 0o644)
	r.finds(t, "b.txt", target+"/sub/b.txt", true)
	r.finds(t, "b.txt", link+"/sub/b.txt", true)
}

// A root that is a link is watched (its folder); a link below one never is
func TestLinkedRootIsWatched(t *testing.T) {
	t.Parallel()
	target := tree(t, "sub/a.txt")
	link := filepath.Join(t.TempDir(), "docs")
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}
	w, err := newWatcher(8)
	if err != nil {
		t.Skip("no inotify:", err)
	}
	defer w.file.Close()
	if ok, _ := w.add(link, true); !ok {
		t.Error("the linked root isn't watched")
	}
	if ok, _ := w.add(filepath.Join(t.TempDir(), "x"), false); ok {
		t.Error("a missing folder is watched")
	}
	inner := filepath.Join(target, "in")
	if err := os.Symlink(filepath.Join(target, "sub"), inner); err != nil {
		t.Fatal(err)
	}
	if ok, _ := w.add(inner, false); ok {
		t.Error("a link below a root is watched")
	}
}

// A linked root leading elsewhere sends no event: housekeeping finds it,
// reads it again and watches where it leads
func TestLinkedRootRetargeted(t *testing.T) {
	t.Parallel()
	old, now := tree(t, "a.txt"), tree(t, "b.txt")
	link := filepath.Join(t.TempDir(), "docs")
	if err := os.Symlink(old, link); err != nil {
		t.Fatal(err)
	}
	clock := time.Now()
	l := loopOn(t, link, &clock)
	w, err := newWatcher(8)
	if err != nil {
		t.Skip("no inotify:", err)
	}
	defer w.file.Close()
	l.w = w
	l.changed[link] = true
	l.flush()
	if d, _ := l.ix().Lookup(link); !l.ix().Watched(d) {
		t.Fatal("the linked root isn't watched")
	}
	os.Remove(link)
	os.Symlink(now, link)
	l.housekeep()
	l.flush()
	found := l.ix().FindAll([]string{link + "/a.txt", link + "/b.txt"})
	if _, ok := found[link+"/b.txt"]; !ok || len(found) != 1 {
		t.Errorf("after the link moved: %v", found)
	}
	if d, _ := l.ix().Lookup(link); !l.ix().Watched(d) || l.w.byPath[link] == 0 {
		t.Error("not watched where it leads")
	}
}

// A disk mounted again at a root (another device number) is read, not
// emptied: needs mounts, so it runs under `unshare -rm go test` and
// skips elsewhere
func TestRootRemounted(t *testing.T) {
	root := filepath.Join(t.TempDir(), "disk")
	os.Mkdir(root, 0o755)
	mount := func(file string) {
		t.Helper()
		if err := unix.Mount("tmpfs", root, "tmpfs", 0, ""); err != nil {
			t.Skip("can't mount here:", err)
		}
		os.WriteFile(filepath.Join(root, file), nil, 0o644)
	}
	mount("a.txt")
	t.Cleanup(func() { unix.Unmount(root, unix.MNT_DETACH) })
	now := time.Now()
	l := loopOn(t, root, &now)
	// The old disk kept open: the new one gets another device number
	old, _ := os.Open(root)
	defer old.Close()
	unix.Unmount(root, unix.MNT_DETACH)
	mount("b.txt")
	l.changed[root] = true
	l.flush()
	ix := l.ix()
	if _, ok := ix.FindAll([]string{root + "/b.txt"})[root+"/b.txt"]; !ok {
		t.Errorf("the remounted root's files are missing: %d entries", ix.Len())
	}
}

// A folder below a root mounted again is read before the root: the device
// kept for the root is found stale, not the folder another disk's
func TestRootRemountedReadBelowFirst(t *testing.T) {
	t.Parallel()
	root := tree(t, "sub/a")
	f := newFilter([]string{root}, nil, nil, false)
	f.devs[root] = ^uint64(0)
	if fo, err := f.read(root, root+"/sub"); err != nil || len(fo.kids) != 1 {
		t.Errorf("read %v, %v", fo.kids, err)
	}
}

// Files left out at the cap come back once removals make room: a folder
// read when the index was full is read again, as is one never read
func TestLeftOutComeBack(t *testing.T) {
	t.Parallel()
	var paths []string
	for i := range 30 {
		paths = append(paths, fmt.Sprintf("a/fa%02d", i), fmt.Sprintf("b/fb%02d", i), fmt.Sprintf("c/fc%02d", i))
	}
	root := tree(t, paths...)
	r := start(t, Options{MaxEntries: 40, WatchBudget: 10}, Settings{Enabled: true, Roots: []string{root}})
	// The files indexed in folder dir
	count := func(dir string) int {
		n := 0
		for _, it := range r.Query(Query{Text: "f", Dir: root + "/" + dir, Limit: 100}).Items {
			if filepath.Dir(it.Path) == root+"/"+dir {
				n++
			}
		}
		return n
	}
	r.Query(Query{Text: "f", Limit: 1})
	// The folder read first whole, the next in part, the last never
	// read (in the order the disk lists them)
	if !testkit.Eventually(func() bool { s := r.State(); return s.Phase == PhaseReady && s.Truncated && s.Entries == 40 }) {
		t.Fatalf("state %+v", r.State())
	}
	var whole string
	rest := []string{}
	for _, d := range []string{"a", "b", "c"} {
		if count(d) == 30 {
			whole = d
		} else {
			rest = append(rest, d)
		}
	}
	if whole == "" || count(rest[0])+count(rest[1]) != 6 {
		t.Fatalf("a %d, b %d, c %d", count("a"), count("b"), count("c"))
	}
	// Its room goes to the other two, the index full again
	if err := os.RemoveAll(filepath.Join(root, whole)); err != nil {
		t.Fatal(err)
	}
	if !testkit.Eventually(func() bool {
		s := r.State()
		return s.Truncated && s.Entries == 40 && count(rest[0]) > 0 && count(rest[1]) > 0 && count(rest[0])+count(rest[1]) == 37
	}) {
		t.Fatalf("after %s: state %+v, %s %d, %s %d", whole, r.State(), rest[0], count(rest[0]), rest[1], count(rest[1]))
	}
	// Room for all of the last
	if err := os.RemoveAll(filepath.Join(root, rest[0])); err != nil {
		t.Fatal(err)
	}
	if !testkit.Eventually(func() bool { s := r.State(); return !s.Truncated && s.Entries == 32 && count(rest[1]) == 30 }) {
		t.Errorf("after %s: state %+v, %s %d", rest[0], r.State(), rest[1], count(rest[1]))
	}
}

func TestLeftOutNoExtraReads(t *testing.T) {
	t.Parallel()
	root := tree(t, "a/x1", "a/x2", "b/y1", "b/y2", "b/y3")
	now := time.Now()
	s := New(Options{CacheFile: filepath.Join(t.TempDir(), "c.bin"), MaxEntries: 6, Now: func() time.Time { return now }})
	st := Settings{Enabled: true, Roots: []string{root}}
	l := &loop{s: s, changed: map[string]bool{}, written: map[string]bool{}, cur: st, active: true, phase: PhaseReady,
		f: newFilter(st.Roots, nil, nil, false)}
	ix := filesearch.New()
	ix.AddRoot(root)
	l.setIndex(ix)
	for _, p := range []string{root, root + "/a", root + "/b"} {
		l.readDir(t, p)
	}
	b, _ := ix.Lookup(root + "/b")
	if !l.truncated || !ix.LeftOutDir(b) || ix.LeftOut() != 1 || ix.Len() != 6 {
		t.Fatalf("truncated %v, b left out %v, %d entries", l.truncated, ix.LeftOutDir(b), ix.Len())
	}
	// The mark is kept by the cache
	var buf bytes.Buffer
	if err := ix.Encode(&buf, 1); err != nil {
		t.Fatal(err)
	}
	if back, err := filesearch.Decode(buf.Bytes(), 1); err != nil || back.LeftOut() != 1 {
		t.Errorf("decoded: %v", err)
	}
	// A stat pass of the full index doesn't read b, nor asks a refill
	if dirs, _ := serve(t, CrawlRequest{Roots: st.Roots, Stat: []StatDir{{Path: root + "/b", Mtime: ix.Mtime(b)}}}); len(dirs) != 0 {
		t.Errorf("b read again: %v", dirs)
	}
	l.refill = true
	var req CrawlRequest
	if l.refillPass(&req) || len(req.Stat) > 0 || !l.truncated {
		t.Errorf("a full index refilled: %+v", req.Stat)
	}
	// Room made: b is asked for whatever its time, and read whole
	os.Remove(root + "/a/x1")
	os.Remove(root + "/a/x2")
	l.readDir(t, root+"/a")
	if !l.refill || !l.refillPass(&req) || !slices.Equal(req.Stat, []StatDir{{Path: root + "/b"}}) || l.truncated {
		t.Fatalf("refill %+v, truncated %v", req.Stat, l.truncated)
	}
	// A pass that didn't finish (its child failed) is asked again
	var again CrawlRequest
	if !l.refillPass(&again) || !slices.Equal(again.Stat, req.Stat) {
		t.Errorf("after a lost pass: %+v", again.Stat)
	}
	dirs, _ := serve(t, CrawlRequest{Roots: st.Roots, Stat: req.Stat})
	if len(dirs[root+"/b"]) != 3 {
		t.Fatalf("b read as %v", dirs)
	}
	fo, _ := l.f.read(root, root+"/b")
	l.applyDir(root+"/b", fo.mtime, fo.kids, true)
	if ix.LeftOutDir(b) || ix.LeftOut() != 0 || ix.Len() != 6 || l.truncated {
		t.Errorf("after the refill: left out %v, %d entries, truncated %v", ix.LeftOutDir(b), ix.Len(), l.truncated)
	}
	// A marked folder the child can't read is no longer asked for
	kids := append(fo.kids, filesearch.Child{Name: []byte("y4")})
	if ix.ReplaceDir(b, root+"/b", fo.mtime, kids, ix.Len()); ix.LeftOut() != 1 {
		t.Fatalf("b not marked: %d", ix.LeftOut())
	}
	// A refill pass's folders are passed over once the index is full
	l.child = &child{stat: true, refill: true}
	n := ix.Len()
	l.truncated = false
	l.childMsg(childMsg{kind: msgDir, path: root + "/a", kids: []filesearch.Child{{Name: []byte("new")}}})
	if ix.Len() != n || !l.truncated {
		t.Errorf("a full index replaced a refill's folder: %d entries, truncated %v", ix.Len(), l.truncated)
	}
	l.childMsg(childMsg{kind: msgGone, path: root + "/b"})
	l.child = nil
	if ix.LeftOut() != 0 {
		t.Errorf("an unreadable folder still marked: %d", ix.LeftOut())
	}
}

// Files removed one at a time from a full index don't each re-read every
// folder left out: a refill waits for room of a hundredth of the cap
func TestLeftOutRefillWaitsForRoom(t *testing.T) {
	t.Parallel()
	var paths []string
	for i := range 300 {
		paths = append(paths, fmt.Sprintf("a/f%03d", i))
	}
	for i := range 10 {
		paths = append(paths, fmt.Sprintf("z/f%d", i))
	}
	root := tree(t, paths...)
	now := time.Now()
	s := New(Options{CacheFile: filepath.Join(t.TempDir(), "c.bin"), MaxEntries: 300, Now: func() time.Time { return now }})
	st := Settings{Enabled: true, Roots: []string{root}}
	l := &loop{s: s, changed: map[string]bool{}, written: map[string]bool{}, cur: st, active: true, phase: PhaseReady,
		f: newFilter(st.Roots, nil, nil, false)}
	ix := filesearch.New()
	ix.AddRoot(root)
	l.setIndex(ix)
	l.readDir(t, root)
	l.readDir(t, root+"/z")
	l.readDir(t, root+"/a")
	if ix.Len() != 300 || ix.LeftOut() != 1 {
		t.Fatalf("%d entries, %d left out", ix.Len(), ix.LeftOut())
	}
	for i := range 4 {
		os.Remove(fmt.Sprintf("%s/z/f%d", root, i))
		l.readDir(t, root+"/z")
		var req CrawlRequest
		refilled := l.refillPass(&req)
		if want := i == 3; refilled != want {
			t.Errorf("%d removed: refilled %v, want %v", i+1, refilled, want)
		}
	}
}
