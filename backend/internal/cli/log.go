package cli

import (
	"context"
	"flag"
	"os"
	"os/exec"
	"syscall"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/daemon"
	"github.com/axiom-shell/axiom/backend/internal/tree"
)

func logCommand() *Command {
	return &Command{
		Name:    "log",
		Summary: "Show the shell's log (debug lines only with --debug; -f follows)",
		Args:    "[-- QS-ARGS…]",
		Help: `Prints the log of the shell axiom runs: quickshell's log of the
instance running from the shell's QML folder, which the daemon names (with
no daemon, the tree here or the installed one). console.log and debug lines
are left out unless --debug. Anything after "--" goes to "qs log" as is:
  axiom log -f            follow it
  axiom log -- -t 50      only the last 50 lines
Attach its output to a bug report, with "axiom bug-info".`,
		Setup: func(fs *flag.FlagSet) Runner {
			var follow bool
			fs.BoolVar(&follow, "f", false, "follow the log")
			fs.BoolVar(&follow, "follow", false, "follow the log")
			debug := fs.Bool("debug", false, "include console.log and debug output")
			dir := fs.String("tree", "", "read the shell of this tree, not the running one")
			qs := fs.String("qs", "qs", "the quickshell binary")
			return func(ctx context.Context, e *Env, args []string) error {
				qml, err := logQMLDir(ctx, e, *dir)
				if err != nil {
					return err
				}
				return execQS(logArgv(*qs, qml, follow, *debug, args))
			}
		},
	}
}

// logRules hides console.log and debug output, as the shell's own log
// view (scripts/log.sh) did by default.
const logRules = "*.debug=false"

// logArgv is the `qs log` command reading the instance that runs from qml.
func logArgv(qs, qml string, follow, debug bool, extra []string) []string {
	argv := []string{qs, "log", "-p", qml}
	if !debug {
		argv = append(argv, "-r", logRules)
	}
	if follow {
		argv = append(argv, "-f")
	}
	return append(argv, extra...)
}

// logQMLDir is the QML folder whose shell's log to read: --tree's; else
// the one the running daemon's shell runs from (daemon.status); else, with
// no daemon (or --offline), the tree here or the installed one.
func logQMLDir(ctx context.Context, e *Env, dir string) (string, error) {
	if dir == "" && !e.Globals.Offline {
		var status daemon.StatusResult
		if call(ctx, e, "daemon.status", nil, &status) == nil {
			if status.QMLDir != "" {
				return status.QMLDir, nil
			}
			if status.Tree != "" {
				return tree.QMLDir(status.Tree), nil
			}
		}
	}
	wd, _ := os.Getwd()
	root, err := tree.Find(dir, e.Getenv, wd)
	if err != nil {
		return "", err
	}
	return tree.QMLDir(root), nil
}

// execQS replaces this process with argv (qs found on PATH), so `-f`
// follows until interrupted, as qs itself would.
func execQS(argv []string) error {
	path, err := exec.LookPath(argv[0])
	if err != nil {
		return axerr.Wrap(axerr.NotFound, err, "quickshell (%s) isn't installed", argv[0])
	}
	err = syscall.Exec(path, argv, os.Environ())
	return axerr.Wrap(axerr.Unavailable, err, "running %s", path)
}
