package daemon

import (
	"github.com/axiom-shell/axiom/backend/internal/powerprofiles"
)

// newPower is the holder of a window rule's power profile in
// power-profiles-daemon; the user picking a profile overrides the rule.
func (d *Daemon) newPower() *powerprofiles.Holder {
	return powerprofiles.New(powerprofiles.Options{
		SystemBus: d.systemBus,
		// Only posts to the engine's loop, never calls back into it
		OnOverridden: func() { d.windowRules.Override("powerProfile") },
		Log:          d.opts.Log.With("part", "powerprofiles"),
	})
}

// powerPart: the holder, run for the daemon's life (it dials only while a rule holds a profile).
func (d *Daemon) powerPart() part {
	return part{name: "powerprofiles", run: d.power.Run}
}
