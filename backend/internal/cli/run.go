package cli

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"os"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/daemon"
	"github.com/axiom-shell/axiom/backend/internal/logfile"
	"github.com/axiom-shell/axiom/backend/internal/tree"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

func runCommand() *Command {
	return &Command{
		Name:    "run",
		Summary: "Run axiom on this display: the shell, its config and its socket",
		Help: `Starts the daemon for $WAYLAND_DISPLAY and the shell (quickshell) as its
child, restarting the shell if it crashes. Put "axiom run" in your
compositor's autostart. With --dev it starts in dev mode whatever was
chosen last (see "axiom dev"), and logs go to the terminal too.`,
		Setup: func(fs *flag.FlagSet) Runner {
			dir := fs.String("tree", "", "the axiom tree to run (default: $AXIOM_TREE, the one here, else the installed one)")
			dev := fs.Bool("dev", false, "start in dev mode and log to the terminal")
			noShell := fs.Bool("no-shell", false, "run the daemon without starting the shell")
			qs := fs.String("qs", "qs", "the quickshell binary")
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) > 0 {
					return usageError([]string{"axiom", "run"}, "takes no arguments")
				}
				wd, _ := os.Getwd()
				root, err := tree.Find(*dir, e.Getenv, wd)
				if err != nil {
					return err
				}
				dirs := xdg.Resolve(e.Getenv)
				lf, err := logfile.Open(dirs.State+"log/daemon.log", 2<<20)
				if err != nil {
					return err
				}
				defer lf.Close()
				var out io.Writer = lf
				var shellOut io.Writer
				if *dev {
					out = io.MultiWriter(lf, e.Stderr)
					shellOut = e.Stderr
				}
				// Debug while dev mode is on: the daemon sets it
				level := new(slog.LevelVar)
				log := slog.New(slog.NewTextHandler(out, &slog.HandlerOptions{Level: level}))
				return daemon.Run(ctx, daemon.Options{
					Tree: root, Dev: *dev, NoShell: *noShell, QS: *qs,
					Getenv: e.Getenv, Log: log, LogLevel: level, ShellOutput: shellOut,
				})
			}
		},
	}
}

func pingCommand() *Command {
	return &Command{
		Name:    "ping",
		Summary: "Check that axiom runs here, and which",
		Setup: func(fs *flag.FlagSet) Runner {
			return func(ctx context.Context, e *Env, args []string) error {
				var status daemon.StatusResult
				if err := call(ctx, e, "daemon.status", nil, &status); err != nil {
					return err
				}
				return e.Output(status, func(w io.Writer) {
					shell := "no shell"
					if status.Shell != nil {
						if status.Shell.Running {
							shell = fmt.Sprintf("shell pid %d", status.Shell.PID)
						} else {
							shell = "shell not running"
						}
					}
					fmt.Fprintf(w, "axiom %s on %s: pid %d, %s, up %s\n", status.Version, status.Display, status.PID, shell, status.Uptime)
					if !status.Compatible {
						fmt.Fprintf(w, "read-only: %s\n", status.Reason)
					}
				})
			}
		},
	}
}

func restartCommand() *Command {
	return &Command{
		Name:    "restart",
		Summary: "Restart the shell (the daemon keeps running)",
		Setup: func(fs *flag.FlagSet) Runner {
			return func(ctx context.Context, e *Env, args []string) error {
				return call(ctx, e, "shell.restart", nil, nil)
			}
		},
	}
}

func quitCommand() *Command {
	return &Command{
		Name:    "quit",
		Summary: "Stop axiom on this display: the shell and the daemon",
		Setup: func(fs *flag.FlagSet) Runner {
			return func(ctx context.Context, e *Env, args []string) error {
				return call(ctx, e, "daemon.shutdown", nil, nil)
			}
		},
	}
}

func daemonCommand() *Command {
	return &Command{
		Name:    "daemon",
		Summary: "The daemon itself: its status, its log, an in-place upgrade",
		Subs: []*Command{
			{
				Name:    "status",
				Summary: "Show the daemon's state (as JSON with --json)",
				Setup: func(fs *flag.FlagSet) Runner {
					return func(ctx context.Context, e *Env, args []string) error {
						var status daemon.StatusResult
						if err := call(ctx, e, "daemon.status", nil, &status); err != nil {
							return err
						}
						return e.Output(status, func(w io.Writer) {
							fmt.Fprintf(w, "axiom %s (protocol %d) on %s, pid %d, up %s\n", status.Version, status.Protocol, status.Display, status.PID, status.Uptime)
							fmt.Fprintf(w, "tree     %s\nconfig   %srevision %d\nclients  %d\n", status.Tree, status.Dirs.Config, status.State.Revision, status.Clients)
							if status.Shell != nil {
								fmt.Fprintf(w, "shell    running %v, pid %d, restarts %d\n", status.Shell.Running, status.Shell.PID, status.Shell.Restarts)
							}
						})
					}
				},
			},
			{
				Name:    "reexec",
				Summary: "Replace the daemon with the binary now on disk, keeping the shell running",
				Setup: func(fs *flag.FlagSet) Runner {
					return func(ctx context.Context, e *Env, args []string) error {
						return call(ctx, e, "daemon.reexec", nil, nil)
					}
				},
			},
			{
				Name:    "logs",
				Summary: "Print the daemon's log",
				Setup: func(fs *flag.FlagSet) Runner {
					return func(ctx context.Context, e *Env, args []string) error {
						data, err := os.ReadFile(xdg.Resolve(e.Getenv).State + "log/daemon.log")
						if errors.Is(err, os.ErrNotExist) {
							return axerr.Wrap(axerr.NotFound, err, "no daemon log yet")
						}
						if err != nil {
							return axerr.Wrap(axerr.Unavailable, err, "reading the daemon log")
						}
						_, err = e.Stdout.Write(data)
						return err
					}
				},
			},
		},
	}
}
