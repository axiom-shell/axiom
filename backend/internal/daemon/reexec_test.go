package daemon

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"time"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/store"
)

// A daemon that doesn't get the instance lock leaves whatever sits at the
// socket's path alone: only the lock's holder may remove a stale socket.
// Once the lock is free, the next daemon replaces it with its own (0600).
func TestStaleSocketIsRemovedOnlyUnderTheInstanceLock(t *testing.T) {
	t.Parallel()
	td := newTestDaemon(t)
	held, err := fsx.TryLock(td.runtime.Lock())
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(td.socket, []byte("stale"), 0o600); err != nil {
		t.Fatal(err)
	}
	err = runBriefly(t, td)
	if axerr.KindOf(err) != axerr.Running {
		t.Fatalf("run with the lock held elsewhere: %v, want Running", err)
	}
	if data, err := os.ReadFile(td.socket); err != nil || string(data) != "stale" {
		t.Fatalf("the socket's path was touched without the lock: %q %v", data, err)
	}

	// Released with forks held off: a child a parallel test forked while
	// the lock was held carries its descriptor (and so the flock) until it
	// execs. os/exec forks under ForkLock, so with its read lock none is
	// between fork and exec, and the close frees the lock at once
	syscall.ForkLock.RLock()
	held.Release()
	syscall.ForkLock.RUnlock()
	td.start(t, nil)
	info, err := os.Lstat(td.socket)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode()&os.ModeSocket == 0 || info.Mode().Perm() != 0o600 {
		t.Errorf("the socket is %v, want a socket with 0600", info.Mode())
	}
}

// runBriefly runs a daemon that should refuse to start: should it start
// after all, it is stopped (returning nil) rather than left running.
func runBriefly(t *testing.T, td *testDaemon) error {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return Run(ctx, td.options(nil))
}

// handoffFixture is what an image before a re-exec holds: the instance
// lock, the config's writer lock and the listening socket.
type handoffFixture struct {
	instance, config *fsx.Lock
	listener         *os.File
}

func newHandoffFixture(t *testing.T, td *testDaemon) *handoffFixture {
	t.Helper()
	instance, err := fsx.TryLock(td.runtime.Lock())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { instance.Release() })
	if err := os.MkdirAll(td.dirs.Config, 0o700); err != nil {
		t.Fatal(err)
	}
	config, err := fsx.TryLock(filepath.Join(td.dirs.Config, store.FileName+".lock"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { config.Release() })
	ln, err := rpc.Listen(td.socket)
	if err != nil {
		t.Fatal(err)
	}
	listener, err := ln.File()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { listener.Close() })
	// The socket file stays for the image after: only this copy goes
	ln.SetUnlinkOnClose(false)
	ln.Close()
	return &handoffFixture{instance: instance, config: config, listener: listener}
}

// dup is a descriptor of f's for the daemon to take over (it closes what
// it adopts, so the test's own copies stay its).
func dup(t *testing.T, f *os.File) int {
	t.Helper()
	fd, err := unix.FcntlInt(f.Fd(), unix.F_DUPFD_CLOEXEC, 3)
	if err != nil {
		t.Fatal(err)
	}
	return fd
}

func (td *testDaemon) setHandoff(t *testing.T, h handoff) {
	t.Helper()
	raw, err := json.Marshal(h)
	if err != nil {
		t.Fatal(err)
	}
	td.env[reexecEnv] = string(raw)
}

// A daemon handed this display's held locks and socket takes them over
// and serves on the same socket; when it stops, the socket goes.
func TestAdoptedHandoffServes(t *testing.T) {
	t.Parallel()
	td := newTestDaemon(t)
	fx := newHandoffFixture(t, td)
	td.setHandoff(t, handoff{
		Lock:       dup(t, fx.instance.File()),
		ConfigLock: dup(t, fx.config.File()),
		Listener:   dup(t, fx.listener),
	})
	ctx, cancel := context.WithCancel(context.Background())
	var runErr error
	stopped := make(chan struct{})
	go func() { runErr = Run(ctx, td.options(nil)); close(stopped) }()
	// Stopped before its folders go, also when the test fails early
	t.Cleanup(func() {
		cancel()
		select {
		case <-stopped:
		case <-time.After(10 * time.Second):
			t.Error("the daemon didn't stop")
		}
	})

	callCtx, callCancel := context.WithTimeout(ctx, 10*time.Second)
	defer callCancel()
	c, err := rpc.Dial(callCtx, td.socket, rpc.NewRegistry(), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	var hello HelloResult
	params := map[string]any{"protocol": buildinfo.Protocol(), "client": "test", "pid": os.Getpid()}
	if err := c.Call(callCtx, "daemon.hello", params, &hello); err != nil {
		select {
		case <-stopped:
			t.Fatalf("hello: %v (the daemon stopped: %v)", err, runErr)
		default:
			t.Fatalf("hello: %v", err)
		}
	}
	cancel()
	select {
	case <-stopped:
		if runErr != nil {
			t.Fatalf("run: %v", runErr)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("the daemon didn't stop")
	}
	if _, err := os.Lstat(td.socket); !os.IsNotExist(err) {
		t.Errorf("the adopted socket outlived the daemon: %v", err)
	}
}

// A handoff whose instance lock isn't this display's held lock is refused
// before anything is taken over: another file, or this one's lock file
// opened anew (which doesn't hold the lock its holder has).
func TestHandoffWithoutTheHeldLockIsRefused(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name string
		lock func(t *testing.T, td *testDaemon) *os.File
	}{
		{"another file", func(t *testing.T, td *testDaemon) *os.File {
			other, err := fsx.TryLock(filepath.Join(t.TempDir(), "other.lock"))
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { other.Release() })
			return other.File()
		}},
		{"not the holder", func(t *testing.T, td *testDaemon) *os.File {
			f, err := os.Open(td.runtime.Lock())
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { f.Close() })
			return f
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			td := newTestDaemon(t)
			fx := newHandoffFixture(t, td)
			configFD, listenerFD := dup(t, fx.config.File()), dup(t, fx.listener)
			// Never taken over: refused at the instance lock
			t.Cleanup(func() { unix.Close(configFD); unix.Close(listenerFD) })
			td.setHandoff(t, handoff{Lock: dup(t, tc.lock(t, td)), ConfigLock: configFD, Listener: listenerFD})
			err := runBriefly(t, td)
			if axerr.KindOf(err) != axerr.Refused {
				t.Fatalf("run: %v, want Refused", err)
			}
		})
	}
}
