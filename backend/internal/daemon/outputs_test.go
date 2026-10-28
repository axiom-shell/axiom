package daemon

import (
	"bufio"
	"context"
	"encoding/binary"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// serveOnce answers each connection to path with reply(what it was sent),
// sending what it was sent on the returned channel
func serveOnce(t *testing.T, path string, read func(net.Conn) string, reply func(net.Conn, string)) <-chan string {
	t.Helper()
	l, err := net.Listen("unix", path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { l.Close() })
	asked := make(chan string, 16)
	go func() {
		for {
			c, err := l.Accept()
			if err != nil {
				return
			}
			got := read(c)
			asked <- got
			reply(c, got)
			c.Close()
		}
	}()
	return asked
}

// Monitor Apply (outputs.apply) goes to the compositor running, in its own
// terms, and what it refuses comes back refused
func TestApplyOutputs(t *testing.T) {
	t.Parallel()
	dir, err := os.MkdirTemp("", "axout")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	rules, _ := jsonx.Unmarshal([]byte(`[{"output": "HDMI-A-1", "disabled": true}, {"output": "desc:TV", "mirror": "desc:Main"}]`))
	details, _ := jsonx.Unmarshal([]byte(`[{"name": "DP-1", "description": "Main"}, {"name": "DP-2", "description": "TV"}]`))

	hyprReply := "ok"
	hypr := serveOnce(t, filepath.Join(dir, ".socket.sock"), func(c net.Conn) string {
		buf := make([]byte, 1<<16)
		n, _ := c.Read(buf)
		return string(buf[:n])
	}, func(c net.Conn, _ string) { io.WriteString(c, hyprReply) })
	h := &ipc.Hypr{Dir: dir}
	if err := applyOutputs(ctx, h, nil, nil, rules, details); err != nil {
		t.Fatal(err)
	}
	if got := <-hypr; got != `eval hl.monitor({ output = "HDMI-A-1", disabled = true })`+"\n"+`hl.monitor({ output = "desc:TV", mode = "preferred", position = "0x0", scale = 1, mirror = "DP-1" })` {
		t.Errorf("hyprland: %q", got)
	}

	niriPath := filepath.Join(dir, "niri.sock")
	niri := serveOnce(t, niriPath, func(c net.Conn) string {
		line, _ := bufio.NewReader(c).ReadString('\n')
		return strings.TrimSpace(line)
	}, func(c net.Conn, got string) {
		if strings.Contains(got, `"On"`) {
			io.WriteString(c, `{"Err":"no such output"}`+"\n")
			return
		}
		io.WriteString(c, `{"Ok":"Handled"}`+"\n")
	})
	n := &ipc.Niri{Path: niriPath}
	// On first, so an output isn't turned off before another takes over;
	// the refused On doesn't stop the rest, and comes back refused
	err = applyOutputs(ctx, nil, n, nil, rules, details)
	if axerr.KindOf(err) != axerr.Refused {
		t.Fatalf("niri refusing: %v", err)
	}
	var sent []string
	for len(niri) > 0 {
		sent = append(sent, <-niri)
	}
	if len(sent) != 6 || sent[0] != `{"Output":{"output":"DP-2","action":"On"}}` || !strings.Contains(sent[5], `"Off"`) {
		t.Errorf("niri: %q", sent)
	}

	swayPath := filepath.Join(dir, "sway.sock")
	sway := serveOnce(t, swayPath, func(c net.Conn) string {
		head := make([]byte, 14)
		io.ReadFull(c, head)
		body := make([]byte, binary.LittleEndian.Uint32(head[6:]))
		io.ReadFull(c, body)
		return string(body)
	}, func(c net.Conn, _ string) {
		body := `[{"success":true},{"success":false,"error":"Unknown output"}]`
		head := make([]byte, 14)
		copy(head, "i3-ipc")
		binary.LittleEndian.PutUint32(head[6:], uint32(len(body)))
		c.Write(append(head, body...))
	})
	err = applyOutputs(ctx, nil, nil, &ipc.Sway{Path: swayPath}, rules, details)
	if axerr.KindOf(err) != axerr.Refused || !strings.Contains(err.Error(), "Unknown output") {
		t.Fatalf("sway refusing: %v", err)
	}
	if got := <-sway; got != `output TV enable pos 0 0 scale 1 transform normal adaptive_sync off render_bit_depth 8; output HDMI-A-1 disable` {
		t.Errorf("sway: %q", got)
	}

	if err := applyOutputs(ctx, nil, nil, nil, rules, details); axerr.KindOf(err) != axerr.Unavailable {
		t.Errorf("no compositor: %v", err)
	}
}
