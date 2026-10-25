package cli

import (
	"context"
	"flag"
	"fmt"
	"io"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/netif"
)

// netCommand answers what the daemon's net.addresses does, for a shell
// with no daemon (the greeter's NetworkingManager), in the same shape
// with --json.
func netCommand() *Command {
	return &Command{
		Name:    "net",
		Summary: "What the shell asks about a network interface",
		Subs: []*Command{{
			Name:    "address",
			Summary: "A network interface's IPv4 address (nothing for none)",
			Args:    "DEVICE",
			Setup: func(fs *flag.FlagSet) Runner {
				return func(ctx context.Context, e *Env, args []string) error {
					if len(args) != 1 {
						return axerr.New(axerr.BadRequest, "net address takes one device")
					}
					ip := netif.IPv4(args[0])
					return e.Output(map[string]any{"ipv4": ip}, func(w io.Writer) {
						if ip != "" {
							fmt.Fprintln(w, ip)
						}
					})
				}
			},
		}},
	}
}
