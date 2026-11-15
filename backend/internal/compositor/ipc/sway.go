package ipc

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
)

// Sway is a sway instance's IPC socket ($SWAYSOCK, i3's protocol).
type Sway struct {
	Path string
}

// SwayFromEnv is the sway the environment names, or nil.
func SwayFromEnv(getenv func(string) string) *Sway {
	if p := getenv("SWAYSOCK"); p != "" {
		return &Sway{Path: p}
	}
	return nil
}

// i3 IPC message types
const (
	swayRunCommand      = 0
	swaySubscribe       = 2
	swayGetOutputs      = 3
	swayGetTree         = 4
	swayGetVersion      = 7
	swayGetBindingModes = 8
)

// i3 IPC event types (the high bit marks an event)
const (
	swayEventBit       = 0x80000000
	SwayEventWorkspace = swayEventBit
	SwayEventWindow    = swayEventBit | 3
)

const swayMagic = "i3-ipc"

func swayWrite(conn net.Conn, kind uint32, payload []byte) error {
	head := make([]byte, 14)
	copy(head, swayMagic)
	binary.LittleEndian.PutUint32(head[6:], uint32(len(payload)))
	binary.LittleEndian.PutUint32(head[10:], kind)
	_, err := conn.Write(append(head, payload...))
	return err
}

func swayRead(conn net.Conn) (uint32, []byte, error) {
	head := make([]byte, 14)
	if _, err := io.ReadFull(conn, head); err != nil {
		return 0, nil, err
	}
	if string(head[:6]) != swayMagic {
		return 0, nil, fmt.Errorf("sway: not an i3-ipc reply")
	}
	size := binary.LittleEndian.Uint32(head[6:])
	if size > 64<<20 {
		return 0, nil, fmt.Errorf("sway: a %d byte reply", size)
	}
	body := make([]byte, size)
	if _, err := io.ReadFull(conn, body); err != nil {
		return 0, nil, err
	}
	return binary.LittleEndian.Uint32(head[10:]), body, nil
}

func (s *Sway) request(ctx context.Context, kind uint32, payload string, reply any) error {
	return ctxErr(ctx, s.roundTrip(ctx, kind, payload, reply))
}

func (s *Sway) roundTrip(ctx context.Context, kind uint32, payload string, reply any) error {
	conn, err := dial(ctx, s.Path)
	if err != nil {
		return err
	}
	defer conn.Close()
	if err := swayWrite(conn, kind, []byte(payload)); err != nil {
		return err
	}
	_, body, err := swayRead(conn)
	if err != nil {
		return err
	}
	return json.Unmarshal(body, reply)
}

// SwayResult is one command's outcome.
type SwayResult struct {
	Success bool   `json:"success"`
	Error   string `json:"error"`
}

// Run runs a command list (`;` or `,` between commands); one result per
// command sway ran (it stops at an invalid one).
func (s *Sway) Run(ctx context.Context, commands string) ([]SwayResult, error) {
	if commands == "" {
		return nil, nil
	}
	var out []SwayResult
	err := s.request(ctx, swayRunCommand, commands, &out)
	return out, err
}

// BindingModes lists the binding modes sway's config defines.
func (s *Sway) BindingModes(ctx context.Context) ([]string, error) {
	var out []string
	err := s.request(ctx, swayGetBindingModes, "", &out)
	return out, err
}

// Outputs lists sway's outputs (GET_OUTPUTS), disabled ones too.
func (s *Sway) Outputs(ctx context.Context) ([]render.Output, error) {
	var reply []struct {
		Name                string
		Make, Model, Serial string
		Active              *bool
	}
	if err := s.request(ctx, swayGetOutputs, "", &reply); err != nil {
		return nil, err
	}
	out := make([]render.Output, len(reply))
	for i, o := range reply {
		out[i] = render.Output{Name: o.Name, Description: describe(o.Make, o.Model, o.Serial), Disabled: o.Active != nil && !*o.Active}
	}
	return out, nil
}

// Version is sway's version as people read it ("sway 1.12").
func (s *Sway) Version(ctx context.Context) (string, error) {
	var reply struct {
		HumanReadable string `json:"human_readable"`
	}
	if err := s.request(ctx, swayGetVersion, "", &reply); err != nil {
		return "", err
	}
	return "sway " + reply.HumanReadable, nil
}

// Tree is sway's container tree (GET_TREE), as sway sent it.
func (s *Sway) Tree(ctx context.Context) (json.RawMessage, error) {
	var out json.RawMessage
	err := s.request(ctx, swayGetTree, "", &out)
	return out, err
}

// Reloads streams sway's config reloads (workspace events whose change is
// "reload") until ctx ends or the socket closes.
func (s *Sway) Reloads(ctx context.Context, out chan<- Reload) error {
	return s.Events(ctx, []string{"workspace"}, nil, func(kind uint32, body []byte) {
		if kind != SwayEventWorkspace {
			return
		}
		var event struct {
			Change string `json:"change"`
		}
		if json.Unmarshal(body, &event) == nil && event.Change == "reload" {
			select {
			case out <- Reload{}:
			case <-ctx.Done():
			}
		}
	})
}

// Events subscribes to the event kinds ("window", "workspace", …) and reads
// them until ctx ends (nil) or the socket closes: started once sway has
// accepted the subscription (an error if it refuses), then event with each event's type and body (a
// body is only valid during its call).
func (s *Sway) Events(ctx context.Context, kinds []string, started func(), event func(kind uint32, body []byte)) error {
	conn, err := dial(context.Background(), s.Path)
	if err != nil {
		return err
	}
	defer conn.Close()
	// Closing the connection is what ends a read blocked on it
	defer context.AfterFunc(ctx, func() { conn.Close() })()
	subscribe, err := json.Marshal(kinds)
	if err != nil {
		return err
	}
	if err := swayWrite(conn, swaySubscribe, subscribe); err != nil {
		return err
	}
	// The reply comes before any event, inside dial's deadline
	_, reply, err := swayRead(conn)
	if err != nil {
		if ctx.Err() != nil {
			return nil
		}
		return err
	}
	var ok struct{ Success bool }
	if json.Unmarshal(reply, &ok) != nil || !ok.Success {
		return fmt.Errorf("sway: subscribe refused: %s", reply)
	}
	conn.SetDeadline(time.Time{})
	if started != nil {
		started()
	}
	for {
		kind, body, err := swayRead(conn)
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			return err
		}
		// The reply to the subscription is a plain type, not an event
		if kind&swayEventBit == 0 {
			continue
		}
		event(kind, body)
		if ctx.Err() != nil {
			return nil
		}
	}
}
