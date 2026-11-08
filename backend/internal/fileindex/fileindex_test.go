package fileindex

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
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

// The stat pass reads a folder whose time changed, and says one is gone
func TestStatPass(t *testing.T) {
	t.Parallel()
	root := tree(t, "a/x", "b/y", "c/")
	st, _ := os.Lstat(filepath.Join(root, "b"))
	got, kinds := serve(t, CrawlRequest{Roots: []string{root}, Stat: []StatDir{
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
	root := tree(t, "a.txt", "b.txt", "c.txt")
	r := start(t, Options{WatchBudget: -1}, Settings{})
	xbel := `<xbel version="1.0"><bookmark href="file://` + root + `/a.txt" modified="2026-01-02T10:00:00Z"/>` +
		`<bookmark href="file://` + root + `/gone.txt" modified="2026-01-03T10:00:00Z"/></xbel>`
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
	root := tree(t, "Zeta.txt", "alpha.txt", "beta/", ".hid", "report.pdf")
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
	if len(res.Items) != 2 || res.Total != 5 || !res.Items[1].Dir || !res.Items[1].Link {
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
