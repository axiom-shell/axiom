package cli

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/assets"
	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/saved"
	"github.com/axiom-shell/axiom/backend/internal/schema"
	"github.com/axiom-shell/axiom/backend/internal/store"
	"github.com/axiom-shell/axiom/backend/internal/tree"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

func configCommand() *Command {
	return &Command{
		Name:    "config",
		Summary: "Read, change and check the config",
		Help: `With axiom running, changes go through it (the shell shows them at once);
without, or with --offline, the file is read and written directly. Paths are
keys joined by dots, a list's item by its id: Bars.main.location (or
Bars[main].location, quoted in zsh).`,
		Subs: []*Command{
			configPathCommand(),
			configGetCommand(),
			configSetCommand(),
			configResetCommand(),
			configValidateCommand(),
			configShareCommand(),
			configStatusCommand(),
		},
	}
}

// configDir is the config folder: --config-dir, else $XDG_CONFIG_HOME/axiom.
func configDir(e *Env) string {
	if e.Globals.ConfigDir != "" {
		return e.Globals.ConfigDir
	}
	return xdg.Resolve(e.Getenv).Config
}

// offlinePipeline is the pipeline used without a daemon: this binary's own
// schema, or a tree's with --tree.
func offlinePipeline(e *Env, treeDir string) (config.Pipeline, error) {
	var data []byte
	var err error
	if treeDir != "" {
		root, ferr := tree.Find(treeDir, e.Getenv, "")
		if ferr != nil {
			return nil, ferr
		}
		data, err = tree.BuildSchema(root)
	} else {
		data, err = assets.Read("config/json/config.schema.json")
	}
	if err != nil {
		return nil, err
	}
	root, err := jsonx.Unmarshal(data)
	if err != nil {
		return nil, err
	}
	return config.V2Pipeline{S: schema.New(root)}, nil
}

// current is the config as the daemon has it, or read from the file
// (offline), with the pipeline its schema is read through.
func current(ctx context.Context, e *Env, treeDir string) (*jsonx.Object, store.State, config.Pipeline, bool, error) {
	pipeline, err := offlinePipeline(e, treeDir)
	if err != nil {
		return nil, store.State{}, nil, false, err
	}
	if !e.Globals.Offline {
		var res struct {
			Config json.RawMessage `json:"config"`
			State  store.State     `json:"state"`
		}
		err := call(ctx, e, "config.get", nil, &res)
		if err == nil {
			v, err := jsonx.Unmarshal(res.Config)
			if err != nil {
				return nil, store.State{}, nil, false, err
			}
			return v.(*jsonx.Object), res.State, pipeline, true, nil
		}
		if axerr.KindOf(err) != axerr.Unavailable {
			return nil, store.State{}, nil, false, err
		}
	}
	cfg, st, err := store.Peek(store.Options{Dir: configDir(e), Pipeline: pipeline})
	return cfg, st, pipeline, false, err
}

func configPathCommand() *Command {
	return &Command{
		Name:    "path",
		Summary: "Show where the config and axiom's other files are",
		Setup: func(fs *flag.FlagSet) Runner {
			return func(ctx context.Context, e *Env, args []string) error {
				dirs := xdg.Resolve(e.Getenv)
				file := filepath.Join(configDir(e), store.FileName)
				return e.Output(map[string]any{"config": file, "dirs": dirs}, func(w io.Writer) {
					fmt.Fprintln(w, file)
				})
			}
		},
	}
}

func configGetCommand() *Command {
	return &Command{
		Name:    "get",
		Summary: "Print a setting (or a section, or the whole config)",
		Args:    "[PATH]",
		Setup: func(fs *flag.FlagSet) Runner {
			showSchema := fs.Bool("schema", false, "print the setting's schema instead of its value")
			treeDir := fs.String("tree", "", "read through this tree's schema")
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) > 1 {
					return usageError([]string{"axiom", "config", "get"}, "takes one path")
				}
				cfg, _, pipeline, _, err := current(ctx, e, *treeDir)
				if err != nil {
					return err
				}
				var path config.Path
				if len(args) == 1 {
					if path, err = config.ParsePath(args[0]); err != nil {
						return err
					}
					path = config.Resolve(cfg, path)
				}
				var value any
				var ok bool
				if *showSchema {
					value, ok = config.NodeAt(pipeline.Schema(), cfg, path)
				} else {
					value, ok = config.Lookup(cfg, path)
				}
				if !ok {
					return axerr.New(axerr.NotFound, "no setting %s", path)
				}
				if e.Globals.JSON {
					_, err := e.Stdout.Write(jsonx.Marshal(value))
					return err
				}
				if s, ok := value.(string); ok {
					fmt.Fprintln(e.Stdout, s)
					return nil
				}
				_, err = e.Stdout.Write(jsonx.Marshal(value))
				return err
			}
		},
	}
}

func configSetCommand() *Command {
	return &Command{
		Name:    "set",
		Summary: "Change a setting",
		Args:    "PATH VALUE",
		Help: `VALUE is read as the setting's type: on/off for a switch, a number, the
text itself for a string, JSON for anything else (or always, with --value-json).
A setting that takes something over on this PC (the compositor mode, the lock
screen, idle, polkit, the greeter) also needs --takeover.`,
		Setup: func(fs *flag.FlagSet) Runner {
			takeover := fs.Bool("takeover", false, "allow changing a takeover setting")
			asJSON := fs.Bool("value-json", false, "read VALUE as JSON")
			treeDir := fs.String("tree", "", "check against this tree's schema (offline)")
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) != 2 {
					return usageError([]string{"axiom", "config", "set"}, "takes a path and a value")
				}
				path, err := config.ParsePath(args[0])
				if err != nil {
					return err
				}
				cfg, _, pipeline, _, err := current(ctx, e, *treeDir)
				if err != nil {
					return err
				}
				path = config.Resolve(cfg, path)
				var value any
				if *asJSON {
					if value, err = jsonx.Unmarshal([]byte(args[1])); err != nil {
						return axerr.New(axerr.BadRequest, "VALUE isn't JSON: %v", err)
					}
				} else {
					node, ok := config.NodeAt(pipeline.Schema(), cfg, path)
					if !ok {
						return axerr.New(axerr.NotFound, "no setting %s", path)
					}
					if value, err = config.ParseValue(node, args[1]); err != nil {
						return err
					}
				}
				return applyOps(ctx, e, *treeDir, []config.Op{config.SetValue(path, value)}, *takeover)
			}
		},
	}
}

func configResetCommand() *Command {
	return &Command{
		Name:    "reset",
		Summary: "Put a setting back to its default",
		Args:    "PATH",
		Setup: func(fs *flag.FlagSet) Runner {
			takeover := fs.Bool("takeover", false, "allow changing a takeover setting")
			treeDir := fs.String("tree", "", "check against this tree's schema (offline)")
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) != 1 {
					return usageError([]string{"axiom", "config", "reset"}, "takes a path")
				}
				path, err := config.ParsePath(args[0])
				if err != nil {
					return err
				}
				cfg, _, _, _, err := current(ctx, e, *treeDir)
				if err != nil {
					return err
				}
				path = config.Resolve(cfg, path)
				// Deleting a key fills it back with its default
				return applyOps(ctx, e, *treeDir, []config.Op{{Op: "delete", Path: path}}, *takeover)
			}
		},
	}
}

// applyOps writes ops through the daemon, or (offline, or none running)
// to the file under the writer lock.
func applyOps(ctx context.Context, e *Env, treeDir string, ops []config.Op, takeover bool) error {
	if !e.Globals.Offline {
		var res struct {
			Revision int64 `json:"revision"`
		}
		err := call(ctx, e, "config.set", map[string]any{"ops": ops, "takeover": takeover}, &res)
		if err == nil {
			return e.Output(res, func(w io.Writer) {})
		}
		if axerr.KindOf(err) != axerr.Unavailable {
			return err
		}
	}
	pipeline, err := offlinePipeline(e, treeDir)
	if err != nil {
		return err
	}
	opts := store.Options{Dir: configDir(e), Pipeline: pipeline}
	if e.Globals.ConfigDir == "" {
		// The takeovers kept are the XDG config's: never another folder's
		opts.TakeoversFile = filepath.Join(xdg.Resolve(e.Getenv).State, store.TakeoversFile)
	}
	s, err := store.Open(opts)
	if err != nil {
		if axerr.KindOf(err) == axerr.Running {
			return &axerr.Error{Kind: axerr.Running, Message: "axiom is running and owns the config: drop --offline to change it through axiom", Err: err}
		}
		return err
	}
	defer s.Close()
	rev, err := s.Set(ops, store.SetOptions{Takeover: takeover})
	if err != nil {
		return err
	}
	return e.Output(map[string]any{"revision": rev}, func(w io.Writer) {})
}

func configValidateCommand() *Command {
	return &Command{
		Name:    "validate",
		Summary: "Check a config file (default: the config) without changing it",
		Args:    "[FILE]",
		Setup: func(fs *flag.FlagSet) Runner {
			treeDir := fs.String("tree", "", "check against this tree's schema")
			return func(ctx context.Context, e *Env, args []string) error {
				file := filepath.Join(configDir(e), store.FileName)
				if len(args) == 1 {
					file = args[0]
				} else if len(args) > 1 {
					return usageError([]string{"axiom", "config", "validate"}, "takes one file")
				}
				parsed, err := readConfigFile(file)
				if err != nil {
					return err
				}
				pipeline, err := offlinePipeline(e, *treeDir)
				if err != nil {
					return err
				}
				loaded, err := pipeline.Load(parsed)
				if err != nil {
					return err
				}
				result := map[string]any{"file": file, "valid": len(loaded.Errors) == 0, "migrated": loaded.Migrated, "removed": loaded.Removed, "changes": loaded.Changes}
				if len(loaded.Errors) > 0 {
					e := &axerr.Error{Kind: axerr.InvalidConfig, Message: fmt.Sprintf("%s is invalid (%d problems)", file, len(loaded.Errors))}
					for _, line := range loaded.Errors {
						path, msg, _ := strings.Cut(line, ": ")
						e.Issues = append(e.Issues, axerr.Issue{Path: path, Message: msg})
					}
					return e
				}
				return e.Output(result, func(w io.Writer) {
					fmt.Fprintf(w, "%s is valid", file)
					if loaded.Migrated {
						fmt.Fprintf(w, " (from an older version: %d changes when loaded)", len(loaded.Changes))
					}
					if len(loaded.Removed) > 0 {
						fmt.Fprintf(w, "; unknown keys dropped: %s", strings.Join(loaded.Removed, ", "))
					}
					fmt.Fprintln(w)
				})
			}
		},
	}
}

// readConfigFile is file parsed, or an invalid_config error when it isn't
// JSON.
func readConfigFile(file string) (any, error) {
	data, err := os.ReadFile(file)
	if err != nil {
		return nil, axerr.Wrap(axerr.NotFound, err, "reading %s", file)
	}
	parsed, err := jsonx.Unmarshal(data)
	if err != nil {
		return nil, &axerr.Error{Kind: axerr.InvalidConfig, Message: file + " isn't JSON", Issues: []axerr.Issue{{Path: "", Message: err.Error()}}}
	}
	return parsed, nil
}

func configShareCommand() *Command {
	return &Command{
		Name:    "share",
		Summary: "Print a shared config file as Export would write it",
		Args:    "FILE",
		Help: `FILE (an export of any version) is loaded as an import is, then printed as
Export writes it: its title and description, then only its look, without what
it holds that's personal (keybinds, apps), runs a command, belongs to the PC
(monitor names, wallpapers, accounts) or takes something over. Those are listed
as dropped, each with its scope. With --places, a monitor already named by its
place (#2, @primary, *) is kept. Nothing is changed or applied; the
community setups' checks run this.`,
		Setup: func(fs *flag.FlagSet) Runner {
			treeDir := fs.String("tree", "", "load through this tree's schema")
			places := fs.Bool("places", false, "keep monitors named by their place")
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) != 1 {
					return usageError([]string{"axiom", "config", "share"}, "takes one file")
				}
				file := args[0]
				parsed, err := readConfigFile(file)
				if err != nil {
					return err
				}
				pipeline, err := offlinePipeline(e, *treeDir)
				if err != nil {
					return err
				}
				shared, err := saved.Share(pipeline, parsed, filepath.Base(file), *places)
				if err != nil {
					return err
				}
				l := shared.Loaded
				result := map[string]any{
					"file": file, "valid": true, "migrated": l.Migrated, "removed": l.Removed, "changes": l.Changes,
					"format": shared.Export.Value("format"), "version": shared.Export.Value("version"),
					"config": json.RawMessage(jsonx.Marshal(shared.Export)), "dropped": shared.Dropped,
				}
				return e.Output(result, func(w io.Writer) {
					w.Write(jsonx.Marshal(shared.Export))
					for _, d := range shared.Dropped {
						fmt.Fprintf(e.Stderr, "left out (%s): %s\n", d.Scope, d.Path)
					}
					if len(l.Removed) > 0 {
						fmt.Fprintf(e.Stderr, "unknown keys dropped: %s\n", strings.Join(l.Removed, ", "))
					}
				})
			}
		},
	}
}

func configStatusCommand() *Command {
	return &Command{
		Name:    "status",
		Summary: "Say whether the config loads, and its revision",
		Setup: func(fs *flag.FlagSet) Runner {
			return func(ctx context.Context, e *Env, args []string) error {
				_, st, _, online, err := current(ctx, e, "")
				if err != nil {
					return err
				}
				return e.Output(map[string]any{"online": online, "state": st}, func(w io.Writer) {
					switch {
					case st.Blocked:
						fmt.Fprintf(w, "the config doesn't load (%d problems): saves are blocked until it's fixed\n", len(st.Issues))
						for _, i := range st.Issues {
							fmt.Fprintf(w, "  %s: %s\n", i.Path, i.Message)
						}
					case st.Missing:
						fmt.Fprintln(w, "no config file (the defaults apply)")
					default:
						fmt.Fprintf(w, "ok (revision %d", st.Revision)
						if !online {
							fmt.Fprint(w, ", read from the file: axiom isn't running")
						}
						fmt.Fprintln(w, ")")
					}
				})
			}
		},
	}
}
