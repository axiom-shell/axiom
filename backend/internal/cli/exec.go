package cli

import (
	"context"
	"flag"
)

func execCommand() *Command {
	return &Command{
		Name:    "exec",
		Summary: "Reach the commands the shell watches",
		Subs: []*Command{{
			Name:    "refresh",
			Summary: "Run a watched command again now (what Waybar's signal did)",
			Args:    "COMMAND",
			Help: `COMMAND is the watched shell command exactly as the widget or module
runs it (a Button's label command, a CommandOutput's command), e.g. in a
script after it changed what the command shows:
  axiom exec refresh "~/bin/vpn-status"
A command nobody watches is left alone. A streamed command keeps running
and only publishes its last line again.`,
			Setup: func(fs *flag.FlagSet) Runner {
				return func(ctx context.Context, e *Env, args []string) error {
					if len(args) != 1 {
						return usageError([]string{"axiom", "exec", "refresh"}, "takes one command")
					}
					return call(ctx, e, "exec.refresh", map[string]string{"command": args[0]}, nil)
				}
			},
		}},
	}
}
