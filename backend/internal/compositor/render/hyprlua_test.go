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
	data, err := os.ReadFile(filepath.Join(testkit.RepoRoot(), "config/json/config.schema.json"))
	if err != nil {
		t.Fatal(err)
	}
	return parse(t, string(data))
}

// The monitors' Lua (MonitorsLua), run with a stubbed hl, picks the
// profile MonitorLayout.matchProfile picks, resolves a mirror to its
// connector, resets an output only another profile names, and drops the
// handlers of an earlier run
func TestMonitorsLuaPicks(t *testing.T) {
	t.Parallel()
	profiles := parse(t, `[
		{"name": "Desk", "outputs": [{"output": "desc:AOC", "mode": "3440x1440@240"}, {"output": "HDMI-A-1", "disabled": true}]},
		{"name": "TV", "outputs": [{"output": "desc:AOC", "mode": "3440x1440@144"}, {"output": "desc:LG TV", "mode": "1920x1080@60", "x": 3440, "mirror": "desc:AOC"}]}]`)
	if got := strings.Join(MonitorsLua(jsonx.Arr()), "\n"); !strings.Contains(got, "sub:remove()") || strings.Contains(got, "axiom_apply_monitors") {
		t.Errorf("no profiles: only the unsubscribing:\n%s", got)
	}
	runLua(t, `connected, applied, removed = {}, {}, 0
hl = {
  get_monitors = function() return connected end,
  monitor = function(spec) applied[#applied + 1] = spec end,
  on = function() return { remove = function() removed = removed + 1 end } end,
}
aoc = { name = "DP-1", description = "AOC" }
tv = { name = "HDMI-A-1", description = "LG TV" }
function check(monitors, mode)
  connected, applied = monitors, {}
  axiom_apply_monitors()
  assert(applied[1].mode == mode, "picked " .. tostring(applied[1].mode) .. ", wanted " .. mode)
end`, strings.Join(MonitorsLua(profiles), "\n"), `check({ aoc }, "3440x1440@240")
check({ tv }, "3440x1440@144")
-- The TV profile mirrors onto the AOC's connector, and resets the output
-- Desk disables
check({ aoc, tv }, "3440x1440@144")
assert(applied[2].mirror == "DP-1", "mirror resolved to a connector")
local reset = false
for _, spec in ipairs(applied) do
  if spec.output == "HDMI-A-1" and spec.mode == "preferred" then reset = true end
end
assert(reset, "the output Desk disables goes back to its defaults")
-- A first start, nothing reported yet: the first profile
check({}, "3440x1440@240")`, strings.Join(MonitorsLua(profiles), "\n"), `assert(removed == 2, "earlier handlers removed")`)
}

// The greeter's Hyprland (GreeterLua): the monitors always, and the
// x-greeter input options of the parts that are on, as Lua that runs
func TestGreeterLua(t *testing.T) {
	t.Parallel()
	inputSchema := get(get(repoSchema(t), "properties"), "Input")
	profiles := parse(t, `[{"name": "desk", "outputs": [{"output": "DP-1"}]}]`)
	stub := `hl = { config = function(t) end, monitor = function(t) end, get_monitors = function() return {} end, on = function() return { remove = function() end } end }`

	none := GreeterLua(profiles, inputSchema, nil, nil)
	if strings.Contains(strings.Join(none, "\n"), "hl.config") {
		t.Errorf("no input: nothing set:\n%s", strings.Join(none, "\n"))
	}
	off := parse(t, `{"keyboard": {"enabled": false, "layout": "us,de"}, "mouse": {"enabled": false, "sensitivity": -50}}`)
	if got := GreeterLua(profiles, inputSchema, off, nil); len(got) != len(none) {
		t.Errorf("every part off: nothing set:\n%s", strings.Join(got, "\n"))
	}
	on := parse(t, `{"keyboard": {"enabled": true, "layout": "us,de"}, "mouse": {"enabled": true, "sensitivity": -50}, "touchpad": {"enabled": false, "naturalScroll": true}}`)
	lines := GreeterLua(profiles, inputSchema, on, nil)
	config := lines[len(lines)-1]
	for _, want := range []string{"hl.config(", `kb_layout = "us,de"`, "sensitivity = -0.5"} {
		if !strings.Contains(config, want) {
			t.Errorf("no %q in %s", want, config)
		}
	}
	if strings.Contains(config, "touchpad") {
		t.Errorf("its part is off: %s", config)
	}
	runLua(t, stub, strings.Join(lines, "\n"))
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
