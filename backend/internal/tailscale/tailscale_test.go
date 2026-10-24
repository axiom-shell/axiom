package tailscale

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"testing"
)

func TestParse(t *testing.T) {
	t.Parallel()
	running, err := os.ReadFile("testdata/status.json")
	if err != nil {
		t.Fatal(err)
	}
	cases := []struct {
		name string
		out  string
		want State
	}{
		{"running", string(running), State{Available: true, BackendState: "Running", TailnetName: "example.ts.net", IP: "100.64.0.7"}},
		{"logged out", `{"BackendState": "NeedsLogin", "Self": {"TailscaleIPs": null}}`, State{Available: true, BackendState: "NeedsLogin"}},
		// tailscaled not running: an error on stderr, nothing on stdout
		{"no daemon", ``, State{Available: true}},
		{"garbage", `{"BackendState": `, State{Available: true}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := Parse([]byte(tc.out)); got != tc.want {
				t.Errorf("got %+v, want %+v", got, tc.want)
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
		{"not installed", func(string) (string, error) { return "", exec.ErrNotFound }, State{}, false},
		{"installed", func(string) (string, error) { return "/usr/bin/tailscale", nil }, State{Available: true, BackendState: "Stopped"}, false},
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
			if err == nil && got.(State) != tc.want {
				t.Errorf("got %+v, want %+v", got, tc.want)
			}
		})
	}
}
