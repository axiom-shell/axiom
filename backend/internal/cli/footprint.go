package cli

import (
	"context"
	"flag"
	"fmt"
	"io"
	"text/tabwriter"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/daemon"
	"github.com/axiom-shell/axiom/backend/internal/footprint"
)

// `axiom footprint`: what axiom changed outside its own folders, and taking
// it out again (docs/dev/backend/footprint.md). It works on the ledger
// itself, so it runs without a daemon (the uninstall uses it); a daemon
// that answers is told afterwards, and Settings' card refreshes.
func footprintCommand() *Command {
	return &Command{
		Name:    "footprint",
		Summary: "What axiom changed outside its own folders, and undoing it",
		Help: `The ledger of files, gsettings keys, app configs and default apps axiom
changed outside its own folders. "undo" takes out only axiom's own change, and
leaves what was changed since (the outcome says so). It never puts back a
whole-file backup.`,
		Subs: []*Command{footprintListCommand(), footprintUndoCommand()},
	}
}

func footprintListCommand() *Command {
	return &Command{
		Name:    "list",
		Summary: "List the changes axiom made, each as present, changed or gone",
		Setup: func(fs *flag.FlagSet) Runner {
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) > 0 {
					return usageError([]string{"axiom", "footprint", "list"}, "takes no arguments")
				}
				rows := daemon.NewLedger(e.Getenv, nil, nil).List(ctx)
				return e.Output(daemon.FootprintListResult{Rows: rows}, func(w io.Writer) {
					if len(rows) == 0 {
						fmt.Fprintln(w, "axiom changed nothing outside its own folders")
						return
					}
					tw := tabwriter.NewWriter(w, 0, 4, 2, ' ', 0)
					for _, r := range rows {
						flags := ""
						if r.Inferred {
							flags += " inferred"
						}
						if r.System {
							flags += " system"
						}
						if r.State == footprint.StatePending {
							flags += " pending"
						}
						fmt.Fprintf(tw, "%s\t%s\t%s\t%s%s\n", r.Status, r.Kind, r.Target+keySuffix(r.Key), r.Owner, flags)
					}
					tw.Flush()
				})
			}
		},
	}
}

func keySuffix(key string) string {
	if key == "" {
		return ""
	}
	return " [" + key + "]"
}

func footprintUndoCommand() *Command {
	trail := []string{"axiom", "footprint", "undo"}
	return &Command{
		Name:    "undo",
		Summary: "Take out the changes of some rows, a setting's, or all",
		Args:    "(ID... | --owner PATH | --all)",
		Help: `ID is a row's id (axiom footprint list --json). --owner takes out every
row a setting caused (its path: ThemeIntegrations.gtk; "" for the compositor's
include and autostart lines). --all takes every row but the system's own
choices (default apps, input method engines: --include-system) and the ones
axiom found without a record of writing them (--force). A named row of that
kind is undone, an inferred one only with --force. --dry-run changes nothing
and says what would happen.`,
		Setup: func(fs *flag.FlagSet) Runner {
			owner := fs.String("owner", "", "undo the rows a setting caused (its path)")
			all := fs.Bool("all", false, "undo every row (not the system's own choices or inferred rows)")
			force := fs.Bool("force", false, "undo inferred rows too")
			system := fs.Bool("include-system", false, "with --all: the system's own choices too (default apps, input methods)")
			dry := fs.Bool("dry-run", false, "change nothing, say what would happen")
			return func(ctx context.Context, e *Env, args []string) error {
				ownerGiven := false
				fs.Visit(func(f *flag.Flag) { ownerGiven = ownerGiven || f.Name == "owner" })
				modes := len(args)
				if ownerGiven {
					modes++
				}
				if *all {
					modes++
				}
				if modes == 0 || (len(args) > 0 && (ownerGiven || *all)) || (ownerGiven && *all) {
					return usageError(trail, "takes row ids, or --owner, or --all")
				}
				l := daemon.NewLedger(e.Getenv, nil, nil)
				o := footprint.UndoOptions{Force: *force, IncludeSystem: *system, DryRun: *dry}
				ids := args
				switch {
				case *all:
					ids = l.Select(o)
				case ownerGiven:
					ids = l.SelectOwner(*owner)
				}
				results := l.Undo(ctx, ids, o)
				if !*dry && !e.Globals.Offline {
					// Best effort: the daemon's card refreshes. Without
					// Exec, so a daemon of another protocol never runs this
					// command again
					quiet := *e
					quiet.Exec = nil
					_ = call(ctx, &quiet, "footprint.notify", nil, nil)
				}
				failed := 0
				for _, r := range results {
					if r.Outcome == footprint.OutcomeFailed || r.Outcome == footprint.OutcomeRefused {
						failed++
					}
				}
				err := e.Output(daemon.FootprintUndoResult{Results: results}, func(w io.Writer) {
					if len(results) == 0 {
						fmt.Fprintln(w, "nothing to undo")
					}
					for _, r := range results {
						fmt.Fprintf(w, "%s: %s", r.Outcome, r.ID)
						if r.Detail != "" {
							fmt.Fprintf(w, " (%s)", r.Detail)
						}
						fmt.Fprintln(w)
					}
				})
				if err == nil && failed > 0 {
					err = axerr.New(axerr.Failed, "%d changes couldn't be undone", failed)
				}
				return err
			}
		},
	}
}
