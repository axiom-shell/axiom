package cli

import (
	"context"
	"flag"
	"fmt"
	"io"

	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
)

// Root is the whole command table.
func Root() *Command {
	root := &Command{
		Name:    "axiom",
		Summary: "The axiom desktop: runs the shell, owns its config, and is its command line.",
		Subs: []*Command{
			runCommand(),
			greeterCommand(),
			pingCommand(),
			restartCommand(),
			quitCommand(),
			daemonCommand(),
			devCommand(),
			configCommand(),
			schemaCommand(),
			lockCommand(),
			ipcCommand(),
			compositorCommand(),
			debugCommand(),
			versionCommand(),
		},
	}
	root.Subs = append(root.Subs, namedCommandList()...)
	return root
}

func versionCommand() *Command {
	return &Command{
		Name:    "version",
		Summary: "Show this binary's version, commit and protocol",
		Setup: func(fs *flag.FlagSet) Runner {
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) > 0 {
					return usageError([]string{"axiom", "version"}, "takes no arguments")
				}
				info := buildinfo.Get()
				return e.Output(info, func(w io.Writer) {
					commit := info.Commit
					if len(commit) > 12 {
						commit = commit[:12]
					}
					if info.Dirty {
						commit += "-dirty"
					}
					if commit == "" {
						commit = "unknown"
					}
					fmt.Fprintf(w, "axiom %s (commit %s, %s, %s, protocol %d)\n",
						info.Version, commit, info.GoVersion, info.Platform, info.Protocol)
				})
			}
		},
	}
}
