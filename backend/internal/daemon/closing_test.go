package daemon

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// A re-exec or quit tells the daemon topic's subscribers first and waits
// for them to close their side (the shell's socket warns on a close it
// didn't make), but no longer than its wait for one that doesn't.
func TestAnnounceClosingWaitsForTheClientsToClose(t *testing.T) {
	t.Parallel()
	dir, err := os.MkdirTemp("", "ax") // short: a sockaddr_un
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	path := filepath.Join(dir, "s.sock")
	ln, err := rpc.Listen(path)
	if err != nil {
		t.Fatal(err)
	}
	connected := make(chan struct{}, 4)
	server := &rpc.Server{Registry: rpc.NewRegistry(), OnConnect: func(c *rpc.Conn) {
		c.SetValue(sessionKey{}, &session{Client: "shell", all: true})
		connected <- struct{}{}
	}}
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	go server.Serve(ctx, ln)

	// dial connects a client that, told the daemon is closing, says what
	// it was told and closes itself when closes is true
	dial := func(closes bool) <-chan daemonClosing {
		told := make(chan daemonClosing, 1)
		reg := rpc.NewRegistry()
		var c *rpc.Conn
		rpc.Handle(reg, "daemon.closing", func(_ context.Context, _ *rpc.Conn, p daemonClosing) (struct{}, error) {
			told <- p
			if closes {
				go c.Close()
			}
			return struct{}{}, nil
		})
		c, err = rpc.Dial(context.Background(), path, reg, nil)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { c.Close() })
		<-connected
		return told
	}

	told := dial(true)
	start := time.Now()
	announceClosing(server, true, 5*time.Second)
	if waited := time.Since(start); waited > 2*time.Second {
		t.Errorf("waited %v for a client that closed at once", waited)
	}
	if p := <-told; !p.Reexec {
		t.Errorf("told %+v, want a re-exec", p)
	}

	stays := dial(false)
	start = time.Now()
	announceClosing(server, false, 100*time.Millisecond)
	if waited := time.Since(start); waited < 100*time.Millisecond || waited > 2*time.Second {
		t.Errorf("waited %v for a client that stays, want the wait (100ms)", waited)
	}
	if p := <-stays; p.Reexec {
		t.Errorf("told %+v, want a quit", p)
	}
}
