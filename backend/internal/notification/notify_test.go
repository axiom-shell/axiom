package notification

import (
	"context"
	"reflect"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
)

func testCtx(t *testing.T) context.Context {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	t.Cleanup(cancel)
	return ctx
}

func dial(t *testing.T, bus *dbustest.Bus) *dbus.Conn {
	t.Helper()
	conn, err := dbus.Dial(testCtx(t), bus.Address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	return conn
}

// fakeServer answers Notify with id 7, hands each call's body to calls,
// then sends the signals after (a signal's member and its second
// argument; another id first, which Send must skip).
func fakeServer(t *testing.T, bus *dbustest.Bus, after ...[2]any) chan []any {
	t.Helper()
	calls := make(chan []any, 1)
	conn := dial(t, bus)
	if _, err := conn.RequestName(testCtx(t), busName, dbus.NameDoNotQueue); err != nil {
		t.Fatal(err)
	}
	_, err := conn.Export(path, dbus.Interface{Name: iface, Methods: map[string]dbus.Method{
		"Notify": {In: "susssasa{sv}i", Out: "u", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			calls <- m.Body
			go func() {
				for _, s := range after {
					sig := "us"
					if s[0] == "NotificationClosed" {
						sig = "uu"
					}
					_ = conn.Emit(path, iface, s[0].(string), sig, uint32(3), s[1])
					_ = conn.Emit(path, iface, s[0].(string), sig, uint32(7), s[1])
				}
			}()
			return []any{uint32(7)}, nil
		}},
	}})
	if err != nil {
		t.Fatal(err)
	}
	return calls
}

func TestSendWithoutActions(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	calls := fakeServer(t, bus)
	picked, err := Send(testCtx(t), dial(t, bus), Notification{AppName: "axiom", Summary: "Hi", Body: "there", Icon: "/a.png", DesktopEntry: "axiom-update", Urgency: "critical"})
	if err != nil || picked != "" {
		t.Fatalf("%q %v", picked, err)
	}
	body := <-calls
	want := []any{"axiom", uint32(0), "/a.png", "Hi", "there", []string(nil), map[string]dbus.Variant{
		"desktop-entry": dbus.MakeVariant("axiom-update"),
		"urgency":       dbus.MakeVariant(uint8(2)),
	}, int32(-1)}
	if !reflect.DeepEqual(body, want) {
		t.Fatalf("Notify got %#v\nwant %#v", body, want)
	}
}

func TestSendWaitsForAButton(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	calls := fakeServer(t, bus, [2]any{"ActionInvoked", "edit"})
	picked, err := Send(testCtx(t), dial(t, bus), Notification{AppName: "axiom", Summary: "s", Actions: []Action{{"edit", "Edit"}, {"open", "Open"}}})
	if err != nil || picked != "edit" {
		t.Fatalf("%q %v", picked, err)
	}
	if body := <-calls; !reflect.DeepEqual(body[5], []string{"edit", "Edit", "open", "Open"}) {
		t.Fatalf("actions: %#v", body[5])
	}
}

func TestSendClosedWithoutAPick(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	fakeServer(t, bus, [2]any{"NotificationClosed", uint32(2)})
	picked, err := Send(testCtx(t), dial(t, bus), Notification{Summary: "s", Actions: []Action{{"edit", "Edit"}}})
	if err != nil || picked != "" {
		t.Fatalf("%q %v", picked, err)
	}
}

func TestSendWithNoServer(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	if _, err := Send(testCtx(t), dial(t, bus), Notification{Summary: "s"}); err == nil {
		t.Fatal("sent with no server")
	}
}
