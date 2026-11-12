package session

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"syscall"
)

// BusUnit is a portal service: the bus name it owns and its user unit.
type BusUnit struct {
	Bus  string `json:"bus"`
	Unit string `json:"unit"`
}

const (
	portalBus  = "org.freedesktop.portal.Desktop"
	portalUnit = "xdg-desktop-portal.service"
)

// RestartPortal restarts the portal frontend and the backends names list
// so a changed config is read, reaching only this session's: for each, the
// process owning its name on bus. No owner: nothing to do (it reads its
// config when it is started). When the user manager is this session's
// (UnitsAllowed) and its unit's MainPID is that process, the unit is
// restarted; otherwise the process gets SIGTERM, and the bus starts it
// again at the next call.
func RestartPortal(ctx context.Context, bus Bus, systemctl SystemctlFunc, signal SignalFunc, names []BusUnit) error {
	all := append([]BusUnit{{Bus: portalBus, Unit: portalUnit}}, names...)
	allowed := UnitsAllowed(ctx, bus)
	var failed []string
	seen := map[string]bool{}
	for _, n := range all {
		if seen[n.Bus] {
			continue
		}
		seen[n.Bus] = true
		pid, err := bus.ConnectionPID(ctx, n.Bus)
		if err != nil || pid == 0 {
			continue
		}
		if allowed && systemctl != nil {
			out, err := systemctl(ctx, "show", "-p", "MainPID", "--value", n.Unit)
			if main, _ := strconv.Atoi(strings.TrimSpace(out)); err == nil && main == int(pid) {
				if _, err := systemctl(ctx, "restart", n.Unit); err != nil {
					failed = append(failed, n.Unit+": "+err.Error())
				}
				continue
			}
		}
		if err := signal(int(pid), syscall.SIGTERM); err != nil {
			failed = append(failed, fmt.Sprintf("%s: %v", n.Bus, err))
		}
	}
	if len(failed) > 0 {
		return fmt.Errorf("restarting the portal: %s", strings.Join(failed, "; "))
	}
	return nil
}
