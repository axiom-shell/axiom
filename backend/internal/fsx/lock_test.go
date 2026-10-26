package fsx

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// A lock adopted across an exec (inherited without close-on-exec) gets
// close-on-exec back, so the children started after don't hold it.
func TestAdoptSetsCloseOnExec(t *testing.T) {
	t.Parallel()
	path := filepath.Join(t.TempDir(), "daemon.lock")
	l, err := TryLock(path)
	if err != nil {
		t.Fatal(err)
	}
	defer l.Release()
	fd := int(l.File().Fd())
	if _, err := unix.FcntlInt(uintptr(fd), unix.F_SETFD, 0); err != nil {
		t.Fatal(err)
	}
	adopted, err := Adopt(l.File(), path)
	if err != nil {
		t.Fatal(err)
	}
	flags, err := unix.FcntlInt(uintptr(int(adopted.File().Fd())), unix.F_GETFD, 0)
	if err != nil || flags&unix.FD_CLOEXEC == 0 {
		t.Errorf("flags %#x err %v: close-on-exec not set", flags, err)
	}
}

// Adopt trusts an inherited descriptor only when it is the lock file at
// path and holds its lock: a descriptor of another file (or of one that
// replaced it) or one that isn't the holder's is refused.
func TestAdoptRefusesAnotherLock(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name string
		// inherited is the descriptor handed over for the lock at path
		inherited func(t *testing.T, path string) *os.File
	}{
		{"another file", func(t *testing.T, path string) *os.File {
			other, err := TryLock(filepath.Join(filepath.Dir(path), "other.lock"))
			if err != nil {
				t.Fatal(err)
			}
			return other.File()
		}},
		{"the file it replaced", func(t *testing.T, path string) *os.File {
			old, err := os.Open(path)
			if err != nil {
				t.Fatal(err)
			}
			if err := os.Rename(filepath.Join(filepath.Dir(path), "new"), path); err != nil {
				t.Fatal(err)
			}
			return old
		}},
		{"not the holder", func(t *testing.T, path string) *os.File {
			f, err := os.Open(path)
			if err != nil {
				t.Fatal(err)
			}
			return f
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			dir := t.TempDir()
			path := filepath.Join(dir, "daemon.lock")
			if err := os.WriteFile(filepath.Join(dir, "new"), nil, 0o600); err != nil {
				t.Fatal(err)
			}
			held, err := TryLock(path)
			if err != nil {
				t.Fatal(err)
			}
			defer held.Release()
			f := tc.inherited(t, path)
			defer f.Close()
			if _, err := Adopt(f, path); axerr.KindOf(err) != axerr.Refused {
				t.Fatalf("Adopt: %v, want Refused", err)
			}
		})
	}
}

func TestLockDirWaitsForTheHolder(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	l, err := LockDir(context.Background(), dir)
	if err != nil {
		t.Fatal(err)
	}
	// Held (another descriptor counts as another holder): a second waits,
	// until its context ends
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	if _, err := LockDir(ctx, dir); err == nil {
		t.Fatal("locked twice")
	}
	got := make(chan error, 1)
	go func() {
		l2, err := LockDir(context.Background(), dir)
		l2.Release()
		got <- err
	}()
	time.Sleep(100 * time.Millisecond)
	l.Release()
	select {
	case err := <-got:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("never got the lock once released")
	}
	// Nothing was added to the folder
	if entries, _ := os.ReadDir(dir); len(entries) != 0 {
		t.Fatalf("left %v", entries)
	}
}
