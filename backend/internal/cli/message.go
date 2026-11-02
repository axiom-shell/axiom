package cli

import (
	"context"
	"flag"
)

// messageCommand shows a message card on an OSD. Its own command rather
// than a named one for its flags: it always calls osd.message with all
// four arguments (IPC functions take no optional ones), "" for a flag not
// given.
func messageCommand() *Command {
	return &Command{
		Name:    "message",
		Summary: "Show a message card on the OSD",
		Args:    "ICON TEXT",
		Help: `Shows TEXT with ICON (a Material Symbols name, such as "info" or
"download_done") as a card on the first OSD that picks Messages
(under its Detail cards), or with --osd on that one; where none
does, as a notification.

  axiom message info "Backup done"
  axiom message --detail "42 files, 1.2 GB" download_done "Backup done"
  axiom message --osd top warning "Disk almost full"`,
		Setup: func(fs *flag.FlagSet) Runner {
			detail := fs.String("detail", "", "a faint second line under TEXT")
			osd := fs.String("osd", "", "the id of the OSD to show it on")
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) != 2 {
					return usageError([]string{"axiom", "message"}, "takes ICON TEXT")
				}
				return ipcCall(ctx, e, "osd", "message", messageArgs(*osd, *detail, args[0], args[1]))
			}
		},
	}
}

// messageArgs are osd.message's arguments, in its order.
func messageArgs(osd, detail, icon, text string) []string {
	return []string{osd, icon, text, detail}
}
