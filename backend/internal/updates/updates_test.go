package updates

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"os/exec"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestParse(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name, format, out string
		want              []Package
	}{
		{"pacman", "pacman", "linux 6.9.1.arch1-1 -> 6.9.2.arch1-1\nnot an update line\n  mesa 1:24.1-1 -> 1:24.2-1  \n", []Package{
			{"linux", "6.9.1.arch1-1", "6.9.2.arch1-1"},
			{"mesa", "1:24.1-1", "1:24.2-1"},
		}},
		// dnf5's `check-update --quiet`, as Fedora 44 prints it (plus dnf4's
		// obsoletes block, whose installed rows are skipped)
		{"dnf", "dnf", "Upgrades\n" +
			"ca-certificates.noarch             2026.2.90_v9.0.317-1.fc44 updates\n" +
			"elfutils-default-yama-scope.noarch 0.196-1.fc44              updates\n" +
			"glib2.x86_64                       2.88.4-1.fc44             updates\n" +
			"Obsoleting packages\n" +
			"grub2-tools.x86_64                 1:2.12-30.fc44            updates\n" +
			"    grub2-tools-efi.x86_64         1:2.12-28.fc44            @updates\n", []Package{
			{"ca-certificates", "", "2026.2.90_v9.0.317-1.fc44"},
			{"elfutils-default-yama-scope", "", "0.196-1.fc44"},
			{"glib2", "", "2.88.4-1.fc44"},
			{"grub2-tools", "", "1:2.12-30.fc44"},
		}},
		{"no output", "pacman", "", []Package{}},
		{"unknown format", "unknown", "a 1 -> 2", []Package{}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := Parse(tc.format, []byte(tc.out)); !reflect.DeepEqual(got, tc.want) {
				t.Errorf("got %+v, want %+v", got, tc.want)
			}
		})
	}
}

var arch = `{"check": {"command": ["checkupdates", "--nocolor"], "found": [0], "none": [2], "format": "pacman"}`

func TestFetch(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name      string
		requests  []string
		installed []string
		code      int
		want      State
		wantRuns  []string
	}{
		{"unsupported", []string{`{"interval": 60000}`}, nil, 0, State{Repo: []Package{}, AUR: []Package{}}, nil},
		{"updates", []string{arch + `}`}, []string{"checkupdates"}, 0,
			State{Repo: []Package{{"a", "1", "2"}}, AUR: []Package{}}, []string{"checkupdates --nocolor"}},
		{"none", []string{arch + `}`}, []string{"checkupdates"}, 2,
			State{Repo: []Package{{"a", "1", "2"}}, AUR: []Package{}}, []string{"checkupdates --nocolor"}},
		{"failed", []string{arch + `}`}, []string{"checkupdates"}, 1,
			State{Repo: []Package{}, AUR: []Package{}, Error: "checkupdates failed (1): db locked"}, []string{"checkupdates --nocolor"}},
		{"not installed", []string{arch + `}`}, nil, 0,
			State{Repo: []Package{}, AUR: []Package{}, Error: "checkupdates: executable file not found in $PATH"}, nil},
		// Any subscriber asking for the AUR has it checked
		{"aur", []string{arch + `}`, arch + `, "aurHelper": "paru"}`}, []string{"checkupdates", "paru"}, 0,
			State{Repo: []Package{{"a", "1", "2"}}, AUR: []Package{{"a", "1", "2"}}}, []string{"checkupdates --nocolor", "paru -Qua"}},
		{"aur helper missing", []string{arch + `, "aurHelper": "yay"}`}, []string{"checkupdates"}, 0,
			State{Repo: []Package{{"a", "1", "2"}}, AUR: []Package{}}, []string{"checkupdates --nocolor"}},
		// Never a path or shell text
		{"aur helper not a name", []string{arch + `, "aurHelper": "/tmp/x; rm"}`}, []string{"checkupdates"}, 0,
			State{Repo: []Package{{"a", "1", "2"}}, AUR: []Package{}}, []string{"checkupdates --nocolor"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			var runs []string
			src := Source(Options{
				Now: func() time.Time { return time.UnixMilli(1000) },
				LookPath: func(file string) (string, error) {
					for _, c := range tc.installed {
						if c == file {
							return file, nil
						}
					}
					return "", exec.ErrNotFound
				},
				Run: func(ctx context.Context, bin string, args ...string) ([]byte, int, string) {
					runs = append(runs, strings.Join(append([]string{bin}, args...), " "))
					return []byte("a 1 -> 2\n"), tc.code, "db locked"
				},
			})
			var requests []json.RawMessage
			for _, r := range tc.requests {
				requests = append(requests, json.RawMessage(r))
			}
			got, err := src.Fetch(context.Background(), requests)
			tc.want.At = 1000
			if err != nil {
				t.Fatal(err)
			} else if !reflect.DeepEqual(got, tc.want) {
				t.Errorf("got %+v, want %+v", got, tc.want)
			}
			if !reflect.DeepEqual(runs, tc.wantRuns) {
				t.Errorf("ran %q, want %q", runs, tc.wantRuns)
			}
		})
	}
}

// A failed check keeps the packages the last one found
func TestFetchKeepsLastOnFailure(t *testing.T) {
	t.Parallel()
	code := 0
	src := Source(Options{
		LookPath: func(file string) (string, error) { return file, nil },
		Run: func(ctx context.Context, bin string, args ...string) ([]byte, int, string) {
			return []byte("a 1 -> 2\n"), code, "offline"
		},
	})
	requests := []json.RawMessage{json.RawMessage(arch + `}`)}
	if _, err := src.Fetch(context.Background(), requests); err != nil {
		t.Fatal(err)
	}
	code = 1
	got, _ := src.Fetch(context.Background(), requests)
	if st := got.(State); len(st.Repo) != 1 || st.Error == "" {
		t.Errorf("got %+v, want the last packages and an error", st)
	}
}

// A check killed by its context ending (a re-exec) is no failure: no
// warning, and nothing replaces the last state
func TestFetchCancelledIsQuiet(t *testing.T) {
	t.Parallel()
	var logged bytes.Buffer
	ctx, cancel := context.WithCancel(context.Background())
	src := Source(Options{
		Log:      slog.New(slog.NewTextHandler(&logged, nil)),
		LookPath: func(file string) (string, error) { return file, nil },
		Run: func(ctx context.Context, bin string, args ...string) ([]byte, int, string) {
			cancel()
			return nil, -1, ""
		},
	})
	if _, err := src.Fetch(ctx, []json.RawMessage{json.RawMessage(arch + `}`)}); err == nil {
		t.Error("a cancelled fetch returned no error")
	}
	if logged.Len() > 0 {
		t.Errorf("logged %q, want nothing", logged.String())
	}
}
