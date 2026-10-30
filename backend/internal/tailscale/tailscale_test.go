package tailscale

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"reflect"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

func TestParse(t *testing.T) {
	t.Parallel()
	running, err := os.ReadFile("testdata/status.json")
	if err != nil {
		t.Fatal(err)
	}
	empty := State{Available: true, IPs: []string{}, Health: []string{}, Peers: []Peer{}}
	cases := []struct {
		name string
		out  string
		want State
	}{
		{"running", string(running), State{
			Available: true, BackendState: "Running", TailnetName: "example.ts.net", IP: "100.64.0.7",
			Version: "1.104.1", HostName: "laptop", DNSName: "laptop.example.ts.net",
			IPs: []string{"100.64.0.7", "fd7a:115c:a1e0::7"}, MagicDNSSuffix: "example.ts.net",
			Health:   []string{"Some peers are advertising routes but --accept-routes is false"},
			ExitNode: "nas", ExitNodeIP: "100.64.0.2",
			Account:   Account{LoginName: "me@example.com", DisplayName: "Me"},
			KeyExpiry: "2027-04-28T11:48:50Z",
			Peers: []Peer{
				// online first, by name whatever its case; relayed while active
				// without a direct address
				{Name: "Desktop", DNSName: "Desktop.example.ts.net", OS: "windows", IPs: []string{"100.64.0.3"},
					Online: true, Active: true, Relay: "ams", RxBytes: 512, TxBytes: 256},
				{Name: "nas", DNSName: "nas.example.ts.net", OS: "linux", IPs: []string{"100.64.0.2", "fd7a:115c:a1e0::2"},
					Online: true, Active: true, ExitNode: true, ExitNodeOption: true, Relay: "fra", Direct: true, RxBytes: 2048, TxBytes: 1024},
				{Name: "phone", DNSName: "phone.example.ts.net", OS: "android", IPs: []string{"100.64.0.9"},
					Relay: "fra", LastSeen: "2026-10-20T08:30:00Z"},
			},
		}},
		{"needs login", `{"BackendState": "NeedsLogin", "AuthURL": "https://login.example/a/1", "Self": {"TailscaleIPs": null}, "Health": null}`,
			State{Available: true, BackendState: "NeedsLogin", AuthURL: "https://login.example/a/1", IPs: []string{}, Health: []string{}, Peers: []Peer{}}},
		{"a peer without MagicDNS", `{"Peer": {"k": {"HostName": "box", "DNSName": "", "TailscaleIPs": null, "LastSeen": "never"}}}`,
			State{Available: true, IPs: []string{}, Health: []string{}, Peers: []Peer{{Name: "box", IPs: []string{}}}}},
		// tailscaled not running: an error on stderr, nothing on stdout
		{"no daemon", ``, empty},
		{"garbage", `{"BackendState": `, empty},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := Parse([]byte(tc.out)); !reflect.DeepEqual(got, tc.want) {
				t.Errorf("got %+v\nwant %+v", got, tc.want)
			}
		})
	}
}

func TestFetch(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name     string
		lookPath func(string) (string, error)
		want     State
		wantErr  bool
	}{
		{"not installed", func(string) (string, error) { return "", exec.ErrNotFound }, State{IPs: []string{}, Health: []string{}, Peers: []Peer{}}, false},
		{"installed", func(string) (string, error) { return "/usr/bin/tailscale", nil },
			State{Available: true, BackendState: "Stopped", IPs: []string{}, Health: []string{}, Peers: []Peer{}}, false},
		{"can't tell", func(string) (string, error) { return "", errors.New("permission denied") }, State{}, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			src := Source(Options{LookPath: tc.lookPath, Query: func(ctx context.Context, bin string, args ...string) ([]byte, []byte) {
				return []byte(`{"BackendState": "Stopped"}`), nil
			}})
			got, err := src.Fetch(context.Background(), nil)
			if (err != nil) != tc.wantErr {
				t.Fatalf("err %v", err)
			}
			if err == nil && !reflect.DeepEqual(got.(State), tc.want) {
				t.Errorf("got %+v, want %+v", got, tc.want)
			}
		})
	}
}

// Connect never runs the real tailscale: Run is a stub recording its
// arguments.
func TestConnect(t *testing.T) {
	t.Parallel()
	found := func(string) (string, error) { return "/usr/bin/tailscale", nil }
	cases := []struct {
		name     string
		up       bool
		lookPath func(string) (string, error)
		out      string
		err      error
		wantArgs []string
		wantKind axerr.Kind // "" for no error
	}{
		{"up", true, found, "", nil, []string{"up"}, ""},
		{"down", false, found, "", nil, []string{"down"}, ""},
		{"no operator", false, found, "Access denied: prefs write access denied\n\nUse 'sudo tailscale down'.", errors.New("exit status 1"), []string{"down"}, axerr.Refused},
		{"another failure", true, found, "backend error: boom", errors.New("exit status 1"), []string{"up"}, axerr.Internal},
		{"not installed", true, func(string) (string, error) { return "", exec.ErrNotFound }, "", nil, nil, axerr.Unavailable},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			var args []string
			o := Options{LookPath: tc.lookPath, Run: func(ctx context.Context, bin string, a ...string) ([]byte, error) {
				args = a
				return []byte(tc.out), tc.err
			}}
			err := Connect(context.Background(), o, tc.up)
			if !reflect.DeepEqual(args, tc.wantArgs) {
				t.Errorf("ran %v, want %v", args, tc.wantArgs)
			}
			if tc.wantKind == "" {
				if err != nil {
					t.Fatalf("err %v", err)
				}
				return
			}
			if axerr.KindOf(err) != tc.wantKind {
				t.Fatalf("err %v (kind %q), want kind %q", err, axerr.KindOf(err), tc.wantKind)
			}
		})
	}
}

// `tailscale up` waiting for a login past its timeout isn't a failure:
// the login link shows in the state instead. A cancelled caller is.
func TestConnectWaitingForLogin(t *testing.T) {
	t.Parallel()
	waits := func(cancel func()) Options {
		return Options{
			LookPath:  func(string) (string, error) { return "/usr/bin/tailscale", nil },
			UpTimeout: 10 * time.Millisecond,
			Run: func(runCtx context.Context, bin string, a ...string) ([]byte, error) {
				cancel()
				<-runCtx.Done()
				return nil, errors.New("signal: killed")
			},
		}
	}
	if err := Connect(context.Background(), waits(func() {}), true); err != nil {
		t.Errorf("timed out waiting for a login: %v, want no error", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	if err := Connect(ctx, waits(cancel), true); err == nil {
		t.Error("a cancelled up reported success")
	}
}

func TestParsePrefs(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name string
		out  string
		want Prefs
	}{
		{"read", `{"RouteAll": true, "CorpDNS": false, "ShieldsUp": true, "ExitNodeAllowLANAccess": true, "WantRunning": true}`,
			Prefs{Known: true, AcceptRoutes: true, ShieldsUp: true, ExitNodeAllowLAN: true}},
		// a shape it doesn't know: not guessed at
		{"no CorpDNS", `{"RouteAll": true}`, Prefs{}},
		{"garbage", `Access denied`, Prefs{}},
	}
	for _, tc := range cases {
		if got := ParsePrefs([]byte(tc.out)); got != tc.want {
			t.Errorf("%s: got %+v, want %+v", tc.name, got, tc.want)
		}
	}
}

func TestDetailsFetch(t *testing.T) {
	t.Parallel()
	profiles, err := os.ReadFile("testdata/profiles.json")
	if err != nil {
		t.Fatal(err)
	}
	found := func(string) (string, error) { return "/usr/bin/tailscale", nil }
	cases := []struct {
		name     string
		lookPath func(string) (string, error)
		profiles string
		stderr   string
		want     Details
	}{
		{"operator", found, string(profiles), "", Details{
			Prefs: Prefs{Known: true, AcceptDNS: true},
			Profiles: []Profile{
				{ID: "3a1b", Nickname: "", Tailnet: "example.ts.net", Account: "me@example.com", Selected: true},
				{ID: "7c2d", Nickname: "work", Tailnet: "work.example", Account: "me@work.example"},
			},
		}},
		{"no operator", found, "", "Access denied: profiles access denied\n\nUse 'sudo tailscale switch --list'.",
			Details{Prefs: Prefs{Known: true, AcceptDNS: true}, Profiles: []Profile{}, ProfilesDenied: true}},
		{"not installed", func(string) (string, error) { return "", exec.ErrNotFound }, "", "", Details{Profiles: []Profile{}}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			src := DetailsSource(Options{LookPath: tc.lookPath, Query: func(ctx context.Context, bin string, args ...string) ([]byte, []byte) {
				if args[0] == "debug" {
					return []byte(`{"RouteAll": false, "CorpDNS": true}`), nil
				}
				return []byte(tc.profiles), []byte(tc.stderr)
			}})
			got, err := src.Fetch(context.Background(), nil)
			if err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(got.(Details), tc.want) {
				t.Errorf("got %+v\nwant %+v", got, tc.want)
			}
		})
	}
}

func TestSetArgs(t *testing.T) {
	t.Parallel()
	str := func(s string) *string { return &s }
	yes, no := true, false
	cases := []struct {
		name string
		r    SetRequest
		want []string
	}{
		{"nothing", SetRequest{}, nil},
		{"exit node", SetRequest{ExitNode: str("100.64.0.2")}, []string{"set", "--exit-node=100.64.0.2"}},
		{"no exit node", SetRequest{ExitNode: str("")}, []string{"set", "--exit-node="}},
		// a value never reads as a flag of its own
		{"a flag as value", SetRequest{ExitNode: str("--ssh")}, []string{"set", "--exit-node=--ssh"}},
		{"switches", SetRequest{AcceptRoutes: &yes, AcceptDNS: &no, ShieldsUp: &yes, ExitNodeAllowLAN: &no},
			[]string{"set", "--exit-node-allow-lan-access=false", "--accept-routes=true", "--accept-dns=false", "--shields-up=true"}},
	}
	for _, tc := range cases {
		if got := tc.r.Args(); !reflect.DeepEqual(got, tc.want) {
			t.Errorf("%s: got %v, want %v", tc.name, got, tc.want)
		}
	}
}

// The actions never run the real tailscale or pkexec: Run is a stub
// recording what it ran.
func TestActions(t *testing.T) {
	t.Parallel()
	found := func(f string) (string, error) { return "/usr/bin/" + f, nil }
	denied := "Access denied: prefs write access denied"
	yes := true
	cases := []struct {
		name     string
		act      func(Options) error
		out      string
		err      error
		wantRun  []string
		wantKind axerr.Kind
	}{
		{"switch", func(o Options) error { return Switch(context.Background(), o, "7c2d") }, "", nil,
			[]string{"/usr/bin/tailscale", "switch", "7c2d"}, ""},
		{"switch to a flag", func(o Options) error { return Switch(context.Background(), o, "--help") }, "", nil, nil, axerr.BadRequest},
		{"switch refused", func(o Options) error { return Switch(context.Background(), o, "7c2d") }, denied, errors.New("exit status 1"),
			[]string{"/usr/bin/tailscale", "switch", "7c2d"}, axerr.Refused},
		{"login", func(o Options) error { return Login(context.Background(), o) }, "", nil, []string{"/usr/bin/tailscale", "login"}, ""},
		{"set", func(o Options) error { return Set(context.Background(), o, SetRequest{ShieldsUp: &yes}) }, "", nil,
			[]string{"/usr/bin/tailscale", "set", "--shields-up=true"}, ""},
		{"set refused", func(o Options) error { return Set(context.Background(), o, SetRequest{ShieldsUp: &yes}) }, denied, errors.New("exit status 1"),
			[]string{"/usr/bin/tailscale", "set", "--shields-up=true"}, axerr.Refused},
		{"set nothing", func(o Options) error { return Set(context.Background(), o, SetRequest{}) }, "", nil, nil, axerr.BadRequest},
		{"grant", func(o Options) error { return GrantOperator(context.Background(), o, "me") }, "", nil,
			[]string{"/usr/bin/pkexec", "/usr/bin/tailscale", "set", "--operator=me"}, ""},
		{"grant to a flag", func(o Options) error { return GrantOperator(context.Background(), o, "-x") }, "", nil, nil, axerr.BadRequest},
		{"grant fails", func(o Options) error { return GrantOperator(context.Background(), o, "me") }, "boom", errors.New("exit status 1"),
			[]string{"/usr/bin/pkexec", "/usr/bin/tailscale", "set", "--operator=me"}, axerr.Internal},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			var ran []string
			o := Options{LookPath: found, Run: func(ctx context.Context, bin string, a ...string) ([]byte, error) {
				ran = append([]string{bin}, a...)
				return []byte(tc.out), tc.err
			}}
			err := tc.act(o)
			if !reflect.DeepEqual(ran, tc.wantRun) {
				t.Errorf("ran %v, want %v", ran, tc.wantRun)
			}
			if axerr.KindOf(err) != tc.wantKind && !(tc.wantKind == "" && err == nil) {
				t.Errorf("err %v (kind %q), want kind %q", err, axerr.KindOf(err), tc.wantKind)
			}
		})
	}
}

// pkexec dismissed (126) or failed authentication (127) is Unauthorized.
func TestGrantOperatorDismissed(t *testing.T) {
	t.Parallel()
	exitErr := exec.Command("sh", "-c", "exit 126").Run()
	o := Options{
		LookPath: func(f string) (string, error) { return "/usr/bin/" + f, nil },
		Run:      func(context.Context, string, ...string) ([]byte, error) { return nil, exitErr },
	}
	if err := GrantOperator(context.Background(), o, "me"); axerr.KindOf(err) != axerr.Unauthorized {
		t.Errorf("err %v (kind %q), want unauthorized", err, axerr.KindOf(err))
	}
}
