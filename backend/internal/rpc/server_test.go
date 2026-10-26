package rpc

import (
	"os"
	"path/filepath"
	"testing"
)

// Listen replaces what sits at the path (its caller holds the lock that
// makes that safe) with a socket only this user may connect to, and the
// socket goes with the listener.
func TestListenMakesAPrivateSocket(t *testing.T) {
	t.Parallel()
	// Short: the path must fit a sockaddr_un
	dir, err := os.MkdirTemp("", "ax")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	for _, stale := range []bool{false, true} {
		path := filepath.Join(dir, "axiom.sock")
		if stale {
			if err := os.WriteFile(path, []byte("stale"), 0o644); err != nil {
				t.Fatal(err)
			}
		}
		ln, err := Listen(path)
		if err != nil {
			t.Fatalf("stale %v: %v", stale, err)
		}
		info, err := os.Lstat(path)
		if err != nil {
			t.Fatal(err)
		}
		if info.Mode()&os.ModeSocket == 0 || info.Mode().Perm() != 0o600 {
			t.Errorf("stale %v: the socket is %v, want a socket with 0600", stale, info.Mode())
		}
		ln.Close()
		if _, err := os.Lstat(path); !os.IsNotExist(err) {
			t.Errorf("stale %v: the socket outlived its listener: %v", stale, err)
		}
	}
}
