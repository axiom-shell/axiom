package ipc

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"
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

// Reloads streams niri's config loads (ConfigLoaded events, Failed when niri
// couldn't load it) until ctx ends or the socket closes. The stream's first
// ConfigLoaded is the state niri starts it with, not a reload: it's left
// out.
func (n *Niri) Reloads(ctx context.Context, out chan<- Reload) error {
	started := false
	return n.Events(ctx, nil, func(line []byte) {
		var event struct {
			ConfigLoaded *struct {
				Failed bool `json:"failed"`
			} `json:"ConfigLoaded"`
		}
		if json.Unmarshal(line, &event) != nil || event.ConfigLoaded == nil {
			return
		}
		if !started {
			started = true
			return
		}
		select {
		case out <- Reload{Failed: event.ConfigLoaded.Failed}:
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
