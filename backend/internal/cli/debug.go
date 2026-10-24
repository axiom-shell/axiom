package cli

import (
	"context"
	"flag"
	"fmt"
	"io"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/wayland/outputs"
	"github.com/axiom-shell/axiom/backend/internal/wayland/wire"
)

func debugCommand() *Command {
	return &Command{
		Name:    "debug",
		Summary: "Look into the environment axiom runs in",
		Subs: []*Command{{
			Name:    "wayland-outputs",
			Summary: "List the outputs as the daemon sees them (wl_output, xdg_output)",
			Setup: func(fs *flag.FlagSet) Runner {
				return func(ctx context.Context, e *Env, args []string) error {
					socket, err := wire.SocketPath(e.Getenv)
					if err != nil {
						return err
					}
					list, err := outputs.List(socket, 5*time.Second)
					if err != nil {
						return err
					}
					return e.Output(list, func(w io.Writer) {
						for _, o := range list {
							fmt.Fprintf(w, "%-12s %5d,%-5d %5dx%-5d scale %d  %s\n", o.Name, o.X, o.Y, o.Width, o.Height, o.Scale, o.Description)
						}
					})
				}
			},
		}, {
			Name:    "wayland-globals",
			Summary: "List the Wayland protocols the compositor offers",
			Setup: func(fs *flag.FlagSet) Runner {
				return func(ctx context.Context, e *Env, args []string) error {
					socket, err := wire.SocketPath(e.Getenv)
					if err != nil {
						return err
					}
					globals, err := wire.Globals(socket, 5*time.Second)
					if err != nil {
						return err
					}
					return e.Output(globals, func(w io.Writer) {
						for _, g := range globals {
							fmt.Fprintf(w, "%-52s v%d\n", g.Interface, g.Version)
						}
					})
				}
			},
		}},
	}
}
