package ipcroute

import (
	"context"
	"encoding/json"
	"net"
	"testing"

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

var targets = []Target{
	{Name: "osd", Functions: []Function{{Name: "show", Args: 2}, {Name: "fails"}}},
}

// A registered target is called over the shell's connection with the
// command line's text; anything else is refused, and everything once the
// connection is forgotten.
func TestCallRoutes(t *testing.T) {
	t.Parallel()
	conn := shellConn(t)
	r := New(Options{})
	ctx := context.Background()
	if _, err := r.Call(ctx, CallParams{Target: "osd", Function: "show"}); axerr.KindOf(err) != axerr.Unavailable {
		t.Errorf("before a registration: %v, want Unavailable", err)
	}
	if !r.Register(conn, targets) {
		t.Fatal("a registration was dropped")
	}
	for _, c := range []struct {
		p    CallParams
		want string
		kind axerr.Kind
	}{
		{CallParams{Target: "osd", Function: "show", Args: []string{"5", "a b"}}, `osd.show["5","a b"]`, ""},
		{CallParams{Target: "osd", Function: "fails"}, "", axerr.NotFound},
		{CallParams{Target: "osd", Function: "show", Args: []string{"5"}}, "", axerr.BadRequest},
		{CallParams{Target: "osd", Function: "hide"}, "", axerr.NotFound},
		{CallParams{Target: "other", Function: "f"}, "", axerr.NotFound},
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
	if _, err := r.Call(ctx, CallParams{Target: "osd", Function: "fails"}); axerr.KindOf(err) != axerr.Unavailable {
		t.Errorf("after Forget: %v, want Unavailable", err)
	}
}

// A later registration replaces the last, none lands from a connection
// that closed, and only the shell's connection forgets its targets.
func TestRegistrations(t *testing.T) {
	t.Parallel()
	r := New(Options{})
	first, second := shellConn(t), shellConn(t)
	r.Register(first, targets)
	if !r.Register(second, []Target{{Name: "other"}}) {
		t.Fatal("the latest registration was dropped")
	}
	if got := r.Targets(); len(got) != 1 || got[0].Name != "other" {
		t.Errorf("targets %+v, want the latest's", got)
	}
	r.Forget(first)
	if len(r.Targets()) != 1 {
		t.Error("forgetting another connection dropped the shell's targets")
	}
	second.Close()
	<-second.Done()
	if r.Register(second, targets) {
		t.Error("a closed connection registered")
	}
	r.Forget(second)
	if len(r.Targets()) != 0 {
		t.Error("the shell's targets outlived its connection")
	}
}
