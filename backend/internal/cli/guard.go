package cli

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/logfile"
	"github.com/axiom-shell/axiom/backend/internal/session"
	"github.com/axiom-shell/axiom/backend/internal/wayland/wire"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

func guardCommand() *Command {
	return &Command{
		Name:    "guard",
		Summary: "Undo axiom's session effects if the daemon dies (started by axiom run)",
		Hidden:  true,
		Help: `What the daemon starts so that a crash or a kill leaves nothing behind
(docs/dev/backend/session-teardown.md): it waits, with the daemon's
pidfd as descriptor 3, for the daemon or the compositor to end, then runs
the teardown the daemon didn't. --stage1 starts it in a session of its own
and returns; never run it by hand.`,
		Setup: func(fs *flag.FlagSet) Runner {
			stage1 := fs.Bool("stage1", false, "start the guard detached, and return")
			display := fs.String("display", "", "the Wayland display it guards")
			return func(ctx context.Context, e *Env, args []string) error {
				pidfd := os.NewFile(uintptr(session.PidfdFD), "pidfd")
				if pidfd == nil {
					return usageError([]string{"axiom", "guard"}, "needs the daemon's pidfd as descriptor 3")
				}
				if *stage1 {
					exe, err := os.Executable()
					if err != nil {
						return err
					}
					d := xdg.DisplayName(e.Getenv("WAYLAND_DISPLAY"))
					if d == "" {
						return axerr.New(axerr.Unavailable, "no usable $WAYLAND_DISPLAY")
					}
					return session.Stage1(exe, d, pidfd)
				}
				rt, err := xdg.ForDisplay(e.Getenv, false)
				if err != nil {
					return err
				}
				if *display != "" && *display != rt.Display {
					return usageError([]string{"axiom", "guard"}, fmt.Sprintf("--display %s isn't $WAYLAND_DISPLAY (%s)", *display, rt.Display))
				}
				dirs := xdg.Resolve(e.Getenv)
				lf, err := logfile.Open(filepath.Join(dirs.State, "log", "guard.log"), 1<<20)
				if err != nil {
					return err
				}
				defer lf.Close()
				log := slog.New(slog.NewTextHandler(lf, nil))
				logf := func(format string, args ...any) { log.Info(fmt.Sprintf(format, args...)) }
				socket, err := wire.SocketPath(e.Getenv)
				if err != nil {
					return err
				}
				return session.RunGuard(ctx, session.GuardOptions{
					Dir: rt.Dir, Pidfd: int(pidfd.Fd()), WaylandSocket: socket, Log: logf,
					Base: session.TeardownOptions{
						Scope: session.ScopeFrom(e.Getenv), State: session.StoreFrom(e.Getenv, logf),
						Portal: session.PortalEnvFrom(e.Getenv), Log: logf,
					},
					DialBus: func(ctx context.Context) (session.Bus, func()) {
						addr, err := dbus.SessionAddress(e.Getenv)
						if err != nil {
							return nil, nil
						}
						conn, err := dbus.Dial(ctx, addr, dbus.Options{})
						if err != nil {
							logf("guard: no session bus: %v", err)
							return nil, nil
						}
						return conn, func() { conn.Close() }
					},
				})
			}
		},
	}
}
