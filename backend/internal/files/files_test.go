package files

import (
	"context"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

type fakeConn struct {
	mu      sync.Mutex
	changed []string
}

func (c *fakeConn) Notify(method string, params any) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.changed = append(c.changed, params.(Changed).Path)
	return nil
}

func (c *fakeConn) got() []string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return append([]string{}, c.changed...)
}

func newFiles(t *testing.T) *Files {
	ctx, cancel := context.WithCancel(context.Background())
	var wg sync.WaitGroup
	t.Cleanup(func() {
		cancel()
		wg.Wait()
	})
	return New(Options{Method: "file.changed", Context: ctx, Debounce: 10 * time.Millisecond, Go: func(fn func(context.Context)) {
		wg.Add(1)
		go func() {
			defer wg.Done()
			fn(ctx)
		}()
	}})
}

// waitFor polls until c has n changes.
func waitFor(t *testing.T, c *fakeConn, n int) []string {
	t.Helper()
	if !testkit.Eventually(func() bool { return len(c.got()) >= n }) {
		t.Fatalf("waited for %d changes, got %v", n, c.got())
	}
	return c.got()
}

// A write makes the folders it needs (0700), replaces the file whole and
// keeps an existing file's mode; a relative path is refused.
func TestWrite(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	f := New(Options{})
	path := filepath.Join(dir, "a", "b", "state.json")
	if err := f.Write(path, "one"); err != nil {
		t.Fatal(err)
	}
	if info, err := os.Stat(filepath.Dir(path)); err != nil || info.Mode().Perm() != 0o700 {
		t.Errorf("folder: %v, %v", info, err)
	}
	if err := os.Chmod(path, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := f.Write(path, "two"); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil || string(data) != "two" {
		t.Errorf("content %q, %v", data, err)
	}
	if info, _ := os.Stat(path); info.Mode().Perm() != 0o600 {
		t.Errorf("mode %v, want the file's own 0600", info.Mode())
	}
	for _, bad := range []string{"", "state.json", "a/state.json"} {
		if err := f.Write(bad, "x"); axerr.KindOf(err) != axerr.BadRequest {
			t.Errorf("Write(%q): %v, want bad_request", bad, err)
		}
		if err := f.Watch(&fakeConn{}, bad); axerr.KindOf(err) != axerr.BadRequest {
			t.Errorf("Watch(%q): %v, want bad_request", bad, err)
		}
	}
}

// A change made elsewhere is pushed to the connections watching the path,
// once its burst settles; this package's own write isn't; unwatched and
// forgotten connections hear nothing more.
func TestWatch(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	f := newFiles(t)
	path := filepath.Join(dir, "todo.json")
	// Pushes name the path as it was asked for
	asked := dir + "//todo.json"
	other := filepath.Join(dir, "other.json")
	a, b := &fakeConn{}, &fakeConn{}
	for _, c := range []*fakeConn{a, b} {
		if err := f.Watch(c, asked); err != nil {
			t.Fatal(err)
		}
	}
	if err := f.Write(path, "mine"); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(other, []byte("not watched"), 0o644); err != nil {
		t.Fatal(err)
	}
	time.Sleep(50 * time.Millisecond)
	if got := a.got(); len(got) != 0 {
		t.Fatalf("pushed %v for its own write and an unwatched file", got)
	}
	// An editor writing in place, in pieces: one push
	if err := os.WriteFile(path, []byte("the"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("theirs"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := waitFor(t, a, 1); len(got) != 1 || got[0] != asked {
		t.Errorf("a got %v", got)
	}
	waitFor(t, b, 1)

	f.Unwatch(a, asked)
	f.Forget(b)
	if err := os.WriteFile(path, []byte("again"), 0o644); err != nil {
		t.Fatal(err)
	}
	time.Sleep(50 * time.Millisecond)
	if len(a.got()) != 1 || len(b.got()) != 1 {
		t.Errorf("pushed after unwatch: %v, %v", a.got(), b.got())
	}
}

// A path whose folder doesn't exist yet is watched once a write makes it.
func TestWatchFolderMadeByWrite(t *testing.T) {
	t.Parallel()
	f := newFiles(t)
	path := filepath.Join(t.TempDir(), "new", "todo.json")
	c := &fakeConn{}
	if err := f.Watch(c, path); err != nil {
		t.Fatal(err)
	}
	if err := f.Write(path, "mine"); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("theirs"), 0o644); err != nil {
		t.Fatal(err)
	}
	waitFor(t, c, 1)
}
