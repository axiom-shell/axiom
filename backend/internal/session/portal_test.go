package session

import (
	"context"
	"strconv"
	"syscall"
	"testing"
)

func TestRestartPortalSystemctlForTheUnitsMainPID(t *testing.T) {
	c := &calls{out: map[string]string{"show -p MainPID --value xdg-desktop-portal.service": "77\n", "show -p MainPID --value xdg-desktop-portal-wlr.service": "88\n"}}
	bus := fakeBus{owners: map[string]uint32{systemd: 1, portalBus: 77, "org.freedesktop.impl.portal.desktop.wlr": 88}}
	s := c.seams()
	err := RestartPortal(context.Background(), bus, s.Systemctl, s.Signal, []BusUnit{{Bus: "org.freedesktop.impl.portal.desktop.wlr", Unit: "xdg-desktop-portal-wlr.service"}})
	if err != nil {
		t.Fatal(err)
	}
	want := "systemctl show -p MainPID --value xdg-desktop-portal.service\nsystemctl restart xdg-desktop-portal.service\nsystemctl show -p MainPID --value xdg-desktop-portal-wlr.service\nsystemctl restart xdg-desktop-portal-wlr.service"
	if c.got() != want {
		t.Fatalf("calls:\n%s", c.got())
	}
}

func TestRestartPortalSignalsAnOwnerOutsideSystemd(t *testing.T) {
	c := &calls{out: map[string]string{"show -p MainPID --value xdg-desktop-portal.service": "5\n"}}
	// the unit's main pid isn't the owner's: SIGTERM it
	bus := fakeBus{owners: map[string]uint32{systemd: 1, portalBus: 77}}
	s := c.seams()
	RestartPortal(context.Background(), bus, s.Systemctl, s.Signal, nil)
	if got := c.got(); got != "systemctl show -p MainPID --value xdg-desktop-portal.service\nsignal 77 "+itoa(int(syscall.SIGTERM)) {
		t.Fatalf("calls: %q", got)
	}
	// no systemd on the bus: no systemctl at all
	c2 := &calls{}
	s = c2.seams()
	RestartPortal(context.Background(), fakeBus{owners: map[string]uint32{portalBus: 77}}, s.Systemctl, s.Signal, nil)
	if got := c2.got(); got != "signal 77 15" {
		t.Fatalf("calls: %q", got)
	}
}

func TestRestartPortalNoOwnerNoRestart(t *testing.T) {
	c := &calls{}
	s := c.seams()
	if err := RestartPortal(context.Background(), fakeBus{owners: map[string]uint32{systemd: 1}}, s.Systemctl, s.Signal, nil); err != nil {
		t.Fatal(err)
	}
	if got := c.got(); got != "" {
		t.Fatalf("calls: %q", got)
	}
}

func itoa(n int) string { return strconv.Itoa(n) }
