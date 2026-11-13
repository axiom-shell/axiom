package ipc

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"slices"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
)

// Niri is a niri instance's socket ($NIRI_SOCKET): one JSON request per
// line, one reply ({"Ok": …} or {"Err": …}) per request.
type Niri struct {
	Path string
}

// NiriFromEnv is the niri the environment names, or nil.
func NiriFromEnv(getenv func(string) string) *Niri {
	if p := getenv("NIRI_SOCKET"); p != "" {
		return &Niri{Path: p}
	}
	return nil
}

// ErrRefused: niri answered a request with an Err.
var ErrRefused = errors.New("niri refused it")

// Request sends one request (a JSON value) and returns the reply's Ok.
func (n *Niri) Request(ctx context.Context, request any) (json.RawMessage, error) {
	ok, err := n.request(ctx, request)
	return ok, ctxErr(ctx, err)
}

func (n *Niri) request(ctx context.Context, request any) (json.RawMessage, error) {
	conn, err := dial(ctx, n.Path)
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	data, err := json.Marshal(request)
	if err != nil {
		return nil, err
	}
	if _, err := conn.Write(append(data, '\n')); err != nil {
		return nil, err
	}
	line, err := bufio.NewReader(conn).ReadBytes('\n')
	// A cancel or deadline mid-reply leaves a partial line: that is ctx's error
	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	if err != nil && len(line) == 0 {
		return nil, err
	}
	var reply struct {
		Ok  json.RawMessage `json:"Ok"`
		Err *string         `json:"Err"`
	}
	if err := json.Unmarshal(line, &reply); err != nil {
		return nil, err
	}
	if reply.Err != nil {
		return nil, fmt.Errorf("%w: %s", ErrRefused, *reply.Err)
	}
	return reply.Ok, nil
}

// Action runs an action ({"LoadConfigFile": {…}}).
func (n *Niri) Action(ctx context.Context, action any) error {
	_, err := n.Request(ctx, map[string]any{"Action": action})
	return err
}

// Outputs lists niri's outputs (the Outputs request), disabled ones (no
// logical output) too, by name.
func (n *Niri) Outputs(ctx context.Context) ([]render.Output, error) {
	ok, err := n.Request(ctx, "Outputs")
	if err != nil {
		return nil, err
	}
	var reply struct {
		Outputs map[string]struct {
			Make, Model, Serial string
			Logical             *struct{}
		}
	}
	if err := json.Unmarshal(ok, &reply); err != nil {
		return nil, err
	}
	var out []render.Output
	for _, name := range slices.Sorted(maps.Keys(reply.Outputs)) {
		o := reply.Outputs[name]
		out = append(out, render.Output{Name: name, Description: describe(o.Make, o.Model, o.Serial), Disabled: o.Logical == nil})
	}
	return out, nil
}

// NiriWindow is one of niri's windows (the Windows request).
type NiriWindow struct {
	ID          uint64      `json:"id"`
	Title       string      `json:"title"`
	AppID       string      `json:"app_id"`
	PID         int         `json:"pid"`          // 0 when niri doesn't know it (null)
	WorkspaceID *uint64     `json:"workspace_id"` // nil for a window on no workspace
	Focused     bool        `json:"is_focused"`
	Floating    bool        `json:"is_floating"`
	Layout      *NiriLayout `json:"layout"`
}

// NiriLayout is where niri puts a window: TileSize is the tile's size in
// logical pixels ([width, height]), which tells a fullscreen tile (niri
// 26.04 has no fullscreen field).
type NiriLayout struct {
	TileSize []float64 `json:"tile_size"`
}

// Windows lists niri's windows.
func (n *Niri) Windows(ctx context.Context) ([]NiriWindow, error) {
	ok, err := n.Request(ctx, "Windows")
	if err != nil {
		return nil, err
	}
	var reply struct{ Windows []NiriWindow }
	if err := json.Unmarshal(ok, &reply); err != nil {
		return nil, err
	}
	return reply.Windows, nil
}

// Version is niri's version as people read it ("niri 26.04 (abc1234)").
func (n *Niri) Version(ctx context.Context) (string, error) {
	ok, err := n.Request(ctx, "Version")
	if err != nil {
		return "", err
	}
	var reply struct{ Version string }
	if err := json.Unmarshal(ok, &reply); err != nil {
		return "", err
	}
	return "niri " + reply.Version, nil
}

// Reloads streams niri's config loads (ConfigLoaded events, Failed when niri
// couldn't load it) until ctx ends or the socket closes. The stream's first
// ConfigLoaded is the state niri starts it with, not a reload: Initial.
func (n *Niri) Reloads(ctx context.Context, out chan<- Reload) error {
	initial := true
	return n.Events(ctx, nil, func(line []byte) {
		var event struct {
			ConfigLoaded *struct {
				Failed bool `json:"failed"`
			} `json:"ConfigLoaded"`
		}
		if json.Unmarshal(line, &event) != nil || event.ConfigLoaded == nil {
			return
		}
		r := Reload{Failed: event.ConfigLoaded.Failed, Initial: initial}
		initial = false
		select {
		case out <- r:
		case <-ctx.Done():
		}
	})
}

// Events reads niri's event stream until ctx ends (nil) or the socket
// closes: started once it's connected, then event with each event's line
// ({"WindowFocusChanged": {…}}; the reply to the request itself left out),
// which starts with niri's full state. A line is only valid during its
// call.
func (n *Niri) Events(ctx context.Context, started func(), event func(line []byte)) error {
	conn, err := dial(context.Background(), n.Path)
	if err != nil {
		return err
	}
	defer conn.Close()
	// Closing the connection is what ends a read blocked on it
	defer context.AfterFunc(ctx, func() { conn.Close() })()
	if _, err := conn.Write([]byte("\"EventStream\"\n")); err != nil {
		return err
	}
	conn.SetDeadline(time.Time{})
	if started != nil {
		started()
	}
	lines := bufio.NewScanner(conn)
	lines.Buffer(make([]byte, 64*1024), 16*1024*1024)
	first := true
	for lines.Scan() {
		if first {
			first = false
			var reply struct {
				Ok, Err json.RawMessage
			}
			if json.Unmarshal(lines.Bytes(), &reply) == nil && (reply.Ok != nil || reply.Err != nil) {
				continue
			}
		}
		event(lines.Bytes())
		if ctx.Err() != nil {
			return nil
		}
	}
	if ctx.Err() != nil {
		return nil
	}
	return lines.Err()
}
