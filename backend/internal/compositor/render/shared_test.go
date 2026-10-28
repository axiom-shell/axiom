package render

import (
	"bufio"
	"compress/gzip"
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

var (
	tablesOnce sync.Once
	tables     *Tables
	tablesErr  error
)

func repoTables(t *testing.T) *Tables {
	t.Helper()
	tablesOnce.Do(func() {
		tables, tablesErr = ParseTables(func(p string) (string, error) {
			data, err := os.ReadFile(filepath.Join(testkit.RepoRoot(), p))
			return string(data), err
		})
	})
	if tablesErr != nil {
		t.Fatal(tablesErr)
	}
	return tables
}

// replayed turns a recorded argument back into what the JS was handed: a
// {"$fn": answers} a function answering by its arguments, {"$undefined":
// true} nil
func replayed(v any) any {
	switch x := v.(type) {
	case *jsonx.Object:
		if x.Len() == 1 && isTrue(x.Value("$undefined")) {
			return nil
		}
		if x.Len() == 1 && x.Has("$fn") {
			answers := replayed(x.Value("$fn"))
			return Func(func(args ...any) any {
				return get(answers, string(jsonx.MarshalCompact(jsonx.Arr(args...))))
			})
		}
		out := jsonx.NewObject()
		for _, k := range x.Keys() {
			out.Set(k, replayed(x.Value(k)))
		}
		return out
	case *jsonx.Array:
		out := jsonx.Arr()
		for _, item := range x.Items {
			out.Append(replayed(item))
		}
		return out
	}
	return v
}

// The shared cases of the helpers the shell still uses (recorded from
// their JS tests) replayed through the port, so the two copies stay one:
// each output must be the JS bytes exactly. Ops with no port (KeyNames'
// key events, LayerStack.sequence: the shell's alone) are left to the JS.
func TestSharedCases(t *testing.T) {
	t.Parallel()
	tab := repoTables(t)
	ran := map[string]int{}
	for _, suite := range []string{"BindActions.", "BindKeys.", "KeyNames.", "LayerStack."} {
		for _, c := range testkit.Cases(t, suite) {
			op, ok := ops[c.Op]
			if !ok {
				continue
			}
			ran[c.Op]++
			args := make([]any, len(c.Args))
			for i, a := range c.Args {
				args[i] = replayed(a)
			}
			// The bind actions' table the JS is handed first is the one
			// the port holds (actions.JSON): its ops take what follows, as
			// the frozen cases recorded them
			if strings.HasPrefix(c.Op, "BindActions.") && len(args) > 0 && has(args[0], "ipcActions") {
				args = args[1:]
			}
			t.Run(c.Name, func(t *testing.T) {
				c.Compare(t, op(tab, args))
			})
		}
	}
	names := make([]string, 0, len(ran))
	for n := range ran {
		names = append(names, n)
	}
	sort.Strings(names)
	t.Logf("replayed: %s", strings.Join(names, " "))
}

// The helpers' cases as recorded from their JS tests when the config
// writers moved into the binary (testdata/frozen.jsonl.gz: each call and
// the exact bytes V4 made of it), replayed through the port. Most of
// those JS functions are gone; the ones the shell still uses go on being
// recorded, and TestSharedCases replays those too.
func TestFrozenCases(t *testing.T) {
	t.Parallel()
	tab := repoTables(t)
	ran := 0
	for _, c := range frozenCases(t) {
		op, ok := ops[c.Op]
		if !ok {
			continue
		}
		ran++
		if got := string(jsonx.Marshal(op(tab, c.Args))); got != c.Expected {
			g, w := strings.Split(got, "\n"), strings.Split(c.Expected, "\n")
			for i := 0; i < len(g) || i < len(w); i++ {
				var x, y string
				if i < len(g) {
					x = g[i]
				}
				if i < len(w) {
					y = w[i]
				}
				if x != y {
					t.Errorf("%s: line %d: got %q, want %q", c.Name, i+1, x, y)
					break
				}
			}
		}
	}
	if ran < 500 {
		t.Fatalf("only %d frozen cases replayed", ran)
	}
}

type frozenCase struct {
	Name, Op, Expected string
	Args               []any
}

// frozenCases are testdata/frozen.jsonl.gz's cases, their arguments as the
// JS was handed them
func frozenCases(t *testing.T) []frozenCase {
	t.Helper()
	f, err := os.Open(filepath.Join("testdata", "frozen.jsonl.gz"))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	gz, err := gzip.NewReader(f)
	if err != nil {
		t.Fatal(err)
	}
	var out []frozenCase
	lines := bufio.NewScanner(gz)
	lines.Buffer(nil, 64<<20)
	for lines.Scan() {
		var c struct {
			Name     string          `json:"name"`
			Op       string          `json:"op"`
			Args     json.RawMessage `json:"args"`
			Expected string          `json:"expected"`
		}
		if err := json.Unmarshal(lines.Bytes(), &c); err != nil {
			t.Fatal(err)
		}
		raw, err := jsonx.Unmarshal(c.Args)
		if err != nil {
			t.Fatalf("%s: %v", c.Name, err)
		}
		var args []any
		for _, a := range items(raw) {
			args = append(args, replayed(a))
		}
		out = append(out, frozenCase{c.Name, c.Op, c.Expected, args})
	}
	if err := lines.Err(); err != nil {
		t.Fatal(err)
	}
	return out
}

// arg is args[i], nil past the end (an argument left out)
func arg(a []any, i int) any {
	if i < len(a) {
		return a[i]
	}
	return nil
}

func argStr(a []any, i int) string { return str(arg(a, i)) }

func strList(list []string) any { return strs(list) }

func objects(list []*jsonx.Object) any {
	out := jsonx.Arr()
	for _, o := range list {
		out.Append(o)
	}
	return out
}

// ops maps each recorded op onto the port
var ops = map[string]func(t *Tables, a []any) any{
	"BindActions.appliesUnder":   func(t *Tables, a []any) any { return t.AppliesUnder(arg(a, 0), argStr(a, 1), arg(a, 2)) },
	"BindActions.argumentKind":   func(t *Tables, a []any) any { return t.ArgumentKind(arg(a, 0)) },
	"BindActions.callFunction":   func(t *Tables, a []any) any { return t.CallFunction(arg(a, 0)) },
	"BindActions.callOf":         func(t *Tables, a []any) any { return t.CallOf(arg(a, 0)) },
	"BindActions.defaultLabel":   func(t *Tables, a []any) any { return t.DefaultLabel(arg(a, 0)) },
	"BindActions.descriptionFor": func(t *Tables, a []any) any { return t.DescriptionFor(arg(a, 0)) },
	"BindActions.hasCalls":       func(t *Tables, a []any) any { return t.HasCalls(arg(a, 0)) },
	"BindActions.hasOwnSection":  func(t *Tables, a []any) any { return HasOwnSection(arg(a, 0)) },
	"BindActions.keySupported":   func(t *Tables, a []any) any { return t.KeySupported(arg(a, 0), arg(a, 1)) },
	"BindActions.needsArgument":  func(t *Tables, a []any) any { return t.NeedsArgument(arg(a, 0)) },
	"BindActions.sectionFor":     func(t *Tables, a []any) any { return t.SectionFor(arg(a, 0)) },
	"BindActions.supported":      func(t *Tables, a []any) any { return t.Supported(arg(a, 0), arg(a, 1)) },
	"BindActions.switcherHeld":   func(t *Tables, a []any) any { return strList(SwitcherHeld(stringList(arg(a, 0)))) },

	"BindKeys.entryId":       func(t *Tables, a []any) any { return EntryID(arg(a, 0)) },
	"BindKeys.keyId":         func(t *Tables, a []any) any { return KeyID(arg(a, 0)) },
	"BindKeys.mergeBinds":    func(t *Tables, a []any) any { return MergeBinds(arg(a, 0), arg(a, 1)) },
	"BindKeys.runtimeBinds":  func(t *Tables, a []any) any { return RuntimeBinds(arg(a, 0), arg(a, 1)) },
	"BindKeys.userKeyCounts": func(t *Tables, a []any) any { return UserKeyCounts(arg(a, 0), arg(a, 1)) },

	"KeyNames.join":        func(t *Tables, a []any) any { return JoinKey(stringList(arg(a, 0)), argStr(a, 1)) },
	"KeyNames.split":       func(t *Tables, a []any) any { return SplitKey(arg(a, 0)).json() },
	"KeyNames.tapModifier": func(t *Tables, a []any) any { return TapModifier(arg(a, 0)) },

	"CompositorLayer.alphaHex": func(t *Tables, a []any) any { return AlphaHex(num(arg(a, 0))) },
	"CompositorLayer.gaussianShadow": func(t *Tables, a []any) any {
		r, al := GaussianShadow(arg(a, 0))
		return jsonx.Obj("radius", r, "alpha", al)
	},
	"CompositorLayer.hex":         func(t *Tables, a []any) any { return Hex(arg(a, 0)) },
	"CompositorLayer.input":       func(t *Tables, a []any) any { return Input(arg(a, 0), arg(a, 1)) },
	"CompositorLayer.look":        func(t *Tables, a []any) any { return Look(arg(a, 0), arg(a, 1)) },
	"CompositorLayer.luminance":   func(t *Tables, a []any) any { return Luminance(arg(a, 0)) },
	"CompositorLayer.sessionEnv":  func(t *Tables, a []any) any { return SessionEnv(arg(a, 0), arg(a, 1), arg(a, 2)) },
	"CompositorLayer.surfaceBlur": func(t *Tables, a []any) any { return objects(t.SurfaceBlur(arg(a, 0))) },

	"HyprLua.blurLua":       func(t *Tables, a []any) any { return strList(t.BlurLua(arg(a, 0))) },
	"HyprLua.configTable":   func(t *Tables, a []any) any { return ConfigTable(arg(a, 0), arg(a, 1), arg(a, 2), arg(a, 3)) },
	"HyprLua.greeterLua":    func(t *Tables, a []any) any { return strList(GreeterLua(arg(a, 0), arg(a, 1), arg(a, 2))) },
	"HyprLua.inputLua":      func(t *Tables, a []any) any { return strList(InputLua(arg(a, 0), arg(a, 1))) },
	"HyprLua.layerRulesLua": func(t *Tables, a []any) any { return strList(t.LayerRulesLua()) },
	"HyprLua.leaveSubmap":   func(t *Tables, a []any) any { return LeaveSubmap(argStr(a, 0)) },
	"HyprLua.lookLua":       func(t *Tables, a []any) any { return strList(LookLua(arg(a, 0), arg(a, 1))) },
	"HyprLua.monitorCalls":  func(t *Tables, a []any) any { return strList(MonitorCalls(arg(a, 0), arg(a, 1))) },
	"HyprLua.monitorSpec":   func(t *Tables, a []any) any { return MonitorSpec(arg(a, 0)) },
	"HyprLua.monitorsLua":   func(t *Tables, a []any) any { return strList(MonitorsLua(arg(a, 0))) },
	"HyprLua.serialize": func(t *Tables, a []any) any {
		pad := ""
		if p := arg(a, 1); p != nil {
			pad = str(p)
		}
		return Serialize(arg(a, 0).(*jsonx.Object), pad)
	},
	"HyprLua.softShadow": func(t *Tables, a []any) any {
		r, p, al := SoftShadow(arg(a, 0))
		return jsonx.Obj("range", r, "power", p, "alpha", al)
	},
	"HyprLua.string":           func(t *Tables, a []any) any { return LuaString(arg(a, 0)) },
	"HyprLua.stripsLua":        func(t *Tables, a []any) any { return strList(StripsLua(arg(a, 0), arg(a, 1), arg(a, 2))) },
	"HyprLua.stripsRuntimeLua": func(t *Tables, a []any) any { return strList(StripsRuntimeLua(stringList(arg(a, 0)), argStr(a, 1))) },
	"HyprLua.switcherBindLua":  func(t *Tables, a []any) any { return SwitcherBindLua(arg(a, 0)) },
	"HyprLua.switcherLua":      func(t *Tables, a []any) any { return strList(SwitcherLua(arg(a, 0))) },
	"HyprLua.value":            func(t *Tables, a []any) any { return LuaValue(arg(a, 0)) },

	"HyprConfigLua.animationSet": func(t *Tables, a []any) any {
		if set := AnimationSet(arg(a, 0), arg(a, 1)); set != nil {
			return set
		}
		return nil
	},
	"HyprConfigLua.animationsLua":  func(t *Tables, a []any) any { return AnimationsLua(arg(a, 0), arg(a, 1)) },
	"HyprConfigLua.animationsOff":  func(t *Tables, a []any) any { return AnimationsOff(arg(a, 0), arg(a, 1)) },
	"HyprConfigLua.bindKey":        func(t *Tables, a []any) any { return BindKey(arg(a, 0)) },
	"HyprConfigLua.bindLines":      func(t *Tables, a []any) any { return strList(t.BindLines(arg(a, 0), arg(a, 1))) },
	"HyprConfigLua.bindLua":        func(t *Tables, a []any) any { return t.BindLua(arg(a, 0), arg(a, 1)) },
	"HyprConfigLua.dispatcherLua":  func(t *Tables, a []any) any { return t.DispatcherLua(argStr(a, 0), argStr(a, 1), arg(a, 2)) },
	"HyprConfigLua.emptyModuleLua": func(t *Tables, a []any) any { return EmptyModuleLua(argStr(a, 0)) },
	"HyprConfigLua.managedLua":     func(t *Tables, a []any) any { return t.ManagedLua(argStr(a, 0), arg(a, 1), arg(a, 2)) },
	"HyprConfigLua.moduleLua":      func(t *Tables, a []any) any { return ModuleLua(arg(a, 0)) },
	"HyprConfigLua.releasedLua":    func(t *Tables, a []any) any { return ReleasedLua(arg(a, 0), argStr(a, 1)) },

	"SwayConf.bindCommand":      func(t *Tables, a []any) any { return SwayBindCommand(argStr(a, 0), isTrue(arg(a, 1))) },
	"SwayConf.bindEntries":      func(t *Tables, a []any) any { return t.SwayBindEntries(arg(a, 0), arg(a, 1)) },
	"SwayConf.bindLine":         func(t *Tables, a []any) any { return t.SwayBindLine(arg(a, 0), arg(a, 1), isTrue(arg(a, 2))) },
	"SwayConf.bindLines":        func(t *Tables, a []any) any { return strList(t.SwayBindLines(arg(a, 0), arg(a, 1), isTrue(arg(a, 2)))) },
	"SwayConf.command":          func(t *Tables, a []any) any { return t.SwayCommand(arg(a, 0), arg(a, 1)) },
	"SwayConf.configBinds":      func(t *Tables, a []any) any { return SwayConfigBinds(arg(a, 0)) },
	"SwayConf.fileOutputLines":  func(t *Tables, a []any) any { return strList(SwayFileOutputLines(arg(a, 0))) },
	"SwayConf.floatingModifier": func(t *Tables, a []any) any { return SwayFloatingModifier(arg(a, 0)) },
	"SwayConf.fxLines":          func(t *Tables, a []any) any { return strList(t.SwayFxLines(arg(a, 0), arg(a, 1))) },
	"SwayConf.inputLines":       func(t *Tables, a []any) any { return strList(SwayInputLines(arg(a, 0), arg(a, 1), isTrue(arg(a, 2)))) },
	"SwayConf.isComplete":       func(t *Tables, a []any) any { return t.SwayIsComplete(arg(a, 0), arg(a, 1)) },
	"SwayConf.key":              func(t *Tables, a []any) any { return SwayKeyOf(arg(a, 0)).json() },
	"SwayConf.lookLines":        func(t *Tables, a []any) any { return strList(SwayLookLines(arg(a, 0), isTrue(arg(a, 1)))) },
	"SwayConf.managedText":      func(t *Tables, a []any) any { return SwayManagedText(argStr(a, 0), arg(a, 1)) },
	"SwayConf.moduleText":       func(t *Tables, a []any) any { return SwayModuleText(arg(a, 0)) },
	"SwayConf.optionLines":      func(t *Tables, a []any) any { return strList(SwayOptionLines(arg(a, 0), arg(a, 1))) },
	"SwayConf.outputCommand":    func(t *Tables, a []any) any { return SwayOutputCommand(arg(a, 0)) },
	"SwayConf.outputCommands":   func(t *Tables, a []any) any { return SwayOutputCommands(arg(a, 0)) },
	"SwayConf.quote":            func(t *Tables, a []any) any { return SwayQuote(arg(a, 0)) },
	"SwayConf.releasedText":     func(t *Tables, a []any) any { return SwayReleasedText(arg(a, 0), argStr(a, 1)) },
	"SwayConf.unbindLines":      func(t *Tables, a []any) any { return strList(t.SwayUnbindLines(arg(a, 0), arg(a, 1))) },

	"NiriConf.actionFor":       func(t *Tables, a []any) any { return nilObject(t.NiriActionFor(arg(a, 0), arg(a, 1))) },
	"NiriConf.bindEntries":     func(t *Tables, a []any) any { return t.NiriBindEntries(arg(a, 0), arg(a, 1)) },
	"NiriConf.bindNode":        func(t *Tables, a []any) any { return nilObject(t.NiriBindNode(arg(a, 0), arg(a, 1))) },
	"NiriConf.bindsNode":       func(t *Tables, a []any) any { return nilObject(t.NiriBindsNode(arg(a, 0), arg(a, 1))) },
	"NiriConf.emptyModuleText": func(t *Tables, a []any) any { return NiriEmptyModuleText(argStr(a, 0)) },
	"NiriConf.fileOutputNodes": func(t *Tables, a []any) any { return NiriFileOutputNodes(arg(a, 0)) },
	"NiriConf.inputNodes":      func(t *Tables, a []any) any { return NiriInputNodes(arg(a, 0), arg(a, 1)) },
	"NiriConf.isComplete":      func(t *Tables, a []any) any { return t.NiriIsComplete(arg(a, 0), arg(a, 1)) },
	"NiriConf.key": func(t *Tables, a []any) any {
		if k := NiriKey(arg(a, 0)); k != "" {
			return k
		}
		return nil
	},
	"NiriConf.lookNodes":      func(t *Tables, a []any) any { return NiriLookNodes(arg(a, 0)) },
	"NiriConf.managedText":    func(t *Tables, a []any) any { return NiriManagedText(arg(a, 0)) },
	"NiriConf.merged":         func(t *Tables, a []any) any { return KdlMerged(arg(a, 0)) },
	"NiriConf.moduleText":     func(t *Tables, a []any) any { return NiriModuleText(arg(a, 0)) },
	"NiriConf.node":           func(t *Tables, a []any) any { return Node(arg(a, 0), arg(a, 1), arg(a, 2), arg(a, 3)) },
	"NiriConf.optionNodes":    func(t *Tables, a []any) any { return NiriOptionNodes(arg(a, 0), arg(a, 1), isTrue(arg(a, 2))) },
	"NiriConf.outputNodes":    func(t *Tables, a []any) any { return NiriOutputNodes(arg(a, 0)) },
	"NiriConf.outputRequests": func(t *Tables, a []any) any { return NiriOutputRequests(arg(a, 0), arg(a, 1)) },
	"NiriConf.releasedText":   func(t *Tables, a []any) any { return NiriReleasedText(arg(a, 0), arg(a, 1), arg(a, 2), arg(a, 3)) },
	"NiriConf.serialize": func(t *Tables, a []any) any {
		return KdlSerialize(arg(a, 0), int(num(or(arg(a, 1), 0.0))))
	},
	"NiriConf.setPath": func(t *Tables, a []any) any {
		KdlSetPath(arg(a, 0).(*jsonx.Array), argStr(a, 1), arg(a, 2), arg(a, 3))
		return nil
	},
	"NiriConf.surfaceBlurNodes": func(t *Tables, a []any) any { return t.NiriSurfaceBlurNodes(arg(a, 0)) },
	"NiriConf.wrapperText":      func(t *Tables, a []any) any { return NiriWrapperText(arg(a, 0), arg(a, 1), arg(a, 2)) },
}

// nilObject is an object, or JSON null for none
func nilObject(o *jsonx.Object) any {
	if o == nil {
		return nil
	}
	return o
}
