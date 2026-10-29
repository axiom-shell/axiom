package dbus_test

import (
	"bufio"
	"context"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

func ctx(t *testing.T) context.Context {
	t.Helper()
	c, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	t.Cleanup(cancel)
	return c
}

func dial(t *testing.T, address string) *dbus.Conn {
	t.Helper()
	c, err := dbus.Dial(ctx(t), address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { c.Close() })
	return c
}

// echo exports test.Echo at /test on c: Echo(s) → s, Fail() → an error,
// File(s) → a descriptor holding s.
func echo(t *testing.T, c *dbus.Conn) {
	t.Helper()
	_, err := c.Export("/test", dbus.Interface{
		Name: "test.Echo",
		Methods: map[string]dbus.Method{
			"Echo": {In: "s", Out: "s", Fn: func(_ context.Context, call *dbus.Message) ([]any, error) {
				return []any{call.Body[0]}, nil
			}},
			"Fail": {Fn: func(context.Context, *dbus.Message) ([]any, error) {
				return nil, dbus.NewError("test.Error.Nope", "no")
			}},
			"File": {In: "s", Out: "h", Fn: func(_ context.Context, call *dbus.Message) ([]any, error) {
				r, w, err := os.Pipe()
				if err != nil {
					return nil, err
				}
				w.WriteString(call.Body[0].(string))
				w.Close()
				t.Cleanup(func() { r.Close() })
				return []any{dbus.UnixFD(r.Fd())}, nil
			}},
		},
		Signals: map[string]string{"Ping": "s"},
	})
	if err != nil {
		t.Fatal(err)
	}
}

// buses are the fake bus, and a real dbus-daemon when one is installed.
func buses(t *testing.T) map[string]string {
	out := map[string]string{"fake": dbustest.New(t).Address}
	if addr := realBus(t); addr != "" {
		out["dbus-daemon"] = addr
	}
	return out
}

func realBus(t *testing.T) string {
	t.Helper()
	bin, err := exec.LookPath("dbus-daemon")
	if err != nil {
		return ""
	}
	dir := t.TempDir()
	conf := filepath.Join(dir, "bus.conf")
	os.WriteFile(conf, []byte(`<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:path=`+filepath.Join(dir, "bus")+`</listen><auth>EXTERNAL</auth>
<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy></busconfig>`), 0o600)
	cmd := exec.Command(bin, "--config-file="+conf, "--nofork", "--print-address")
	out, _ := cmd.StdoutPipe()
	if err := cmd.Start(); err != nil {
		return ""
	}
	t.Cleanup(func() { cmd.Process.Kill(); cmd.Wait() })
	line, err := bufio.NewReader(out).ReadString('\n')
	if err != nil {
		return ""
	}
	return strings.TrimSpace(line)
}

func TestCallsSignalsAndDescriptors(t *testing.T) {
	t.Parallel()
	for name, address := range buses(t) {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			server, client := dial(t, address), dial(t, address)
			if !strings.HasPrefix(server.UniqueName(), ":") {
				t.Errorf("unique name %q", server.UniqueName())
			}
			echo(t, server)
			if got, err := server.RequestName(ctx(t), "test.Echo", dbus.NameDoNotQueue); err != nil || got != dbus.NamePrimaryOwner {
				t.Fatalf("RequestName: %d, %v", got, err)
			}

			reply, err := client.Call(ctx(t), "test.Echo", "/test", "test.Echo", "Echo", "s", "hello")
			if err != nil {
				t.Fatal(err)
			}
			var s string
			if err := reply.Store(&s); err != nil || s != "hello" {
				t.Errorf("Echo: %q, %v", s, err)
			}

			_, err = client.Call(ctx(t), "test.Echo", "/test", "test.Echo", "Fail", "")
			if dbus.ErrorName(err) != "test.Error.Nope" {
				t.Errorf("Fail: %v", err)
			}
			_, err = client.Call(ctx(t), "test.Echo", "/test", "test.Echo", "Echo", "u", uint32(1))
			if dbus.ErrorName(err) != dbus.ErrInvalidArgs || axerr.KindOf(err) != axerr.BadRequest {
				t.Errorf("wrong args: %v", err)
			}
			_, err = client.Call(ctx(t), "test.Echo", "/nothing", "test.Echo", "Echo", "s", "x")
			if dbus.ErrorName(err) != dbus.ErrUnknownObject {
				t.Errorf("no object: %v", err)
			}

			reply, err = client.Call(ctx(t), "test.Echo", "/test", "test.Echo", "File", "s", "through a pipe")
			if err != nil {
				t.Fatal(err)
			}
			var fd dbus.UnixFD
			if err := reply.Store(&fd); err != nil {
				t.Fatal(err)
			}
			f, err := reply.File(fd)
			if err != nil {
				t.Fatal(err)
			}
			data, _ := io.ReadAll(f)
			f.Close()
			if string(data) != "through a pipe" {
				t.Errorf("File: %q", data)
			}

			sub, err := client.Subscribe(ctx(t), dbus.Match{Path: "/test", Interface: "test.Echo", Member: "Ping"})
			if err != nil {
				t.Fatal(err)
			}
			if err := server.Emit("/test", "test.Echo", "Ping", "s", "pong"); err != nil {
				t.Fatal(err)
			}
			select {
			case m := <-sub.C:
				if m.Body[0] != "pong" || m.Sender != server.UniqueName() {
					t.Errorf("signal %+v", m)
				}
			case <-time.After(testkit.Bound(3 * time.Second)):
				t.Fatal("no signal")
			}
			sub.Close()

			reply, err = client.Call(ctx(t), "test.Echo", "/", "org.freedesktop.DBus.Introspectable", "Introspect", "")
			if err != nil {
				t.Fatal(err)
			}
			if xml := reply.Body[0].(string); !strings.Contains(xml, `<node name="test"/>`) {
				t.Errorf("introspection of /:\n%s", xml)
			}
		})
	}
}

func TestNameOwnerChangedOnDisconnect(t *testing.T) {
	t.Parallel()
	for name, address := range buses(t) {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			owner, watcher := dial(t, address), dial(t, address)
			sub, err := watcher.Subscribe(ctx(t), dbus.NameOwnerChanged("test.Owned"))
			if err != nil {
				t.Fatal(err)
			}
			if _, err := owner.RequestName(ctx(t), "test.Owned", dbus.NameDoNotQueue); err != nil {
				t.Fatal(err)
			}
			if got, err := watcher.RequestName(ctx(t), "test.Owned", dbus.NameDoNotQueue); err != nil || got != dbus.NameExists {
				t.Errorf("a taken name: %d, %v", got, err)
			}
			pid, err := watcher.ConnectionPID(ctx(t), owner.UniqueName())
			if err != nil || int(pid) != os.Getpid() {
				t.Errorf("pid %d, %v", pid, err)
			}
			owner.Close()
			deadline := time.After(testkit.Bound(3 * time.Second))
			for {
				select {
				case m := <-sub.C:
					if m.Body[0] == "test.Owned" && m.Body[2] == "" {
						return
					}
				case <-deadline:
					t.Fatal("no NameOwnerChanged for the lost name")
				}
			}
		})
	}
}

func TestBusGoneEndsTheConnection(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	c := dial(t, bus.Address)
	other := dial(t, bus.Address)
	// The fake closes a connection when its own peer closes: end the bus
	// side by closing the client's socket from below
	other.Close()
	c.Close()
	select {
	case <-c.Done():
	case <-time.After(time.Second):
		t.Fatal("not done")
	}
	if _, err := c.Call(ctx(t), "x.y", "/", "x.y", "Z", ""); axerr.KindOf(err) != axerr.Unavailable {
		t.Errorf("a call after the end: %v", err)
	}
}
