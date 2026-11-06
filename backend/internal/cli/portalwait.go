package cli

import (
	"context"
	"flag"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/screenshare"
)

// How long portal-wait waits for the daemon to take the portal's name
const portalWaitFor = 15 * time.Second

func portalWaitCommand() *Command {
	return &Command{
		Name:    "portal-wait",
		Summary: "Wait for axiom's screen-share portal (its D-Bus activation)",
		Hidden:  true,
		Help: `What D-Bus runs to start axiom's ScreenCast portal
(org.freedesktop.impl.portal.desktop.axiom, data/portal): the running
daemon serves it under niri, so this only waits for it to take the name,
as xdg-desktop-portal may start first at login. Fails after 15 s.`,
		Setup: func(fs *flag.FlagSet) Runner {
			return func(ctx context.Context, e *Env, args []string) error {
				addr, err := dbus.SessionAddress(e.Getenv)
				if err != nil {
					return axerr.Wrap(axerr.Unavailable, err, "no session bus")
				}
				ctx, cancel := context.WithTimeout(ctx, portalWaitFor)
				defer cancel()
				conn, err := dbus.Dial(ctx, addr, dbus.Options{})
				if err != nil {
					return err
				}
				defer conn.Close()
				sub, err := conn.Subscribe(ctx, dbus.NameOwnerChanged(screenshare.PortalBusName))
				if err != nil {
					return err
				}
				defer sub.Close()
				if owner, err := conn.NameOwner(ctx, screenshare.PortalBusName); err == nil && owner != "" {
					return nil
				}
				for {
					select {
					case <-ctx.Done():
						return axerr.New(axerr.Unavailable, "axiom's portal didn't start: is axiom running under niri?")
					case m, ok := <-sub.C:
						if !ok {
							return axerr.New(axerr.Unavailable, "the session bus closed")
						}
						var name, old, new string
						if m.Store(&name, &old, &new) == nil && new != "" {
							return nil
						}
					}
				}
			}
		},
	}
}
