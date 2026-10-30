// Package tailscale is Tailscale's state for the shell: the `tailscale`
// polled topic (`tailscale status --json` at the shortest interval a
// widget asks for, and only what the widgets and the popout show of it),
// the `tailscaledetails` topic the popout adds (the node's prefs and the
// accounts logged in), and the actions its controls run (`up`, `down`,
// `switch`, `login`, `set`, and granting operator rights through pkexec).
package tailscale

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os/exec"
	"reflect"
	"sort"
	"strconv"
	"strings"
	"sync"
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
	// ExitNode is the name of the peer used as exit node ("" none), and
	// ExitNodeIP its first address
	ExitNode   string `json:"exitNode"`
	ExitNodeIP string `json:"exitNodeIP"`
	// Account is who this machine is logged in as
	Account Account `json:"account"`
	// KeyExpiry is when this machine's node key expires (RFC 3339), ""
	// when it never does
	KeyExpiry string `json:"keyExpiry"`
	// Peers are the tailnet's other devices, online first, then by name
	Peers []Peer `json:"peers"`
}

// Account is a Tailscale user ("" fields when unknown).
type Account struct {
	LoginName   string `json:"loginName"`
	DisplayName string `json:"displayName"`
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
	UserID         int64
	KeyExpiry      string
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
		User           map[string]Account
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
		st.Account = status.User[strconv.FormatInt(self.UserID, 10)]
		if t, err := time.Parse(time.RFC3339, self.KeyExpiry); err == nil && !t.IsZero() {
			st.KeyExpiry = self.KeyExpiry
		}
	}
	for _, n := range status.Peer {
		p := peer(n)
		if p.ExitNode {
			st.ExitNode = p.Name
			if len(p.IPs) > 0 {
				st.ExitNodeIP = p.IPs[0]
			}
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

// Details is what the popout adds to State: the node's prefs its
// switches show, and the accounts logged in on this machine. Profiles is
// never null.
type Details struct {
	Prefs    Prefs     `json:"prefs"`
	Profiles []Profile `json:"profiles"`
	// ProfilesDenied: listing the accounts needs operator rights, which
	// this user doesn't have
	ProfilesDenied bool `json:"profilesDenied"`
}

// Prefs are the node's settings the popout switches (`tailscale set`).
type Prefs struct {
	// Known: `tailscale debug prefs` was read (it isn't a stable
	// interface: the switches hide when it can't be)
	Known            bool `json:"known"`
	AcceptRoutes     bool `json:"acceptRoutes"`
	AcceptDNS        bool `json:"acceptDNS"`
	ShieldsUp        bool `json:"shieldsUp"`
	ExitNodeAllowLAN bool `json:"exitNodeAllowLAN"`
}

// Profile is an account logged in on this machine (`tailscale switch
// --list --json`).
type Profile struct {
	ID       string `json:"id"`
	Nickname string `json:"nickname"`
	Tailnet  string `json:"tailnet"`
	Account  string `json:"account"`
	Selected bool   `json:"selected"`
}

// ParsePrefs reads `tailscale debug prefs`; output it can't read is
// prefs unknown.
func ParsePrefs(out []byte) Prefs {
	var p struct {
		RouteAll, ShieldsUp, ExitNodeAllowLANAccess bool
		CorpDNS                                     *bool
	}
	if json.Unmarshal(out, &p) != nil || p.CorpDNS == nil {
		return Prefs{}
	}
	return Prefs{Known: true, AcceptRoutes: p.RouteAll, AcceptDNS: *p.CorpDNS, ShieldsUp: p.ShieldsUp, ExitNodeAllowLAN: p.ExitNodeAllowLANAccess}
}

// ParseProfiles reads `tailscale switch --list --json`; output it can't
// read is no accounts.
func ParseProfiles(out []byte) []Profile {
	var ps []Profile
	if json.Unmarshal(out, &ps) != nil || ps == nil {
		return []Profile{}
	}
	return ps
}

// Options are what the sources and the actions run; zero values are the
// real ones.
type Options struct {
	LookPath func(file string) (string, error)
	// Query runs a read-only `tailscale <args>` (at most 5 s) and returns
	// its stdout and stderr (its exit status doesn't matter: a stopped
	// tailscaled exits non-zero, and a refusal says so on stderr)
	Query func(ctx context.Context, bin string, args ...string) (stdout, stderr []byte)
	// Run runs `<bin> <args>` (tailscale, or pkexec) and returns its
	// combined output
	Run func(ctx context.Context, bin string, args ...string) ([]byte, error)
	// UpTimeout bounds `tailscale up` and `login`, which wait for a login
	// while one is needed (15 s); the login link then shows in the state
	// (AuthURL)
	UpTimeout time.Duration
}

func (o Options) withDefaults() Options {
	if o.LookPath == nil {
		o.LookPath = exec.LookPath
	}
	if o.Query == nil {
		o.Query = query
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
			out, _ := o.Query(ctx, bin, "status", "--json")
			return Parse(out), nil
		},
	}
}

// DetailsSource is the `tailscaledetails` topic: `tailscale debug prefs`
// and `switch --list --json`, read together, only while the popout or a
// module shows them.
func DetailsSource(o Options) topics.Source {
	o = o.withDefaults()
	return topics.Source{
		Name:    "tailscaledetails",
		Floor:   topics.MinInterval,
		Default: 10 * time.Second,
		Request: reflect.TypeFor[struct{}](),
		State:   reflect.TypeFor[Details](),
		Fetch: func(ctx context.Context, _ []json.RawMessage) (any, error) {
			d := Details{Profiles: []Profile{}}
			bin, err := o.LookPath("tailscale")
			if errors.Is(err, exec.ErrNotFound) {
				return d, nil
			}
			if err != nil {
				return nil, err
			}
			var wg sync.WaitGroup
			var prefs, profiles, profilesErr []byte
			wg.Go(func() { prefs, _ = o.Query(ctx, bin, "debug", "prefs") })
			wg.Go(func() { profiles, profilesErr = o.Query(ctx, bin, "switch", "--list", "--json") })
			wg.Wait()
			d.Prefs = ParsePrefs(prefs)
			d.Profiles = ParseProfiles(profiles)
			d.ProfilesDenied = deniedText(string(profilesErr))
			return d, nil
		},
	}
}

// Connect runs `tailscale up` (up: true) or `tailscale down`, with the
// node's saved settings. Changing them needs operator rights: without,
// the error is Refused and says how to grant them.
func Connect(ctx context.Context, o Options, up bool) error {
	if up {
		return cli(ctx, o, true, "up")
	}
	return cli(ctx, o, false, "down")
}

// Login runs `tailscale login`: a new account beside the ones logged in,
// whose login link then shows in the state.
func Login(ctx context.Context, o Options) error {
	return cli(ctx, o, true, "login")
}

// Switch runs `tailscale switch <id>`, to an account of `switch --list`.
func Switch(ctx context.Context, o Options, id string) error {
	if id == "" || strings.HasPrefix(id, "-") {
		return axerr.New(axerr.BadRequest, "tailscale switch: no account id %q", id)
	}
	return cli(ctx, o, false, "switch", id)
}

// SetRequest is what `tailscale set` changes: only the fields given.
// ExitNode is a peer's address, or "" for none.
type SetRequest struct {
	ExitNode         *string `json:"exitNode,omitempty"`
	ExitNodeAllowLAN *bool   `json:"exitNodeAllowLAN,omitempty"`
	AcceptRoutes     *bool   `json:"acceptRoutes,omitempty"`
	AcceptDNS        *bool   `json:"acceptDNS,omitempty"`
	ShieldsUp        *bool   `json:"shieldsUp,omitempty"`
}

// Args are the `tailscale set` arguments for r, each `--flag=value` so
// no value reads as a flag (nil with nothing to change).
func (r SetRequest) Args() []string {
	var args []string
	if r.ExitNode != nil {
		args = append(args, "--exit-node="+*r.ExitNode)
	}
	for _, f := range []struct {
		flag string
		v    *bool
	}{
		{"exit-node-allow-lan-access", r.ExitNodeAllowLAN},
		{"accept-routes", r.AcceptRoutes},
		{"accept-dns", r.AcceptDNS},
		{"shields-up", r.ShieldsUp},
	} {
		if f.v != nil {
			args = append(args, "--"+f.flag+"="+strconv.FormatBool(*f.v))
		}
	}
	if args == nil {
		return nil
	}
	return append([]string{"set"}, args...)
}

// Set runs `tailscale set` with what r changes, never `up` with flags
// (which resets every setting it isn't given).
func Set(ctx context.Context, o Options, r SetRequest) error {
	args := r.Args()
	if args == nil {
		return axerr.New(axerr.BadRequest, "tailscale set: nothing to change")
	}
	return cli(ctx, o, false, args...)
}

// GrantOperator runs `pkexec tailscale set --operator=<user>`: polkit
// asks for an administrator's password (axiom's agent, or the session's),
// after which user runs every action without it. Dismissed or refused,
// the error is Unauthorized.
func GrantOperator(ctx context.Context, o Options, user string) error {
	o = o.withDefaults()
	if user == "" || strings.HasPrefix(user, "-") {
		return axerr.New(axerr.BadRequest, "tailscale operator: no user name %q", user)
	}
	bin, err := o.LookPath("tailscale")
	if err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "tailscale isn't installed")
	}
	pkexec, err := o.LookPath("pkexec")
	if err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "pkexec isn't installed")
	}
	out, err := o.Run(ctx, pkexec, bin, "set", "--operator="+user)
	if err == nil {
		return nil
	}
	// pkexec exits 126 when the dialog was dismissed, 127 when not
	// authorized (authentication failed, or polkit refused)
	if exit := (*exec.ExitError)(nil); errors.As(err, &exit) && (exit.ExitCode() == 126 || exit.ExitCode() == 127) {
		return axerr.Wrap(axerr.Unauthorized, err, "tailscale operator: not authorized")
	}
	if msg := strings.TrimSpace(string(out)); msg != "" {
		return axerr.Wrap(axerr.Internal, err, "tailscale operator: %s", msg)
	}
	return axerr.Wrap(axerr.Internal, err, "tailscale operator failed")
}

// cli runs `tailscale <args>`. waits: it may wait for a login (up,
// login), so it's cut off after UpTimeout, which isn't a failure: the
// login link shows in the state. Without operator rights the error is
// Refused and says how to grant them.
func cli(ctx context.Context, o Options, waits bool, args ...string) error {
	o = o.withDefaults()
	bin, err := o.LookPath("tailscale")
	if err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "tailscale isn't installed")
	}
	verb := args[0]
	runCtx, cancel := ctx, context.CancelFunc(func() {})
	if waits {
		runCtx, cancel = context.WithTimeout(ctx, o.UpTimeout)
	}
	defer cancel()
	out, err := o.Run(runCtx, bin, args...)
	if err == nil {
		return nil
	}
	if waits && ctx.Err() == nil && errors.Is(runCtx.Err(), context.DeadlineExceeded) {
		// still waiting for a login: the state carries its link
		return nil
	}
	msg := strings.TrimSpace(string(out))
	if deniedText(msg) {
		return axerr.Wrap(axerr.Refused, err, "tailscale %s: access denied: run `sudo tailscale set --operator=$USER` once to allow it", verb)
	}
	if msg == "" {
		return axerr.Wrap(axerr.Internal, err, "tailscale %s failed", verb)
	}
	return axerr.Wrap(axerr.Internal, err, "tailscale %s: %s", verb, msg)
}

// deniedText: tailscaled refused for want of operator rights.
func deniedText(msg string) bool {
	lower := strings.ToLower(msg)
	return strings.Contains(lower, "access denied") || strings.Contains(lower, "permission denied")
}

func query(ctx context.Context, bin string, args ...string) (stdout, stderr []byte) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	var out, errOut bytes.Buffer
	cmd := exec.CommandContext(ctx, bin, args...)
	cmd.Stdout = &out
	cmd.Stderr = &errOut
	cmd.WaitDelay = time.Second
	cmd.Run()
	return out.Bytes(), errOut.Bytes()
}

func run(ctx context.Context, bin string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, bin, args...)
	cmd.WaitDelay = time.Second
	return cmd.CombinedOutput()
}
