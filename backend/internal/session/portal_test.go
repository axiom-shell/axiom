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
	p := portalProcs(t, 77, 88)
	err := RestartPortal(context.Background(), bus, p.scope(), s.Systemctl, s.Signal, []BusUnit{{Bus: "org.freedesktop.impl.portal.desktop.wlr", Unit: "xdg-desktop-portal-wlr.service"}}, nil)
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
	RestartPortal(context.Background(), bus, portalProcs(t, 77).scope(), s.Systemctl, s.Signal, nil, nil)
	if got := c.got(); got != "systemctl show -p MainPID --value xdg-desktop-portal.service\nsignal 77 "+itoa(int(syscall.SIGTERM)) {
		t.Fatalf("calls: %q", got)
	}
	// no systemd on the bus: no systemctl at all
	c2 := &calls{}
	s = c2.seams()
	RestartPortal(context.Background(), fakeBus{owners: map[string]uint32{portalBus: 77}}, portalProcs(t, 77).scope(), s.Systemctl, s.Signal, nil, nil)
	if got := c2.got(); got != "signal 77 15" {
		t.Fatalf("calls: %q", got)
	}
}

func TestRestartPortalNoOwnerNoRestart(t *testing.T) {
	c := &calls{}
	s := c.seams()
	if err := RestartPortal(context.Background(), fakeBus{owners: map[string]uint32{systemd: 1}}, newProc(t).scope(), s.Systemctl, s.Signal, nil, nil); err != nil {
		t.Fatal(err)
	}
	if got := c.got(); got != "" {
		t.Fatalf("calls: %q", got)
	}
}

func itoa(n int) string { return strconv.Itoa(n) }

// portalProcs are owners of this session's runtime folder
func portalProcs(t *testing.T, pids ...int) *fakeProc {
	p := newProc(t)
	for _, pid := range pids {
		p.add(pid, []string{"xdg-desktop-portal"}, "XDG_RUNTIME_DIR=/run/u")
	}
	return p
}

// A scratch daemon on the live bus must not restart the live portal: an
// owner of another runtime folder, or one whose environment can't be read,
// is left alone; one with no XDG_RUNTIME_DIR (activated by D-Bus) isn't.
func TestRestartPortalLeavesAnOwnerOfAnotherRuntimeFolder(t *testing.T) {
	p := newProc(t)
	p.add(10, []string{"xdg-desktop-portal"}, "XDG_RUNTIME_DIR=/run/user/1000")
	p.add(12, []string{"xdg-desktop-portal"}, "A=b")
	for pid, want := range map[int]string{10: "", 11: "", 12: "signal 12 15"} {
		c := &calls{}
		s := c.seams()
		var logged []string
		RestartPortal(context.Background(), fakeBus{owners: map[string]uint32{portalBus: uint32(pid)}}, p.scope(), s.Systemctl, s.Signal, nil,
			func(f string, a ...any) { logged = append(logged, f) })
		if got := c.got(); got != want {
			t.Errorf("owner %d: calls %q, want %q", pid, got, want)
		}
		if want == "" && len(logged) == 0 {
			t.Errorf("owner %d: not logged", pid)
		}
	}
}

func TestUnitsNeedTheBusOfTheRuntimeFolder(t *testing.T) {
	bus := fakeBus{owners: map[string]uint32{systemd: 1}}
	for addr, want := range map[string]bool{
		"unix:path=/run/u/bus":          true,
		"unix:path=/run/u/bus,guid=abc": true,
		"unix:guid=abc,path=/run/u/bus": true,
		"unix:path=/run/user/1000/bus":  false, // the live bus, from a scratch runtime folder
		"unix:path=/tmp/dbus-XYZ/bus":   false, // dbus-run-session
		"unix:abstract=/tmp/dbus-XYZ":   false,
		"":                              false,
	} {
		scope := Scope{RuntimeDir: "/run/u", Bus: addr}
		if got := UnitsAllowed(context.Background(), bus, scope); got != want {
			t.Errorf("%q: allowed = %v, want %v", addr, got, want)
		}
	}
	if UnitsAllowed(context.Background(), fakeBus{owners: map[string]uint32{}}, Scope{RuntimeDir: "/run/u", Bus: "unix:path=/run/u/bus"}) {
		t.Error("allowed without systemd1 on the bus")
	}
}
