package binds

import (
	"context"
	"fmt"
	"math"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"

	lua "github.com/yuin/gopher-lua"

	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
)

// luaBind is one hl.bind call the user's files made
type luaBind struct {
	file string
	line int
	// inFunction: made by a function the file defines, not its main chunk
	// (a helper's call makes binds a handler or another branch would too)
	inFunction bool
	key        string // "" when it isn't a string
	// The dispatcher: its hl.dsp name ("window.close"), arguments and Lua
	// source; lua is "" when it's a Lua function, which can't move
	dispatcher string
	args       []any
	lua        string
	opts       map[string]any
}

type luaUnbind struct {
	file       string
	line       int
	inFunction bool
	key        string
}

type luaFound struct {
	binds   []luaBind
	unbinds []luaUnbind
	errors  []string
}

// runHyprFiles lists the binds Hyprland Lua config files make, by running
// them against a stand-in `hl` that only records hl.bind and hl.unbind (so
// variables, string building and loops all work). Each module is required
// as the managed config does (`user.<name>`), with dir on package.path.
// Nothing else they ask for is done: commands don't run (io.popen reads
// empty, os.execute does nothing), io.open only reads, os.exit, remove and
// rename do nothing, and there's no debug library. Lua 5.1 (gopher-lua):
// a file using 5.4's syntax is one of the errors.
func runHyprFiles(ctx context.Context, dir string, modules []string, getenv func(string) string) (*luaFound, error) {
	// A bounded stack (a runaway recursion, unpack of a huge range): an
	// error, not memory without end. The heap has no such bound: the
	// daemon reads the files in a child limited to MemoryLimit
	L := lua.NewState(lua.Options{SkipOpenLibs: true, CallStackSize: 1024, RegistrySize: 1024 * 20, RegistryMaxSize: 1 << 20})
	defer L.Close()
	L.SetContext(ctx)
	for _, lib := range []struct {
		name string
		open lua.LGFunction
	}{
		{lua.LoadLibName, lua.OpenPackage}, {lua.BaseLibName, lua.OpenBase}, {lua.TabLibName, lua.OpenTable},
		{lua.StringLibName, lua.OpenString}, {lua.MathLibName, lua.OpenMath}, {lua.CoroutineLibName, lua.OpenCoroutine},
		{lua.IoLibName, lua.OpenIo},
	} {
		L.Push(L.NewFunction(lib.open))
		L.Push(lua.LString(lib.name))
		L.Call(1, 0)
	}
	found := &luaFound{}
	sandbox(L, getenv)
	L.SetGlobal("hl", standIn(L, found))
	pkg := L.GetGlobal("package").(*lua.LTable)
	L.SetField(pkg, "path", lua.LString(dir+"/?.lua;"+dir+"/?/init.lua"))
	L.SetField(pkg, "cpath", lua.LString(""))
	require := L.GetGlobal("require")
	for _, module := range modules {
		err := L.CallByParam(lua.P{Fn: require, NRet: 1, Protect: true}, lua.LString(module))
		if ctx.Err() != nil {
			return nil, fmt.Errorf("reading the binds took too long, so nothing moved")
		}
		if err != nil {
			found.errors = append(found.errors, module+": "+luaError(err))
		}
		L.SetTop(0)
	}
	return found, nil
}

func luaError(err error) string {
	if api, ok := err.(*lua.ApiError); ok && api.Object != nil {
		return api.Object.String()
	}
	return err.Error()
}

// sandbox takes what writes, runs or prints out of reach, and adds the 5.4
// names the files may use
func sandbox(L *lua.LState, getenv func(string) string) {
	noop := L.NewFunction(func(L *lua.LState) int { return 0 })
	// What io.popen gives: reading it finds nothing
	empty := L.NewTable()
	L.SetField(empty, "read", noop)
	L.SetField(empty, "lines", L.NewFunction(func(L *lua.LState) int { L.Push(noop); return 1 }))
	L.SetField(empty, "close", L.NewFunction(func(L *lua.LState) int { L.Push(lua.LTrue); return 1 }))
	L.SetField(empty, "write", L.NewFunction(func(L *lua.LState) int { L.Push(L.Get(1)); return 1 }))
	L.SetField(empty, "flush", noop)

	orig := L.GetGlobal("io").(*lua.LTable)
	io := L.NewTable()
	open := L.GetField(orig, "open")
	L.SetField(io, "open", L.NewFunction(func(L *lua.LState) int {
		if mode := L.OptString(2, "r"); strings.ContainsAny(mode, "wa+") {
			L.Push(lua.LNil)
			L.Push(lua.LString("not written while listing binds"))
			return 2
		}
		// The results follow however many arguments it was given
		base := L.GetTop()
		L.Push(open)
		L.Push(L.Get(1))
		L.Push(lua.LString("r"))
		L.Call(2, lua.MultRet)
		return L.GetTop() - base
	}))
	L.SetField(io, "lines", L.GetField(orig, "lines"))
	L.SetField(io, "type", L.GetField(orig, "type"))
	for _, name := range []string{"popen", "output", "input", "tmpfile"} {
		L.SetField(io, name, L.NewFunction(func(L *lua.LState) int { L.Push(empty); return 1 }))
	}
	L.SetField(io, "write", L.NewFunction(func(L *lua.LState) int { L.Push(io); return 1 }))
	L.SetField(io, "read", noop)
	L.SetField(io, "close", noop)
	for _, name := range []string{"stdin", "stdout", "stderr"} {
		L.SetField(io, name, empty)
	}
	L.SetGlobal("io", io)
	// require("io") answers package.loaded's copy: the stand-in there too
	loaded := L.GetField(L.GetGlobal("package"), "loaded").(*lua.LTable)
	L.SetField(loaded, "io", io)

	os := L.NewTable()
	L.SetField(os, "time", L.NewFunction(osTime))
	L.SetField(os, "clock", L.NewFunction(func(L *lua.LState) int { L.Push(lua.LNumber(0)); return 1 }))
	L.SetField(os, "date", L.NewFunction(func(L *lua.LState) int { L.Push(lua.LString("")); return 1 }))
	L.SetField(os, "getenv", L.NewFunction(func(L *lua.LState) int {
		if v := getenv(L.CheckString(1)); v != "" {
			L.Push(lua.LString(v))
		} else {
			L.Push(lua.LNil)
		}
		return 1
	}))
	L.SetField(os, "execute", L.NewFunction(func(L *lua.LState) int {
		L.Push(lua.LTrue)
		L.Push(lua.LString("exit"))
		L.Push(lua.LNumber(0))
		return 3
	}))
	L.SetField(os, "exit", L.NewFunction(func(L *lua.LState) int { L.RaiseError("os.exit"); return 0 }))
	for _, name := range []string{"remove", "rename"} {
		L.SetField(os, name, L.NewFunction(func(L *lua.LState) int { L.Push(lua.LTrue); return 1 }))
	}
	L.SetGlobal("os", os)
	// What the files print goes nowhere
	L.SetGlobal("print", noop)

	// string.rep (and s:rep) as 5.4 has it (a separator too), refusing a
	// result past maxRep: one call would otherwise allocate it all at once
	str := L.GetGlobal("string").(*lua.LTable)
	L.SetField(str, "rep", L.NewFunction(func(L *lua.LState) int {
		s, n, sep := L.CheckString(1), L.CheckInt64(2), L.OptString(3, "")
		if n <= 0 {
			L.Push(lua.LString(""))
			return 1
		}
		if (int64(len(s))+int64(len(sep)))*n > maxRep {
			L.RaiseError("string.rep: a result over %d bytes", maxRep)
		}
		var b strings.Builder
		for i := range n {
			if i > 0 {
				b.WriteString(sep)
			}
			b.WriteString(s)
		}
		L.Push(lua.LString(b.String()))
		return 1
	}))

	// Lua 5.4's names for what 5.1 has, or close to it
	table := L.GetGlobal("table").(*lua.LTable)
	L.SetField(table, "unpack", L.GetGlobal("unpack"))
	L.SetField(table, "pack", L.NewFunction(func(L *lua.LState) int {
		t := L.NewTable()
		n := L.GetTop()
		for i := 1; i <= n; i++ {
			t.RawSetInt(i, L.Get(i))
		}
		t.RawSetString("n", lua.LNumber(n))
		L.Push(t)
		return 1
	}))
	math := L.GetGlobal("math").(*lua.LTable)
	L.SetField(math, "type", L.NewFunction(func(L *lua.LState) int {
		n, ok := L.Get(1).(lua.LNumber)
		switch {
		case !ok:
			L.Push(lua.LNil)
		case isWhole(float64(n)):
			L.Push(lua.LString("integer"))
		default:
			L.Push(lua.LString("float"))
		}
		return 1
	}))
}

// maxRep is the longest string string.rep makes
const maxRep = 16 << 20

func osTime(L *lua.LState) int {
	L.Push(lua.LNumber(0))
	return 1
}

// standIn is the stand-in hl: hl.bind and hl.unbind record, hl.dsp builds
// dispatchers, and anything else (indexing or calling it) gives a sink
// that gives itself, so hl.config{…}, hl.on(…) and x:set_enabled(false)
// all pass. As a list the sink is empty, so ipairs(hl.get_monitors())
// ends at once.
func standIn(L *lua.LState, found *luaFound) *lua.LTable {
	sink := L.NewTable()
	sinkMeta := L.NewTable()
	L.SetField(sinkMeta, "__index", L.NewFunction(func(L *lua.LState) int {
		if _, isNumber := L.Get(2).(lua.LNumber); isNumber {
			L.Push(lua.LNil)
		} else {
			L.Push(sink)
		}
		return 1
	}))
	L.SetField(sinkMeta, "__call", L.NewFunction(func(L *lua.LState) int { L.Push(sink); return 1 }))
	L.SetMetatable(sink, sinkMeta)

	dispatcherMeta := L.NewTable()
	var dsp func(name string) *lua.LTable
	dsp = func(name string) *lua.LTable {
		t := L.NewTable()
		meta := L.NewTable()
		L.SetField(meta, "__index", L.NewFunction(func(L *lua.LState) int {
			key := L.ToString(2)
			if name != "" {
				key = name + "." + key
			}
			L.Push(dsp(key))
			return 1
		}))
		L.SetField(meta, "__call", L.NewFunction(func(L *lua.LState) int {
			d := L.NewTable()
			args := L.NewTable()
			n := L.GetTop() - 1
			for i := 1; i <= n; i++ {
				args.RawSetInt(i, L.Get(i+1))
			}
			d.RawSetString("name", lua.LString(name))
			d.RawSetString("args", args)
			d.RawSetString("n", lua.LNumber(n))
			L.SetMetatable(d, dispatcherMeta)
			L.Push(d)
			return 1
		}))
		L.SetMetatable(t, meta)
		return t
	}

	hl := L.NewTable()
	L.SetField(hl, "dsp", dsp(""))
	L.SetField(hl, "bind", L.NewFunction(func(L *lua.LState) int {
		file, line, inFunction := callSite(L)
		b := luaBind{file: file, line: line, inFunction: inFunction}
		if key, ok := L.Get(1).(lua.LString); ok {
			b.key = string(key)
		}
		if d, ok := L.Get(2).(*lua.LTable); ok && L.GetMetatable(d) == dispatcherMeta {
			name := lua.LVAsString(d.RawGetString("name"))
			args := d.RawGetString("args").(*lua.LTable)
			n := int(lua.LVAsNumber(d.RawGetString("n")))
			ok := name != ""
			var values []any
			var sources []string
			for i := 1; i <= n && ok; i++ {
				v := args.RawGetInt(i)
				if v == lua.LNil || !plain(L, v) {
					ok = false
					break
				}
				values = append(values, toGo(v))
				sources = append(sources, luaSource(v))
			}
			if ok {
				b.dispatcher = name
				b.args = values
				if b.args == nil {
					b.args = []any{}
				}
				b.lua = "hl.dsp." + name + "(" + strings.Join(sources, ", ") + ")"
			}
		}
		if opts, ok := L.Get(3).(*lua.LTable); ok {
			b.opts = map[string]any{}
			opts.ForEach(func(k, v lua.LValue) {
				if plain(L, v) {
					b.opts[k.String()] = toGo(v)
				} else {
					b.opts[k.String()] = v.String()
				}
			})
		}
		found.binds = append(found.binds, b)
		L.Push(sink)
		return 1
	}))
	L.SetField(hl, "unbind", L.NewFunction(func(L *lua.LState) int {
		file, line, inFunction := callSite(L)
		u := luaUnbind{file: file, line: line, inFunction: inFunction}
		if key, ok := L.Get(1).(lua.LString); ok {
			u.key = string(key)
		}
		found.unbinds = append(found.unbinds, u)
		L.Push(sink)
		return 1
	}))
	hlMeta := L.NewTable()
	L.SetField(hlMeta, "__index", L.NewFunction(func(L *lua.LState) int { L.Push(sink); return 1 }))
	L.SetMetatable(hl, hlMeta)
	return hl
}

// callSite is where the hl.* call was made: its file ("" for a chunk that
// isn't one), line, and whether in a function (not a file's main chunk,
// which is defined on line 0)
func callSite(L *lua.LState) (string, int, bool) {
	dbg, ok := L.GetStack(1)
	if !ok {
		return "", 0, false
	}
	if _, err := L.GetInfo("Sl", dbg, lua.LNil); err != nil {
		return "", 0, false
	}
	source := dbg.Source
	if strings.HasPrefix(source, "@") {
		source = source[1:]
	} else if _, err := os.Stat(source); err != nil {
		source = ""
	}
	return source, max(dbg.CurrentLine, 0), dbg.LineDefined > 0
}

// plain: a string, number, boolean or table of them without a metatable
func plain(L *lua.LState, v lua.LValue) bool {
	switch v := v.(type) {
	case lua.LString, lua.LNumber, lua.LBool:
		return true
	case *lua.LTable:
		if L.GetMetatable(v) != lua.LNil {
			return false
		}
		ok := true
		v.ForEach(func(k, val lua.LValue) {
			switch k.(type) {
			case lua.LString, lua.LNumber:
			default:
				ok = false
			}
			if !plain(L, val) {
				ok = false
			}
		})
		return ok
	}
	return false
}

// toGo is a plain value as JSON had it: a table is a list when its keys are
// 1..n (an empty one too), else an object keyed by tostring
func toGo(v lua.LValue) any {
	switch v := v.(type) {
	case lua.LString:
		return string(v)
	case lua.LNumber:
		return float64(v)
	case lua.LBool:
		return bool(v)
	case *lua.LTable:
		n := v.Len()
		count := 0
		v.ForEach(func(lua.LValue, lua.LValue) { count++ })
		if count == n {
			list := make([]any, n)
			for i := 1; i <= n; i++ {
				list[i-1] = toGo(v.RawGetInt(i))
			}
			return list
		}
		obj := map[string]any{}
		v.ForEach(func(k, val lua.LValue) { obj[luaToString(k)] = toGo(val) })
		return obj
	}
	return nil
}

func luaToString(v lua.LValue) string {
	if n, ok := v.(lua.LNumber); ok {
		return numberText(float64(n))
	}
	return v.String()
}

// numberText is a number as Lua's tostring writes it (a whole one as an
// integer: gopher-lua has no integer type)
func numberText(f float64) string {
	switch {
	case math.IsInf(f, 1):
		return "inf"
	case math.IsInf(f, -1):
		return "-inf"
	case math.IsNaN(f):
		return "nan"
	case isWhole(f):
		return strconv.FormatInt(int64(f), 10)
	}
	return strconv.FormatFloat(f, 'g', 14, 64)
}

func isWhole(f float64) bool {
	return f == math.Trunc(f) && math.Abs(f) < 1<<63
}

var (
	luaName     = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)
	luaKeywords = map[string]bool{"and": true, "break": true, "do": true, "else": true, "elseif": true, "end": true,
		"false": true, "for": true, "function": true, "goto": true, "if": true, "in": true, "local": true, "nil": true,
		"not": true, "or": true, "repeat": true, "return": true, "then": true, "true": true, "until": true, "while": true}
)

// luaSource is a plain value as Lua source
func luaSource(v lua.LValue) string {
	switch v := v.(type) {
	case lua.LString:
		return render.LuaString(string(v))
	case lua.LNumber:
		// tostring's nan and inf would read as (nil) globals
		switch f := float64(v); {
		case math.IsNaN(f):
			return "(0/0)"
		case math.IsInf(f, 1):
			return "math.huge"
		case math.IsInf(f, -1):
			return "-math.huge"
		}
		return numberText(float64(v))
	case lua.LBool:
		if v {
			return "true"
		}
		return "false"
	case *lua.LTable:
		n := v.Len()
		var parts []string
		for i := 1; i <= n; i++ {
			parts = append(parts, luaSource(v.RawGetInt(i)))
		}
		var keys []lua.LValue
		v.ForEach(func(k, _ lua.LValue) {
			if num, ok := k.(lua.LNumber); ok && isWhole(float64(num)) && num >= 1 && int(num) <= n {
				return
			}
			keys = append(keys, k)
		})
		sort.SliceStable(keys, func(i, j int) bool { return luaToString(keys[i]) < luaToString(keys[j]) })
		for _, k := range keys {
			name := "[" + luaSource(k) + "]"
			if s, ok := k.(lua.LString); ok && luaName.MatchString(string(s)) && !luaKeywords[string(s)] {
				name = string(s)
			}
			parts = append(parts, name+" = "+luaSource(v.RawGet(k)))
		}
		if len(parts) == 0 {
			return "{}"
		}
		return "{ " + strings.Join(parts, ", ") + " }"
	}
	return v.String()
}
