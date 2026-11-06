package cli

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/daemon"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/screenshare"
)

// fakePicker is a daemon answering screenshare.pick with answer (or
// failing with err), keeping what it was asked.
type fakePicker struct {
	mu     sync.Mutex
	asked  map[string]any
	answer pickResult
	err    error
}

func (f *fakePicker) serve(t *testing.T) string {
	t.Helper()
	dir, err := os.MkdirTemp("", "ax") // short: a sockaddr_un
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	sock := filepath.Join(dir, "s.sock")
	ln, err := rpc.Listen(sock)
	if err != nil {
		t.Fatal(err)
	}
	reg := rpc.NewRegistry()
	rpc.Handle(reg, "daemon.hello", func(context.Context, *rpc.Conn, daemon.HelloParams) (daemon.HelloResult, error) {
		return daemon.HelloResult{}, nil
	})
	rpc.Handle(reg, "screenshare.pick", func(_ context.Context, _ *rpc.Conn, p map[string]any) (pickResult, error) {
		f.mu.Lock()
		defer f.mu.Unlock()
		f.asked = p
		return f.answer, f.err
	})
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	go (&rpc.Server{Registry: reg}).Serve(ctx, ln)
	return sock
}

func runPick(t *testing.T, sock string, env map[string]string, stdin string, args ...string) (string, int) {
	t.Helper()
	var out, errs bytes.Buffer
	e := &Env{Stdin: strings.NewReader(stdin), Stdout: &out, Stderr: &errs, Getenv: func(k string) string { return env[k] }}
	e.Globals.Socket = sock
	if picker := xdphPickerArgs(args, e.Getenv); picker != nil {
		args = picker
	}
	code := Run(context.Background(), Root(), args, e)
	return out.String(), code
}

var xdphEnv = map[string]string{
	screenshare.XDPHOutputsVar: "4:DP-1:0:0:2560:1440;",
	screenshare.XDPHWindowsVar: "12[HC>]kitty[HT>]Terminal[HE>]0[HA>]",
}

func TestPickXDPH(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name   string
		args   []string
		answer pickResult
		want   string
	}{
		{"a screen kept", nil, pickResult{Status: "picked", Choice: &screenshare.Choice{Kind: screenshare.KindScreen, Output: "DP-1"}, Remember: true}, "[SELECTION]r/screen:DP-1\n"},
		{"a window", nil, pickResult{Status: "picked", Choice: &screenshare.Choice{Kind: screenshare.KindWindow, Window: "12"}}, "[SELECTION]/window:12\n"},
		{"xdph lets it keep", []string{"--allow-token"}, pickResult{Status: "picked", Choice: &screenshare.Choice{Kind: screenshare.KindScreen, Output: "DP-1"}}, "[SELECTION]r/screen:DP-1\n"},
		{"cancelled", nil, pickResult{Status: "cancelled"}, ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			f := &fakePicker{answer: tc.answer}
			out, code := runPick(t, f.serve(t), xdphEnv, "", tc.args...)
			if code != 0 || out != tc.want {
				t.Errorf("got %q (exit %d), want %q", out, code, tc.want)
			}
			f.mu.Lock()
			defer f.mu.Unlock()
			if f.asked["backend"] != screenshare.BackendXDPH || f.asked["region"] != true {
				t.Errorf("asked %+v", f.asked)
			}
		})
	}
}

func TestPickXDPW(t *testing.T) {
	t.Parallel()
	lines := "Monitor: DP-1 Dell\nWindow: Terminal (3f2a)\n"
	cases := []struct {
		answer pickResult
		want   string
	}{
		{pickResult{Status: "picked", Choice: &screenshare.Choice{Kind: screenshare.KindScreen, Output: "DP-1"}}, "Monitor: DP-1 Dell\n"},
		{pickResult{Status: "picked", Choice: &screenshare.Choice{Kind: screenshare.KindWindow, Window: "3f2a"}}, "Window: Terminal (3f2a)\n"},
		{pickResult{Status: "cancelled"}, ""},
	}
	for _, tc := range cases {
		f := &fakePicker{answer: tc.answer}
		out, code := runPick(t, f.serve(t), nil, lines, screenSharePickName, "--for", "xdpw")
		if code != 0 || out != tc.want {
			t.Errorf("%+v: got %q (exit %d), want %q", tc.answer, out, code, tc.want)
		}
		f.mu.Lock()
		if f.asked["backend"] != screenshare.BackendXDPW || !reflect.DeepEqual(f.asked["outputs"], []any{map[string]any{"name": "DP-1", "label": "Dell"}}) {
			t.Errorf("asked %+v", f.asked)
		}
		f.mu.Unlock()
	}
}

// Off, or no axiom: hyprland-share-picker answers
func TestPickXDPHFallback(t *testing.T) {
	bin := t.TempDir()
	script := "#!/bin/sh\necho \"[SELECTION]/screen:stock $*\"\n"
	if err := os.WriteFile(filepath.Join(bin, "hyprland-share-picker"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+":/usr/bin:/bin")
	off := &fakePicker{answer: pickResult{Status: "off"}}
	if out, code := runPick(t, off.serve(t), xdphEnv, "", "--allow-token"); code != 0 || out != "[SELECTION]/screen:stock --allow-token\n" {
		t.Errorf("off: %q (exit %d)", out, code)
	}
	gone := &fakePicker{err: axerr.New(axerr.Unavailable, "no shell to show the picker")}
	if out, code := runPick(t, gone.serve(t), xdphEnv, ""); code != 0 || out != "[SELECTION]/screen:stock \n" {
		t.Errorf("no shell: %q (exit %d)", out, code)
	}
}

func TestPickNeedsAPortal(t *testing.T) {
	t.Parallel()
	if _, code := runPick(t, (&fakePicker{}).serve(t), nil, "", screenSharePickName); code != axerr.ExitCode(axerr.New(axerr.BadRequest, "")) {
		t.Errorf("exit %d", code)
	}
	// Without xdph's environment, no command is a usage error, not a pick
	if xdphPickerArgs(nil, func(string) string { return "" }) != nil {
		t.Error("taken for xdph's picker")
	}
}
