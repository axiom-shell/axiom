package binds

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// fx is a scratch compositor dir with a user/ folder
type fx struct {
	t    *testing.T
	dir  string
	kind string
}

func newFx(t *testing.T, kind string) *fx {
	t.Helper()
	dir := filepath.Join(t.TempDir(), kind)
	if err := os.MkdirAll(filepath.Join(dir, "user"), 0o755); err != nil {
		t.Fatal(err)
	}
	return &fx{t: t, dir: dir, kind: kind}
}

func (f *fx) options() Options {
	return Options{Kind: f.kind, Dir: f.dir,
		Getenv:  func(string) string { return "" },
		Now:     func() time.Time { return time.Date(2026, 10, 24, 12, 0, 0, 0, time.UTC) },
		Tracked: func(context.Context, string) bool { return false }}
}

func (f *fx) user(name string) string { return filepath.Join(f.dir, "user", name) }

func (f *fx) write(name, text string) {
	f.t.Helper()
	path := f.user(name)
	os.MkdirAll(filepath.Dir(path), 0o755)
	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		f.t.Fatal(err)
	}
}

func (f *fx) read(name string) string {
	f.t.Helper()
	data, err := os.ReadFile(f.user(name))
	if err != nil {
		f.t.Fatal(err)
	}
	return string(data)
}

func (f *fx) extract(only ...string) *jsonx.Object {
	f.t.Helper()
	o := f.options()
	if len(only) > 0 {
		o.Only = only[0]
	}
	out, err := Extract(context.Background(), o)
	if err != nil {
		f.t.Fatal(err)
	}
	return out
}

func (f *fx) remove(sites any) *jsonx.Object {
	f.t.Helper()
	// As the shell hands it over: through JSON
	list, _ := jsonx.Unmarshal(jsonx.MarshalCompact(sites))
	out, err := Remove(context.Background(), f.options(), list.(*jsonx.Array))
	if err != nil {
		f.t.Fatal(err)
	}
	return out
}

func list(o *jsonx.Object, key string) []*jsonx.Object {
	var out []*jsonx.Object
	for _, v := range o.Value(key).(*jsonx.Array).Items {
		if obj, ok := v.(*jsonx.Object); ok {
			out = append(out, obj)
		}
	}
	return out
}

func byKey(o *jsonx.Object) map[string]string {
	out := map[string]string{}
	for _, b := range list(o, "binds") {
		out[b.Value("key").(string)] = string(jsonx.MarshalCompact(b))
	}
	return out
}

func eq[T comparable](t *testing.T, got, want T) {
	t.Helper()
	if got != want {
		t.Fatalf("got %v, want %v", got, want)
	}
}

func js(v any) string { return string(jsonx.MarshalCompact(v)) }

// --- sway ---

const swayConfig = `set $mod Mod4
set $ipc '/opt/axiom/axiom' ipc
bindsym $mod+q kill
bindsym --no-repeat $mod+Return exec foot
bindsym $mod+h focus left
bindsym --locked XF86AudioRaiseVolume exec $ipc audio volumeUp
bindsym $mod+space exec $ipc appLauncher toggle
bindsym $mod+1 exec $ipc workspaces nth 1 go
bindsym --release $mod+Ctrl+r exec '/opt/axiom/axiom' restart
bindsym $mod+x layout tabbed
bindsym --border $mod+button2 kill
bindcode $mod+49 exec thing
mode "resize" {
    bindsym h resize shrink width 10px
}
bindsym --release button2 kill
bindsym --whole-window $mod+button3 floating toggle
bindsym --input-device=1:1:kbd $mod+y kill
exec_always foo \
bindsym $mod+z kill
bindsym XF86AudioLowerVolume exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindsym $mod+2 workspace number 2
bindsym $mod+3 workspace 3
bindsym $mod+4 workspace number 4:web
bindsym $mod+Shift+2 move container to workspace number 2
bindsym $mod+Shift+3 move to workspace 3
bindsym $mod+Tab workspace next
bindsym $mod+Shift+Tab move window to workspace prev
include ../definitions
bindsym $mod+t exec $term
bindsym $mod+c exec notify-send bye; kill
bindsym $mod+v exec "foot", focus left
bindsym $mod+b exec notify-send "a; b, c"
`

func TestSwayExtract(t *testing.T) {
	t.Parallel()
	f := newFx(t, "sway")
	f.write("00-previous.conf", swayConfig)
	f.write("../definitions", "set $term foot -T 'my term'\n")
	found := f.extract()
	binds := byKey(found)
	// Repeats only where axiom's action does (or a raw command as sway had it)
	eq(t, binds["SUPER + Q"], `{"key":"SUPER + Q","action":"closeWindow"}`)
	eq(t, binds["XF86AudioRaiseVolume"], `{"key":"XF86AudioRaiseVolume","action":"volumeUp","locked":true,"repeating":true}`)
	eq(t, binds["SUPER + CTRL + R"], `{"key":"SUPER + CTRL + R","action":"restartShell","release":true}`)
	eq(t, binds["SUPER + Return"], `{"key":"SUPER + Return","action":"exec","argument":"foot"}`)
	eq(t, binds["SUPER + H"], `{"key":"SUPER + H","action":"focusDir","argument":"left"}`)
	eq(t, binds["SUPER + space"], `{"key":"SUPER + space","action":"launcher","call":"toggle"}`)
	eq(t, binds["SUPER + 1"], `{"key":"SUPER + 1","action":"workspaceNth","argument":"1"}`)
	eq(t, binds["SUPER + X"], `{"key":"SUPER + X","action":"raw","argument":"layout tabbed","compositor":"sway","repeating":true}`)
	eq(t, binds["SUPER + code:49"], `{"key":"SUPER + code:49","action":"exec","argument":"thing"}`)
	// An exec of a media command is its action, as on the other compositors
	eq(t, binds["XF86AudioLowerVolume"], `{"key":"XF86AudioLowerVolume","action":"volumeDown","repeating":true}`)
	// Workspaces by number and next/prev are axiom's; a named one stays sway's
	eq(t, binds["SUPER + 2"], `{"key":"SUPER + 2","action":"workspaceNth","argument":"2"}`)
	eq(t, binds["SUPER + 3"], `{"key":"SUPER + 3","action":"workspaceNth","argument":"3"}`)
	eq(t, binds["SUPER + 4"], `{"key":"SUPER + 4","action":"raw","argument":"workspace number 4:web","compositor":"sway","repeating":true}`)
	eq(t, binds["SUPER + SHIFT + 2"], `{"key":"SUPER + SHIFT + 2","action":"moveWindowNth","argument":"2"}`)
	eq(t, binds["SUPER + SHIFT + 3"], `{"key":"SUPER + SHIFT + 3","action":"moveWindowNth","argument":"3"}`)
	eq(t, binds["SUPER + Tab"], `{"key":"SUPER + Tab","action":"workspaceStep","argument":"right"}`)
	eq(t, binds["SUPER + SHIFT + Tab"], `{"key":"SUPER + SHIFT + Tab","action":"moveWindowStep","argument":"left"}`)
	// A mode's binds aren't seen; sway options axiom binds lack stay
	_, mode := binds["H"]
	eq(t, mode, false)
	// Only over a title bar: axiom's mouse binds are for the whole window
	eq(t, binds["SUPER + mouse:273"], `{"key":"SUPER + mouse:273","action":"toggleFloat"}`)
	// Part of the exec_always above it, to sway
	_, continued := binds["SUPER + Z"]
	eq(t, continued, false)
	var kept []string
	for _, k := range list(found, "kept") {
		kept = append(kept, js(k.Value("line"))+" "+k.Value("key").(string)+" "+k.Value("reason").(string)+": "+k.Value("detail").(string))
	}
	eq(t, strings.Join(kept, ", "), "11 Mod4+button2 options: --border, 16 button2 options: title bar, 18 Mod4+y options: --input-device=1:1:kbd")
	eq(t, list(found, "kept")[0].Value("file"), any(f.user("00-previous.conf")))
	// A variable set in an included file, as sway reads it
	eq(t, binds["SUPER + T"], `{"key":"SUPER + T","action":"exec","argument":"foot -T 'my term'"}`)
	// Several commands, split at a ; or , outside quotes, stay sway's
	eq(t, binds["SUPER + C"], `{"key":"SUPER + C","action":"raw","argument":"exec notify-send bye; kill","compositor":"sway","repeating":true}`)
	eq(t, binds["SUPER + V"], `{"key":"SUPER + V","action":"raw","argument":"exec \"foot\", focus left","compositor":"sway","repeating":true}`)
	eq(t, binds["SUPER + B"], `{"key":"SUPER + B","action":"exec","argument":"notify-send \"a; b, c\""}`)
	// With --only, the variables user/'s earlier files set
	f.write("01-later.conf", "bindsym $mod+e exec $term\n")
	eq(t, byKey(f.extract("01-later.conf"))["SUPER + E"], `{"key":"SUPER + E","action":"exec","argument":"foot -T 'my term'"}`)
	// A file already included isn't read again, as sway skips it
	f.write("01-later.conf", "set $term kitty\ninclude ../definitions\nbindsym $mod+e exec $term\n")
	eq(t, byKey(f.extract("01-later.conf"))["SUPER + E"], `{"key":"SUPER + E","action":"exec","argument":"kitty"}`)
}

// Commenting one line out of a `bindsym { … }` block would leave the rest
// of it there: those binds stay, and say why
func TestSwayBlockBindsStay(t *testing.T) {
	t.Parallel()
	f := newFx(t, "sway")
	f.write("00-previous.conf", "set $mod Mod4\nbindsym --release {\n    $mod+x exec foo\n}\nmode \"m\" {\n    bindsym {\n        h kill\n    }\n}\nbindsym $mod+q kill\n")
	found := f.extract()
	eq(t, len(list(found, "binds")), 1)
	eq(t, list(found, "binds")[0].Value("key"), "SUPER + Q")
	kept := list(found, "kept")
	eq(t, len(kept), 1)
	eq(t, kept[0].Value("key").(string)+" "+js(kept[0].Value("line"))+" "+kept[0].Value("reason").(string), "Mod4+x 3 block")
}

// An exec's text is what sway hands the shell (checked against sway 1.12):
// one quoted word loses its quotes, an escaped quote is a bare one by then,
// several words keep theirs
func TestSwayExecReadAsSwayRunsIt(t *testing.T) {
	t.Parallel()
	f := newFx(t, "sway")
	f.write("00-previous.conf", strings.Join([]string{
		`bindsym Mod4+a exec "'/opt/axiom/axiom' ipc workspaces step 'up' go"`,
		`bindsym Mod4+b exec 'echo "q"; echo  z'`,
		`bindsym Mod4+c exec "grim -g \"$(slurp)\" out.png"`,
		`bindsym Mod4+d exec notify-send "a  b" c`,
		`bindsym Mod4+e resize grow width 10 px,  resize grow height 10 px`,
	}, "\n")+"\n")
	args := map[string]string{}
	for _, b := range list(f.extract(), "binds") {
		arg, _ := b.Value("argument").(string)
		args[b.Value("key").(string)] = b.Value("action").(string) + " " + arg
	}
	eq(t, args["SUPER + A"], "workspaceStep up")
	eq(t, args["SUPER + B"], `exec echo "q"; echo  z`)
	eq(t, args["SUPER + C"], "exec grim -g $(slurp) out.png")
	eq(t, args["SUPER + D"], `exec notify-send "a  b" c`)
	eq(t, args["SUPER + E"], "raw resize grow width 10 px, resize grow height 10 px")
}

// As `axiom compositor claim` adopts it: the line starting axiom commented
// out, the binds calling its IPC left for the merge
func TestSwayIPCVariableIsExpanded(t *testing.T) {
	t.Parallel()
	f := newFx(t, "sway")
	f.write("00-previous.conf", "set $ipc '/opt/axiom/axiom' ipc\nbindsym Mod4+d exec '/opt/axiom/axiom' ipc appLauncher toggle\n"+
		"bindsym Mod4+space exec $ipc appLauncher toggle\n# (axiom starts and loads itself now) exec_always --no-startup-id axiom run\n")
	found := f.extract("00-previous.conf")
	if strings.Contains(js(found.Value("binds")), "$ipc") {
		t.Fatalf("%s", js(found.Value("binds")))
	}
	eq(t, len(list(found, "binds")), 2)
}

func TestSwayRemove(t *testing.T) {
	t.Parallel()
	f := newFx(t, "sway")
	f.write("00-previous.conf", swayConfig)
	found := f.extract()
	done := f.remove(found.Value("sites"))
	eq(t, js(done.Value("failed")), "[]")
	eq(t, int(done.Value("removed").(float64)), len(list(found, "sites")))
	text := f.read("00-previous.conf")
	eq(t, strings.Contains(text, "# (moved into axiom) bindsym $mod+q kill"), true)
	eq(t, strings.Contains(text, "\nbindsym --border $mod+button2 kill"), true)
	backups, _ := os.ReadDir(f.user(".backups"))
	eq(t, len(backups), 1)
	// Moved again: nothing left to move
	eq(t, len(list(f.extract(), "binds")), 0)
}

func TestSwayWhatItReadsDifferently(t *testing.T) {
	t.Parallel()
	f := newFx(t, "sway")
	f.write(".swap.conf", "bindsym Mod4+z kill\n")
	f.write("00-previous.conf", "bindsym Mod4+a exec --no-startup-id foot\r\nbindsym --to-code Mod4+b kill\r\n")
	found := f.extract()
	// No hidden file
	eq(t, js(found.Value("binds")), `[{"key":"SUPER + A","action":"exec","argument":"foot"}]`)
	eq(t, list(found, "kept")[0].Value("reason"), "options")
	done := f.remove(found.Value("sites"))
	// CRLF lines are found
	eq(t, js(done.Value("failed"))+js(done.Value("removed")), "[]1")
}

func TestSwayChangedLineStays(t *testing.T) {
	t.Parallel()
	f := newFx(t, "sway")
	f.write("00-previous.conf", swayConfig)
	found := f.extract()
	f.write("00-previous.conf", strings.Replace(swayConfig, "bindsym $mod+q kill", "bindsym $mod+q exec other", 1))
	done := f.remove(found.Value("sites"))
	failed := list(done, "failed")
	eq(t, len(failed), 1)
	eq(t, js(failed[0].Value("line"))+" "+failed[0].Value("reason").(string), "3 changed")
}

// --- Hyprland ---

func TestHyprNothingToMerge(t *testing.T) {
	t.Parallel()
	eq(t, js(newFx(t, "hyprland").extract()), `{"binds":[],"sites":[],"kept":[],"remapped":[],"tracked":[],"errors":[]}`)
}

func TestHyprExampleConfigMovesCompletelyOntoAxiomActions(t *testing.T) {
	t.Parallel()
	example, err := os.ReadFile("/usr/share/hypr/hyprland.lua")
	if err != nil {
		t.Skip("Hyprland's example config isn't installed")
	}
	f := newFx(t, "hyprland")
	f.write("00-previous.lua", string(example))
	found := f.extract()
	eq(t, js(found.Value("kept")), "[]")
	got := map[string]*jsonx.Object{}
	for _, b := range list(found, "binds") {
		got[b.Value("key").(string)] = b
		if b.Value("action") == "raw" {
			t.Errorf("raw: %s", js(b))
		}
	}
	action := func(key string) string {
		b, ok := got[key]
		if !ok {
			return "-"
		}
		return b.Value("action").(string) + " " + b.Value("argument").(string)
	}
	eq(t, action("SUPER + 0"), "workspaceNth 10")
	// Its split moves off SUPER + J, which axiom's focus down uses
	eq(t, action("SUPER + J"), "-")
	eq(t, action("SUPER + X"), "toggleSplit ")
	// Its special workspace leaves WASD's S for V, and its float V for Z
	eq(t, action("SUPER + S"), "-")
	eq(t, action("SUPER + SHIFT + S"), "-")
	eq(t, action("SUPER + V"), "toggleSpecial magic")
	eq(t, action("SUPER + SHIFT + V"), "moveToSpecial magic")
	eq(t, action("SUPER + Z"), "toggleFloat ")
	eq(t, got["SUPER + mouse_down"].Value("argument"), "right")
	eq(t, got["XF86AudioRaiseVolume"].Value("repeating"), true)
	done := f.remove(found.Value("sites"))
	eq(t, js(done.Value("failed")), "[]")
	text := f.read("00-previous.lua")
	eq(t, strings.Contains(text, "hl.bind("), false)
	eq(t, strings.Contains(text, "hl.window_rule("), true)
	backups, _ := filepath.Glob(f.user("*.axiom-backup-*"))
	eq(t, len(backups), 1)
	eq(t, js(f.extract().Value("binds")), "[]")
}

func TestHyprMappingAndRawLua(t *testing.T) {
	t.Parallel()
	f := newFx(t, "hyprland")
	f.write("binds.lua", strings.Join([]string{
		`local mod = "SUPER"`,
		`hl.bind(mod .. " + T", hl.dsp.exec_cmd("foot"), { description = "Apps: Foot" })`,
		`hl.bind(mod .. " + K", hl.dsp.layout("swapsplit"))`,
		`hl.bind(mod .. " + L", hl.dsp.window.move({ workspace = "e+1" }))`,
		`hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })`,
		`hl.bind(mod .. " + R", hl.dsp.window.resize({ x = 10, y = -20, relative = true }), { repeating = true })`,
		`hl.bind(mod .. " + W", hl.dsp.focus({ workspace = 3 }))`,
		`hl.bind(mod .. " + M", hl.dsp.window.move({ workspace = "special:scratch" }))`,
		`hl.bind(mod .. " + N", hl.dsp.window.tag({ tag = "a\nb", list = { 1, 2 } }))`,
		`hl.bind(mod .. " + D", hl.dsp.exec_cmd("axiom ipc appLauncher toggle"))`,
		`hl.bind(mod .. " + E", hl.dsp.exec_cmd("axiom ipc menu show 'left'"))`,
		"",
	}, "\n"))
	binds := byKey(f.extract())
	eq(t, binds["SUPER + T"], `{"key":"SUPER + T","action":"exec","argument":"foot","call":"toggle","locked":false,"repeating":false,"release":false,"description":"Apps: Foot"}`)
	eq(t, binds["SUPER + K"], `{"key":"SUPER + K","action":"raw","argument":"hl.dsp.layout(\"swapsplit\")","call":"toggle","compositor":"hyprland","locked":false,"repeating":false,"release":false,"description":""}`)
	eq(t, strings.Contains(binds["SUPER + L"], `"action":"moveWindowStep","argument":"right"`), true)
	eq(t, strings.Contains(binds["SUPER + mouse:272"], `"action":"mouseDrag"`), true)
	eq(t, strings.Contains(binds["SUPER + R"], `"action":"resizeWindow","argument":"10 -20"`), true)
	eq(t, strings.Contains(binds["SUPER + R"], `"repeating":true`), true)
	eq(t, strings.Contains(binds["SUPER + W"], `"action":"workspaceNth","argument":"3"`), true)
	eq(t, strings.Contains(binds["SUPER + M"], `"action":"moveToSpecial","argument":"scratch"`), true)
	// Raw Lua as Lua writes it back: list part first, other keys sorted
	eq(t, strings.Contains(binds["SUPER + N"], `"argument":"hl.dsp.window.tag({ list = { 1, 2 }, tag = \"a\\nb\" })"`), true)
	// A command calling axiom is its action, with the call it names
	eq(t, binds["SUPER + D"], `{"key":"SUPER + D","action":"launcher","argument":"","call":"toggle","locked":false,"repeating":false,"release":false,"description":""}`)
	eq(t, strings.Contains(binds["SUPER + E"], `"action":"menu","argument":"left","call":"open"`), true)
}

func TestHyprWhatCantMoveStays(t *testing.T) {
	t.Parallel()
	f := newFx(t, "hyprland")
	f.write("binds.lua", strings.Join([]string{
		`hl.bind("SUPER + A", function() end)`,
		`hl.bind("SUPER + B", hl.dsp.window.close(), { non_consuming = true })`,
		`local used = hl.bind("SUPER + C", hl.dsp.window.close())`,
		"used:set_enabled(false)",
		`hl.bind("SUPER + D", hl.dsp.window.close()) hl.bind("SUPER + E", hl.dsp.window.pin())`,
		`for _, k in ipairs({ "F", "G" }) do`,
		`  hl.bind("SUPER + " .. k, k == "F" and hl.dsp.window.close() or function() end)`,
		"end",
		`hl.bind("SUPER + H", hl.dsp.window.pin())`,
		"",
	}, "\n"))
	found := f.extract()
	eq(t, len(list(found, "binds")), 1)
	eq(t, list(found, "binds")[0].Value("key"), "SUPER + H")
	var reasons []string
	for _, k := range list(found, "kept") {
		reasons = append(reasons, k.Value("key").(string)+" "+k.Value("reason").(string))
	}
	eq(t, strings.Join(reasons, ", "), "SUPER + A function, SUPER + B options, SUPER + C used, SUPER + D notOnly, SUPER + E notOnly, SUPER + F function, SUPER + G function")
	f.remove(found.Value("sites"))
	text := f.read("binds.lua")
	eq(t, strings.Contains(text, "SUPER + H"), false)
	eq(t, strings.Contains(text, "SUPER + C"), true)
}

// An unbind of a moved key goes with it, the key spelled any way Hyprland
// reads it (WIN is SUPER)
func TestHyprUnbindOfAMovedKeyGoesToo(t *testing.T) {
	t.Parallel()
	f := newFx(t, "hyprland")
	f.write("binds.lua", "hl.unbind(\"WIN + q\")\nhl.bind(\"SUPER + Q\", hl.dsp.exec_cmd(\"foot\"))\nhl.unbind(\"SUPER + W\")\n")
	found := f.extract()
	eq(t, len(list(found, "sites")), 2)
	f.remove(found.Value("sites"))
	eq(t, f.read("binds.lua"), "hl.unbind(\"SUPER + W\")\n")
}

// A moved key's hl.unbind and its bind go together or stay together, in
// whichever files they are: here one of them changed since extract
func TestHyprUnbindAndItsBindStayTogether(t *testing.T) {
	t.Parallel()
	for _, changed := range []string{"unbinds.lua", "binds.lua"} {
		f := newFx(t, "hyprland")
		f.write("unbinds.lua", "hl.unbind(\"SUPER + Q\")\n")
		f.write("binds.lua", "hl.bind(\"SUPER + Q\", hl.dsp.exec_cmd(\"foot\"))\nhl.bind(\"SUPER + W\", hl.dsp.window.pin())\n")
		found := f.extract()
		text := strings.Replace(f.read(changed), "SUPER + Q", "SUPER + Q ", 1)
		f.write(changed, text)
		done := f.remove(found.Value("sites"))
		var failed []string
		for _, e := range list(done, "failed") {
			failed = append(failed, filepath.Base(e.Value("file").(string))+":"+js(e.Value("line"))+" "+e.Value("reason").(string))
		}
		want := map[string]string{"unbinds.lua": "binds.lua:1 paired, unbinds.lua:1 changed",
			"binds.lua": "binds.lua:1 changed, unbinds.lua:1 paired"}[changed]
		eq(t, strings.Join(failed, ", "), want)
		eq(t, js(done.Value("removed")), "1")
		eq(t, strings.Contains(f.read("binds.lua"), "SUPER + W"), false)
		eq(t, strings.Contains(f.read("unbinds.lua"), "hl.unbind"), true)
	}
}

// require reads a dot as a folder, so a dotted name never loads: an error,
// and its binds stay
func TestHyprADottedFileIsAnError(t *testing.T) {
	t.Parallel()
	f := newFx(t, "hyprland")
	f.write("my.binds.lua", "hl.bind(\"SUPER + Q\", hl.dsp.window.close())\n")
	found := f.extract()
	eq(t, js(found.Value("binds")), "[]")
	eq(t, strings.HasPrefix(list0(found, "errors"), "user/my.binds.lua: not loaded"), true)
}

func list0(o *jsonx.Object, key string) string {
	items := o.Value(key).(*jsonx.Array).Items
	if len(items) == 0 {
		return ""
	}
	return items[0].(string)
}

// A raw dispatcher's table rebuilt as source that Lua reads back: a
// keyword key bracketed, nan and inf as expressions
func TestHyprRawLuaKeepsKeywordKeysAndOddNumbers(t *testing.T) {
	t.Parallel()
	f := newFx(t, "hyprland")
	f.write("binds.lua", `hl.bind("SUPER + N", hl.dsp.window.tag({ ["end"] = 1, n = 0/0, i = 1/0, m = -1/0 }))`+"\n")
	eq(t, byKey(f.extract())["SUPER + N"] != "", true)
	eq(t, strings.Contains(byKey(f.extract())["SUPER + N"], `hl.dsp.window.tag({ [\"end\"] = 1, i = math.huge, m = -math.huge, n = (0/0) })`), true)
}

func TestHyprMultilineCallAndTrailingComment(t *testing.T) {
	t.Parallel()
	f := newFx(t, "hyprland")
	f.write("binds.lua", "hl.bind(\n  \"SUPER + Q\",\n  hl.dsp.exec_cmd(\"a )\"), -- (\n  { locked = true }\n) -- done\nhl.env(\"A\", \"b\")\n")
	found := f.extract()
	eq(t, list(found, "binds")[0].Value("locked"), true)
	f.remove(found.Value("sites"))
	eq(t, f.read("binds.lua"), "hl.env(\"A\", \"b\")\n")
}

func TestHyprSharedModulesAreLeftAlone(t *testing.T) {
	t.Parallel()
	f := newFx(t, "hyprland")
	f.write("lib/keys.lua", "return function() hl.bind(\"SUPER + Z\", hl.dsp.window.pin()) end\n")
	f.write("binds.lua", "require(\"user.lib.keys\")()\n")
	found := f.extract()
	eq(t, js(found.Value("binds")), "[]")
	eq(t, list(found, "kept")[0].Value("reason"), "shared")
}

func TestHyprRunningTheFilesDoesNothingAndEnds(t *testing.T) {
	t.Parallel()
	f := newFx(t, "hyprland")
	marker := filepath.Join(f.dir, "ran")
	f.write("binds.lua", strings.Join([]string{
		"for _, m in ipairs(hl.get_monitors()) do end",
		`io.popen("touch ` + marker + `")`,
		`io.open("` + marker + `", "w")`,
		`io.output("` + marker + `")`,
		`os.execute("touch ` + marker + `")`,
		`require("io").popen("touch ` + marker + `")`,
		`package.loaded.io.output("` + marker + `")`,
		`print("noise")`,
		`hl.bind("SUPER + Y", hl.dsp.window.close(), { locked = false })`,
		"",
	}, "\n"))
	found := f.extract()
	if _, err := os.Stat(marker); err == nil {
		t.Fatal("a command ran or a file was written")
	}
	eq(t, js(found.Value("errors")), "[]")
	eq(t, list(found, "binds")[0].Value("key"), "SUPER + Y")
	eq(t, list(found, "binds")[0].Value("locked"), false)
}

// io.open still reads, however it's called (the mode left out, or extra
// arguments)
func TestHyprFilesCanReadFiles(t *testing.T) {
	t.Parallel()
	f := newFx(t, "hyprland")
	data := filepath.Join(f.dir, "mod.txt")
	if err := os.WriteFile(data, []byte("SUPER"), 0o644); err != nil {
		t.Fatal(err)
	}
	f.write("binds.lua", strings.Join([]string{
		`local a = io.open("` + data + `")`,
		`local b = io.open("` + data + `", "r", "extra")`,
		`hl.bind(a:read("*a") .. " + Y", hl.dsp.window.close())`,
		`hl.bind(b:read("*a") .. " + U", hl.dsp.window.close())`,
		"",
	}, "\n"))
	found := f.extract()
	eq(t, js(found.Value("errors")), "[]")
	eq(t, list(found, "binds")[0].Value("key"), "SUPER + Y")
	eq(t, list(found, "binds")[1].Value("key"), "SUPER + U")
}

func TestHyprAFileThatNeverEndsTimesOut(t *testing.T) {
	t.Parallel()
	f := newFx(t, "hyprland")
	f.write("binds.lua", "while true do end\n")
	o := f.options()
	o.Timeout = 200 * time.Millisecond
	if _, err := Extract(context.Background(), o); err == nil {
		t.Fatal("no error")
	}
}

// A file using Lua 5.4's syntax is one of the errors, and keeps its binds
func TestHyprLua54FileIsAnError(t *testing.T) {
	t.Parallel()
	f := newFx(t, "hyprland")
	f.write("a.lua", "local x = 7 // 2\nhl.bind(\"SUPER + Q\", hl.dsp.window.close())\n")
	f.write("b.lua", "hl.bind(\"SUPER + W\", hl.dsp.window.close())\n")
	found := f.extract()
	eq(t, len(list(found, "binds")), 1)
	errs := found.Value("errors").(*jsonx.Array).Items
	eq(t, len(errs), 1)
	eq(t, strings.HasPrefix(errs[0].(string), "user.a: "), true)
}

func TestHyprOnlyReadsTheNamedFile(t *testing.T) {
	t.Parallel()
	f := newFx(t, "hyprland")
	f.write("00-previous.lua", "hl.bind(\"SUPER + J\", hl.dsp.layout(\"togglesplit\"))\n")
	f.write("mine.lua", "hl.bind(\"SUPER + J\", hl.dsp.layout(\"togglesplit\"))\n")
	found := f.extract("00-previous.lua")
	real, _ := filepath.EvalSymlinks(f.user("00-previous.lua"))
	eq(t, len(list(found, "sites")), 1)
	eq[any](t, list(found, "sites")[0].Value("file"), real)
	// The adopted example's key moves off axiom's, and says so
	eq(t, js(found.Value("remapped")), `[{"from":"SUPER + J","to":"SUPER + X","action":"toggleSplit"}]`)
	// A file of the user's own keeps its key
	found = f.extract("mine.lua")
	eq(t, list(found, "binds")[0].Value("key"), "SUPER + J")
	eq(t, js(found.Value("remapped")), "[]")
}

func TestHyprAFailedRemovalNamesItsSites(t *testing.T) {
	t.Parallel()
	f := newFx(t, "hyprland")
	f.write("binds.lua", "hl.bind(\"SUPER + Y\", hl.dsp.window.close())\nhl.bind(\"SUPER + U\", hl.dsp.window.pin())\n")
	found := f.extract()
	eq(t, len(list(found, "sites")), 2)
	path := f.user("binds.lua")
	os.Chmod(path, 0o640)
	// The second call is gone by the time remove runs
	os.WriteFile(path, []byte("hl.bind(\"SUPER + Y\", hl.dsp.window.close())\n"), 0o640)
	done := f.remove(found.Value("sites"))
	eq[any](t, done.Value("removed"), float64(1))
	failed := list(done, "failed")
	eq(t, len(failed), 1)
	eq(t, js(failed[0].Value("line"))+" "+failed[0].Value("reason").(string), "2 changed")
	info, _ := os.Stat(path)
	eq(t, info.Mode().Perm(), os.FileMode(0o640))
}

// A file that changed since extract keeps whatever call is on a site's
// line now: here a new first line moves both down one
func TestHyprRemoveLeavesAStatementItDidntRead(t *testing.T) {
	t.Parallel()
	f := newFx(t, "hyprland")
	binds := "hl.bind(\"SUPER + Y\", hl.dsp.window.close())\nhl.bind(\"SUPER + U\", hl.dsp.window.pin())\n"
	f.write("binds.lua", binds)
	found := f.extract()
	text := "hl.bind(\"SUPER + Z\", hl.dsp.exec_cmd(\"mine\"))\n" + binds
	f.write("binds.lua", text)
	done := f.remove(found.Value("sites"))
	var failed []string
	for _, e := range list(done, "failed") {
		failed = append(failed, js(e.Value("line"))+" "+e.Value("reason").(string))
	}
	eq(t, strings.Join(failed, ", ")+" "+js(done.Value("removed")), "1 changed, 2 changed 0")
	eq(t, f.read("binds.lua"), text)
}

// A statement holding an invalid byte (here in its comment) is still the
// one extract read: the site's text reaches remove through JSON, as U+FFFD
func TestHyprRemoveTakesAStatementWithAnInvalidByte(t *testing.T) {
	t.Parallel()
	f := newFx(t, "hyprland")
	f.write("binds.lua", "hl.bind(\"SUPER + Y\", hl.dsp.window.close()) -- \xff\n")
	done := f.remove(f.extract().Value("sites"))
	eq(t, js(done.Value("failed"))+js(done.Value("removed")), "[]1")
	eq(t, f.read("binds.lua"), "")
}

// A helper's hl.bind stays: it also makes binds extract never sees (in a
// submap or hl.on handler, another branch). Its file's own calls, a loop's
// too, still move
func TestHyprABindMadeInAFunctionStays(t *testing.T) {
	t.Parallel()
	f := newFx(t, "hyprland")
	f.write("binds.lua", strings.Join([]string{
		"local function bindx(k, c)",
		"  hl.bind(k, hl.dsp.exec_cmd(c))",
		"end",
		`bindx("SUPER + A", "foo")`,
		`hl.define_submap("resize", function() bindx("x", "bar") end)`,
		`for _, k in ipairs({ "B", "C" }) do`,
		`  hl.bind("SUPER + " .. k, hl.dsp.window.close())`,
		"end",
		"",
	}, "\n"))
	found := f.extract()
	var kept []string
	for _, k := range list(found, "kept") {
		kept = append(kept, k.Value("key").(string)+" "+k.Value("reason").(string))
	}
	eq(t, strings.Join(kept, ", "), "SUPER + A inFunction")
	eq(t, len(list(found, "binds")), 2)
	f.remove(found.Value("sites"))
	text := f.read("binds.lua")
	eq(t, strings.Contains(text, "hl.bind(k, hl.dsp.exec_cmd(c))"), true)
	eq(t, strings.Contains(text, "window.close"), false)
}

// An edit that would leave the file unparsable leaves it alone
func TestHyprRemoveKeepsAFileThatWouldntParse(t *testing.T) {
	t.Parallel()
	f := newFx(t, "hyprland")
	f.write("binds.lua", "hl.bind(\"SUPER + Y\", hl.dsp.window.close())\n")
	found := f.extract()
	text := "if x then\nhl.bind(\"SUPER + Y\", hl.dsp.window.close())\n"
	f.write("binds.lua", text)
	sites := list(found, "sites")
	sites[0].Set("line", float64(2))
	done := f.remove(jsonx.Arr(sites[0]))
	failed := list(done, "failed")
	eq(t, failed[0].Value("reason"), "syntax")
	eq(t, f.read("binds.lua"), text)
}

// --- niri ---

const niriConfig = `input {
    mod-key "Super"
}
binds {
    Mod+Q repeat=false { close-window; }
    Mod+T hotkey-overlay-title="Terminal" { spawn "foot"; }
    Mod+H { focus-column-left; }
    Mod+1 { focus-workspace 1; }
    Mod+Shift+1 { move-column-to-workspace 1; }
    Mod+Space { spawn "/opt/axiom/axiom" "ipc" "appLauncher" "toggle"; }
    XF86AudioRaiseVolume allow-when-locked=true { spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1+ -l 1.0"; }
    Mod+O repeat=false { toggle-overview; }
    Mod+Escape allow-inhibiting=false { toggle-keyboard-shortcuts-inhibit; }
    Mod+Shift+E { quit; }
    Ctrl+Alt+Delete { quit skip-confirmation=true; }
    Mod+W {
        toggle-column-tabbed-display
    }
    Mod+P { spawn "notify-send" "it's" "a b"; }
    Mod+Y { spawn "/opt/My App/app"; }
    Mod+U { spawn "~/my scripts/run;x" "~/b"; }
}
`

func TestNiriExtract(t *testing.T) {
	t.Parallel()
	f := newFx(t, "niri")
	f.write("00-previous.kdl", niriConfig)
	found := f.extract()
	binds := byKey(found)
	eq(t, binds["SUPER + Q"], `{"key":"SUPER + Q","action":"closeWindow"}`)
	eq(t, binds["SUPER + T"], `{"key":"SUPER + T","action":"exec","argument":"foot","description":"Terminal"}`)
	eq(t, binds["SUPER + H"], `{"key":"SUPER + H","action":"focusDir","argument":"left"}`)
	eq(t, binds["SUPER + 1"], `{"key":"SUPER + 1","action":"workspaceNth","argument":"1"}`)
	eq(t, binds["SUPER + SHIFT + 1"], `{"key":"SUPER + SHIFT + 1","action":"moveWindowNth","argument":"1"}`)
	eq(t, binds["SUPER + Space"], `{"key":"SUPER + Space","action":"launcher","call":"toggle"}`)
	eq(t, binds["XF86AudioRaiseVolume"], `{"key":"XF86AudioRaiseVolume","action":"volumeUp","locked":true,"repeating":true}`)
	eq(t, binds["SUPER + O"], `{"key":"SUPER + O","action":"workspaceOverview"}`)
	// niri's quit asks first: it stays niri's; only one that doesn't is a log out
	eq(t, strings.Contains(binds["SUPER + SHIFT + E"], `"action":"raw","argument":"quit"`), true)
	eq(t, binds["CTRL + ALT + Delete"], `{"key":"CTRL + ALT + Delete","action":"exitSession"}`)
	eq(t, strings.Contains(binds["SUPER + W"], `"toggleGroup"`), true)
	eq(t, binds["SUPER + P"], `{"key":"SUPER + P","action":"exec","argument":"notify-send 'it'\"'\"'s' 'a b'"}`)
	// One word is quoted too; only the program's ~ is niri's home
	eq(t, binds["SUPER + Y"], `{"key":"SUPER + Y","action":"exec","argument":"'/opt/My App/app'"}`)
	eq(t, binds["SUPER + U"], `{"key":"SUPER + U","action":"exec","argument":"~/'my scripts/run;x' '~/b'"}`)
	kept := list(found, "kept")
	eq(t, len(kept), 1)
	eq(t, kept[0].Value("key").(string)+" "+kept[0].Value("reason").(string), "Mod+Escape options")
}

func TestNiriRemove(t *testing.T) {
	t.Parallel()
	f := newFx(t, "niri")
	f.write("00-previous.kdl", niriConfig)
	found := f.extract()
	done := f.remove(found.Value("sites"))
	eq(t, js(done.Value("failed")), "[]")
	eq(t, int(done.Value("removed").(float64)), len(list(found, "sites")))
	text := f.read("00-previous.kdl")
	eq(t, strings.Contains(text, "    /* (moved into axiom) */ /-Mod+Q repeat=false { close-window; }"), true)
	// niri's overview bind goes through axiom's (row 16)
	eq(t, strings.Contains(text, "    /* (moved into axiom) */ /-Mod+O repeat=false { toggle-overview; }"), true)
	eq(t, strings.Contains(text, "    Mod+Escape allow-inhibiting=false"), true)
	backups, _ := os.ReadDir(f.user(".backups"))
	eq(t, len(backups), 1)
	eq(t, len(list(f.extract(), "binds")), 0)
}

// Two binds on one line: both go, the first checked against the line as
// read, not as the second's mark left it
func TestNiriRemoveTwoBindsOnALine(t *testing.T) {
	t.Parallel()
	f := newFx(t, "niri")
	f.write("00-previous.kdl", "binds {\n    Mod+T { spawn \"foot\"; }; Mod+Q { close-window; }\n}\n")
	found := f.extract()
	eq(t, len(list(found, "sites")), 2)
	done := f.remove(found.Value("sites"))
	eq(t, js(done.Value("failed"))+js(done.Value("removed")), "[]2")
	eq(t, f.read("00-previous.kdl"), "binds {\n    /* (moved into axiom) */ /-Mod+T { spawn \"foot\"; }; /* (moved into axiom) */ /-Mod+Q { close-window; }\n}\n")
}

func TestNiriChangedLineStays(t *testing.T) {
	t.Parallel()
	f := newFx(t, "niri")
	f.write("00-previous.kdl", niriConfig)
	found := f.extract()
	f.write("00-previous.kdl", strings.Replace(niriConfig, "Mod+Q repeat=false", "Mod+Q", 1))
	done := f.remove(found.Value("sites"))
	failed := list(done, "failed")
	eq(t, len(failed), 1)
	eq(t, js(failed[0].Value("line"))+" "+failed[0].Value("reason").(string), "5 changed")
}

func TestNiriUnparsableFile(t *testing.T) {
	t.Parallel()
	f := newFx(t, "niri")
	f.write("00-previous.kdl", "binds {\n")
	found := f.extract()
	eq(t, js(found.Value("binds")), "[]")
	eq(t, len(list(found, "errors")), 1)
}

func TestNotAUserFile(t *testing.T) {
	t.Parallel()
	for _, kind := range []string{"sway", "niri", "hyprland"} {
		f := newFx(t, kind)
		outside := filepath.Join(f.dir, "config")
		os.WriteFile(outside, []byte("x\n"), 0o644)
		done := f.remove(jsonx.Arr(jsonx.Obj("file", outside, "line", float64(1))))
		eq(t, list(done, "failed")[0].Value("reason"), "notUser")
	}
}

// Only names a file in user/: never a path out of it
func TestOnlyIsAFileName(t *testing.T) {
	t.Parallel()
	f := newFx(t, "sway")
	os.WriteFile(filepath.Join(f.dir, "config"), []byte("bindsym Mod4+q kill\n"), 0o644)
	for _, only := range []string{"../config", "..", "a/b"} {
		o := f.options()
		o.Only = only
		if _, err := Extract(context.Background(), o); err == nil {
			t.Fatalf("%q was read", only)
		}
	}
}

// The marks are the only bytes a removal changes: a file in another
// encoding stays as it was around them
func TestRemovalKeepsTheFilesBytes(t *testing.T) {
	t.Parallel()
	for _, c := range []struct{ kind, name, text, want string }{
		{"sway", "00-previous.conf", "# caf\xe9\nbindsym Mod4+q kill\n", "# caf\xe9\n# (moved into axiom) bindsym Mod4+q kill\n"},
		{"niri", "00-previous.kdl", "// caf\xe9\nbinds {\n    Mod+Q { close-window; }\n}\n",
			"// caf\xe9\nbinds {\n    /* (moved into axiom) */ /-Mod+Q { close-window; }\n}\n"},
	} {
		f := newFx(t, c.kind)
		f.write(c.name, c.text)
		done := f.remove(f.extract().Value("sites"))
		eq(t, js(done.Value("failed")), "[]")
		eq(t, f.read(c.name), c.want)
	}
}

// A file that can't be written is failed, and the others still go: what
// was removed is reported, so nothing removed is put back as kept
func TestAnUnwritableFileFailsAlone(t *testing.T) {
	t.Parallel()
	if os.Geteuid() == 0 {
		t.Skip("root writes anywhere")
	}
	f := newFx(t, "sway")
	f.write("10-a.conf", "bindsym Mod4+a kill\n")
	f.write("20-b.conf", "bindsym Mod4+b kill\n")
	found := f.extract()
	// No backup can go in a read-only .backups
	os.MkdirAll(f.user(".backups"), 0o755)
	os.Chmod(f.user(".backups"), 0o555)
	t.Cleanup(func() { os.Chmod(f.user(".backups"), 0o755) })
	done := f.remove(found.Value("sites"))
	failed := list(done, "failed")
	eq(t, len(failed), 2)
	eq(t, failed[0].Value("reason"), "io")
	eq(t, int(done.Value("removed").(float64)), 0)
	os.Chmod(f.user(".backups"), 0o755)
	f.write("20-b.conf", "bindsym Mod4+b kill\n")
	os.Chmod(f.user("10-a.conf"), 0o444)
	os.Chmod(f.dir+"/user", 0o555)
	t.Cleanup(func() { os.Chmod(f.dir+"/user", 0o755) })
	done = f.remove(found.Value("sites"))
	// Neither file can be replaced in a read-only user/: both fail, alone
	eq(t, len(list(done, "failed")), 2)
}
