package render

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	lua "github.com/yuin/gopher-lua"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// runLua runs chunks in one Lua state, failing on the first that errors
// (an assert in it, or Lua that doesn't parse)
func runLua(t *testing.T, chunks ...string) {
	t.Helper()
	L := lua.NewState()
	defer L.Close()
	for _, chunk := range chunks {
		if err := L.DoString(chunk); err != nil {
			t.Fatalf("%v\n%s", err, chunk)
		}
	}
}

func repoSchema(t *testing.T) any {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(testkit.RepoRoot(), "qml/config/json/config.schema.json"))
	if err != nil {
		t.Fatal(err)
	}
	return parse(t, string(data))
}

// The greeter's Hyprland (GreeterLua): the x-greeter input options of the
// parts that are on, as Lua that runs
func TestGreeterLua(t *testing.T) {
	t.Parallel()
	inputSchema := get(get(repoSchema(t), "properties"), "Input")
	stub := `hl = { config = function(t) end }`

	if none := GreeterLua(inputSchema, nil); len(none) != 0 {
		t.Errorf("no input: nothing set:\n%s", strings.Join(none, "\n"))
	}
	off := parse(t, `{"keyboard": {"enabled": false, "layout": "us,de"}, "mouse": {"enabled": false, "sensitivity": -50}}`)
	if got := GreeterLua(inputSchema, off); len(got) != 0 {
		t.Errorf("every part off: nothing set:\n%s", strings.Join(got, "\n"))
	}
	on := parse(t, `{"keyboard": {"enabled": true, "layout": "us,de"}, "mouse": {"enabled": true, "sensitivity": -50}, "touchpad": {"enabled": false, "naturalScroll": true}}`)
	lines := GreeterLua(inputSchema, on)
	config := strings.Join(lines, "\n")
	for _, want := range []string{"hl.config(", `kb_layout = "us,de"`, "sensitivity = -0.5"} {
		if !strings.Contains(config, want) {
			t.Errorf("no %q in %s", want, config)
		}
	}
	if strings.Contains(config, "touchpad") {
		t.Errorf("its part is off: %s", config)
	}
	runLua(t, stub, strings.Join(lines, "\n"))

	// acceleration left at default writes no accel_profile (Hyprland 0.57
	// refuses ""); another profile is written
	for accel, want := range map[string]string{"default": "", "flat": `accel_profile = "flat"`} {
		mouse := parse(t, `{"mouse": {"enabled": true, "accel": "`+accel+`"}}`)
		got := strings.Join(GreeterLua(inputSchema, mouse), "\n")
		if want == "" && strings.Contains(got, "accel_profile") || !strings.Contains(got, want) {
			t.Errorf("accel %s: want %q in %s", accel, want, got)
		}
	}
}

// A field whose spec names `device: touchpad` (InputLua, GreeterLua)
// leaves the hl.config() table for one hl.device() per pointer named like
// a touchpad, each in a pcall; a mouse is left to the global options
func TestTouchpadDeviceLua(t *testing.T) {
	t.Parallel()
	schema := parse(t, `{"type": "object", "properties": {
		"mouse": {"type": "object", "properties": {"enabled": {"type": "boolean", "x-greeter": true},
			"sensitivity": {"type": "integer", "x-greeter": true, "x-compositor": {"hyprland": {"key": "input.sensitivity", "scale": 0.01, "if": "enabled"}}}}},
		"touchpad": {"type": "object", "properties": {"enabled": {"type": "boolean", "x-greeter": true},
			"accel": {"type": "string", "x-greeter": true, "x-compositor": {"hyprland": {"device": "touchpad", "key": "accel_profile", "skip": "default", "if": "enabled"}}},
			"sensitivity": {"type": "integer", "x-greeter": true, "x-compositor": {"hyprland": {"device": "touchpad", "key": "sensitivity", "scale": 0.01, "if": "enabled"}}},
			"leftHanded": {"type": "boolean", "x-greeter": true, "x-compositor": {"hyprland": {"device": "touchpad", "key": "left_handed", "if": "enabled"}}}}}}}`)
	values := parse(t, `{"mouse": {"enabled": true, "sensitivity": -50}, "touchpad": {"enabled": true, "accel": "adaptive", "sensitivity": 25, "leftHanded": true}}`)
	stub := `set = {}
hl = { config = function(t) config = t end,
  get_devices = function() return {
    { name = "logitech-g502", type = "pointer" }, { name = "elan0001:00-04f3:3138-touchpad", type = "pointer" },
    { name = "bcm5974-trackpad", type = "pointer" }, { name = "at-translated-set-2-keyboard", type = "keyboard" }, { type = "pointer" } } end,
  device = function(spec)
    if spec.name == "elan0001:00-04f3:3138-touchpad" and set.refuse then error("refused") end
    set[spec.name] = spec
  end }`
	check := `assert(config.input.sensitivity == -0.5 and config.input.accel_profile == nil, "the mouse stays global")
for _, name in ipairs({ "elan0001:00-04f3:3138-touchpad", "bcm5974-trackpad" }) do
  local s = set[name]
  assert(s and s.accel_profile == "adaptive" and s.sensitivity == 0.25 and s.left_handed == true, name)
end
assert(set["logitech-g502"] == nil and set["at-translated-set-2-keyboard"] == nil, "only touchpads")`
	for name, lines := range map[string][]string{"input": InputLua(jsonx.Obj("values", values), schema), "greeter": GreeterLua(schema, values)} {
		t.Run(name, func(t *testing.T) {
			lua := strings.Join(lines, "\n")
			runLua(t, stub, lua, check)
			// One touchpad refusing leaves the others
			runLua(t, stub, "set.refuse = true", lua, `assert(set["bcm5974-trackpad"])`)
		})
	}
	// The touchpad's part off: no hl.device(), so it follows the mouse
	off := parse(t, `{"mouse": {"enabled": true, "sensitivity": -50}, "touchpad": {"enabled": false, "sensitivity": 25}}`)
	if got := strings.Join(GreeterLua(schema, off), "\n"); strings.Contains(got, "hl.device") {
		t.Errorf("touchpad part off: %s", got)
	}
	// An older Hyprland with no hl.get_devices runs it all the same
	runLua(t, "hl = { config = function(t) end, device = function() error(\"called\") end }", strings.Join(GreeterLua(schema, values), "\n"))
}

// Every managed Hyprland option, each changed from its default, makes Lua
// that runs and holds each option's path
func TestManagedOptionsAsLua(t *testing.T) {
	t.Parallel()
	managed := get(get(get(get(repoSchema(t), "properties"), "Compositor"), "properties"), "hyprland")
	values := jsonx.NewObject()
	var paths []string
	props := get(managed, "properties").(*jsonx.Object)
	for _, key := range props.Keys() {
		field := props.Value(key)
		spec := get(get(field, "x-compositor"), "hyprland")
		if spec == nil {
			continue
		}
		if s, ok := get(spec, "if").(string); ok {
			values.Set(s, true)
		}
		def := get(field, "default")
		switch {
		case get(field, "type") == "boolean":
			values.Set(key, !isTrue(def))
		case get(field, "type") == "integer":
			if max, ok := get(field, "maximum").(float64); ok && num(def)+1 > max {
				values.Set(key, num(def)-1)
			} else {
				values.Set(key, num(def)+1)
			}
		case get(field, "enum") != nil:
			for _, option := range items(get(field, "enum")) {
				if !jsonx.StrictEqual(option, def) {
					values.Set(key, option)
					break
				}
			}
		case get(field, "type") == "string":
			if get(spec, "value") == "color" {
				values.Set(key, "base08")
			} else {
				values.Set(key, "changed")
			}
		default:
			values.Set(key, def)
		}
		if s, ok := get(spec, "key").(string); ok {
			paths = append(paths, s)
		} else {
			paths = append(paths, stringList(get(spec, "key"))...)
		}
	}
	hex := Func(func(args ...any) any { return "445566" })
	table := ConfigTable(managed, values, hex, nil)
	for _, path := range paths {
		var node any = table
		for _, key := range strings.Split(path, ".") {
			node = get(node, key)
		}
		if node == nil {
			t.Errorf("%s missing from the table", path)
		}
	}
	runLua(t, "hl = { config = function(t) end }\nhl.config("+Serialize(table, "")+")")
}

// LookBlurLua is only the blur's part of LookLua: Hyprland's blur switch
// and the no-window-blur rule, none of the look's other options
func TestLookBlurLua(t *testing.T) {
	t.Parallel()
	look := parse(t, `{"parts":["gaps","blur"],"values":{},"gaps":{"inner":5,"outer":10},"blur":{"windows":false,"surfaces":true}}`)
	got := strings.Join(LookBlurLua(look), "\n")
	for _, want := range []string{"enabled = true", "popups = false", `"axiom-no-window-blur"`, "no_blur = true, enabled = true"} {
		if !strings.Contains(got, want) {
			t.Errorf("no %q in %q", want, got)
		}
	}
	if strings.Contains(got, "gaps") {
		t.Errorf("the gaps sent with the blur: %q", got)
	}
	if lines := LookBlurLua(parse(t, `{"parts":[],"values":{}}`)); len(lines) != 0 {
		t.Errorf("lines with the blur part off: %q", lines)
	}
}

// The profile a module holds (HyprFileMonitorCalls): its own hl.monitor
// calls, not the user's Lua, an older module's picker nor the managed
// file's catch-all
func TestHyprFileMonitorCalls(t *testing.T) {
	t.Parallel()
	text := `hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
function M.monitors()
  hl.monitor({ output = "DP-1", mode = "preferred", position = "0x0", scale = 1 })
  hl.monitor(rule)
        hl.monitor({ output = spec.output, mode = "preferred", position = "auto", scale = "auto" })
end`
	got := HyprFileMonitorCalls(text)
	if len(got) != 1 || got[0] != `hl.monitor({ output = "DP-1", mode = "preferred", position = "0x0", scale = 1 })` {
		t.Errorf("got %q", got)
	}
	if got := HyprFileMonitorCalls(nil); len(got) != 0 {
		t.Errorf("no file: %q", got)
	}
}

func TestIsAgentCommand(t *testing.T) {
	tab := repoTables(t)
	for _, c := range []struct {
		name    string
		command string
		want    bool
	}{
		{"systemd unit", "systemctl --user start hyprpolkitagent", true},
		{"unit with suffix", "systemctl --user start plasma-polkit-agent.service", true},
		{"path", "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1", true},
		{"quoted path", "'/usr/lib/polkit-kde-authentication-agent-1'", true},
		{"bare name with argument", "lxpolkit --verbose", true},
		{"other command", "hypridle", false},
		{"name inside another word", "my-hyprpolkitagent-wrapper", false},
		{"empty", "", false},
	} {
		if got := tab.IsAgentCommand(c.command); got != c.want {
			t.Errorf("%s: IsAgentCommand(%q) = %v, want %v", c.name, c.command, got, c.want)
		}
	}
}
