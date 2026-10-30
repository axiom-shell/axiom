package daemon

import (
	"context"
	"sync"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/wayland/keyhold"
)

// switcherKey is switcher.key: what the held keyboard decided, "commit"
// or "cancel", as Hyprland's switcher submap reports it.
type switcherKey struct {
	Verb string `json:"verb"`
}

// switcherHold is who holds the window switcher's keyboard
// (keyhold.Holder): the shell's connection that asked, told the verb.
type switcherHold struct {
	mu     sync.Mutex
	holder *rpc.Conn
}

// switcherPart: the window switcher's keyboard where the compositor can't
// report its modifier's release (sway, niri).
func (d *Daemon) switcherPart() part {
	return part{name: "switcher", methods: d.switcherMethods}
}

func (d *Daemon) switcherMethods(reg *rpc.Registry) {
	type holdParams struct {
		// The modifiers the switcher's binds are held by: ALT, CTRL,
		// SHIFT, SUPER
		Mods []string `json:"mods"`
	}
	rpc.Handle(reg, "switcher.hold", func(ctx context.Context, c *rpc.Conn, p holdParams) (struct{}, error) {
		// It takes the keyboard from every window: only the shell asks
		if !fromShell(c) {
			return struct{}{}, axerr.New(axerr.Refused, "only the shell holds the switcher's keys")
		}
		mods, err := keyhold.ModifierMask(p.Mods)
		if err != nil {
			return struct{}{}, err
		}
		d.switcherHold.mu.Lock()
		d.switcherHold.holder = c
		d.switcherHold.mu.Unlock()
		return struct{}{}, d.keyHolder.Hold(mods, func(v keyhold.Verb) {
			c.Notify(pushSwitcherKey.Method, switcherKey{Verb: string(v)})
		})
	})
	rpc.Handle(reg, "switcher.release", func(ctx context.Context, c *rpc.Conn, _ struct{}) (struct{}, error) {
		if !fromShell(c) {
			return struct{}{}, axerr.New(axerr.Refused, "only the shell holds the switcher's keys")
		}
		d.releaseSwitcher(nil)
		return struct{}{}, nil
	})
	// A close and the next open sent together must land in that order:
	// a release after the hold would leave the new switcher unheld
	reg.InOrder("switcher.hold", "switcher.release")
}

// releaseSwitcher gives the keyboard back: always (c nil), or when c held
// it (its connection closed: a shell reload mustn't leave it held).
func (d *Daemon) releaseSwitcher(c *rpc.Conn) {
	d.switcherHold.mu.Lock()
	held := d.switcherHold.holder
	if c != nil && held != c {
		d.switcherHold.mu.Unlock()
		return
	}
	d.switcherHold.holder = nil
	d.switcherHold.mu.Unlock()
	d.keyHolder.Release()
}
