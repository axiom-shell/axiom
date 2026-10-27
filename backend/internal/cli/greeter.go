package cli

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/assets"
	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/daemon"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/greeter"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/schema"
	"github.com/axiom-shell/axiom/backend/internal/tree"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// The inherited AXIOM_* variables a greeter's quickshell keeps: the knobs
// for looking at it from a session. Every other one is dropped (as
// supervise does for the shell), so a session axiom's socket, pid, tree or
// handoff never reaches the greeter; axiom greeter sets its own.
var greeterKept = []string{"AXIOM_GREETER_WINDOWED", "AXIOM_COMPOSITOR", "AXIOM_COMPOSITOR_OFF"}

func greeterCommand() *Command {
	return &Command{
		Name:    "greeter",
		Summary: "Run axiom's login screen (greetd's greeter) on its exported config",
		Help: `Loads the config the user's axiom exported for the login screen (the
bundle, <dir>/config/greeter.json), else the snapshot the install took
(fallback/greeter.json), else the defaults, through the same pipeline as
config.json, writes it to a private runtime folder and runs the tree's
greeter.qml on it, staying quickshell's parent until it exits: the
greeter's commands and lookups go through this process, on a socket in
that folder. greeter-session.sh runs it as greetd's user. To look at it
from a session, set AXIOM_GREETER_WINDOWED=1 and point --dir at a
scratch folder.`,
		Setup: func(fs *flag.FlagSet) Runner {
			dir := fs.String("tree", "", "the axiom tree whose greeter runs (default: $AXIOM_TREE, the one here, else the installed one)")
			greeterDir := fs.String("dir", "", "the greeter's folder (default $AXIOM_GREETER_DIR, else /var/lib/axiom-greeter)")
			safe := fs.Bool("safe", false, "skip the bundle: the install's snapshot, else the defaults (also $AXIOM_GREETER_SAFE=1)")
			qs := fs.String("qs", "qs", "the quickshell binary")
			noShell := fs.Bool("no-shell", false, "load and write the config, print where, but don't start the greeter")
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) > 0 {
					return usageError([]string{"axiom", "greeter"}, "takes no arguments")
				}
				wd, _ := os.Getwd()
				root, err := tree.Find(*dir, e.Getenv, wd)
				if err != nil {
					return err
				}
				gdir := *greeterDir
				if gdir == "" {
					gdir = e.Getenv("AXIOM_GREETER_DIR")
				}
				if gdir == "" {
					gdir = "/var/lib/axiom-greeter"
				}
				schemaBytes, err := tree.BuildSchema(root)
				if err != nil {
					// The binary's own: the copy and the binary are installed together
					fmt.Fprintf(e.Stderr, "axiom greeter: the tree's schema doesn't build (%v); using the binary's\n", err)
					if schemaBytes, err = assets.Read(tree.SchemaJSON); err != nil {
						return axerr.Wrap(axerr.Internal, err, "the binary's schema")
					}
				}
				parsed, err := jsonx.Unmarshal(schemaBytes)
				if err != nil {
					return axerr.Wrap(axerr.Internal, err, "the schema")
				}
				fallback := e.Getenv("AXIOM_GREETER_FALLBACK")
				if fallback == "" {
					fallback = filepath.Join(root, "fallback")
				}
				var candidates []greeter.Candidate
				if !*safe && e.Getenv("AXIOM_GREETER_SAFE") != "1" {
					candidates = append(candidates, greeter.Candidate{Source: "bundle", Path: filepath.Join(gdir, "config", "greeter.json")})
				}
				candidates = append(candidates, greeter.Candidate{Source: "fallback", Path: filepath.Join(fallback, "greeter.json")})
				result := greeter.Load(config.V2Pipeline{S: schema.New(parsed)}, candidates)
				for _, p := range result.Problems {
					fmt.Fprintf(e.Stderr, "axiom greeter: skipped the %s: %s\n", p.Source, p.Error)
				}
				run, err := greeterRuntime(e.Getenv, gdir)
				if err != nil {
					return err
				}
				configPath, schemaPath := filepath.Join(run, "config.json"), filepath.Join(run, "config.schema.json")
				if err := fsx.WriteFile(configPath, jsonx.Marshal(result.Config), 0o600); err != nil {
					return axerr.Wrap(axerr.Unavailable, err, "writing the greeter's config")
				}
				if err := fsx.WriteFile(schemaPath, schemaBytes, 0o600); err != nil {
					return axerr.Wrap(axerr.Unavailable, err, "writing the greeter's schema")
				}
				fmt.Fprintf(e.Stderr, "axiom greeter: the config from the %s\n", result.Source)
				if *noShell {
					fmt.Fprintln(e.Stdout, configPath)
					return nil
				}
				bin, err := exec.LookPath(*qs)
				if err != nil {
					return axerr.Wrap(axerr.Unavailable, err, "quickshell (%s)", *qs)
				}
				self, err := os.Executable()
				if err != nil {
					return axerr.Wrap(axerr.Unavailable, err, "finding the axiom binary")
				}
				env := greeterEnv(os.Environ(), map[string]string{
					"AXIOM_GREETER":          "1",
					"AXIOM_GREETER_DIR":      gdir,
					"AXIOM_GREETER_FALLBACK": strings.TrimSuffix(fallback, "/") + "/",
					"AXIOM_GREETER_SOURCE":   result.Source,
					"AXIOM_CONFIG":           configPath,
					"AXIOM_SCHEMA":           schemaPath,
					"AXIOM_TREE":             root,
					// What reads the compositor's config (axiom compositor …)
					"AXIOM_BIN": self,
				})
				return daemon.RunGreeter(ctx, daemon.GreeterOptions{
					Command:    []string{bin, "-p", filepath.Join(root, "greeter.qml")},
					Environ:    env,
					Dir:        run,
					SchemaHash: buildinfo.SchemaHash(schemaBytes),
					Tree:       root,
					Getenv:     e.Getenv,
					Output:     e.Stderr,
					Log:        slog.New(slog.NewTextHandler(e.Stderr, nil)),
				})
			}
		},
	}
}

// greeterRuntime is the private folder the greeter's config is written
// to: $XDG_RUNTIME_DIR/axiom/greeter-<display>, never the session's own
// display folder (a greeter looked at from a session would overwrite the
// daemon's snapshot); without a runtime dir, the greeter's state folder.
func greeterRuntime(getenv func(string) string, gdir string) (string, error) {
	if root, err := xdg.RuntimeRoot(getenv, true); err == nil {
		dir := filepath.Join(root, "greeter")
		if display := xdg.DisplayName(getenv("WAYLAND_DISPLAY")); display != "" {
			dir += "-" + display
		}
		return dir, xdg.PrivateDir(dir, true)
	}
	dir := filepath.Join(gdir, "state", "run")
	return dir, xdg.PrivateDir(dir, true)
}

// greeterEnv is environ with set's variables replacing theirs, and every
// inherited AXIOM_* but greeterKept left out.
func greeterEnv(environ []string, set map[string]string) []string {
	out := make([]string, 0, len(environ)+len(set))
	for _, kv := range environ {
		name, _, _ := strings.Cut(kv, "=")
		if _, replaced := set[name]; replaced || strings.HasPrefix(name, "AXIOM_") && !slices.Contains(greeterKept, name) {
			continue
		}
		out = append(out, kv)
	}
	for name, value := range set {
		out = append(out, name+"="+value)
	}
	return out
}
