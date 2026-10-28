package manager

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/compositor/edit"
	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// Inputs are what the layer is made of (buildInputs: the config's binds,
// profiles, strips, look and input specs, session and options, with the
// shell's facts), as the writers read it.
type Inputs struct{ *jsonx.Object }

func (in Inputs) get(key string) any {
	if in.Object == nil {
		return nil
	}
	return in.Value(key)
}

func (in Inputs) str(key string) string { return jsonx.ToString(orNil(in.get(key), "")) }

func (in Inputs) flag(key string) bool { b, _ := in.get(key).(bool); return b }

func orNil(v, def any) any {
	if v == nil {
		return def
	}
	return v
}

// files are a writer's paths and the lines a user's config needs.
type files struct {
	ConfigDir, IncludePath, ManagedPath, UserDir, UserFiles string
	IncludeLines, AutostartLines                            string
	IncludeTarget, AutostartTarget                          *jsonx.Object
}

func (f files) json() *jsonx.Object {
	return jsonx.Obj("configDir", f.ConfigDir, "includePath", f.IncludePath, "managedPath", f.ManagedPath, "userDir", f.UserDir,
		"userFiles", f.UserFiles, "includeLines", f.IncludeLines, "autostartLines", f.AutostartLines,
		"includeTarget", nilObj(f.IncludeTarget), "autostartTarget", nilObj(f.AutostartTarget))
}

func nilObj(o *jsonx.Object) any {
	if o == nil {
		return nil
	}
	return o
}

// writer is one compositor's config writer: axiom's layer as its own text,
// the files and lines of each mode, and the runtime layer standing in while
// no file of axiom's is loaded (docs/dev/compositor/config-modes.md › The
// writer).
type writer interface {
	files(in Inputs) files
	// The texts, from a spec ({ look, surfaces, input })
	moduleText(in Inputs, spec any) string
	managedText(in Inputs, spec any) string
	emptyModuleText() string
	releasedText(in Inputs, mode string) string
	// What's evaluated at runtime (the look, the input); none where the
	// compositor takes them only from its files (liveByFile)
	liveLines(in Inputs, spec any) []string
	// blurLines: the live lines that follow whether axiom's surfaces blur
	// now (BlurFacts.Now), sent alone when only that changed
	blurLines(in Inputs, spec any) []string
	liveByFile() bool
	// takesBack: a look part the shell sets back itself once it's off
	// (sway's window opacity, set a window at a time), so turning it off
	// reloads nothing
	takesBack(part string) bool
	// validate is "" or why the compositor would refuse text (niri's)
	validate(ctx context.Context, text string) string
	runLive(ctx context.Context, lines []string) bool
	setCursor(ctx context.Context, cursor any)
	// The runtime layer
	runtimeApply(ctx context.Context, in Inputs, live func() []string)
	runtimeClear(ctx context.Context)
	noteReload()
	skippedKeys() []string
	// checkLoaded: whether the mode's file is in effect; failed when the
	// compositor couldn't load its config at all
	checkLoaded(ctx context.Context, in Inputs, mode string) (loaded, failed bool)
	reload(ctx context.Context)
	// screenPower turns every output's screen off or back on (the Idle
	// settings' screen-off step)
	screenPower(ctx context.Context, on bool) error
	reloads(ctx context.Context, out chan<- ipc.Reload) error
	// configReloaded: what the writer reads again after a reload; true when
	// what the layer is made of changed (niri's user binds)
	configReloaded(ctx context.Context, in Inputs) bool
	// ownKey is what the layer is made of beyond the shell's inputs (niri's
	// plan and user files)
	ownKey(in Inputs) string
	complete(in Inputs, bind any) bool
	// entries are the binds in effect (the user's and axiom's), for the
	// Keybinds page; nil where the shell reads them from the compositor
	entries(ctx context.Context, in Inputs) *jsonx.Array
	// seenReload counts a reload at once, off the manager's goroutine
	seenReload()
	takeoverKind() string
	header() string
	monitorPattern() (*regexp.Regexp, string)
	problems(in Inputs) problems
	// runningConfig and userBindsRead: niri's (NiriManager)
	runningConfig(in Inputs) string
	userBindsRead() bool
}

// problems are why a file mode isn't in effect; Runtime, why the runtime
// layer isn't as axiom made it (sway's binds made without knowing the
// user's keys, niri's module it refused)
type problems struct {
	NotIncluded, NotManaged, Blocked, Failed, Runtime string
	Invalid                                           func(string) string
}

// env is what writers share: paths, tables, the schema and the
// compositor's socket
type env struct {
	getenv   func(string) string
	stateDir string // $XDG_STATE_HOME/axiom/ (Paths.userStatePath)
	tables   *render.Tables
	schema   func() any
	logf     func(format string, args ...any)
	state    *runtimeState
}

func (e env) configHome() string {
	if d := e.getenv("XDG_CONFIG_HOME"); d != "" {
		return strings.TrimSuffix(d, "/")
	}
	return filepath.Join(e.getenv("HOME"), ".config")
}

// schemaOf is the schema's properties.<path…>
func (e env) schemaOf(path ...string) any {
	v := e.schema()
	for _, p := range path {
		v = getAny(getAny(v, "properties"), p)
	}
	return v
}

func getAny(v any, key string) any {
	if o, ok := v.(*jsonx.Object); ok {
		return o.Value(key)
	}
	return nil
}

func readFile(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return string(data)
}

// writeFile writes text atomically, making its folder
func writeFile(path, text string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return edit.Replace(path, []byte(text))
}

func activeBinds(in Inputs) any { return orNil(in.get("binds"), jsonx.Arr()) }

func strList(v any) []string {
	var out []string
	if a, ok := v.(*jsonx.Array); ok {
		for _, x := range a.Items {
			out = append(out, jsonx.ToString(x))
		}
	}
	return out
}

// resolveHex is a theme color name's hex, as the shell resolved it
// (Facts.Colors)
func resolveHex(in Inputs) render.Func {
	colors := in.get("colors")
	return func(args ...any) any {
		if len(args) == 0 {
			return nil
		}
		return getAny(colors, jsonx.ToString(args[0]))
	}
}

func startOf(in Inputs) *jsonx.Object {
	return jsonx.Obj("command", startCommand(in), "idle", in.flag("idle"), "polkit", in.flag("polkit"))
}

// startCommand starts axiom: a second `axiom run` on the display exits at
// once, so a reloaded config can't start another copy
func startCommand(in Inputs) string {
	return jsonx.ToString(getAny(in.get("ctx"), "shellCommand")) + " run"
}

func sessionEnv(in Inputs, spec any) any {
	return render.SessionEnv(in.get("session"), getAny(getAny(spec, "input"), "cursor"), jsonx.Obj("qt", in.flag("qt")))
}

func sprintf(format string, args ...any) string { return fmt.Sprintf(format, args...) }
