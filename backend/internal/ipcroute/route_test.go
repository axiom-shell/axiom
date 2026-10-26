package ipcroute

import (
	"context"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// shellConn is the daemon's end of a fake shell's connection, whose
// ipc.call answers with what it was asked
func shellConn(t *testing.T) *rpc.Conn {
	t.Helper()
	daemonSide, shellSide := net.Pipe()
	reg := rpc.NewRegistry()
	rpc.Handle(reg, "ipc.call", func(_ context.Context, _ *rpc.Conn, p map[string]any) (any, error) {
		if p["function"] == "fails" {
			return nil, axerr.New(axerr.NotFound, "no function fails")
		}
		raw, _ := json.Marshal(p["args"])
		return p["target"].(string) + "." + p["function"].(string) + string(raw), nil
	})
	shell := rpc.NewConn(shellSide, reg, rpc.DefaultLimits(), nil)
	daemon := rpc.NewConn(daemonSide, nil, rpc.DefaultLimits(), nil)
	t.Cleanup(func() { daemon.Close(); shell.Close() })
	return daemon
}

// fakeQS is a qs that prints its arguments, for the exec fallback
func fakeQS(t *testing.T) string {
	t.Helper()
	qs := filepath.Join(t.TempDir(), "qs")
	if err := os.WriteFile(qs, []byte("#!/bin/sh\necho \"exec $*\"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	return qs
}

var sigs = map[string][]Function{
	"osd":   {{Name: "show", Args: []Arg{{"value", "int"}, {"muted", "bool"}}}, {Name: "fails"}},
	"other": {{Name: "f"}},
}

// A registered target is called over the shell's connection, its text
// arguments typed by the declaration; anything else goes through
// `qs ipc --pid <shell> call`, as does everything once the connection is
// forgotten.
func TestCallRoutes(t *testing.T) {
	t.Parallel()
	conn := shellConn(t)
	r := New(Options{QS: fakeQS(t), ShellPID: func() int { return 42 }, Timeout: 5 * time.Second})
	if !r.RegisterNames(conn, r.Begin(), []string{"osd", "unknown"}, sigs) {
		t.Fatal("a registration was dropped")
	}
	if got := r.Targets(); len(got) != 1 || got[0].Name != "osd" {
		t.Errorf("targets %+v, want only osd (unknown has no signatures)", got)
	}
	ctx := context.Background()
	for _, c := range []struct {
		p    CallParams
		want string
		kind axerr.Kind
	}{
		{CallParams{Target: "osd", Function: "show", Args: []string{"5", "true"}}, `osd.show[5,true]`, ""},
		{CallParams{Target: "osd", Function: "show", Args: []string{"loud", "true"}}, "", axerr.BadRequest},
		{CallParams{Target: "osd", Function: "hide"}, "", axerr.NotFound},
		{CallParams{Target: "osd", Function: "fails"}, "", axerr.NotFound},
		{CallParams{Target: "other", Function: "f", Args: []string{"a b"}}, "exec ipc --pid 42 call other f a b", ""},
		{CallParams{Target: "osd"}, "", axerr.BadRequest},
	} {
		got, err := r.Call(ctx, c.p)
		ok := err == nil && got == c.want
		if c.kind != "" {
			ok = err != nil && axerr.KindOf(err) == c.kind
		}
		if !ok {
			t.Errorf("%+v: got %q, %v (kind %q), want %q (kind %q)", c.p, got, err, axerr.KindOf(err), c.want, c.kind)
		}
	}

	r.Forget(conn)
	if got, err := r.Call(ctx, CallParams{Target: "osd", Function: "show", Args: []string{"5", "true"}}); err != nil || got != "exec ipc --pid 42 call osd show 5 true" {
		t.Errorf("after Forget: %q, %v, want the exec fallback", got, err)
	}
}

// A disabled target says so rather than calling another screen's; with
// no shell running, the fallback is Unavailable
func TestCallWithoutAnAnsweringShell(t *testing.T) {
	t.Parallel()
	conn := shellConn(t)
	r := New(Options{QS: fakeQS(t), ShellPID: func() int { return 0 }})
	r.RegisterNames(conn, r.Begin(), []string{"osd"}, sigs)
	r.mu.Lock()
	osd := r.targets["osd"]
	osd.Enabled = false
	r.targets["osd"] = osd
	r.mu.Unlock()
	if _, err := r.Call(context.Background(), CallParams{Target: "osd", Function: "show", Args: []string{"1", "false"}}); axerr.KindOf(err) != axerr.Unavailable {
		t.Errorf("a disabled target: %v, want Unavailable", err)
	}
	if _, err := r.Call(context.Background(), CallParams{Target: "other", Function: "f"}); axerr.KindOf(err) != axerr.Unavailable {
		t.Errorf("no shell: %v, want Unavailable", err)
	}
	if _, err := r.Signatures(context.Background()); axerr.KindOf(err) != axerr.Unavailable {
		t.Errorf("signatures with no shell: %v, want Unavailable", err)
	}
}

// Registrations race while their signatures are read: only the latest
// begun lands, and none from a connection that closed meanwhile.
func TestRegistrationRace(t *testing.T) {
	t.Parallel()
	r := New(Options{})
	first, second := shellConn(t), shellConn(t)
	older, newer := r.Begin(), r.Begin()
	if !r.RegisterNames(second, newer, []string{"other"}, sigs) {
		t.Fatal("the latest registration was dropped")
	}
	if r.RegisterNames(first, older, []string{"osd"}, sigs) {
		t.Error("an older registration finishing late replaced the latest")
	}
	if got := r.Targets(); len(got) != 1 || got[0].Name != "other" {
		t.Errorf("targets %+v, want the latest's", got)
	}

	second.Close()
	<-second.Done()
	if r.RegisterNames(second, r.Begin(), []string{"osd"}, sigs) {
		t.Error("a closed connection registered")
	}
	// Forgetting a connection that isn't the shell's changes nothing
	r.Forget(first)
	if len(r.Targets()) != 1 {
		t.Error("forgetting another connection dropped the shell's targets")
	}
	r.Forget(second)
	if len(r.Targets()) != 0 {
		t.Error("the shell's targets outlived its connection")
	}
}
