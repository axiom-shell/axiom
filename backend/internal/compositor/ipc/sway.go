package ipc

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"time"
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
	swayGetBindingModes = 8
	swayEventWorkspace  = 0x80000000
)

const swayMagic = "i3-ipc"

func swayWrite(conn net.Conn, kind uint32, payload []byte) error {
	head := make([]byte, 14)
	copy(head, swayMagic)
	binary.LittleEndian.PutUint32(head[6:], uint32(len(payload)))
	binary.LittleEndian.PutUint32(head[10:], kind)
	if _, err := conn.Write(append(head, payload...)); err != nil {
		return err
	}
	return nil
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

// Reloads streams sway's config reloads (workspace events whose change is
// "reload") until ctx ends or the socket closes.
func (s *Sway) Reloads(ctx context.Context, out chan<- Reload) error {
	conn, err := dial(context.Background(), s.Path)
	if err != nil {
		return err
	}
	defer conn.Close()
	// Closing the connection is what ends a read blocked on it
	defer context.AfterFunc(ctx, func() { conn.Close() })()
	if err := swayWrite(conn, swaySubscribe, []byte(`["workspace"]`)); err != nil {
		return err
	}
	conn.SetDeadline(time.Time{})
	for {
		kind, body, err := swayRead(conn)
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			return err
		}
		if kind != swayEventWorkspace {
			continue
		}
		var event struct {
			Change string `json:"change"`
		}
		if json.Unmarshal(body, &event) == nil && event.Change == "reload" {
			select {
			case out <- Reload{}:
			case <-ctx.Done():
				return nil
			}
		}
	}
}
