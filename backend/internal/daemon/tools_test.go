package daemon

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// notify.send reaches the notification server on the session bus and,
// with buttons, answers the one picked
func TestNotifySend(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	server, err := dbus.Dial(ctx, bus.Address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	defer server.Close()
	if _, err := server.RequestName(ctx, "org.freedesktop.Notifications", dbus.NameDoNotQueue); err != nil {
		t.Fatal(err)
	}
	const path = dbus.ObjectPath("/org/freedesktop/Notifications")
	_, err = server.Export(path, dbus.Interface{Name: "org.freedesktop.Notifications", Methods: map[string]dbus.Method{
		"Notify": {In: "susssasa{sv}i", Out: "u", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			if actions, _ := m.Body[5].([]string); len(actions) > 0 {
				go server.Emit(path, "org.freedesktop.Notifications", "ActionInvoked", "us", uint32(1), actions[0])
			}
			return []any{uint32(1)}, nil
		}},
	}})
	if err != nil {
		t.Fatal(err)
	}

	td := newTestDaemon(t)
	td.env["DBUS_SESSION_BUS_ADDRESS"] = bus.Address
	td.start(t, nil)
	picks := make(chan notifyAction, 1)
	reg := rpc.NewRegistry()
	rpc.Handle(reg, "notify.action", func(_ context.Context, _ *rpc.Conn, a notifyAction) (struct{}, error) {
		picks <- a
		return struct{}{}, nil
	})
	c, err := rpc.Dial(ctx, td.socket, reg, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	if err := c.Call(ctx, "daemon.hello", map[string]any{"protocol": buildinfo.Protocol(), "client": "cli", "pid": os.Getpid()}, nil); err != nil {
		t.Fatal(err)
	}
	var result notifyResult
	if err := c.Call(ctx, "notify.send", map[string]any{"appName": "axiom", "summary": "s", "body": "b"}, &result); err != nil || result.ID != 1 {
		t.Fatalf("without buttons: %+v %v", result, err)
	}
	// With buttons it answers at once; the pick comes as notify.action
	params := map[string]any{"appName": "axiom", "summary": "s", "body": "b", "actions": []any{map[string]any{"id": "edit", "label": "Edit"}}}
	if err := c.Call(ctx, "notify.send", params, &result); err != nil || result.ID != 1 {
		t.Fatalf("with a button: %+v %v", result, err)
	}
	select {
	case a := <-picks:
		if a != (notifyAction{ID: 1, Action: "edit"}) {
			t.Fatalf("pushed %+v", a)
		}
	case <-ctx.Done():
		t.Fatal("no notify.action")
	}

	// No notification server on the bus: unavailable (once the bus has
	// seen it go: a call routed to it before then waits for no reply)
	server.Close()
	if !testkit.Eventually(func() bool { return bus.Owner("org.freedesktop.Notifications") == "" }) {
		t.Fatal("the bus never dropped the closed server")
	}
	if err := c.Call(ctx, "notify.send", map[string]any{"appName": "axiom", "summary": "s", "body": "b"}, nil); axerr.KindOf(err) != axerr.Unavailable {
		t.Fatalf("with no server: %v", err)
	}
}
