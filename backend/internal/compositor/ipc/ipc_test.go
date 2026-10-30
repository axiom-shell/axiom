package ipc

import (
	"bufio"
	"context"
	"encoding/binary"
	"errors"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// listen serves path with handle, one connection at a time on its own
// goroutine
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
	dir, err := os.MkdirTemp("", "axipc")
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

func TestHypr(t *testing.T) {
	t.Parallel()
	dir := short(t)
	listen(t, filepath.Join(dir, ".socket.sock"), func(c net.Conn) {
		buf := make([]byte, 4096)
		n, _ := c.Read(buf)
		switch req := string(buf[:n]); {
		case req == "j/binds":
			io.WriteString(c, `[{"modmask":64,"key":"Q"}]`)
		case req == "eval good()":
			io.WriteString(c, "ok")
		case strings.HasPrefix(req, "eval "):
			io.WriteString(c, "boom: attempt to call nil")
		default:
			io.WriteString(c, "ok")
		}
	})
	events := make(chan net.Conn, 1)
	listen(t, filepath.Join(dir, ".socket2.sock"), func(c net.Conn) {
		events <- c
		<-time.After(5 * time.Second)
	})
	h := &Hypr{Dir: dir}
	binds, err := h.JSON(ctx(t), "binds")
	if err != nil || binds == nil {
		t.Fatalf("binds: %v %v", binds, err)
	}
	if reply, err := h.Eval(ctx(t), "good()"); err != nil || reply != "" {
		t.Fatalf("eval: %q %v", reply, err)
	}
	if reply, _ := h.Eval(ctx(t), "bad()"); !strings.Contains(reply, "boom") {
		t.Fatalf("eval error: %q", reply)
	}
	out := make(chan Reload, 1)
	c, cancel := context.WithCancel(context.Background())
	defer cancel()
	go h.Reloads(c, out)
	conn := <-events
	io.WriteString(conn, "workspace>>2\nconfigreloaded>>\n")
	select {
	case <-out:
	case <-time.After(testkit.Bound(3 * time.Second)):
		t.Fatal("no reload")
	}
}

func TestHyprFromEnv(t *testing.T) {
	t.Parallel()
	env := map[string]string{"XDG_RUNTIME_DIR": "/run/user/1", "HYPRLAND_INSTANCE_SIGNATURE": "abc"}
	h := HyprFromEnv(func(k string) string { return env[k] })
	if h == nil || h.Dir != "/run/user/1/hypr/abc" {
		t.Fatalf("%+v", h)
	}
	if HyprFromEnv(func(string) string { return "" }) != nil {
		t.Fatal("a Hyprland from nothing")
	}
}

func swayReply(c net.Conn, kind uint32, body string) {
	head := make([]byte, 14)
	copy(head, "i3-ipc")
	binary.LittleEndian.PutUint32(head[6:], uint32(len(body)))
	binary.LittleEndian.PutUint32(head[10:], kind)
	c.Write(append(head, body...))
}

func TestSway(t *testing.T) {
	t.Parallel()
	path := filepath.Join(short(t), "sway.sock")
	listen(t, path, func(c net.Conn) {
		for {
			kind, body, err := swayRead(c)
			if err != nil {
				return
			}
			switch kind {
			case swayRunCommand:
				if string(body) == "bad" {
					swayReply(c, kind, `[{"success":false,"error":"Unknown command"}]`)
				} else {
					swayReply(c, kind, `[{"success":true}]`)
				}
			case swayGetBindingModes:
				swayReply(c, kind, `["default","axiom_layer"]`)
			case swaySubscribe:
				swayReply(c, kind, `{"success":true}`)
				swayReply(c, swayEventWorkspace, `{"change":"focus"}`)
				swayReply(c, swayEventWorkspace, `{"change":"reload"}`)
			}
		}
	})
	s := &Sway{Path: path}
	if r, err := s.Run(ctx(t), "kill"); err != nil || len(r) != 1 || !r[0].Success {
		t.Fatalf("run: %+v %v", r, err)
	}
	if r, _ := s.Run(ctx(t), "bad"); len(r) != 1 || r[0].Error != "Unknown command" {
		t.Fatalf("bad: %+v", r)
	}
	if modes, err := s.BindingModes(ctx(t)); err != nil || len(modes) != 2 || modes[1] != "axiom_layer" {
		t.Fatalf("modes: %v %v", modes, err)
	}
	out := make(chan Reload, 2)
	c, cancel := context.WithCancel(context.Background())
	defer cancel()
	go s.Reloads(c, out)
	select {
	case <-out:
	case <-time.After(testkit.Bound(3 * time.Second)):
		t.Fatal("no reload")
	}
	select {
	case <-out:
		t.Fatal("a focus change read as a reload")
	case <-time.After(100 * time.Millisecond):
	}
}

func TestNiri(t *testing.T) {
	t.Parallel()
	path := filepath.Join(short(t), "niri.sock")
	listen(t, path, func(c net.Conn) {
		line, _ := bufio.NewReader(c).ReadString('\n')
		switch {
		case line == "\"EventStream\"\n":
			io.WriteString(c, `{"Ok":"Handled"}`+"\n")
			io.WriteString(c, `{"ConfigLoaded":{"failed":false}}`+"\n")
			io.WriteString(c, `{"WorkspacesChanged":{}}`+"\n")
			io.WriteString(c, `{"ConfigLoaded":{"failed":true}}`+"\n")
			time.Sleep(3 * time.Second)
		case strings.Contains(line, "LoadConfigFile"):
			io.WriteString(c, `{"Ok":"Handled"}`+"\n")
		default:
			io.WriteString(c, `{"Err":"no"}`+"\n")
		}
	})
	n := &Niri{Path: path}
	if err := n.Action(ctx(t), map[string]any{"LoadConfigFile": map[string]any{"path": nil}}); err != nil {
		t.Fatal(err)
	}
	if err := n.Action(ctx(t), map[string]any{"Quit": map[string]any{}}); !errors.Is(err, ErrRefused) {
		t.Fatal("an Err read as Ok:", err)
	}
	out := make(chan Reload, 2)
	c, cancel := context.WithCancel(context.Background())
	defer cancel()
	go n.Reloads(c, out)
	// The stream's first ConfigLoaded is niri's state, not a reload
	select {
	case r := <-out:
		if !r.Failed {
			t.Fatal("the start state read as a reload")
		}
	case <-time.After(testkit.Bound(3 * time.Second)):
		t.Fatal("no reload")
	}
}

// Each compositor's version as a bug report shows it
func TestVersion(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name    string
		version func(ctx context.Context, dir string) (string, error)
		want    string
	}{
		{"Hyprland", func(ctx context.Context, dir string) (string, error) {
			listen(t, filepath.Join(dir, ".socket.sock"), func(c net.Conn) {
				buf := make([]byte, 64)
				if n, _ := c.Read(buf); string(buf[:n]) == "j/version" {
					io.WriteString(c, `{"branch":"main","commit":"efb50993780079460b0cbed1363e2166a2de1d9f","version":"0.55.0","tag":"v0.55.0-12"}`)
				}
			})
			return (&Hypr{Dir: dir}).Version(ctx)
		}, "Hyprland 0.55.0 (commit efb5099)"},
		{"niri", func(ctx context.Context, dir string) (string, error) {
			path := filepath.Join(dir, "niri.sock")
			listen(t, path, func(c net.Conn) {
				if line, _ := bufio.NewReader(c).ReadString('\n'); line == "\"Version\"\n" {
					io.WriteString(c, `{"Ok":{"Version":"26.04 (abc1234)"}}`+"\n")
				}
			})
			return (&Niri{Path: path}).Version(ctx)
		}, "niri 26.04 (abc1234)"},
		{"sway", func(ctx context.Context, dir string) (string, error) {
			path := filepath.Join(dir, "sway.sock")
			listen(t, path, func(c net.Conn) {
				if kind, _, err := swayRead(c); err == nil && kind == swayGetVersion {
					swayReply(c, kind, `{"human_readable":"1.12","major":1,"minor":12}`)
				}
			})
			return (&Sway{Path: path}).Version(ctx)
		}, "sway 1.12"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got, err := tc.version(ctx(t), short(t)); err != nil || got != tc.want {
				t.Errorf("Version = %q, %v; want %q", got, err, tc.want)
			}
		})
	}
}
