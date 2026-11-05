package daemon

import (
	"bufio"
	"encoding/json"
	"net"
	"strings"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/chat"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// A fast reply to a shell that stopped reading is gathered, not queued a
// piece at a time until the connection is dropped; every piece still
// arrives, in order.
func TestChatDeltasGatherWhileBacklogged(t *testing.T) {
	t.Parallel()
	a, b := net.Pipe()
	c := rpc.NewConn(a, nil, rpc.Limits{MaxLine: 1 << 20, MaxDepth: 8, MaxInFlight: 4, QueueSize: 8}, nil)
	t.Cleanup(func() { c.Close(); b.Close() })
	emit, flush := gatherDeltas(c)
	var want strings.Builder
	for i := 0; i < 1000; i++ {
		kind := "thinking"
		if i >= 500 {
			kind = "text"
		}
		emit(chat.Delta{ID: "r1", Kind: kind, Text: string(rune('a' + i%26))})
		want.WriteString(string(rune('a' + i%26)))
	}
	flush()
	select {
	case <-c.Done():
		t.Fatal("dropped the shell for a fast reply")
	default:
	}
	r := bufio.NewReader(b)
	var got strings.Builder
	lines, sawText := 0, false
	for got.Len() < want.Len() {
		b.SetReadDeadline(time.Now().Add(2 * time.Second))
		line, err := r.ReadBytes('\n')
		if err != nil {
			t.Fatalf("read: %v (after %q)", err, got.String())
		}
		var m struct {
			Method string
			Params chat.Delta
		}
		json.Unmarshal(line, &m)
		if m.Method != "chat.delta" || m.Params.ID != "r1" {
			t.Fatalf("got %s", line)
		}
		if m.Params.Kind == "thinking" && sawText {
			t.Error("thinking after the text")
		}
		sawText = sawText || m.Params.Kind == "text"
		got.WriteString(m.Params.Text)
		lines++
	}
	if got.String() != want.String() {
		t.Errorf("got %q, want %q", got.String(), want.String())
	}
	if lines > 20 {
		t.Errorf("%d pushes for 1000 pieces", lines)
	}
}
