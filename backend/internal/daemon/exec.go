package daemon

import (
	"context"

	"github.com/axiom-shell/axiom/backend/internal/command"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// execPart: the commands the shell runs (CommandManager's run and
// runDetached) and watches (its acquire), answered by package command.
func (d *Daemon) execPart() part {
	return part{name: "exec", methods: d.execMethods}
}

func (d *Daemon) execMethods(reg *rpc.Registry) {
	execHandlers(reg, d.commandOptions, func() *command.Watches { return d.watches })
}

// execHandlers are exec.run and exec.spawn, run with options' (the
// shell's, the greeter's quickshell's environment), and exec.watch,
// exec.unwatch and exec.refresh on watches' commands (which run with the
// same options).
func execHandlers(reg *rpc.Registry, options func() command.Options, watches func() *command.Watches) {
	type runParams struct {
		Argv []string `json:"argv"`
		// Written to stdin (null: none): how secrets travel, never argv
		Input *string `json:"input"`
	}
	type spawnParams struct {
		Argv []string `json:"argv"`
	}
	type commandParams struct {
		Command string `json:"command"`
	}
	rpc.Handle(reg, "exec.run", func(ctx context.Context, c *rpc.Conn, p runParams) (command.Result, error) {
		return command.Run(ctx, options(), p.Argv, p.Input)
	})
	rpc.Handle(reg, "exec.spawn", func(ctx context.Context, c *rpc.Conn, p spawnParams) (struct{}, error) {
		return struct{}{}, command.Spawn(ctx, options(), p.Argv)
	})
	// Outputs come as exec.outputs pushes, to this connection only
	rpc.Handle(reg, "exec.watch", func(ctx context.Context, c *rpc.Conn, p command.WatchRequest) (struct{}, error) {
		return struct{}{}, watches().Watch(c, p)
	})
	rpc.Handle(reg, "exec.unwatch", func(ctx context.Context, c *rpc.Conn, p commandParams) (struct{}, error) {
		watches().Unwatch(c, p.Command)
		return struct{}{}, nil
	})
	rpc.Handle(reg, "exec.refresh", func(ctx context.Context, c *rpc.Conn, p commandParams) (struct{}, error) {
		watches().Refresh(p.Command)
		return struct{}{}, nil
	})
}

// commandOptions: commands get the shell's environment, as they did when
// the shell started them itself (the daemon's own without a shell)
func (d *Daemon) commandOptions() command.Options {
	o := command.Options{Children: &d.children}
	if d.shell != nil {
		o.Env = d.shell.Environ()
	}
	return o
}
