package daemon

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"sync/atomic"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
	"github.com/axiom-shell/axiom/backend/internal/fileindex"
	"github.com/axiom-shell/axiom/backend/internal/filesearch"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"github.com/axiom-shell/axiom/backend/internal/thumbnail"
)

// The test binary is the daemon's children too (it runs /proc/self/exe):
// `<test binary> index-crawl` and `<test binary> thumbnail`
func TestMain(m *testing.M) {
	if len(os.Args) > 1 {
		var err error
		switch os.Args[1] {
		case fileindex.ChildCommand:
			err = fileindex.RunChild(context.Background(), os.Stdin, os.Stdout)
		case thumbnail.ChildCommand:
			err = thumbnail.RunChild(context.Background(), os.Stdin)
		default:
			os.Exit(m.Run())
		}
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
		}
		os.Exit(axerr.ExitCode(err))
	}
	os.Exit(m.Run())
}

// fileTree makes empty files under a new folder.
func fileTree(t *testing.T, paths ...string) string {
	t.Helper()
	root := t.TempDir()
	for _, p := range paths {
		full := filepath.Join(root, p)
		os.MkdirAll(filepath.Dir(full), 0o755)
		if err := os.WriteFile(full, nil, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

// shellConn says hello as the shell, its filesearch.state pushes counted.
func shellConn(t *testing.T, td *testDaemon, states *atomic.Int32) *rpc.Conn {
	t.Helper()
	reg := rpc.NewRegistry()
	rpc.Handle(reg, "filesearch.state", func(_ context.Context, _ *rpc.Conn, st fileindex.State) (struct{}, error) {
		if states != nil {
			states.Add(1)
		}
		return struct{}{}, nil
	})
	c, err := rpc.Dial(context.Background(), td.socket, reg, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { c.Close() })
	params := map[string]any{"protocol": buildinfo.Protocol(), "client": "shell", "pid": os.Getpid(), "subscribe": []string{"fileSearch"}}
	if err := c.Call(context.Background(), "daemon.hello", params, nil); err != nil {
		t.Fatal(err)
	}
	return c
}

func isUs(pid int) bool { return pid == os.Getpid() }

func TestFileSearchIsTheShellsAlone(t *testing.T) {
	t.Parallel()
	td := newTestDaemon(t)
	td.fileSearch = &fileindex.Settings{Enabled: true, Roots: []string{t.TempDir()}}
	td.start(t, isUs)
	c, err := td.connect(t, "cli", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	for method, params := range map[string]any{
		"filesearch.get":       map[string]any{},
		"filesearch.query":     map[string]any{"id": 1, "query": "x", "limit": 5},
		"filesearch.browse":    map[string]any{"path": "/", "limit": 5},
		"filesearch.recent":    map[string]any{"limit": 5},
		"filesearch.used":      map[string]any{"path": "/x"},
		"filesearch.thumbnail": map[string]any{"path": "/x.png", "size": "normal"},
		"filesearch.reveal":    map[string]any{"path": "/x"},
	} {
		if err := c.Call(context.Background(), method, params, nil); axerr.KindOf(err) != axerr.Refused {
			t.Errorf("%s from the CLI: %v", method, err)
		}
	}
}

func TestFileSearchQuery(t *testing.T) {
	t.Parallel()
	root := fileTree(t, "docs/report.pdf", "docs/notes.txt", "pics/cat.png")
	td := newTestDaemon(t)
	td.fileSearch = &fileindex.Settings{Enabled: true, Roots: []string{root}}
	td.start(t, isUs)
	var states atomic.Int32
	c := shellConn(t, td, &states)
	ctx := context.Background()
	var res fileQueryResult
	found := testkit.Eventually(func() bool {
		res = fileQueryResult{}
		c.Call(ctx, "filesearch.query", map[string]any{"id": 1, "query": "report", "limit": 5}, &res)
		return len(res.Items) > 0
	})
	if !found || res.Items[0].Path != root+"/docs/report.pdf" || res.ID != 1 || res.Stale || !res.Indexed {
		t.Fatalf("query: %+v", res)
	}
	var st fileindex.State
	if err := c.Call(ctx, "filesearch.get", struct{}{}, &st); err != nil || st.Entries != 6 {
		t.Errorf("state %+v %v", st, err)
	}
	if !testkit.Eventually(func() bool { return states.Load() > 0 }) {
		t.Error("no filesearch.state pushed")
	}
	// Newest wins: once id 10 ran, an older id answers stale
	if err := c.Call(ctx, "filesearch.query", map[string]any{"id": 10, "query": "notes", "limit": 5}, &res); err != nil || res.Stale || len(res.Items) != 1 {
		t.Fatalf("id 10: %+v %v", res, err)
	}
	if err := c.Call(ctx, "filesearch.query", map[string]any{"id": 9, "query": "notes", "limit": 5}, &res); err != nil || !res.Stale || len(res.Items) != 0 {
		t.Errorf("id 9 after 10: %+v %v", res, err)
	}
	// The rest of the surface
	var browse fileindex.BrowseResult
	if err := c.Call(ctx, "filesearch.browse", map[string]any{"path": root + "/docs", "limit": 10}, &browse); err != nil || len(browse.Items) != 2 {
		t.Errorf("browse %+v %v", browse, err)
	}
	if err := c.Call(ctx, "filesearch.used", map[string]any{"path": root + "/pics/cat.png"}, nil); err != nil {
		t.Fatal(err)
	}
	var recent struct {
		Items []fileindex.Item `json:"items"`
	}
	if err := c.Call(ctx, "filesearch.recent", map[string]any{"limit": 5}, &recent); err != nil || len(recent.Items) != 1 || recent.Items[0].Name != "cat.png" {
		t.Errorf("recent %+v %v", recent, err)
	}
	var thumb thumbnail.Result
	if err := c.Call(ctx, "filesearch.thumbnail", map[string]any{"path": root + "/pics/cat.png", "size": "normal"}, &thumb); err != nil || !thumb.Failed {
		t.Errorf("an empty png's thumbnail: %+v %v", thumb, err)
	}
}

// A query (and any other call) answers within its budget while a crawl
// of a large tree runs: the crawl is a child at idle priority, and the
// daemon only applies its folders
func TestFileSearchAnswersDuringACrawl(t *testing.T) {
	t.Parallel()
	var paths []string
	for d := range 2000 {
		for f := range 5 {
			paths = append(paths, fmt.Sprintf("d%02d/sub%d/file-%d-%d.txt", d%40, d, d, f))
		}
	}
	root := fileTree(t, paths...)
	td := newTestDaemon(t)
	td.fileSearch = &fileindex.Settings{Enabled: true, Roots: []string{root}}
	// Paced, so it's still crawling while the test asks
	td.fileSearchOptions = func(o *fileindex.Options) { o.Pause = 100 * time.Millisecond; o.WatchBudget = 100 }
	td.start(t, isUs)
	c := shellConn(t, td, nil)
	ctx := context.Background()
	budget := testkit.Bound(250 * time.Millisecond)
	crawling, worst := 0, time.Duration(0)
	deadline := time.Now().Add(testkit.Bound(20 * time.Second))
	for id := 1; time.Now().Before(deadline); id++ {
		start := time.Now()
		var res fileQueryResult
		if err := c.Call(ctx, "filesearch.query", map[string]any{"id": id, "query": "file-1999", "limit": 20}, &res); err != nil {
			t.Fatal(err)
		}
		var status json.RawMessage
		if err := c.Call(ctx, "daemon.status", struct{}{}, &status); err != nil {
			t.Fatal(err)
		}
		worst = max(worst, time.Since(start))
		var st fileindex.State
		c.Call(ctx, "filesearch.get", struct{}{}, &st)
		if st.Phase == fileindex.PhaseCrawling {
			crawling++
		} else if st.Phase == fileindex.PhaseReady {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	if crawling < 5 {
		t.Fatalf("asked only %d times while it crawled", crawling)
	}
	if worst > budget {
		t.Errorf("a query and a status took %v during the crawl, over %v", worst, budget)
	}
	t.Logf("%d asks while crawling, the slowest %v", crawling, worst)
}

func TestFileSearchReveal(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	ctx, cancel := context.WithTimeout(context.Background(), testkit.Bound(10*time.Second))
	defer cancel()
	fm, err := dbus.Dial(ctx, bus.Address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	defer fm.Close()
	shown := make(chan []string, 1)
	_, err = fm.Export("/org/freedesktop/FileManager1", dbus.Interface{Name: "org.freedesktop.FileManager1", Methods: map[string]dbus.Method{
		"ShowItems": {In: "ass", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			uris, _ := m.Body[0].([]string)
			shown <- uris
			return nil, nil
		}},
	}})
	if err != nil {
		t.Fatal(err)
	}
	td := newTestDaemon(t)
	td.env["DBUS_SESSION_BUS_ADDRESS"] = bus.Address
	// With no file manager answering, the folder opens with the default
	// one: `true`, harmless
	os.MkdirAll(filepath.Join(td.env["XDG_DATA_HOME"], "applications"), 0o755)
	os.WriteFile(filepath.Join(td.env["XDG_DATA_HOME"], "applications", "testfm.desktop"),
		[]byte("[Desktop Entry]\nType=Application\nName=Test FM\nExec=true %U\nMimeType=inode/directory;\n"), 0o644)
	os.MkdirAll(td.env["XDG_CONFIG_HOME"], 0o755)
	os.WriteFile(filepath.Join(td.env["XDG_CONFIG_HOME"], "mimeapps.list"), []byte("[Default Applications]\ninode/directory=testfm.desktop\n"), 0o644)
	td.start(t, isUs)
	c := shellConn(t, td, nil)
	file := fileTree(t, "a b/c.txt") + "/a b/c.txt"
	var res struct {
		Via string `json:"via"`
	}
	// No owner yet: the folder
	if err := c.Call(ctx, "filesearch.reveal", map[string]any{"path": file}, &res); err != nil || res.Via != "folder" {
		t.Fatalf("no file manager: %+v %v", res, err)
	}
	if _, err := fm.RequestName(ctx, "org.freedesktop.FileManager1", dbus.NameDoNotQueue); err != nil {
		t.Fatal(err)
	}
	if err := c.Call(ctx, "filesearch.reveal", map[string]any{"path": file}, &res); err != nil || res.Via != "showItems" {
		t.Fatalf("a file manager: %+v %v", res, err)
	}
	if uris := <-shown; !slices.Equal(uris, []string{filesearch.FileURI(file)}) {
		t.Errorf("showed %q", uris)
	}
}
