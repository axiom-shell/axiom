// Package cli is the axiom command line: one command table that the router,
// the help text, shell completions and docs/dev/generated/cli.md all come
// from. Commands are thin: they parse arguments, call a library package (or
// the daemon), and print either text or, with --json, one JSON value.
package cli

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// Env is everything a command touches outside its own arguments, so tests
// run commands without a process of their own.
type Env struct {
	Stdin  io.Reader
	Stdout io.Writer
	Stderr io.Writer
	Getenv func(string) string

	Globals Globals
}

// Globals are the flags every command takes.
type Globals struct {
	JSON      bool   // print one JSON value instead of text
	Offline   bool   // never talk to a daemon; use the files directly
	ConfigDir string // the config folder instead of $XDG_CONFIG_HOME/axiom
	Socket    string // the daemon socket instead of the display's
}

// Runner runs a parsed command with its positional arguments.
type Runner func(ctx context.Context, e *Env, args []string) error

// Command is one node of the command table: a group (Subs) or a leaf
// (Setup).
type Command struct {
	Name    string
	Summary string // one line, shown in lists
	Args    string // positional synopsis ("PATH VALUE"), leaves only
	Help    string // longer text shown by `help <command>`
	Hidden  bool   // left out of help and completions (one-time tools)
	// Setup registers the leaf's flags and returns its runner, which reads
	// them through the closure.
	Setup func(fs *flag.FlagSet) Runner
	Subs  []*Command
}

// Main runs the command line and returns the process exit code.
func Main(args []string, e *Env) int {
	ctx, stop := signal.NotifyContext(context.Background(), shutdownSignals(signal.Ignored)...)
	defer stop()
	return Run(ctx, Root(), args, e)
}

// shutdownSignals are the signals that end a command cleanly (a daemon
// stops its shell first): SIGINT, SIGTERM, and SIGHUP (the terminal of an
// `axiom run --dev` closed) unless it was started with SIGHUP ignored
// (nohup), which notifying it would undo.
func shutdownSignals(ignored func(os.Signal) bool) []os.Signal {
	sigs := []os.Signal{os.Interrupt, syscall.SIGTERM}
	if !ignored(syscall.SIGHUP) {
		sigs = append(sigs, syscall.SIGHUP)
	}
	return sigs
}

// Run dispatches args (without the program name) through root.
func Run(ctx context.Context, root *Command, args []string, e *Env) int {
	err := dispatch(ctx, root, []string{root.Name}, args, e)
	if errors.Is(err, flag.ErrHelp) {
		return 0
	}
	if err != nil {
		reportError(e, err)
	}
	return axerr.ExitCode(err)
}

func dispatch(ctx context.Context, cmd *Command, trail []string, args []string, e *Env) error {
	if cmd.Setup == nil {
		if len(args) == 0 || args[0] == "-h" || args[0] == "--help" {
			writeHelp(e.Stdout, cmd, trail)
			if len(args) == 0 {
				return usageError(trail, "missing command")
			}
			return flag.ErrHelp
		}
		// Global flags may come before the subcommand (axiom --json config get)
		if strings.HasPrefix(args[0], "-") {
			rest, err := parseGlobalsOnly(args, e)
			if err != nil {
				return usageError(trail, err.Error())
			}
			return dispatch(ctx, cmd, trail, rest, e)
		}
		sub := cmd.find(args[0])
		if sub == nil {
			return usageError(trail, fmt.Sprintf("unknown command %q", args[0]))
		}
		return dispatch(ctx, sub, append(trail, sub.Name), args[1:], e)
	}

	fs := flag.NewFlagSet(strings.Join(trail, " "), flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	run := cmd.Setup(fs)
	addGlobals(fs, &e.Globals)
	positional, err := parseInterleaved(fs, args)
	if errors.Is(err, flag.ErrHelp) {
		writeHelp(e.Stdout, cmd, trail)
		return flag.ErrHelp
	}
	if err != nil {
		return usageError(trail, err.Error())
	}
	return run(ctx, e, positional)
}

func (c *Command) find(name string) *Command {
	for _, s := range c.Subs {
		if s.Name == name {
			return s
		}
	}
	return nil
}

func addGlobals(fs *flag.FlagSet, g *Globals) {
	fs.BoolVar(&g.JSON, "json", g.JSON, "print one JSON value")
	fs.BoolVar(&g.Offline, "offline", g.Offline, "use the files directly, never a running daemon")
	fs.StringVar(&g.ConfigDir, "config-dir", g.ConfigDir, "the config folder (default $XDG_CONFIG_HOME/axiom)")
	fs.StringVar(&g.Socket, "socket", g.Socket, "the daemon socket (default the display's)")
}

// parseGlobalsOnly takes leading global flags off args.
func parseGlobalsOnly(args []string, e *Env) ([]string, error) {
	fs := flag.NewFlagSet("axiom", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	addGlobals(fs, &e.Globals)
	if err := fs.Parse(args); err != nil {
		return nil, err
	}
	return fs.Args(), nil
}

// parseInterleaved parses flags wherever they appear among the positional
// arguments (`config get Bars --json`). Everything after the first "--" is
// positional, so a value starting with "-" can still be passed.
func parseInterleaved(fs *flag.FlagSet, args []string) ([]string, error) {
	var tail []string
	for i, a := range args {
		if a == "--" {
			args, tail = args[:i], args[i+1:]
			break
		}
	}
	var positional []string
	for {
		if err := fs.Parse(args); err != nil {
			return nil, err
		}
		args = fs.Args()
		if len(args) == 0 {
			return append(positional, tail...), nil
		}
		positional = append(positional, args[0])
		args = args[1:]
	}
}

// usageError is a bad-request error naming the command to get help on.
func usageError(trail []string, msg string) error {
	return axerr.New(axerr.BadRequest, "%s (see `%s --help`)", msg, strings.Join(trail, " "))
}

// reportError prints err as text, or as {"error": …} with --json.
func reportError(e *Env, err error) {
	if e.Globals.JSON {
		body := map[string]any{
			"kind":    axerr.KindOf(err),
			"message": err.Error(),
		}
		if issues := axerr.IssuesOf(err); len(issues) > 0 {
			body["issues"] = issues
		}
		_ = writeJSON(e.Stdout, map[string]any{"error": body})
		return
	}
	fmt.Fprintln(e.Stderr, "axiom:", err)
	for _, issue := range axerr.IssuesOf(err) {
		fmt.Fprintf(e.Stderr, "  %s: %s\n", issue.Path, issue.Message)
	}
}

// Output prints a command's result: value as JSON with --json, else the
// text human writes.
func (e *Env) Output(value any, human func(w io.Writer)) error {
	if e.Globals.JSON {
		return writeJSON(e.Stdout, value)
	}
	human(e.Stdout)
	return nil
}

func writeJSON(w io.Writer, value any) error {
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	return enc.Encode(value)
}
