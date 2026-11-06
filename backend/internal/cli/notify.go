package cli

import (
	"context"
	"flag"
	"fmt"
	"io"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/notification"
)

// notifyCommand sends a desktop notification through the daemon's
// notify.send, as notify-send did: it reaches the shell's own server like
// any other app's (do not disturb and the rules apply).
func notifyCommand() *Command {
	return &Command{
		Name:    "notify",
		Summary: "Send a desktop notification",
		Args:    "TITLE [BODY]",
		Help: `Sends a notification titled TITLE. With buttons (--action ID=LABEL,
once per button) or --wait it waits until a button is picked or the
notification closes, and prints the picked button's ID (nothing when
it closed without one), as notify-send --action does.

  axiom notify "Backup done" "42 files, 1.2 GB"
  axiom notify --icon dialog-warning --urgency critical "Disk almost full"
  axiom notify --action open=Open --action later=Later "Update ready"`,
		Setup: func(fs *flag.FlagSet) Runner {
			var n notification.Notification
			fs.StringVar(&n.Icon, "icon", "", "an icon name or a picture's path")
			fs.StringVar(&n.Urgency, "urgency", "", "low, normal or critical")
			fs.StringVar(&n.Key, "key", "", "a newer notification of the same key replaces this one")
			fs.BoolVar(&n.Transient, "transient", false, "show it without keeping it in the list")
			fs.BoolVar(&n.Wait, "wait", false, "wait until it closes (buttons wait anyway)")
			fs.Func("action", "a button, `ID=LABEL` (repeatable)", func(s string) error {
				id, label, ok := strings.Cut(s, "=")
				if !ok || id == "" || label == "" {
					return fmt.Errorf("an action is ID=LABEL")
				}
				n.Actions = append(n.Actions, notification.Action{ID: id, Label: label})
				return nil
			})
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) < 1 || len(args) > 2 {
					return usageError([]string{"axiom", "notify"}, "takes TITLE [BODY]")
				}
				switch n.Urgency {
				case "", "low", "normal", "critical":
				default:
					return usageError([]string{"axiom", "notify"}, "--urgency is low, normal or critical")
				}
				n.AppName, n.Summary = "axiom", args[0]
				if len(args) == 2 {
					n.Body = args[1]
				}
				n.Wait = n.Wait || len(n.Actions) > 0
				var result struct {
					ID     uint32 `json:"id"`
					Action string `json:"action,omitempty"`
				}
				if err := call(ctx, e, "notify.send", n, &result); err != nil {
					return err
				}
				return e.Output(result, func(w io.Writer) {
					if result.Action != "" {
						fmt.Fprintln(w, result.Action)
					}
				})
			}
		},
	}
}
