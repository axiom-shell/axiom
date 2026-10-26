// Package tailscale is Tailscale's state for the shell, the `tailscale`
// polled topic (`tailscale status --json` at the shortest interval a
// widget asks for, and only what the widgets and the popout show of it),
// and the `tailscale up` / `down` the popout's buttons run.
package tailscale

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os/exec"
	"reflect"
	"sort"
	"strings"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/topics"
)

// State is what the shell shows (TailscaleManager). Lists are never null.
type State struct {
	// Available: tailscale is installed
	Available bool `json:"available"`
	// BackendState is "Running", "Stopped", "NeedsLogin", … ("" unknown:
	// tailscaled isn't running)
	BackendState string `json:"backendState"`
	TailnetName  string `json:"tailnetName"`
	IP           string `json:"ip"` // this machine's first Tailscale address
	// Version is tailscaled's
	Version string `json:"version"`
	// HostName is this machine's OS host name; DNSName its MagicDNS name
	// (without the trailing dot)
	HostName string   `json:"hostName"`
	DNSName  string   `json:"dnsName"`
	IPs      []string `json:"ips"` // every Tailscale address of this machine
	// MagicDNSSuffix is the tailnet's DNS suffix ("" without MagicDNS)
	MagicDNSSuffix string `json:"magicDNSSuffix"`
	// AuthURL is where to log in, while a login waits for it
	AuthURL string `json:"authURL"`
	// Health is tailscaled's warnings, as it words them
	Health []string `json:"health"`
	// ExitNode is the name of the peer used as exit node ("" none)
	ExitNode string `json:"exitNode"`
	// Peers are the tailnet's other devices, online first, then by name
	Peers []Peer `json:"peers"`
}

// Peer is another device on the tailnet.
type Peer struct {
	// Name is its MagicDNS name's first label (its host name without one)
	Name    string   `json:"name"`
	DNSName string   `json:"dnsName"`
	OS      string   `json:"os"`
	IPs     []string `json:"ips"`
	Online  bool     `json:"online"`
	// Active: traffic flowed to it recently
	Active bool `json:"active"`
	// ExitNode: this machine routes through it; ExitNodeOption: it offers
	ExitNode       bool `json:"exitNode"`
	ExitNodeOption bool `json:"exitNodeOption"`
	// Relay is the DERP region its traffic goes through when not direct;
	// Direct: an active connection with a direct address
	Relay  string `json:"relay"`
	Direct bool   `json:"direct"`
	// LastSeen is when it was last online (RFC 3339), "" while it is or
	// never was
	LastSeen string `json:"lastSeen"`
	RxBytes  int64  `json:"rxBytes"`
	TxBytes  int64  `json:"txBytes"`
}

type statusNode struct {
	HostName       string
	DNSName        string
	OS             string
	TailscaleIPs   []string
	CurAddr        string
	Relay          string
	RxBytes        int64
	TxBytes        int64
	LastSeen       string
	Online         bool
	Active         bool
	ExitNode       bool
	ExitNodeOption bool
}

// Parse reads `tailscale status --json`. Output it can't read is a state
// unknown, as when tailscaled isn't running.
func Parse(out []byte) State {
	var status struct {
		Version        string
		BackendState   string
		AuthURL        string
		MagicDNSSuffix string
		Health         []string
		CurrentTailnet *struct{ Name string }
		Self           *statusNode
		Peer           map[string]statusNode
	}
	st := State{Available: true, IPs: []string{}, Health: []string{}, Peers: []Peer{}}
	if json.Unmarshal(out, &status) != nil {
		return st
	}
	st.BackendState = status.BackendState
	st.Version = status.Version
	st.AuthURL = status.AuthURL
	st.MagicDNSSuffix = status.MagicDNSSuffix
	if status.Health != nil {
		st.Health = status.Health
	}
	if status.CurrentTailnet != nil {
		st.TailnetName = status.CurrentTailnet.Name
	}
	if self := status.Self; self != nil {
		st.HostName = self.HostName
		st.DNSName = strings.TrimSuffix(self.DNSName, ".")
		if len(self.TailscaleIPs) > 0 {
			st.IPs = self.TailscaleIPs
			st.IP = self.TailscaleIPs[0]
		}
	}
	for _, n := range status.Peer {
		p := peer(n)
		if p.ExitNode {
			st.ExitNode = p.Name
		}
		st.Peers = append(st.Peers, p)
	}
	sort.Slice(st.Peers, func(i, j int) bool {
		a, b := st.Peers[i], st.Peers[j]
		if a.Online != b.Online {
			return a.Online
		}
		if la, lb := strings.ToLower(a.Name), strings.ToLower(b.Name); la != lb {
			return la < lb
		}
		return a.DNSName < b.DNSName
	})
	return st
}

func peer(n statusNode) Peer {
	dns := strings.TrimSuffix(n.DNSName, ".")
	name, _, _ := strings.Cut(dns, ".")
	if name == "" {
		name = n.HostName
	}
	p := Peer{
		Name: name, DNSName: dns, OS: n.OS, IPs: n.TailscaleIPs,
		Online: n.Online, Active: n.Active, ExitNode: n.ExitNode, ExitNodeOption: n.ExitNodeOption,
		Relay: n.Relay, Direct: n.Active && n.CurAddr != "",
		RxBytes: n.RxBytes, TxBytes: n.TxBytes,
	}
	if p.IPs == nil {
		p.IPs = []string{}
	}
	// tailscaled writes the zero time for a peer online now (or never seen)
	if t, err := time.Parse(time.RFC3339, n.LastSeen); err == nil && !t.IsZero() && !n.Online {
		p.LastSeen = n.LastSeen
	}
	return p
}

// Options are what the source and the actions run; zero values are the
// real ones.
type Options struct {
	LookPath func(file string) (string, error)
	// Status runs `tailscale status --json` and returns its stdout (its
	// exit status doesn't matter: a stopped tailscaled exits non-zero)
	Status func(ctx context.Context, bin string) []byte
	// Run runs `tailscale <args>` and returns its combined output
	Run func(ctx context.Context, bin string, args ...string) ([]byte, error)
	// UpTimeout bounds `tailscale up`, which waits for a login while one
	// is needed (15 s); the login link then shows in the state (AuthURL)
	UpTimeout time.Duration
}

func (o Options) withDefaults() Options {
	if o.LookPath == nil {
		o.LookPath = exec.LookPath
	}
	if o.Status == nil {
		o.Status = status
	}
	if o.Run == nil {
		o.Run = run
	}
	if o.UpTimeout == 0 {
		o.UpTimeout = 15 * time.Second
	}
	return o
}

// Source is the `tailscale` topic.
func Source(o Options) topics.Source {
	o = o.withDefaults()
	return topics.Source{
		Name:    "tailscale",
		Floor:   topics.MinInterval,
		Default: 10 * time.Second,
		Request: reflect.TypeFor[struct{}](),
		State:   reflect.TypeFor[State](),
		Fetch: func(ctx context.Context, _ []json.RawMessage) (any, error) {
			bin, err := o.LookPath("tailscale")
			if errors.Is(err, exec.ErrNotFound) {
				return State{IPs: []string{}, Health: []string{}, Peers: []Peer{}}, nil
			}
			if err != nil {
				return nil, err
			}
			return Parse(o.Status(ctx, bin)), nil
		},
	}
}

// Connect runs `tailscale up` (up: true) or `tailscale down`, with the
// node's saved settings. Changing them needs operator rights: without,
// the error is Refused and says how to grant them.
func Connect(ctx context.Context, o Options, up bool) error {
	o = o.withDefaults()
	bin, err := o.LookPath("tailscale")
	if err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "tailscale isn't installed")
	}
	verb := "down"
	if up {
		verb = "up"
	}
	runCtx, cancel := ctx, context.CancelFunc(func() {})
	if up {
		runCtx, cancel = context.WithTimeout(ctx, o.UpTimeout)
	}
	defer cancel()
	out, err := o.Run(runCtx, bin, verb)
	if err == nil {
		return nil
	}
	if up && ctx.Err() == nil && errors.Is(runCtx.Err(), context.DeadlineExceeded) {
		// still waiting for a login: the state carries its link
		return nil
	}
	msg := strings.TrimSpace(string(out))
	lower := strings.ToLower(msg)
	if strings.Contains(lower, "access denied") || strings.Contains(lower, "permission denied") {
		return axerr.Wrap(axerr.Refused, err, "tailscale %s: access denied: run `sudo tailscale set --operator=$USER` once to allow it", verb)
	}
	if msg == "" {
		return axerr.Wrap(axerr.Internal, err, "tailscale %s failed", verb)
	}
	return axerr.Wrap(axerr.Internal, err, "tailscale %s: %s", verb, msg)
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

func run(ctx context.Context, bin string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, bin, args...)
	cmd.WaitDelay = time.Second
	return cmd.CombinedOutput()
}
