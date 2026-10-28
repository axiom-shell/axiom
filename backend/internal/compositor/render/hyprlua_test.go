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
// calls, not the user's Lua nor an older module's picker
func TestHyprFileMonitorCalls(t *testing.T) {
	t.Parallel()
	text := `function M.monitors()
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
