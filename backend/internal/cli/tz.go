package cli

import (
	"context"
	"flag"
	"fmt"
	"io"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/tz"
)

// tzCommand answers what the daemon's tz.zones and tz.offsets do, for a
// shell with no daemon (the greeter's TimeZoneManager), in the same
// shape with --json.
func tzCommand() *Command {
	return &Command{
		Name:    "tz",
		Summary: "The system's time zones and their UTC offsets",
		Subs: []*Command{{
			Name:    "zones",
			Summary: "List the system's time zones",
			Setup: func(fs *flag.FlagSet) Runner {
				return func(ctx context.Context, e *Env, args []string) error {
					zones := append([]string{}, tz.Zones(tz.Dir(e.Getenv))...)
					return e.Output(map[string]any{"zones": zones}, func(w io.Writer) {
						for _, zone := range zones {
							fmt.Fprintln(w, zone)
						}
					})
				}
			},
		}, {
			Name:    "offsets",
			Summary: "Each zone's UTC offset now, in minutes east",
			Args:    "ZONE…",
			Setup: func(fs *flag.FlagSet) Runner {
				return func(ctx context.Context, e *Env, args []string) error {
					offsets := tz.Offsets(tz.Dir(e.Getenv), args, time.Now())
					return e.Output(map[string]any{"offsets": offsets}, func(w io.Writer) {
						for _, zone := range args {
							if offset, ok := offsets[zone]; ok {
								fmt.Fprintf(w, "%-32s %+d\n", zone, offset)
							}
						}
					})
				}
			},
		}},
	}
}
