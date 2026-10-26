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
			ExitNode: "nas",
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
			src := Source(Options{LookPath: tc.lookPath, Status: func(ctx context.Context, bin string) []byte {
				return []byte(`{"BackendState": "Stopped"}`)
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
