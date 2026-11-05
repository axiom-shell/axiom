package share

import (
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/schema"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"github.com/axiom-shell/axiom/backend/internal/tree"
)

func v2(t *testing.T) *schema.Schema {
	t.Helper()
	data, err := tree.BuildSchema(testkit.RepoRoot())
	if err != nil {
		t.Fatal(err)
	}
	root, err := jsonx.Unmarshal(data)
	if err != nil {
		t.Fatal(err)
	}
	return schema.New(root)
}

func parse(t *testing.T, text string) *jsonx.Object {
	t.Helper()
	v, err := jsonx.Unmarshal([]byte(text))
	if err != nil {
		t.Fatal(err)
	}
	return v.(*jsonx.Object)
}

func filled(t *testing.T, s *schema.Schema, text string) *jsonx.Object {
	t.Helper()
	v, _ := config.ApplyDefaults(s, parse(t, text), true, s.Root())
	return v.(*jsonx.Object)
}

// A format-2 export names monitors by place (a ScreenTarget's names), and
// applies onto another PC's monitors in those places: an item naming only
// places it doesn't have is turned off (bars) or left out (desktop
// layouts), by its x-monitorRef.
func TestScreenTargetsByPlace(t *testing.T) {
	t.Parallel()
	s := v2(t)
	mine := filled(t, s, `{"format": 2, "version": 76,
		"Bars": {"items": [
			{"id": "main", "screen": {"mode": "primary"}},
			{"id": "side", "location": "left", "screen": {"mode": "named", "names": ["DP-2"]}}
		]},
		"Desktop": {"items": [
			{"id": "primary", "screen": {"mode": "primary"}},
			{"id": "dp-2", "screen": {"mode": "named", "names": ["DP-2"]}}
		]}}`)
	exported := Pick(s, mine, nil, Monitors{"DP-1", "DP-2"})
	bars := exported.Value("Bars").(*jsonx.Object).Value("items").(*jsonx.Array)
	if got := string(jsonx.MarshalCompact(bars.Items[1].(*jsonx.Object).Value("screen"))); got != `{"mode":"named","names":["#2"]}` {
		t.Errorf("side bar's screen: %s", got)
	}

	// One monitor here: place 2 is missing
	theirs := filled(t, s, `{"format": 2, "version": 76}`)
	applied := Apply(s, theirs, exported, nil, Monitors{"HDMI-A-1"}).(*jsonx.Object)
	gotBars := applied.Value("Bars").(*jsonx.Object).Value("items").(*jsonx.Array)
	if gotBars.Len() != 2 {
		t.Fatalf("bars: %s", jsonx.MarshalCompact(gotBars))
	}
	side := gotBars.Items[1].(*jsonx.Object)
	if side.Value("enabled") != false {
		t.Errorf("a bar on a monitor this PC hasn't is on: %s", jsonx.MarshalCompact(side))
	}
	desktop := applied.Value("Desktop").(*jsonx.Object).Value("items").(*jsonx.Array)
	if desktop.Len() != 1 || desktop.Items[0].(*jsonx.Object).Value("id") != "primary" {
		t.Errorf("desktop layouts: %s", jsonx.MarshalCompact(desktop))
	}

	// Two monitors here: place 2 is this PC's second
	applied = Apply(s, theirs, exported, nil, Monitors{"eDP-1", "HDMI-A-1"}).(*jsonx.Object)
	side = applied.Value("Bars").(*jsonx.Object).Value("items").(*jsonx.Array).Items[1].(*jsonx.Object)
	if got := string(jsonx.MarshalCompact(side.Value("screen"))); got != `{"mode":"named","names":["HDMI-A-1"]}` || side.Value("enabled") != true {
		t.Errorf("side bar: %s", jsonx.MarshalCompact(side))
	}
}

// Items match by id: the example's look replaces the user's item of the
// same id, whose machine settings (the monitors it names) stay.
func TestItemsMatchByID(t *testing.T) {
	t.Parallel()
	s := v2(t)
	theirs := filled(t, s, `{"format": 2, "version": 76,
		"Dock": {"items": [{"id": "main", "screen": {"mode": "named", "names": ["DP-1"]}, "edge": "left"}]}}`)
	example := parse(t, `{"Dock": {"items": [{"id": "main", "edge": "bottom", "screen": {"mode": "inherit", "names": []}}]}}`)
	applied := Apply(s, theirs, example, nil, Monitors{"DP-1"}).(*jsonx.Object)
	dock := applied.Value("Dock").(*jsonx.Object).Value("items").(*jsonx.Array).Items[0].(*jsonx.Object)
	if dock.Value("edge") != "bottom" {
		t.Errorf("the look wasn't taken: %s", jsonx.MarshalCompact(dock))
	}
	if got := string(jsonx.MarshalCompact(dock.Value("screen"))); got != `{"mode":"inherit","names":["DP-1"]}` {
		t.Errorf("screen: %s", got)
	}
}

// A format-1 file older than a moved key's version keeps the user's value
// of it (at its format-2 path) when it doesn't hold it, and takes its own
// when it does.
func TestKeepMovedKeysV2(t *testing.T) {
	t.Parallel()
	cfg := parse(t, `{"WindowLook": {"shape": {"enabled": false, "rounding": 8}}, "Idle": {"dim": {"timeout": 150000}}}`)
	held := parse(t, `{"Idle": {"dim": {"timeout": 150000}}}`)
	current := parse(t, `{"WindowLook": {"shape": {"enabled": true, "rounding": 12}}, "Idle": {"dim": {"timeout": 60000}}}`)
	got := string(jsonx.MarshalCompact(KeepMovedKeys(cfg, held, current, 57.0)))
	want := `{"WindowLook":{"shape":{"enabled":true,"rounding":12}},"Idle":{"dim":{"timeout":150000}}}`
	if got != want {
		t.Errorf("got  %s\nwant %s", got, want)
	}
	if got := string(jsonx.MarshalCompact(KeepMovedKeys(cfg, held, current, 75.0))); got != string(jsonx.MarshalCompact(cfg)) {
		t.Errorf("a version-75 file kept the user's: %s", got)
	}
	// niri's hot corner (v71) is a HotCorners item since v82: the user's
	// corners stay
	corners := parse(t, `{"HotCorners": {"items": [{"id": "niri-corner", "corner": "topLeft"}]}}`)
	if got := string(jsonx.MarshalCompact(KeepMovedKeys(parse(t, `{"HotCorners": {"items": []}}`), parse(t, `{}`), corners, 70.0))); got != string(jsonx.MarshalCompact(corners)) {
		t.Errorf("a version-70 file dropped the user's hot corners: %s", got)
	}
}

// Every moved key is a setting of the schema, so a key a format-2 step
// renames or removes is kept at its new place, not silently lost.
func TestMovedKeysAreSettings(t *testing.T) {
	t.Parallel()
	s := v2(t)
	for _, moved := range movedKeys {
		for _, dotted := range moved.paths {
			node := s.Root()
			for _, key := range strings.Split(dotted, ".") {
				node = schema.Get(schema.Get(s.Resolve(node), "properties"), key)
			}
			if node == nil {
				t.Errorf("v%v's %s isn't in the schema", moved.version, dotted)
			}
		}
	}
}
