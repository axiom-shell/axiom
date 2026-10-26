// Package tailscale is Tailscale's state for the shell, the `tailscale`
// polled topic: `tailscale status --json` at the shortest interval a
// widget asks for, and only what the widgets show of it.
package tailscale

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os/exec"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/topics"
)

// State is what the shell shows (TailscaleManager).
type State struct {
	// Available: tailscale is installed
	Available bool `json:"available"`
	// BackendState is "Running", "Stopped", "NeedsLogin", … ("" unknown:
	// tailscaled isn't running)
	BackendState string `json:"backendState"`
	TailnetName  string `json:"tailnetName"`
	IP           string `json:"ip"` // this machine's first Tailscale address
}

// Parse reads `tailscale status --json`. Output it can't read is a state
// unknown, as when tailscaled isn't running.
func Parse(out []byte) State {
	var status struct {
		BackendState   string
		CurrentTailnet *struct{ Name string }
		Self           *struct{ TailscaleIPs []string }
	}
	st := State{Available: true}
	if json.Unmarshal(out, &status) != nil {
		return st
	}
	st.BackendState = status.BackendState
	if status.CurrentTailnet != nil {
		st.TailnetName = status.CurrentTailnet.Name
	}
	if status.Self != nil && len(status.Self.TailscaleIPs) > 0 {
		st.IP = status.Self.TailscaleIPs[0]
	}
	return st
}

// Options are what the source runs; zero values are the real ones.
type Options struct {
	LookPath func(file string) (string, error)
	// Status runs `tailscale status --json` and returns its stdout (its
	// exit status doesn't matter: a stopped tailscaled exits non-zero)
	Status func(ctx context.Context, bin string) []byte
}

// Source is the `tailscale` topic.
func Source(o Options) topics.Source {
	if o.LookPath == nil {
		o.LookPath = exec.LookPath
	}
	if o.Status == nil {
		o.Status = status
	}
	return topics.Source{
		Name:    "tailscale",
		Floor:   topics.MinInterval,
		Default: 10 * time.Second,
		Fetch: func(ctx context.Context, _ []json.RawMessage) (any, error) {
			bin, err := o.LookPath("tailscale")
			if errors.Is(err, exec.ErrNotFound) {
				return State{}, nil
			}
			if err != nil {
				return nil, err
			}
			return Parse(o.Status(ctx, bin)), nil
		},
	}
}

func status(ctx context.Context, bin string) []byte {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	var out bytes.Buffer
	cmd := exec.CommandContext(ctx, bin, "status", "--json")
	cmd.Stdout = &out
	cmd.WaitDelay = time.Second
	cmd.Run()
	return out.Bytes()
}
