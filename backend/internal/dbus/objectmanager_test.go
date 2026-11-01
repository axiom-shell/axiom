package dbus_test

import (
	"context"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// GetManagedObjects and the add/remove signals read back what a manager
// sends, on every bus
func TestObjectManager(t *testing.T) {
	t.Parallel()
	for name, addr := range buses(t) {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			svc, cli := dial(t, addr), dial(t, addr)
			objs := map[dbus.ObjectPath]map[string]map[string]dbus.Variant{
				"/m/a": {"x.Thing": {"Name": dbus.MakeVariant("a"), "Dev": dbus.MakeVariant([]byte("/dev/a\x00"))}},
			}
			_, err := svc.Export("/m", dbus.Interface{Name: dbus.IfaceObjectManager, Methods: map[string]dbus.Method{
				"GetManagedObjects": {Out: "a{oa{sa{sv}}}", Fn: func(context.Context, *dbus.Message) ([]any, error) {
					return []any{objs}, nil
				}},
			}})
			if err != nil {
				t.Fatal(err)
			}
			got, err := cli.GetManagedObjects(ctx(t), svc.UniqueName(), "/m")
			if err != nil {
				t.Fatal(err)
			}
			if got["/m/a"]["x.Thing"]["Name"].Value != "a" || string(got["/m/a"]["x.Thing"]["Dev"].Value.([]byte)) != "/dev/a\x00" {
				t.Errorf("GetManagedObjects = %v", got)
			}

			added, err := cli.Subscribe(ctx(t), dbus.Match{Sender: svc.UniqueName(), Path: "/m", Interface: dbus.IfaceObjectManager, Member: "InterfacesAdded"})
			if err != nil {
				t.Fatal(err)
			}
			removed, err := cli.Subscribe(ctx(t), dbus.Match{Sender: svc.UniqueName(), Path: "/m", Interface: dbus.IfaceObjectManager, Member: "InterfacesRemoved"})
			if err != nil {
				t.Fatal(err)
			}
			svc.Emit("/m", dbus.IfaceObjectManager, "InterfacesAdded", "oa{sa{sv}}", dbus.ObjectPath("/m/b"),
				map[string]map[string]dbus.Variant{"x.Thing": {"Name": dbus.MakeVariant("b")}, "x.Empty": {}})
			svc.Emit("/m", dbus.IfaceObjectManager, "InterfacesRemoved", "oas", dbus.ObjectPath("/m/a"), []string{"x.Thing"})
			select {
			case m := <-added.C:
				p, ifaces, err := dbus.InterfacesAdded(m)
				if err != nil || p != "/m/b" || ifaces["x.Thing"]["Name"].Value != "b" || ifaces["x.Empty"] == nil {
					t.Errorf("InterfacesAdded = %v %v %v", p, ifaces, err)
				}
			case <-time.After(testkit.Bound(5 * time.Second)):
				t.Fatal("no InterfacesAdded")
			}
			select {
			case m := <-removed.C:
				p, ifaces, err := dbus.InterfacesRemoved(m)
				if err != nil || p != "/m/a" || len(ifaces) != 1 || ifaces[0] != "x.Thing" {
					t.Errorf("InterfacesRemoved = %v %v %v", p, ifaces, err)
				}
				if _, _, err := dbus.InterfacesAdded(m); err == nil {
					t.Error("InterfacesAdded read a removal")
				}
			case <-time.After(testkit.Bound(5 * time.Second)):
				t.Fatal("no InterfacesRemoved")
			}
		})
	}
}
