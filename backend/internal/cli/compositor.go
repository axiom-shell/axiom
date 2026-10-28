package cli

import (
	"context"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/compositor/binds"
	"github.com/axiom-shell/axiom/backend/internal/compositor/takeover"
	"github.com/axiom-shell/axiom/backend/internal/compositor/userconf"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

func compositorCommand() *Command {
	return &Command{
		Name:    "compositor",
		Summary: "The compositor's config: the managed mode's takeover, the bind merge, reading the user's config",
		Subs: []*Command{
			takeoverCommand("check", "Say what taking the config over would do", takeover.Check),
			takeoverCommand("claim", "Take the config over for the managed mode", takeover.Claim),
			takeoverCommand("release", "Give the config back on leaving the managed mode", takeover.Release),
			{
				Name:    "binds",
				Summary: "Move the binds in a managed config's user/ files into axiom",
				Subs: []*Command{
					bindsCommand("extract", "Print what can move into axiom and what stays (writes nothing)", "DIR"),
					bindsCommand("remove", "Take the moved binds out of their files, after a dated backup", "DIR SITES"),
				},
			},
			niriCommand(),
			swayTextCommand(),
		},
	}
}

func takeoverCommand(verb, summary string, run func(context.Context, takeover.Options) (string, error)) *Command {
	trail := []string{"axiom", "compositor", verb}
	return &Command{
		Name:    verb,
		Summary: summary,
		Args:    "DIR HEADER [FALLBACK]",
		Help: "DIR is the compositor's config dir, HEADER the first-line prefix of a file axiom wrote, " +
			"FALLBACK what release writes when nothing was set aside (release needs it). " +
			"Prints one word (docs/dev/hyprland/managed-takeover.md); never touches a symlinked or git-tracked dir.",
		Setup: func(fs *flag.FlagSet) Runner {
			kind := fs.String("kind", "", "hyprland, sway or niri")
			return func(ctx context.Context, e *Env, args []string) error {
				k, ok := takeover.KindNamed(*kind)
				if !ok {
					return usageError(trail, fmt.Sprintf("unknown --kind %q", *kind))
				}
				if len(args) < 2 || len(args) > 3 || (verb == "release" && len(args) < 3) {
					return usageError(trail, "takes DIR HEADER [FALLBACK] (release needs FALLBACK)")
				}
				o := takeover.Options{Kind: k, Dir: args[0], Header: args[1], Getenv: e.Getenv}
				if len(args) == 3 {
					o.Fallback = args[2]
				}
				result, err := run(ctx, o)
				if err != nil {
					return err
				}
				return e.Output(map[string]any{"result": result}, func(w io.Writer) { fmt.Fprintln(w, result) })
			}
		},
	}
}

func bindsCommand(verb, summary, synopsis string) *Command {
	trail := []string{"axiom", "compositor", "binds", verb}
	return &Command{
		Name:    verb,
		Summary: summary,
		Args:    synopsis,
		Help: "DIR is the compositor's config dir; SITES the `sites` extract printed, as JSON. " +
			"Prints JSON (internal/compositor/binds, docs/dev/hyprland/bind-merge.md).",
		Setup: func(fs *flag.FlagSet) Runner {
			kind := fs.String("kind", "", "hyprland, sway or niri")
			only := fs.String("only", "", "extract: just this file of user/ (the one a takeover adopted)")
			memory := fs.Int64("memory-limit", 0, "extract: cap this process's memory at this many bytes first (the daemon's child running Hyprland's files)")
			return func(ctx context.Context, e *Env, args []string) error {
				if want := strings.Count(synopsis, " ") + 1; len(args) != want {
					return usageError(trail, "takes "+synopsis)
				}
				if *memory > 0 && verb == "extract" {
					if err := binds.LimitMemory(*memory); err != nil {
						return err
					}
				}
				o := binds.Options{Kind: *kind, Dir: args[0], Only: *only, Getenv: e.Getenv}
				var result *jsonx.Object
				var err error
				if verb == "extract" {
					result, err = binds.Extract(ctx, o)
				} else {
					sites, perr := jsonx.Unmarshal([]byte(args[1]))
					list, ok := jsonx.AsArray(sites)
					if perr != nil || !ok {
						return usageError(trail, "SITES must be a JSON array")
					}
					result, err = binds.Remove(ctx, o, list)
				}
				if err != nil {
					return err
				}
				return printJSONX(e, result)
			}
		},
	}
}

// printJSONX prints a jsonx value as one line of JSON
func printJSONX(e *Env, v any) error {
	_, err := fmt.Fprintf(e.Stdout, "%s\n", jsonx.MarshalCompact(v))
	return err
}

// stringList is a flag given any number of times
type stringList []string

func (s *stringList) String() string     { return strings.Join(*s, ",") }
func (s *stringList) Set(v string) error { *s = append(*s, v); return nil }

func niriCommand() *Command {
	trail := []string{"axiom", "compositor", "niri"}
	return &Command{
		Name:    "niri",
		Summary: "What the running niri's config holds, as JSON",
		Args:    "main|includes|binds|info",
		Help: `main      the config file niri loads: { main }
includes  every file it loads, its includes followed: { main, files, missing }
binds     the binds in effect, as BindKeys' entries ({ modmask, key, keycode, submap, description })
info      what NiriManager follows: { gaps, struts, layouts, blur, modKey }

The config is --config, else the one the niri $NIRI_SOCKET names started with. --skip leaves files out
(axiom's own module), --skip-header a file's own nodes when it starts with the text (axiom's managed config).
Fails when the config can't be read or parsed.`,
		Setup: func(fs *flag.FlagSet) Runner {
			config := fs.String("config", "", "the config (default: the running niri's)")
			var skip stringList
			fs.Var(&skip, "skip", "a file to leave out (any number of times)")
			skipHeader := fs.String("skip-header", "", "leave out the own nodes of a file starting with this")
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) != 1 {
					return usageError(trail, "takes one of main, includes, binds, info")
				}
				main := *config
				if main == "" {
					main = userconf.NiriMain(e.Getenv)
				}
				if args[0] == "main" {
					return printJSONX(e, jsonx.Obj("main", main))
				}
				r, err := userconf.ResolveNiri(main, skip, *skipHeader, e.Getenv)
				if err != nil {
					return axerr.New(axerr.InvalidConfig, "%s: %v", main, err)
				}
				if len(r.Loaded) == 0 {
					return axerr.New(axerr.NotFound, "%s: not found", main)
				}
				switch args[0] {
				case "includes":
					return printJSONX(e, jsonx.Obj("main", main, "files", strings2(r.Loaded), "missing", strings2(r.Missing)))
				case "binds":
					return printJSONX(e, userconf.NiriBinds(r.Files, userconf.RunningNested(e.Getenv)))
				case "info":
					return printJSONX(e, userconf.NiriInfo(r.Files, userconf.RunningNested(e.Getenv)))
				}
				return usageError(trail, fmt.Sprintf("unknown %q (main, includes, binds, info)", args[0]))
			}
		},
	}
}

func strings2(list []string) *jsonx.Array {
	out := jsonx.Arr()
	for _, s := range list {
		out.Append(s)
	}
	return out
}

func swayTextCommand() *Command {
	trail := []string{"axiom", "compositor", "sway-text"}
	return &Command{
		Name:    "sway-text",
		Summary: "Print the sway config in effect as one text, its includes put in",
		Help: `The main config is --config, else the one the running sway was started with, else the first of the places
sway looks. Includes are put in where they are (globs, ~, environment and $variables), each file once; --skip
leaves files out (axiom's own module), --skip-header the own lines of a file starting with the text (axiom's
managed config). Fails when no config is found.`,
		Setup: func(fs *flag.FlagSet) Runner {
			config := fs.String("config", "", "the main config (default: the running sway's)")
			var skip stringList
			fs.Var(&skip, "skip", "a file to leave out (any number of times)")
			skipHeader := fs.String("skip-header", "", "leave out the own lines of files starting with this")
			return func(ctx context.Context, e *Env, args []string) error {
				if len(args) > 0 {
					return usageError(trail, "takes no arguments")
				}
				main := *config
				if main == "" {
					main = userconf.SwayMain(e.Getenv)
				}
				if info, err := os.Stat(main); main == "" || err != nil || !info.Mode().IsRegular() {
					return axerr.New(axerr.NotFound, "no sway config found")
				}
				text, _ := userconf.SwayText(main, skip, *skipHeader, e.Getenv)
				_, err := fmt.Fprintln(e.Stdout, text)
				return err
			}
		},
	}
}
