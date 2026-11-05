package cli

import (
	"context"
	"flag"
	"fmt"
	"io"
	"os/exec"
	"strings"
	"syscall"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/mimeapps"
)

func openCommand() *Command {
	return &Command{
		Name:    "open",
		Summary: "Open a URL, a file or an app in the default app",
		Args:    "TARGET [ARG...]",
		Help: `TARGET is what to open: a URL, a file or folder, or one of the default apps
Settings › General › Default apps sets:
  browser mail fileManager terminal textEditor images video music pdf archives
followed by what it's given (the URLs or files; the terminal's command to run).
A custom command the config sets (Apps.commands.<role>) is used in place of
the default. The keybinds run it, e.g.:
  axiom open browser
  axiom open terminal -- htop
  axiom open ~/Downloads
  axiom open https://example.com
The running axiom starts it, as the shell starts apps; without one it's
worked out here, from the config file and the mimeapps lists.`,
		Setup: func(fs *flag.FlagSet) Runner {
			print := fs.Bool("print", false, "print the command it would start, worked out here, and start nothing")
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) == 0 {
					return usageError([]string{"axiom", "open"}, "takes what to open")
				}
				target, rest := args[0], args[1:]
				if len(rest) > 0 && rest[0] == "--" {
					rest = rest[1:]
				}
				if *print {
					argv, err := commandHere(ctx, e, target, rest)
					if err != nil {
						return err
					}
					return e.Output(argv, func(w io.Writer) { fmt.Fprintln(w, strings.Join(argv, " ")) })
				}
				if !e.Globals.Offline {
					err := call(ctx, e, "apps.open", map[string]any{"target": target, "args": rest}, nil)
					if err == nil || axerr.KindOf(err) != axerr.Unavailable {
						return err
					}
				}
				return openHere(ctx, e, target, rest)
			}
		},
	}
}

// openHere opens target with no daemon to ask: the config file's
// overrides, this process's environment, started in a session of its own
// so it outlives the command.
func openHere(ctx context.Context, e *Env, target string, args []string) error {
	argv, err := commandHere(ctx, e, target, args)
	if err != nil {
		return err
	}
	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	cmd.Stdin, cmd.Stdout, cmd.Stderr = nil, nil, nil
	if err := cmd.Start(); err != nil {
		return axerr.Wrap(axerr.NotFound, err, "starting %s", argv[0])
	}
	return cmd.Process.Release()
}

// commandHere is what opens target, worked out in this process.
func commandHere(ctx context.Context, e *Env, target string, args []string) ([]string, error) {
	offline := *e
	offline.Globals.Offline = true
	cfg, _, _, _, _ := current(ctx, &offline, "")
	return mimeapps.Load(mimeapps.FromEnv(e.Getenv)).Command(target, args, mimeapps.OverridesFrom(cfg))
}
