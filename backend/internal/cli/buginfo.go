package cli

import (
	"context"
	"flag"
	"fmt"
	"io"
	"os/exec"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/buginfo"
	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
	"github.com/axiom-shell/axiom/backend/internal/tree"
)

func bugInfoCommand() *Command {
	return &Command{
		Name:    "bug-info",
		Summary: "Print what a bug report needs to know about this machine",
		Help: "Prints the block the bug report form's System info field asks for: axiom's version, the binary's\n" +
			"and whether it runs, Quickshell's, the compositor's and how many monitors are on, the distribution,\n" +
			"and the config's format, version, compositor mode and whether it loads. Nothing personal: no\n" +
			"monitor names, no paths.",
		Setup: func(fs *flag.FlagSet) Runner {
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) > 0 {
					return usageError([]string{"axiom", "bug-info"}, "takes no arguments")
				}
				r, err := bugReport(ctx, e)
				if err != nil {
					return err
				}
				return e.Output(r, func(w io.Writer) {
					for _, line := range [][2]string{
						{"axiom", r.Axiom}, {"Binary", r.Binary}, {"Quickshell", r.Quickshell}, {"Compositor", r.Compositor},
						{"Monitors", r.Monitors}, {"Distro", r.Distro}, {"Config", r.Config},
					} {
						fmt.Fprintf(w, "%-11s %s\n", line[0]+":", line[1])
					}
				})
			}
		},
	}
}

// bugReport reads the binary, the tree and the config from the daemon
// when one runs (what the shell really runs), else from this binary and
// the files.
func bugReport(ctx context.Context, e *Env) (buginfo.Report, error) {
	var r buginfo.Report
	var treeDir string
	if !e.Globals.Offline {
		c, hello, err := connect(ctx, e)
		switch {
		case err == nil:
			c.Close()
			r.Binary = fmt.Sprintf("axiom %s (commit %s), running", hello.Version, shortCommit(hello.Commit))
			treeDir = hello.Tree
		case axerr.KindOf(err) != axerr.Unavailable:
			return r, err
		}
	}
	if r.Binary == "" {
		info := buildinfo.Get()
		r.Binary = fmt.Sprintf("axiom %s (commit %s), not running", info.Version, shortCommit(info.Commit))
		// The installed tree, as `axiom run` from $HOME finds it
		treeDir, _ = tree.Find("", e.Getenv, "/")
	}
	cfg, st, _, _, err := current(ctx, e, "")
	if err != nil && axerr.KindOf(err) != axerr.InvalidConfig {
		return r, err
	}
	r.Config = buginfo.ConfigLine(cfg, st)
	buginfo.Machine(ctx, buginfo.Options{
		Tree:       treeDir,
		Compositor: buginfo.CompositorFromEnv(e.Getenv),
		Desktop:    e.Getenv("XDG_CURRENT_DESKTOP"),
		Output: func(ctx context.Context, name string, args ...string) (string, error) {
			out, err := exec.CommandContext(ctx, name, args...).Output()
			return string(out), err
		},
		OSRelease: []string{"/etc/os-release", "/usr/lib/os-release"},
	}, &r)
	return r, nil
}

func shortCommit(commit string) string {
	if commit == "" {
		return buginfo.Unknown
	}
	return commit[:min(len(commit), 12)]
}
