package place

import (
	"bufio"
	"context"
	"encoding/binary"
	"encoding/json"
	"io"
	"net"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/windowrules"
)

type stepList = []windowrules.Step

func env(kv ...string) func(string) string {
	return func(k string) string {
		for i := 0; i+1 < len(kv); i += 2 {
			if kv[i] == k {
				return kv[i+1]
			}
		}
		return ""
	}
}

func TestNew(t *testing.T) {
	t.Parallel()
	if New(Options{Getenv: env()}) != nil {
		t.Error("a dispatcher with no compositor")
	}
	for name, tc := range map[string]struct {
		env  func(string) string
		want string
	}{
		"hyprland": {env("HYPRLAND_INSTANCE_SIGNATURE", "sig", "XDG_RUNTIME_DIR", "/run/user/1"), "hypr"},
		"sway":     {env("SWAYSOCK", "/x/sway.sock"), "sway"},
		"niri":     {env("NIRI_SOCKET", "/x/niri.sock"), "niri"},
	} {
		d := New(Options{Getenv: tc.env})
		if d == nil {
			t.Errorf("%s: nil", name)
			continue
		}
		var got string
		switch d.b.(type) {
		case hypr:
			got = "hypr"
		case sway:
			got = "sway"
		case niri:
			got = "niri"
		}
		if got != tc.want {
			t.Errorf("%s: %T", name, d.b)
		}
	}
}

func TestRunNothing(t *testing.T) {
	t.Parallel()
	// No steps: no request, so the unreachable socket is never dialled
	d := &Dispatcher{b: niri{&ipc.Niri{Path: "/nonexistent"}}}
	if err := d.Run(context.Background(), "1", nil); err != nil {
		t.Fatal(err)
	}
}

func TestHyprChunk(t *testing.T) {
	t.Parallel()
	steps := stepList{
		{Kind: windowrules.StepOutput, Output: `DP-"1"`},
		{Kind: windowrules.StepMove, Workspace: "3"},
		{Kind: windowrules.StepMove, Workspace: "my ws"},
		{Kind: windowrules.StepMove, Special: "g", Show: true},
		{Kind: windowrules.StepMove, Special: "g"},
		{Kind: windowrules.StepFloat},
		{Kind: windowrules.StepSize, Width: 400, Height: 300},
		{Kind: windowrules.StepCenter},
		{Kind: windowrules.StepFullscreen},
		{Kind: windowrules.StepMaximize},
		{Kind: windowrules.StepPin},
		{Kind: windowrules.StepLook, Rules: []string{"a", "b"}, Tearing: true},
		{Kind: windowrules.StepFocus},
	}
	const w = `window = "address:0x5f"`
	want := hyprPrelude + strings.Join([]string{
		`run(function() return hl.dsp.window.move({ monitor = "DP-\"1\"", ` + w + ` }) end)`,
		`run(function() return hl.dsp.window.move({ workspace = "3", follow = false, ` + w + ` }) end)`,
		`run(function() return hl.dsp.window.move({ workspace = "name:my ws", follow = false, ` + w + ` }) end)`,
		`run(function() return hl.dsp.window.move({ workspace = "special:g", follow = true, ` + w + ` }) end)`,
		`run(function() return hl.dsp.window.move({ workspace = "special:g", follow = false, ` + w + ` }) end)`,
		`run(function() return hl.dsp.window.float({ action = "enable", ` + w + ` }) end)`,
		`run(function() return hl.dsp.window.resize({ x = 400, y = 300, ` + w + ` }) end)`,
		`run(function() return hl.dsp.window.center({ ` + w + ` }) end)`,
		`run(function() return hl.dsp.window.fullscreen({ action = "set", ` + w + ` }) end)`,
		`run(function() return hl.dsp.window.fullscreen({ mode = "maximized", action = "set", ` + w + ` }) end)`,
		`run(function() return hl.dsp.window.pin({ action = "enable", ` + w + ` }) end)`,
		`run(function() return hl.dsp.window.tag({ tag = "+axiom-rule-a", ` + w + ` }) end)`,
		`run(function() return hl.dsp.window.tag({ tag = "+axiom-rule-b", ` + w + ` }) end)`,
		`run(function() return hl.dsp.focus({ ` + w + ` }) end)`,
	}, "\n") + hyprEpilogue
	got, err := hyprChunk("0x5f", steps)
	if err != nil || got != want {
		t.Fatalf("%v\n%s\nwant\n%s", err, got, want)
	}
	if _, err := hyprChunk(`0x5f" }) end) --`, steps); err == nil {
		t.Error("a bad address was sent")
	}
	if got, err := hyprChunk("0x5f", stepList{{Kind: windowrules.StepLook}}); got != "" || err != nil {
		t.Errorf("a look of no rules: %q %v", got, err)
	}
}

func TestSwayCommands(t *testing.T) {
	t.Parallel()
	steps := stepList{
		{Kind: windowrules.StepOutput, Output: "DP-1"},
		{Kind: windowrules.StepMove, Workspace: "3"},
		{Kind: windowrules.StepMove, Workspace: `my "ws"`},
		{Kind: windowrules.StepMove, Special: "g", Show: true},
		{Kind: windowrules.StepMove, Special: "h"},
		{Kind: windowrules.StepFloat},
		{Kind: windowrules.StepSize, Width: 400, Height: 300},
		{Kind: windowrules.StepCenter},
		{Kind: windowrules.StepFullscreen},
		{Kind: windowrules.StepMaximize},
		{Kind: windowrules.StepPin},
		{Kind: windowrules.StepLook, Rules: []string{"a"}},
		{Kind: windowrules.StepLook, Tearing: true},
		{Kind: windowrules.StepFocus},
	}
	c := "[con_id=42] "
	want := strings.Join([]string{
		c + "move container to output DP-1",
		c + "move container to workspace number 3",
		c + `move container to workspace "my "'"'"ws"'"'`,
		c + "mark --add axiom-special-g-42", c + "move scratchpad", c + "scratchpad show",
		c + "mark --add axiom-special-h-42", c + "move scratchpad",
		c + "floating enable",
		c + "resize set 400 px 300 px",
		c + "move position center",
		c + "fullscreen enable",
		c + "sticky enable",
		c + "allow_tearing yes",
		c + "focus",
	}, "; ")
	got, err := swayCommands("42", steps, nil)
	if err != nil || got != want {
		t.Fatalf("%v\n%s\nwant\n%s", err, got, want)
	}
	for _, id := range []string{"0x5f", "", "4 2", "-1"} {
		if _, err := swayCommands(id, steps, nil); err == nil {
			t.Errorf("id %q accepted", id)
		}
	}
}

func TestSwayMovesOutOfItsGroup(t *testing.T) {
	t.Parallel()
	tree := json.RawMessage(`{"id":1,"nodes":[{"id":2,"nodes":[{"id":42,"marks":["axiom-special-a-42","keep"]}],"floating_nodes":[{"id":43,"marks":["axiom-special-z-43"]}]}]}`)
	marks := specialMarks(tree, "42")
	if !reflect.DeepEqual(marks, []string{"axiom-special-a-42"}) {
		t.Fatalf("marks %v", marks)
	}
	got, err := swayCommands("42", stepList{{Kind: windowrules.StepMove, Special: "b"}}, marks)
	want := "[con_id=42] unmark axiom-special-a-42; [con_id=42] mark --add axiom-special-b-42; [con_id=42] move scratchpad"
	if err != nil || got != want {
		t.Fatalf("%v\n%s\nwant\n%s", err, got, want)
	}
}

func TestNiriActions(t *testing.T) {
	t.Parallel()
	steps := stepList{
		{Kind: windowrules.StepOutput, Output: "DP-1"},
		{Kind: windowrules.StepMove, Workspace: "3"},
		{Kind: windowrules.StepMove, Workspace: "web"},
		{Kind: windowrules.StepFloat},
		{Kind: windowrules.StepSize, Width: 400, Height: 300},
		{Kind: windowrules.StepCenter},
		{Kind: windowrules.StepFullscreen},
		{Kind: windowrules.StepFocus},
	}
	want := []string{
		`{"MoveWindowToMonitor":{"id":7,"output":"DP-1"}}`,
		`{"MoveWindowToWorkspace":{"focus":false,"reference":{"Index":3},"window_id":7}}`,
		`{"MoveWindowToWorkspace":{"focus":false,"reference":{"Name":"web"},"window_id":7}}`,
		`{"MoveWindowToFloating":{"id":7}}`,
		`{"SetWindowWidth":{"change":{"SetFixed":400},"id":7}}`,
		`{"SetWindowHeight":{"change":{"SetFixed":300},"id":7}}`,
		`{"CenterWindow":{"id":7}}`,
		`{"FullscreenWindow":{"id":7}}`,
		`{"FocusWindow":{"id":7}}`,
	}
	acts, err := niriActions("7", steps)
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, a := range acts {
		b, _ := json.Marshal(a)
		got = append(got, string(b))
	}
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Fatalf("got\n%s\nwant\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
	// No by-id action for these: skipped, not sent
	skipped, err := niriActions("7", stepList{
		{Kind: windowrules.StepMove, Special: "g"}, {Kind: windowrules.StepMaximize}, {Kind: windowrules.StepPin},
		{Kind: windowrules.StepLook, Rules: []string{"a"}, Tearing: true},
	})
	if err != nil || len(skipped) != 0 {
		t.Errorf("skipped steps sent: %v %v", skipped, err)
	}
	// an index niri can't take is an error beside the other actions
	acts, err = niriActions("7", stepList{{Kind: windowrules.StepMove, Workspace: "300"}, {Kind: windowrules.StepFloat}})
	if err == nil || len(acts) != 1 {
		t.Errorf("workspace 300: %v %v", acts, err)
	}
	for _, id := range []string{"0x5f", "", "-1"} {
		if _, err := niriActions(id, steps); err == nil {
			t.Errorf("id %q accepted", id)
		}
	}
}

// listen serves path with handle, one goroutine per connection.
func listen(t *testing.T, path string, handle func(net.Conn)) {
	t.Helper()
	l, err := net.Listen("unix", path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { l.Close() })
	go func() {
		for {
			c, err := l.Accept()
			if err != nil {
				return
			}
			go func() {
				defer c.Close()
				handle(c)
			}()
		}
	}()
}

func short(t *testing.T) string {
	t.Helper()
	// Unix socket paths are short: t.TempDir can be too long
	dir, err := os.MkdirTemp("", "axplace")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	return dir
}

func ctx(t *testing.T) context.Context {
	c, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	t.Cleanup(cancel)
	return c
}

func TestRunHypr(t *testing.T) {
	t.Parallel()
	dir := short(t)
	var mu sync.Mutex
	var requests []string
	reply := "ok"
	listen(t, filepath.Join(dir, ".socket.sock"), func(c net.Conn) {
		buf := make([]byte, 8192)
		n, _ := c.Read(buf)
		mu.Lock()
		requests = append(requests, string(buf[:n]))
		r := reply
		mu.Unlock()
		io.WriteString(c, r)
	})
	d := &Dispatcher{b: hypr{&ipc.Hypr{Dir: dir}}}
	steps := stepList{{Kind: windowrules.StepFloat}, {Kind: windowrules.StepCenter}}
	if err := d.Run(ctx(t), "0xab", steps); err != nil {
		t.Fatal(err)
	}
	mu.Lock()
	if len(requests) != 1 || !strings.HasPrefix(requests[0], "eval local errs") || strings.Count(requests[0], "run(function()") != 2 {
		t.Errorf("requests: %q", requests)
	}
	reply = "attempt to call nil"
	mu.Unlock()
	if err := d.Run(ctx(t), "0xab", steps); err == nil || !strings.Contains(err.Error(), "attempt to call nil") {
		t.Errorf("a refused chunk: %v", err)
	}
}

func swayReply(c net.Conn, kind uint32, body string) {
	head := make([]byte, 14)
	copy(head, "i3-ipc")
	binary.LittleEndian.PutUint32(head[6:], uint32(len(body)))
	binary.LittleEndian.PutUint32(head[10:], kind)
	c.Write(append(head, body...))
}

func TestRunSway(t *testing.T) {
	t.Parallel()
	path := filepath.Join(short(t), "sway.sock")
	got := make(chan string, 4)
	listen(t, path, func(c net.Conn) {
		head := make([]byte, 14)
		if _, err := io.ReadFull(c, head); err != nil {
			return
		}
		body := make([]byte, binary.LittleEndian.Uint32(head[6:]))
		io.ReadFull(c, body)
		got <- string(body)
		if strings.Contains(string(body), "floating") {
			swayReply(c, 0, `[{"success":true},{"success":false,"error":"No matching node."}]`)
			return
		}
		swayReply(c, 0, `[{"success":true}]`)
	})
	d := &Dispatcher{b: sway{&ipc.Sway{Path: path}}}
	if err := d.Run(ctx(t), "9", stepList{{Kind: windowrules.StepFocus}}); err != nil {
		t.Fatal(err)
	}
	if body := <-got; body != "[con_id=9] focus" {
		t.Errorf("sent %q", body)
	}
	err := d.Run(ctx(t), "9", stepList{{Kind: windowrules.StepFloat}, {Kind: windowrules.StepFocus}})
	if err == nil || !strings.Contains(err.Error(), "No matching node.") {
		t.Errorf("a failed command: %v", err)
	}
	// A look that does nothing here sends nothing
	if err := d.Run(ctx(t), "9", stepList{{Kind: windowrules.StepLook, Rules: []string{"a"}}}); err != nil || len(got) != 1 {
		t.Errorf("a look sent a command: %v %d", err, len(got))
	}
}

func TestRunNiri(t *testing.T) {
	t.Parallel()
	path := filepath.Join(short(t), "niri.sock")
	var mu sync.Mutex
	var lines []string
	listen(t, path, func(c net.Conn) {
		line, _ := bufio.NewReader(c).ReadString('\n')
		mu.Lock()
		lines = append(lines, strings.TrimSpace(line))
		mu.Unlock()
		if strings.Contains(line, "CenterWindow") {
			io.WriteString(c, `{"Err":"no"}`+"\n")
			return
		}
		io.WriteString(c, `{"Ok":"Handled"}`+"\n")
	})
	d := &Dispatcher{b: niri{&ipc.Niri{Path: path}}}
	err := d.Run(ctx(t), "5", stepList{{Kind: windowrules.StepFloat}, {Kind: windowrules.StepCenter}, {Kind: windowrules.StepFocus}})
	if err == nil {
		t.Error("a refused action wasn't returned")
	}
	mu.Lock()
	defer mu.Unlock()
	// Every step is tried, the failure doesn't stop the rest
	if len(lines) != 3 || !strings.Contains(lines[2], "FocusWindow") {
		t.Errorf("requests: %q", lines)
	}
}
