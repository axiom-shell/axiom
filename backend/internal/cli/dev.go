package cli

import (
	"context"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/daemon"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

func devCommand() *Command {
	show := func(ctx context.Context, e *Env, method string, params any) error {
		var st daemon.DevState
		if err := call(ctx, e, method, params, &st); err != nil {
			return err
		}
		return e.Output(st, func(w io.Writer) { printDevState(w, st) })
	}
	leaf := func(name, summary string, run func(ctx context.Context, e *Env) error) *Command {
		return &Command{
			Name:    name,
			Summary: summary,
			Setup: func(fs *flag.FlagSet) Runner {
				return func(ctx context.Context, e *Env, args []string) error {
					if len(args) > 0 {
						return usageError([]string{"axiom", "dev", name}, "takes no arguments")
					}
					return run(ctx, e)
				}
			},
		}
	}
	// dev.set of the tree or the options; with no axiom running (or
	// --offline) they're saved for its next start, as install.sh asks
	// before the first one
	setChoice := func(ctx context.Context, e *Env, p daemon.DevSetParams) error {
		if !e.Globals.Offline {
			// Only a daemon that can't be reached is "none running": its
			// own refusals are the answer
			c, _, err := connect(ctx, e)
			if err == nil {
				c.Close()
				return show(ctx, e, "dev.set", p)
			}
			if axerr.KindOf(err) != axerr.Unavailable {
				return err
			}
		}
		tree, options, err := daemon.SaveDevChoice(xdg.Resolve(e.Getenv), p)
		if err != nil {
			return err
		}
		return e.Output(map[string]any{"tree": tree, "options": options}, func(w io.Writer) {
			fmt.Fprintf(w, "no axiom is running: saved for its next start\ndev tree     %s\n", orNone(tree, "none"))
		})
	}
	setDev := func(on bool) func(ctx context.Context, e *Env) error {
		return func(ctx context.Context, e *Env) error {
			return show(ctx, e, "dev.set", map[string]bool{"enabled": on})
		}
	}
	return &Command{
		Name:    "dev",
		Summary: "Dev mode: run a clone of axiom, rebuilt as you edit it, on its own config",
		Help: `Dev mode runs a dev tree (a clone, "axiom dev set <clone>") instead of the
installed one: its own axiom binary, built from the clone into
$XDG_STATE_HOME/axiom/dev/, its QML, and its own config
($XDG_CONFIG_HOME/axiom/dev/config.json, copied from yours the first
time). It's switched while axiom runs and remembered across sessions. While
it's on, an edit to the clone's Go source builds it again and re-execs into
it, a YAML edit rebuilds the schema, and the log is at debug level. At
login the installed axiom starts first and switches to the dev build once
it's built. Turning it off goes back to the installed binary, tree and
config. With no axiom running, "set" and "options" are saved for its next
start.`,
		Subs: []*Command{
			leaf("status", "Show dev mode: the trees, the dev build and the config", func(ctx context.Context, e *Env) error {
				return show(ctx, e, "dev.get", nil)
			}),
			leaf("on", "Turn dev mode on (and keep it on across sessions)", setDev(true)),
			leaf("off", "Turn dev mode off, back on the installed axiom", setDev(false)),
			leaf("rebuild", "Build the dev tree now and re-exec into it", func(ctx context.Context, e *Env) error {
				return call(ctx, e, "dev.rebuild", nil, nil)
			}),
			{
				Name:    "set",
				Summary: "Make a clone the dev tree (--clear: none)",
				Args:    "[PATH]",
				Setup: func(fs *flag.FlagSet) Runner {
					clearTree := fs.Bool("clear", false, "clear the dev tree (dev mode must be off)")
					return func(ctx context.Context, e *Env, args []string) error {
						var dir string
						switch {
						case *clearTree && len(args) == 0:
						case !*clearTree && len(args) == 1:
							abs, err := devTreeArg(args[0])
							if err != nil {
								return err
							}
							dir = abs
						default:
							return usageError([]string{"axiom", "dev", "set"}, "takes a path, or --clear")
						}
						return setChoice(ctx, e, daemon.DevSetParams{Tree: &dir})
					}
				},
			},
			{
				Name:    "options",
				Summary: "Show or hide the developer options in Settings",
				Args:    "on|off",
				Setup: func(fs *flag.FlagSet) Runner {
					return func(ctx context.Context, e *Env, args []string) error {
						if len(args) != 1 || (args[0] != "on" && args[0] != "off") {
							return usageError([]string{"axiom", "dev", "options"}, "takes on or off")
						}
						on := args[0] == "on"
						return setChoice(ctx, e, daemon.DevSetParams{Options: &on})
					}
				},
			},
			devConfigCommand(),
		},
	}
}

// devTreeArg is the dev tree given, absolute (the daemon resolves it
// further, and checks it).
func devTreeArg(path string) (string, error) {
	if filepath.IsAbs(path) {
		return filepath.Clean(path), nil
	}
	wd, err := os.Getwd()
	if err != nil {
		return "", err
	}
	return filepath.Join(wd, path), nil
}

// printDevState is `axiom dev status`'s text.
func printDevState(w io.Writer, st daemon.DevState) {
	state := "off"
	switch {
	case st.Enabled && st.Active:
		state = "on, running the dev tree"
	case st.Enabled && st.Building:
		state = "on, the installed axiom running while the dev tree builds"
	case st.Enabled:
		state = "on, the installed axiom running"
	case st.Active:
		state = "off, still running the dev tree"
	}
	fmt.Fprintf(w, "dev mode     %s\n", state)
	fmt.Fprintf(w, "install tree %s\n", orNone(st.InstallTree, "unknown"))
	fmt.Fprintf(w, "dev tree     %s\n", orNone(st.Tree, "none (axiom dev set <clone>)"))
	if st.Tree != "" {
		if rev := devRevision(st.Branch, st.Commit, st.Dirty); rev != "" {
			fmt.Fprintf(w, "checkout     %s\n", rev)
		}
		build := "fresh"
		if !st.Build.Fresh {
			build = "stale: " + st.Build.Why
		}
		if st.Build.At != nil {
			build += fmt.Sprintf(" (built %s", st.Build.At.Local().Format("2006-01-02 15:04"))
			if st.Build.Commit != "" {
				build += " at " + devRevision("", st.Build.Commit, st.Build.Dirty)
			}
			build += ")"
		}
		fmt.Fprintf(w, "dev build    %s\n", build)
	}
	config := st.Config.LivePath
	if st.Active {
		config = st.Config.Path
	}
	fmt.Fprintf(w, "config       %s\n", config)
	if st.Active && st.Config.Note != "" {
		fmt.Fprintf(w, "             %s\n", st.Config.Note)
	}
	fmt.Fprintf(w, "binary       %s\ninstalled    %s\n", st.Binary, st.Installed)
	if st.Tree != "" && !st.Available {
		fmt.Fprintf(w, "builds       %s\n", st.Unavailable)
	}
	if b := st.LastBuild; b != nil {
		result := "ok"
		if !b.OK {
			result = "failed"
		}
		fmt.Fprintf(w, "last build   %s at %s\n", result, b.At.Local().Format("15:04:05"))
		if !b.OK {
			fmt.Fprintln(w, b.Output)
		}
	}
}

// devRevision is branch@sha (short), "-dirty" with changes.
func devRevision(branch, commit string, dirty bool) string {
	if len(commit) > 12 {
		commit = commit[:12]
	}
	rev := commit
	if branch != "" {
		rev = branch + "@" + commit
	}
	if dirty && rev != "" {
		rev += "-dirty"
	}
	return rev
}

func orNone(s, none string) string {
	if s == "" {
		return none
	}
	return s
}
