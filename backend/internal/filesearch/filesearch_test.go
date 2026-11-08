package filesearch

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"hash/crc32"
	"io"
	"math/rand/v2"
	"os"
	"path"
	"path/filepath"
	"runtime"
	"slices"
	"sort"
	"strings"
	"testing"
	"time"
)

// build is an index of one root holding paths (relative; a trailing "/"
// is an empty folder), every file's time at mtime.
func build(t testing.TB, root string, mtime int64, paths ...string) *Index {
	t.Helper()
	ix := New()
	r := ix.AddRoot(root)
	kids := map[string][]Child{}
	dirs := map[string]bool{"": true}
	for _, p := range paths {
		isDir := strings.HasSuffix(p, "/")
		p = strings.TrimSuffix(p, "/")
		segs := strings.Split(p, "/")
		for k := range segs {
			dir, name := strings.Join(segs[:k], "/"), segs[k]
			sub := strings.Join(segs[:k+1], "/")
			d := k < len(segs)-1 || isDir
			if d && dirs[sub] || !d && slices.ContainsFunc(kids[dir], func(c Child) bool { return string(c.Name) == name }) {
				continue
			}
			if d {
				dirs[sub] = true
			}
			kids[dir] = append(kids[dir], Child{Name: []byte(name), Dir: d, Mtime: mtime})
		}
	}
	// Breadth first: a folder's contents once it's in the index
	order := make([]string, 0, len(dirs))
	for d := range dirs {
		order = append(order, d)
	}
	sort.Slice(order, func(a, b int) bool {
		if ca, cb := strings.Count(order[a], "/"), strings.Count(order[b], "/"); order[a] == "" || order[b] == "" || ca != cb {
			return order[a] == "" || order[b] != "" && ca < cb
		}
		return order[a] < order[b]
	})
	for _, d := range order {
		full := root
		if d != "" {
			full = path.Join(root, d)
		}
		i, ok := ix.Lookup(full)
		if !ok {
			t.Fatalf("no folder %s", full)
		}
		if d == "" {
			i = r
		}
		ix.ReplaceDir(i, full, mtime, kids[d], 0)
	}
	return ix
}

func names(ix *Index, hits []Hit) []string {
	var out []string
	for _, h := range hits {
		out = append(out, ix.Path(h.Entry))
	}
	return out
}

func TestScore(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		text, q string
		want    int
	}{
		{"report", "report", 100},
		{"report.pdf", "report", 80},
		{"my-report.pdf", "report", 65},
		{"my report", "report", 65},
		{"myreport", "report", 50},
		{"rxexpxoxrxt", "report", 30 - 2*(11-6)},
		{"r", "re", 0},
		{"abc", "x", 0},
		{"rap", "rp", 28},
		{"", "a", 0},
		{"a", "", 0},
	} {
		if got := Score([]byte(c.text), []byte(c.q)); got != c.want {
			t.Errorf("Score(%q, %q) = %d, want %d", c.text, c.q, got, c.want)
		}
	}
}

func TestSearch(t *testing.T) {
	t.Parallel()
	now := time.Date(2026, 11, 8, 12, 0, 0, 0, time.UTC).UnixNano()
	old := now - 400*24*3600*1e9
	ix := build(t, "/home/u", old,
		"Documents/report.pdf",
		"Documents/Reports/q3.ods",
		"Documents/notes/todo.txt",
		"Downloads/report-final.pdf",
		"code/axiom/README.md",
		"code/axiom/backend/main.go",
		".config/app/report.conf",
		"Music/Report Song.mp3",
		"Trips/İstanbul.jpg",
		"empty/",
	)
	for _, c := range []struct {
		name   string
		q      string
		under  string
		hidden bool
		want   []string // in order (a prefix of the hits)
		not    []string
	}{
		{name: "exact and prefix", q: "report", want: []string{"/home/u/Documents/Reports", "/home/u/Documents/report.pdf"},
			not: []string{"/home/u/.config/app/report.conf"}},
		{name: "hidden on asks", q: "report.conf", hidden: true, want: []string{"/home/u/.config/app/report.conf"}},
		{name: "smart case", q: "Report", want: []string{"/home/u/Documents/Reports", "/home/u/Music/Report Song.mp3"},
			not: []string{"/home/u/Documents/report.pdf"}},
		{name: "segments", q: "doc/rep", want: []string{"/home/u/Documents/Reports", "/home/u/Documents/report.pdf"},
			not: []string{"/home/u/Downloads/report-final.pdf"}},
		{name: "folder only", q: "notes/", want: []string{"/home/u/Documents/notes/todo.txt"}},
		{name: "every token", q: "axiom main", want: []string{"/home/u/code/axiom/backend/main.go"},
			not: []string{"/home/u/code/axiom/README.md"}},
		{name: "under a folder", q: "report", under: "/home/u/Downloads", want: []string{"/home/u/Downloads/report-final.pdf"},
			not: []string{"/home/u/Documents/report.pdf"}},
		{name: "under a hidden folder shows hidden", q: "report", under: "/home/u/.config", want: []string{"/home/u/.config/app/report.conf"}},
		{name: "a letter lowered into ASCII", q: "istanbul", want: []string{"/home/u/Trips/İstanbul.jpg"}},
		{name: "no match", q: "zzzz"},
	} {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			under := NoEntry
			if c.under != "" {
				var ok bool
				if under, ok = ix.Lookup(c.under); !ok {
					t.Fatalf("no %s", c.under)
				}
			}
			hits, stale := ix.Search(Query{Pattern: ParsePattern(c.q), Under: under, Hidden: c.hidden, Limit: 20, Now: now, Shards: 3})
			if stale {
				t.Fatal("stale")
			}
			got := names(ix, hits)
			if len(got) < len(c.want) || !slices.Equal(got[:len(c.want)], c.want) {
				t.Errorf("%q: got %q, want first %q", c.q, got, c.want)
			}
			for _, n := range c.not {
				if slices.Contains(got, n) {
					t.Errorf("%q: got %s", c.q, n)
				}
			}
			if c.want == nil && len(got) > 0 {
				t.Errorf("%q: got %q", c.q, got)
			}
		})
	}
}

// Recency and use lift an entry over an equal match
func TestRankRecencyAndUse(t *testing.T) {
	t.Parallel()
	now := time.Now().UnixNano()
	ix := build(t, "/r", now-400*24*3600*1e9, "a/notes.txt", "b/notes.txt")
	b, _ := ix.Find("/r/b/notes.txt")
	a, _ := ix.Find("/r/a/notes.txt")
	q := Query{Pattern: ParsePattern("notes"), Under: NoEntry, Limit: 5, Now: now}
	hits, _ := ix.Search(q)
	if hits[0].Entry != a {
		t.Fatalf("tie: got %q", names(ix, hits))
	}
	q.Bonus = map[uint32]float64{b: UseBonus(Frecency(Use{Count: 3, Last: now / 1e6}, now/1e6))}
	if hits, _ = ix.Search(q); hits[0].Entry != b {
		t.Errorf("used: got %q", names(ix, hits))
	}
	ix.ReplaceDir(ix.Parent(a), "/r/a", now, []Child{{Name: []byte("notes.txt"), Mtime: now}}, 0)
	q.Bonus = nil
	if hits, _ = ix.Search(q); hits[0].Entry != a {
		t.Errorf("recent: got %q", names(ix, hits))
	}
}

func TestStaleStops(t *testing.T) {
	t.Parallel()
	var paths []string
	for i := range 40000 {
		paths = append(paths, fmt.Sprintf("d%d/file%d.txt", i%100, i))
	}
	ix := build(t, "/r", 0, paths...)
	calls := 0
	_, stale := ix.Search(Query{Pattern: ParsePattern("file"), Under: NoEntry, Limit: 10, Stale: func() bool { calls++; return true }})
	if !stale || calls == 0 {
		t.Errorf("stale %v after %d checks", stale, calls)
	}
}

func TestPatternKeepsEightTokens(t *testing.T) {
	t.Parallel()
	p := ParsePattern(strings.Repeat("word ", 300))
	if len(p.tokens) != maxTokens {
		t.Errorf("%d tokens from 300 words, want %d", len(p.tokens), maxTokens)
	}
}

func TestReplaceDir(t *testing.T) {
	t.Parallel()
	ix := build(t, "/r", 1e9, "a/x.txt", "a/sub/deep.txt", "b.txt")
	a, _ := ix.Lookup("/r/a")
	sub, _ := ix.Lookup("/r/a/sub")
	ix.SetWatched(sub, true)
	before := ix.Len()
	// sub goes, y.txt comes, x.txt changes time
	ch := ix.ReplaceDir(a, "/r/a", 5e9, []Child{{Name: []byte("x.txt"), Mtime: 7e9}, {Name: []byte("y.txt"), Mtime: 7e9}, {Name: []byte("new"), Dir: true}}, 0)
	if ch.Removed != 2 || ch.Added != 2 || len(ch.NewDirs) != 1 || !slices.Equal(ch.GoneWatched, []uint32{sub}) {
		t.Errorf("change %+v", ch)
	}
	if ix.Len() != before {
		t.Errorf("len %d, want %d", ix.Len(), before)
	}
	if _, ok := ix.Lookup("/r/a/sub"); ok {
		t.Error("removed folder still looked up")
	}
	if _, ok := ix.Find("/r/a/sub/deep.txt"); ok {
		t.Error("removed file still found")
	}
	x, _ := ix.Find("/r/a/x.txt")
	if ix.Mtime(x) != 7e9 || ix.Mtime(a) != 5e9 {
		t.Errorf("times %d %d", ix.Mtime(x), ix.Mtime(a))
	}
	n, _ := ix.Lookup("/r/a/new")
	if ix.Mtime(n) != 0 {
		t.Error("a new folder has a time before it's read")
	}
	// A file turned folder is replaced
	r := ix.Roots()[0]
	ch = ix.ReplaceDir(r, "/r", 1e9, []Child{{Name: []byte("a"), Dir: true}, {Name: []byte("b.txt"), Dir: true}}, 0)
	if ch.Removed != 1 || ch.Added != 1 {
		t.Errorf("file to folder: %+v", ch)
	}
	if _, ok := ix.Lookup("/r/b.txt"); !ok {
		t.Error("b.txt isn't a folder")
	}
	// The cap
	ch = ix.ReplaceDir(n, "/r/a/new", 1e9, []Child{{Name: []byte("1")}, {Name: []byte("2")}, {Name: []byte("3")}}, ix.Len()+1)
	if !ch.Truncated || ch.Added != 1 {
		t.Errorf("cap: %+v", ch)
	}
}

func TestCompact(t *testing.T) {
	t.Parallel()
	var paths []string
	for i := range 3000 {
		paths = append(paths, fmt.Sprintf("d%d/f%d", i%30, i))
	}
	ix := build(t, "/r", 1e9, paths...)
	r := ix.Roots()[0]
	var keep []Child
	for i := range 10 {
		keep = append(keep, Child{Name: fmt.Appendf(nil, "d%d", i), Dir: true})
	}
	ix.ReplaceDir(r, "/r", 1e9, keep, 0)
	if !ix.NeedsCompact() {
		t.Fatalf("%d removed of %d: no compaction", ix.removed, ix.n)
	}
	// The root and the ten folders kept
	if ix.Folders() != 1+10 {
		t.Errorf("%d folders after removing 20, want 11", ix.Folders())
	}
	c := ix.Compact()
	if c.Len() != ix.Len() || c.removed != 0 || c.Len() != 1+10+1000 || c.Folders() != ix.Folders() {
		t.Errorf("compacted %d (removed %d, %d folders), was %d live (%d folders)", c.Len(), c.removed, c.Folders(), ix.Len(), ix.Folders())
	}
	if i, ok := c.Find("/r/d3/f33"); !ok || c.Path(i) != "/r/d3/f33" {
		t.Error("lost /r/d3/f33")
	}
	if _, ok := c.Find("/r/d13/f13"); ok {
		t.Error("kept a removed file")
	}
	hits, _ := c.Search(Query{Pattern: ParsePattern("f33"), Under: NoEntry, Limit: 1})
	if len(hits) != 1 || c.Path(hits[0].Entry) != "/r/d3/f33" {
		t.Errorf("search after compaction: %q", names(c, hits))
	}
}

func encode(t testing.TB, ix *Index, key uint64) []byte {
	t.Helper()
	var b bytes.Buffer
	if err := ix.Encode(&b, key); err != nil {
		t.Fatal(err)
	}
	return b.Bytes()
}

func TestSnapshot(t *testing.T) {
	t.Parallel()
	ix := build(t, "/home/u", 3e9, "a/b/c.txt", ".hidden/x", "a/link", "e/")
	r2 := ix.AddRoot("/")
	ix.ReplaceDir(r2, "/", 2e9, []Child{{Name: []byte("etc"), Dir: true}}, 0)
	// A removed folder, its entries left until compaction
	if d, ok := ix.Lookup("/home/u/a"); ok {
		ix.ReplaceDir(d, "/home/u/a", 3e9, []Child{{Name: []byte("link")}}, 0)
	}
	data := encode(t, ix, 42)
	got, err := Decode(data, 42)
	if err != nil {
		t.Fatal(err)
	}
	if got.Len() != ix.Len() {
		t.Errorf("len %d, want %d", got.Len(), ix.Len())
	}
	if _, ok := got.Find("/home/u/a/b/c.txt"); ok {
		t.Error("kept a removed file")
	}
	for _, p := range []string{"/home/u/a/link", "/home/u/.hidden/x", "/home/u/e", "/etc"} {
		i, ok := got.Find(p)
		j, _ := ix.Find(p)
		if !ok || got.Mtime(i) != ix.Mtime(j) || got.IsDir(i) != ix.IsDir(j) {
			t.Errorf("%s: %v", p, ok)
		}
	}
	if i, _ := got.Find("/home/u/.hidden/x"); got.at(i).flags&flagHidden == 0 {
		t.Error("lost hidden")
	}
	if !bytes.Equal(encode(t, got, 42), data) {
		t.Error("a second round trip differs")
	}
	for _, c := range []struct {
		name string
		data []byte
		key  uint64
		want error
	}{
		{"other settings", data, 7, ErrOtherSettings},
		{"cut short", data[:len(data)-9], 42, ErrBadSnapshot},
		{"flipped", func() []byte { d := bytes.Clone(data); d[30] ^= 1; return d }(), 42, ErrBadSnapshot},
		{"empty", nil, 42, ErrBadSnapshot},
		{"another version", func() []byte {
			d := bytes.Clone(data[:len(data)-4])
			d[4] = 9
			return withCRC(d)
		}(), 42, ErrOldSnapshot},
	} {
		if _, err := Decode(c.data, c.key); !errors.Is(err, c.want) {
			t.Errorf("%s: %v, want %v", c.name, err, c.want)
		}
	}
}

func TestExcludes(t *testing.T) {
	t.Parallel()
	x := ParseExcludes([]string{".git", "*.pyc", ".local/share/Trash", "go/pkg", "", "[bad"})
	for rel, want := range map[string]bool{
		".git":               true,
		"code/axiom/.git":    true,
		"a/b.pyc":            true,
		"a/b.py":             false,
		".local/share/Trash": true,
		".local/share/other": false,
		"go/pkg":             true,
		"src/go/pkg":         true,
		"go/pkgx":            false,
		"[bad":               false,
	} {
		if got := x.Skip(rel); got != want {
			t.Errorf("Skip(%q) = %v", rel, got)
		}
	}
}

func TestURIs(t *testing.T) {
	t.Parallel()
	for path, uri := range map[string]string{
		"/home/u/a b.png":      "file:///home/u/a%20b.png",
		"/home/u/ünï.txt":      "file:///home/u/%C3%BCn%C3%AF.txt",
		"/x/(1)+[2]#%.jpg":     "file:///x/(1)+%5B2%5D%23%25.jpg",
		"/home/u/it's~fine@!,": "file:///home/u/it's~fine@!,",
		// As GLib.filename_to_uri has it: ; escaped, the rest kept
		"/t/a;b=$&*:.png": "file:///t/a%3Bb=$&*:.png",
	} {
		if got := FileURI(path); got != uri {
			t.Errorf("FileURI(%q) = %q, want %q", path, got, uri)
		}
		if got := PathOfURI(uri); got != path {
			t.Errorf("PathOfURI(%q) = %q", uri, got)
		}
	}
	for _, uri := range []string{"https://x/y", "file://otherhost/x", "file:relative"} {
		if got := PathOfURI(uri); got != "" {
			t.Errorf("PathOfURI(%q) = %q", uri, got)
		}
	}
	if got := PathOfURI("file://localhost/a"); got != "/a" {
		t.Errorf("localhost: %q", got)
	}
}

func TestXBEL(t *testing.T) {
	t.Parallel()
	data := []byte(`<?xml version="1.0" encoding="UTF-8"?>
<xbel version="1.0" xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks" xmlns:mime="http://www.freedesktop.org/standards/shared-mime-info">
  <bookmark href="file:///home/u/a%20b.txt" added="2026-01-01T10:00:00.123456Z" modified="2026-01-02T10:00:00Z" visited="2026-01-01T11:00:00Z">
    <info><metadata owner="http://freedesktop.org"><mime:mime-type type="text/plain"/></metadata></info>
  </bookmark>
  <bookmark href="https://example.com/x" added="2026-01-01T10:00:00Z"/>
  <bookmark href="file:///home/u/c.png" added="bad"/>
</xbel>`)
	got := ParseXBEL(data)
	want := []Recent{
		{Path: "/home/u/a b.txt", Time: time.Date(2026, 1, 2, 10, 0, 0, 0, time.UTC).UnixMilli(), Mime: "text/plain"},
		{Path: "/home/u/c.png"},
	}
	if !slices.Equal(got, want) {
		t.Errorf("got %+v", got)
	}
	if ParseXBEL([]byte("<xbel><bookmark")) != nil {
		t.Error("a broken file gave entries")
	}
}

func TestFrecency(t *testing.T) {
	t.Parallel()
	const day = 86400000
	for _, c := range []struct {
		use  Use
		age  int64
		want float64
	}{
		{Use{Count: 2}, 0, 2},
		{Use{Count: 2}, 3 * day, 1.4},
		{Use{Count: 2}, 10 * day, 1},
		{Use{Count: 2}, 40 * day, 0.5},
		{Use{}, 0, 0},
	} {
		got := Frecency(Use{Count: c.use.Count, Last: 1e12}, 1e12+c.age)
		if d := got - c.want; d > 1e-9 || d < -1e-9 {
			t.Errorf("%+v at %d: %v, want %v", c.use, c.age, got, c.want)
		}
	}
	if UseBonus(0) != 0 || UseBonus(1e6) != 25 || UseBonus(1) != 8 {
		t.Errorf("bonus %v %v %v", UseBonus(0), UseBonus(1e6), UseBonus(1))
	}
}

// withCRC is d with its CRC appended (a test's hand-made file).
func withCRC(d []byte) []byte {
	return binary.LittleEndian.AppendUint32(d, crc32.ChecksumIEEE(d))
}

// synthetic is an index of about n entries: folders of 2-12 levels with
// 10-30 files each, named from a vocabulary like a home folder's.
func synthetic(tb testing.TB, n int) *Index {
	tb.Helper()
	rng := rand.New(rand.NewPCG(1, 2))
	words := []string{"report", "notes", "photo", "img", "draft", "final", "backup", "invoice", "project", "src",
		"main", "test", "data", "config", "readme", "music", "video", "doc", "page", "build", "cache", "lib", "util", "index"}
	exts := []string{".txt", ".pdf", ".png", ".jpg", ".go", ".md", ".json", ".mp3", ".odt", ".py", ".rs", ""}
	word := func() string {
		w := words[rng.IntN(len(words))]
		if rng.IntN(2) == 0 {
			w += "_" + words[rng.IntN(len(words))]
		}
		if rng.IntN(3) == 0 {
			w += fmt.Sprint(rng.IntN(1000))
		}
		return w
	}
	ix := New()
	root := ix.AddRoot("/home/user")
	type dir struct {
		i     uint32
		path  string
		depth int
	}
	queue := []dir{{root, "/home/user", 0}}
	now := time.Now().UnixNano()
	for len(queue) > 0 && ix.Len() < n {
		d := queue[0]
		queue = queue[1:]
		var kids []Child
		seen := map[string]bool{}
		for range 10 + rng.IntN(20) {
			name := word() + exts[rng.IntN(len(exts))]
			if !seen[name] {
				seen[name] = true
				kids = append(kids, Child{Name: []byte(name), Mtime: now - rng.Int64N(400*24*3600*1e9)})
			}
		}
		if d.depth < 12 {
			for range 2 + rng.IntN(3) {
				name := word()
				if !seen[name] {
					seen[name] = true
					kids = append(kids, Child{Name: []byte(name), Dir: true})
				}
			}
		}
		ch := ix.ReplaceDir(d.i, d.path, now, kids, n)
		for _, nd := range ch.NewDirs {
			queue = append(queue, dir{nd, d.path + "/" + ix.Name(nd), d.depth + 1})
		}
	}
	return ix
}

// The search budget: p50 ≤ 10 ms and p95 ≤ 25 ms over a million entries
// (reported as p50-ms and p95-ms)
func BenchmarkSearch1M(b *testing.B) {
	ix := synthetic(b, 1_000_000)
	queries := []string{"rep", "report", "notes final", "doc/rep", "img2", "zzq", "Photo", "proj/src main", "re"}
	var times []time.Duration
	now := time.Now().UnixNano()
	runtime.GC()
	b.ResetTimer()
	for i := 0; b.Loop(); i++ {
		start := time.Now()
		ix.Search(Query{Pattern: ParsePattern(queries[i%len(queries)]), Under: NoEntry, Limit: 50, Now: now, Shards: runtime.GOMAXPROCS(0)})
		times = append(times, time.Since(start))
	}
	slices.Sort(times)
	if len(times) > 0 {
		b.ReportMetric(float64(times[len(times)/2].Microseconds())/1000, "p50-ms")
		b.ReportMetric(float64(times[len(times)*95/100].Microseconds())/1000, "p95-ms")
	}
	b.ReportMetric(float64(ix.Len()), "entries")
}

// The cache's write over a million entries: how long the daemon's loop is
// busy with it (to a file, as the daemon writes it; no fsync)
func BenchmarkEncode1M(b *testing.B) {
	ix := synthetic(b, 1_000_000)
	path := filepath.Join(b.TempDir(), "cache")
	var size int64
	b.ResetTimer()
	for b.Loop() {
		f, err := os.Create(path)
		if err != nil {
			b.Fatal(err)
		}
		if err := ix.Encode(f, 1); err != nil {
			b.Fatal(err)
		}
		size, _ = f.Seek(0, io.SeekCurrent)
		f.Close()
	}
	b.ReportMetric(float64(size)/1e6, "MB")
}
