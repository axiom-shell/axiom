package ipc

import (
	"bufio"
	"encoding/json"
	"io"
	"net"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

// pushes records what a stream notified
type pushes struct {
	mu  sync.Mutex
	got []string
}

func (p *pushes) Notify(method string, params any) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if raw, ok := params.(json.RawMessage); ok {
		method += " " + string(raw)
	}
	p.got = append(p.got, method)
	return nil
}

func (p *pushes) list() []string {
	p.mu.Lock()
	defer p.mu.Unlock()
	return append([]string(nil), p.got...)
}

// waitFor waits until p has n pushes and returns them
func (p *pushes) waitFor(t *testing.T, n int) []string {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if got := p.list(); len(got) >= n {
			return got
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("pushes: %q, want %d", p.list(), n)
	return nil
}

// eventStream serves niri's stream: its reply, then each connection's
// events, held open until the client closes it
func eventStream(c net.Conn) {
	line, _ := bufio.NewReader(c).ReadString('\n')
	if line != "\"EventStream\"\n" {
		return
	}
	io.WriteString(c, `{"Ok":"Handled"}`+"\n")
	io.WriteString(c, `{"WorkspacesChanged":{"workspaces":[]}}`+"\n")
	io.WriteString(c, `{"WindowFocusChanged":{"id":4}}`+"\n")
	io.Copy(io.Discard, c)
}

func TestNiriStreams(t *testing.T) {
	t.Parallel()
	path := filepath.Join(short(t), "niri.sock")
	s := NewNiriStreams(&Niri{Path: path}, NiriStreamsOptions{
		Started: func(s Subscriber) { s.Notify("started", nil) },
		Event:   func(s Subscriber, event json.RawMessage) { s.Notify("event", event) },
		Context: ctx(t), Retry: 20 * time.Millisecond})
	p := &pushes{}
	// niri isn't there yet: a failed connect is tried again
	s.Watch(p)
	time.Sleep(50 * time.Millisecond)
	listen(t, path, eventStream)
	want := []string{"started", `event {"WorkspacesChanged":{"workspaces":[]}}`, `event {"WindowFocusChanged":{"id":4}}`}
	got := p.waitFor(t, 3)
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("pushes: %q, want %q", got, want)
		}
	}
	// Watching again starts over from the full state
	s.Watch(p)
	if got := p.waitFor(t, 6); got[3] != "started" {
		t.Fatalf("watched again: %q", got)
	}
	s.Forget(p)
	time.Sleep(50 * time.Millisecond)
	if got := p.list(); len(got) != 6 {
		t.Fatalf("pushed after Forget: %q", got)
	}
}
