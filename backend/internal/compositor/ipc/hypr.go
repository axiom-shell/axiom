package ipc

import (
	"bufio"
	"context"
	"encoding/json"
	"io"
	"path/filepath"
	"strings"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// Hypr is a Hyprland instance's sockets: one request per connection on
// .socket.sock (Hyprland answers and closes), events on .socket2.sock.
type Hypr struct {
	Dir string // $XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE
}

// HyprFromEnv is the Hyprland instance the environment names, or nil.
func HyprFromEnv(getenv func(string) string) *Hypr {
	sig := getenv("HYPRLAND_INSTANCE_SIGNATURE")
	if sig == "" || getenv("XDG_RUNTIME_DIR") == "" {
		return nil
	}
	return &Hypr{Dir: filepath.Join(getenv("XDG_RUNTIME_DIR"), "hypr", sig)}
}

// Request sends one request ("reload", "j/binds", "eval …") and returns the
// reply.
func (h *Hypr) Request(ctx context.Context, command string) (string, error) {
	conn, err := dial(ctx, filepath.Join(h.Dir, ".socket.sock"))
	if err != nil {
		return "", err
	}
	defer conn.Close()
	if _, err := io.WriteString(conn, command); err != nil {
		return "", err
	}
	reply, err := io.ReadAll(conn)
	if err != nil && len(reply) == 0 {
		return "", err
	}
	return string(reply), nil
}

// JSON sends "j/<command>" and parses the reply.
func (h *Hypr) JSON(ctx context.Context, command string) (any, error) {
	reply, err := h.Request(ctx, "j/"+command)
	if err != nil {
		return nil, err
	}
	return jsonx.Unmarshal([]byte(reply))
}

// Outputs lists Hyprland's monitors ("monitors all"), disabled ones too,
// with the description Hyprland gives the shell.
func (h *Hypr) Outputs(ctx context.Context) ([]render.Output, error) {
	reply, err := h.Request(ctx, "j/monitors all")
	if err != nil {
		return nil, err
	}
	var out []render.Output
	if err := json.Unmarshal([]byte(reply), &out); err != nil {
		return nil, err
	}
	return out, nil
}

// Version is Hyprland's version as people read it ("Hyprland 0.55.0").
func (h *Hypr) Version(ctx context.Context) (string, error) {
	reply, err := h.Request(ctx, "j/version")
	if err != nil {
		return "", err
	}
	var v struct{ Version, Tag string }
	if err := json.Unmarshal([]byte(reply), &v); err != nil {
		return "", err
	}
	if v.Version == "" {
		v.Version = strings.TrimPrefix(v.Tag, "v")
	}
	return "Hyprland " + v.Version, nil
}

// Eval runs Lua in Hyprland's config state: "" when it ran, else Hyprland's
// error.
func (h *Hypr) Eval(ctx context.Context, lua string) (string, error) {
	reply, err := h.Request(ctx, "eval "+lua)
	if err != nil {
		return "", err
	}
	if reply = strings.TrimSpace(reply); reply == "ok" {
		return "", nil
	}
	if reply == "" {
		reply = "no reply"
	}
	return reply, nil
}

// Reloads streams Hyprland's config reloads (configreloaded events) until
// ctx ends or the socket closes.
func (h *Hypr) Reloads(ctx context.Context, out chan<- Reload) error {
	conn, err := dial(context.Background(), filepath.Join(h.Dir, ".socket2.sock"))
	if err != nil {
		return err
	}
	conn.SetDeadline(time.Time{})
	defer conn.Close()
	// Closing the connection is what ends a read blocked on it
	defer context.AfterFunc(ctx, func() { conn.Close() })()
	lines := bufio.NewScanner(conn)
	lines.Buffer(make([]byte, 64*1024), 1024*1024)
	for lines.Scan() {
		if name, _, _ := strings.Cut(lines.Text(), ">>"); name == "configreloaded" {
			select {
			case out <- Reload{}:
			case <-ctx.Done():
				return nil
			}
		}
	}
	if ctx.Err() != nil {
		return nil
	}
	return lines.Err()
}
