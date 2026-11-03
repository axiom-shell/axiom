package cli

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"strings"
	"text/tabwriter"

	"github.com/axiom-shell/axiom/backend/internal/config"
)

// devDiff is dev.config.diff's result as the CLI reads it (rows' values
// kept as JSON).
type devDiff struct {
	Rows []struct {
		Path    config.Path     `json:"path"`
		Side    string          `json:"side"`
		Dev     json.RawMessage `json:"dev,omitempty"`
		Live    json.RawMessage `json:"live,omitempty"`
		DevOnly bool            `json:"devOnly"`
	} `json:"rows"`
	LiveChanged bool `json:"liveChanged"`
}

// devConfigCommand is `axiom dev config`: the dev config against live.
func devConfigCommand() *Command {
	return &Command{
		Name:    "config",
		Summary: "Compare the dev config with yours and copy settings between them",
		Help: `While dev mode runs the dev tree, its config is its own. "diff" lists every
setting the two disagree on, with the side that changed it since they last
matched (dev, live or both); "copy" copies settings either way (a path
copies every difference under it; to live only what the installed axiom
knows); "pull" brings your config's changes over (--merge: where dev left
the setting alone; --replace: dev becomes your config's copy).`,
		Subs: []*Command{
			{
				Name:    "diff",
				Summary: "List the settings the dev config and yours disagree on",
				Setup: func(fs *flag.FlagSet) Runner {
					return func(ctx context.Context, e *Env, args []string) error {
						if len(args) > 0 {
							return usageError([]string{"axiom", "dev", "config", "diff"}, "takes no arguments")
						}
						var diff devDiff
						if err := call(ctx, e, "dev.config.diff", nil, &diff); err != nil {
							return err
						}
						return e.Output(diff, func(w io.Writer) { printDevDiff(w, diff) })
					}
				},
			},
			{
				Name:    "copy",
				Summary: "Copy settings to your config or to the dev config",
				Args:    "PATH...",
				Setup: func(fs *flag.FlagSet) Runner {
					to := fs.String("to", "", "where they go: live or dev")
					return func(ctx context.Context, e *Env, args []string) error {
						if (*to != "live" && *to != "dev") || len(args) == 0 {
							return usageError([]string{"axiom", "dev", "config", "copy"}, "takes --to live|dev and the settings' paths")
						}
						paths := make([]config.Path, 0, len(args))
						for _, a := range args {
							p, err := config.ParsePath(a)
							if err != nil {
								return err
							}
							if len(p) == 0 {
								return usageError([]string{"axiom", "dev", "config", "copy"}, "an empty path")
							}
							paths = append(paths, p)
						}
						var res struct {
							Copied []config.Path `json:"copied"`
							Diff   devDiff       `json:"diff"`
						}
						if err := call(ctx, e, "dev.config.copy", map[string]any{"paths": paths, "to": *to}, &res); err != nil {
							return err
						}
						return e.Output(res, func(w io.Writer) {
							fmt.Fprintf(w, "copied to %s: %s\n", *to, cliPaths(res.Copied))
						})
					}
				},
			},
			{
				Name:    "pull",
				Summary: "Bring your config's changes over to the dev config",
				Setup: func(fs *flag.FlagSet) Runner {
					merge := fs.Bool("merge", false, "only the settings dev left as they were")
					replace := fs.Bool("replace", false, "make the dev config your config's copy")
					return func(ctx context.Context, e *Env, args []string) error {
						if len(args) > 0 || *merge == *replace {
							return usageError([]string{"axiom", "dev", "config", "pull"}, "takes --merge or --replace")
						}
						mode := "merge"
						if *replace {
							mode = "replace"
						}
						var res struct {
							Merged    []config.Path `json:"merged"`
							Conflicts []config.Path `json:"conflicts"`
							Diff      devDiff       `json:"diff"`
						}
						if err := call(ctx, e, "dev.config.pull", map[string]string{"mode": mode}, &res); err != nil {
							return err
						}
						return e.Output(res, func(w io.Writer) {
							if *replace {
								fmt.Fprintln(w, "the dev config is your config's copy now")
								return
							}
							fmt.Fprintf(w, "brought over: %s\n", orNone(cliPaths(res.Merged), "nothing"))
							if len(res.Conflicts) > 0 {
								fmt.Fprintf(w, "changed on both sides, kept as dev's: %s\n", cliPaths(res.Conflicts))
							}
						})
					}
				},
			},
		},
	}
}

// printDevDiff is `axiom dev config diff`'s text.
func printDevDiff(w io.Writer, diff devDiff) {
	if len(diff.Rows) == 0 {
		fmt.Fprintln(w, "the dev config and yours agree")
	} else {
		tw := tabwriter.NewWriter(w, 0, 4, 2, ' ', 0)
		fmt.Fprintln(tw, "SETTING\tCHANGED IN\tDEV\tLIVE")
		for _, r := range diff.Rows {
			side := r.Side
			if r.DevOnly {
				side += " (dev only)"
			}
			fmt.Fprintf(tw, "%s\t%s\t%s\t%s\n", cliPath(r.Path), side, orNone(string(r.Dev), "-"), orNone(string(r.Live), "-"))
		}
		tw.Flush()
	}
	if diff.LiveChanged {
		fmt.Fprintln(w, "your config changed since the dev config's copy: axiom dev config pull --merge|--replace")
	}
}

// cliPath is a path as the command line writes it (`Bars[main].location`,
// config.ParsePath's form).
func cliPath(p config.Path) string {
	var b strings.Builder
	for _, s := range p {
		if s.ID != "" {
			b.WriteString("[" + s.ID + "]")
			continue
		}
		if b.Len() > 0 {
			b.WriteByte('.')
		}
		b.WriteString(s.Key)
	}
	return b.String()
}

func cliPaths(paths []config.Path) string {
	out := make([]string, len(paths))
	for i, p := range paths {
		out[i] = cliPath(p)
	}
	return strings.Join(out, ", ")
}
