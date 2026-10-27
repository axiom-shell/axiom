package daemon

import (
	"context"

	"github.com/axiom-shell/axiom/backend/internal/command"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// execPart: the commands the shell runs (CommandManager's run and
// runDetached), answered by package command.
func (d *Daemon) execPart() part {
	return part{name: "exec", methods: d.execMethods}
}

func (d *Daemon) execMethods(reg *rpc.Registry) {
	execHandlers(reg, d.commandOptions)
}

// execHandlers are exec.run and exec.spawn, run with options' (the
// shell's, the greeter's quickshell's environment).
func execHandlers(reg *rpc.Registry, options func() command.Options) {
	type runParams struct {
		Argv []string `json:"argv"`
		// Written to stdin (null: none): how secrets travel, never argv
		Input *string `json:"input"`
	}
	type spawnParams struct {
		Argv []string `json:"argv"`
	}
	rpc.Handle(reg, "exec.run", func(ctx context.Context, c *rpc.Conn, p runParams) (command.Result, error) {
		return command.Run(ctx, options(), p.Argv, p.Input)
	})
	rpc.Handle(reg, "exec.spawn", func(ctx context.Context, c *rpc.Conn, p spawnParams) (struct{}, error) {
		return struct{}{}, command.Spawn(ctx, options(), p.Argv)
	})
}

// commandOptions: commands get the shell's environment, as they did when
// the shell started them itself (the daemon's own without a shell)
func (d *Daemon) commandOptions() command.Options {
	if d.shell == nil {
		return command.Options{}
	}
	return command.Options{Env: d.shell.Environ()}
}
