package ipc

import (
	"context"
	"errors"
	"io"
	"net"
	"path/filepath"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// A compositor that accepts a request and never answers must not hold the
// caller: a ctx deadline or a cancel ends the request with ctx's error.
func TestRequestsHonourContext(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	hang := func(c net.Conn) { io.Copy(io.Discard, c) }
	listen(t, filepath.Join(dir, "niri.sock"), hang)
	listen(t, filepath.Join(dir, "sway.sock"), hang)
	listen(t, filepath.Join(dir, ".socket.sock"), hang)
	calls := map[string]func(ctx context.Context) error{
		"niri": func(ctx context.Context) error {
			_, err := (&Niri{Path: filepath.Join(dir, "niri.sock")}).Request(ctx, "Outputs")
			return err
		},
		"sway": func(ctx context.Context) error {
			_, err := (&Sway{Path: filepath.Join(dir, "sway.sock")}).Run(ctx, "nop")
			return err
		},
		"hypr": func(ctx context.Context) error {
			_, err := (&Hypr{Dir: dir}).Request(ctx, "j/binds")
			return err
		},
	}
	for name, call := range calls {
		t.Run(name+" deadline", func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
			defer cancel()
			returns(t, call, ctx, context.DeadlineExceeded)
		})
		t.Run(name+" cancel", func(t *testing.T) {
			ctx, cancel := context.WithCancel(context.Background())
			time.AfterFunc(100*time.Millisecond, cancel)
			returns(t, call, ctx, context.Canceled)
		})
	}
}

func returns(t *testing.T, call func(context.Context) error, ctx context.Context, want error) {
	t.Helper()
	done := make(chan error, 1)
	go func() { done <- call(ctx) }()
	select {
	case err := <-done:
		if !errors.Is(err, want) {
			t.Errorf("error %v, want %v", err, want)
		}
	case <-time.After(testkit.Bound(2 * time.Second)):
		t.Fatal("the request didn't return")
	}
}

// A compositor that writes part of a reply and stalls: the cancel ends the
// request with ctx's error, never the partial reply.
func TestPartialReplyIsNotSuccess(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	stall := func(partial string) func(net.Conn) {
		return func(c net.Conn) {
			c.Write([]byte(partial))
			io.Copy(io.Discard, c)
		}
	}
	listen(t, filepath.Join(dir, "niri.sock"), stall(`{"Ok":"Handled"}`))
	listen(t, filepath.Join(dir, ".socket.sock"), stall("ok"))
	calls := map[string]func(ctx context.Context) error{
		"niri": func(ctx context.Context) error {
			_, err := (&Niri{Path: filepath.Join(dir, "niri.sock")}).Request(ctx, "Outputs")
			return err
		},
		"hypr": func(ctx context.Context) error {
			_, err := (&Hypr{Dir: dir}).Request(ctx, "j/binds")
			return err
		},
	}
	for name, call := range calls {
		t.Run(name, func(t *testing.T) {
			ctx, cancel := context.WithCancel(context.Background())
			time.AfterFunc(100*time.Millisecond, cancel)
			returns(t, call, ctx, context.Canceled)
		})
	}
}
