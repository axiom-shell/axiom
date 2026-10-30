package convert_test

import (
	"fmt"
	"sort"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/migrate/convert"
	"github.com/axiom-shell/axiom/backend/internal/migrate/legacy"
	"github.com/axiom-shell/axiom/backend/internal/migrate/steps"
	"github.com/axiom-shell/axiom/backend/internal/schema"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"github.com/axiom-shell/axiom/backend/internal/tree"
)

func v2Schema(t *testing.T) *schema.Schema {
	t.Helper()
	data, err := tree.BuildSchema(testkit.RepoRoot())
	if err != nil {
		t.Fatal(err)
	}
	parsed, err := jsonx.Unmarshal(data)
	if err != nil {
		t.Fatal(err)
	}
	return schema.New(parsed)
}

func legacyDefaults(t *testing.T) *jsonx.Object {
	t.Helper()
	s := schema.New(legacy.Schema())
	filled, _ := config.ApplyDefaults(s, jsonx.NewObject(), true, s.Root())
	return filled.(*jsonx.Object)
}

// diffs lists the paths where a and b differ.
func diffs(a, b any, path string, out *[]string) {
	ao, aok := a.(*jsonx.Object)
	bo, bok := b.(*jsonx.Object)
	if aok && bok {
		keys := map[string]bool{}
		for _, k := range ao.Keys() {
			keys[k] = true
		}
		for _, k := range bo.Keys() {
			keys[k] = true
		}
		sorted := make([]string, 0, len(keys))
		for k := range keys {
			sorted = append(sorted, k)
		}
		sort.Strings(sorted)
		for _, k := range sorted {
			av, ah := ao.Get(k)
			bv, bh := bo.Get(k)
			switch {
			case !ah:
				*out = append(*out, fmt.Sprintf("%s.%s: only in the second (%s)", path, k, short(bv)))
			case !bh:
				*out = append(*out, fmt.Sprintf("%s.%s: only in the first (%s)", path, k, short(av)))
			default:
				diffs(av, bv, path+"."+k, out)
			}
		}
		return
	}
	aa, aok := a.(*jsonx.Array)
	ba, bok := b.(*jsonx.Array)
	if aok && bok && aa.Len() == ba.Len() {
		for i := range aa.Items {
			diffs(aa.Items[i], ba.Items[i], fmt.Sprintf("%s[%d]", path, i), out)
		}
		return
	}
	if !jsonx.Equal(a, b) {
		*out = append(*out, fmt.Sprintf("%s: %s vs %s", path, short(a), short(b)))
	}
}

func short(v any) string {
	s := string(jsonx.MarshalCompact(v))
	if len(s) > 120 {
		s = s[:117] + "..."
	}
	return s
}

// toCurrent converts a format-1 config and runs the format-2 steps on it,
// as a load does.
func toCurrent(cfg *jsonx.Object) *jsonx.Object {
	converted := convert.ToV2(cfg).Config
	steps.Migrate(converted)
	return converted
}

// The format-1 defaults, converted and migrated, are the format-2
// defaults: the schema's shape and the converter agree on every key. A
// section format 1 never had (Tailscale, from v79) is filled from its
// defaults at load, like any missing section, and so is a key added to a
// format-1 section since (addedSinceV1), or to a bar widget
// (widgetKeysAddedSinceV1).
func TestDefaultsConvertToV2Defaults(t *testing.T) {
	t.Parallel()
	s := v2Schema(t)
	converted := toCurrent(legacyDefaults(t))
	legacyRoot, _ := legacy.Schema().Value("properties").(*jsonx.Object)
	if errs := config.ValidationErrors(s, converted, s.Root()); len(errs) > 0 {
		t.Errorf("the converted defaults don't validate:\n%v", errs)
	}
	pruned := jsonx.Clone(converted)
	if removed := config.Prune(s, pruned, s.Root()); len(removed) > 0 {
		t.Errorf("pruning the converted defaults removes %v", removed)
	}
	defaults, _ := config.ApplyDefaults(s, jsonx.NewObject(), true, s.Root())
	for _, k := range defaults.(*jsonx.Object).Keys() {
		if !converted.Has(k) && !legacyRoot.Has(k) {
			defaults.(*jsonx.Object).Delete(k)
		}
	}
	for _, path := range addedSinceV1 {
		parts := strings.Split(path, ".")
		parent, _ := defaults.(*jsonx.Object)
		for _, k := range parts[:len(parts)-1] {
			parent, _ = parent.Value(k).(*jsonx.Object)
		}
		parent.Delete(parts[len(parts)-1])
	}
	bars, _ := defaults.(*jsonx.Object).Value("Bars").(*jsonx.Object)
	items, _ := bars.Value("items").(*jsonx.Array)
	for _, bar := range items.Items {
		sections, _ := bar.(*jsonx.Object).Value("widgets").(*jsonx.Object)
		for _, side := range sections.Keys() {
			widgets, _ := sections.Value(side).(*jsonx.Array)
			for _, w := range widgets.Items {
				if props, ok := w.(*jsonx.Object).Value("properties").(*jsonx.Object); ok {
					for _, key := range widgetKeysAddedSinceV1 {
						props.Delete(key)
					}
				}
			}
		}
	}
	var out []string
	diffs(converted, defaults, "", &out)
	for _, d := range out {
		t.Error(d)
	}
}

// Keys added to a format-1 section after format 1 was frozen: no format-1
// config has them, so they come from their default at load
var addedSinceV1 = []string{"Compositor.sway.specialWorkspaces", "Compositor.niri.tabIndicator", "WorkspaceOverlay.compositorOverview", "WindowSwitcher.compositorSwitcher", "Overlay.moduleBorders", "Notifications.clickFocuses", "Notifications.motion", "Notifications.gap", "Notifications.dnd", "Notifications.apps"}

// Bar widget settings added since, the same way (a widget's display style)
var widgetKeysAddedSinceV1 = []string{"appearance"}

// Every frozen corpus config (each past schema version's defaults, the
// examples, old configs), as the legacy pipeline loads it, converts to a
// valid format-2 config that pruning leaves whole.
func TestCorpusConvertsValid(t *testing.T) {
	t.Parallel()
	s := v2Schema(t)
	old := schema.New(legacy.Schema())
	checked := 0
	for _, c := range testkit.Frozen(t, "load") {
		loaded, err := config.LoadLegacy(old, c.Input)
		// A config invalid at version 75 (blocked there) stays invalid
		if err != nil || len(loaded.Errors) > 0 || loaded.Config == nil {
			continue
		}
		converted := toCurrent(loaded.Config)
		filled, _ := config.ApplyDefaults(s, converted, true, s.Root())
		if errs := config.ValidationErrors(s, filled, s.Root()); len(errs) > 0 {
			t.Errorf("%s: %v", c.Name, errs)
		}
		if removed := config.Prune(s, jsonx.Clone(filled), s.Root()); len(removed) > 0 {
			t.Errorf("%s: pruning removes %v", c.Name, removed)
		}
		checked++
	}
	if checked < 50 {
		t.Fatalf("only %d corpus configs", checked)
	}
}

// Ids items already had survive the conversion; made ones never take one
// a later item owns, and a duplicate or invalid one is replaced.
func TestConvertKeepsIDs(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name      string
		providers string
		want      []string
	}{
		{"kept", `[{"id":"anthropic","name":"Anthropic"},{"id":"openai","name":"OpenAI"}]`, []string{"anthropic", "openai"}},
		{"made before an owner", `[{"name":"Anthropic"},{"id":"anthropic","name":"Mine"}]`, []string{"anthropic-2", "anthropic"}},
		{"duplicate", `[{"id":"a","name":"A"},{"id":"a","name":"B"}]`, []string{"a", "b"}},
		{"invalid", `[{"id":"-x","name":"Local"}]`, []string{"local"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			providers, err := jsonx.Unmarshal([]byte(c.providers))
			if err != nil {
				t.Fatal(err)
			}
			cfg := jsonx.Obj("Chat", jsonx.Obj("providers", providers))
			got := convert.ToV2(cfg).Config
			chat, _ := got.Value("Chat").(*jsonx.Object)
			list, _ := chat.Value("providers").(*jsonx.Array)
			var ids []string
			for _, it := range list.Items {
				id, _ := it.(*jsonx.Object).Value("id").(string)
				ids = append(ids, id)
			}
			if fmt.Sprint(ids) != fmt.Sprint(c.want) {
				t.Errorf("ids %v, want %v", ids, c.want)
			}
		})
	}
}

// Sections convert to their format-2 shape, each moved or grouped key
// where the first of its old keys was (key order is part of the output).
// section "" checks the whole config.
func TestConvertShapes(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name, section, in, want string
	}{
		{"the envelope first, sections in place", "",
			`{"$schema":"s","EdgeMenus":[],"Bars":[],"Weather":{},"version":75,"format":1}`,
			`{"$schema":"s","format":2,"version":76,"EdgeMenus":{"items":[]},"Bars":{"items":[]},"Weather":{},"Compositor":{}}`},
		{"a monitors setting renamed in place", "General",
			`{"General":{"monitors":"all","scale":1}}`,
			`{"screen":{"mode":"all"},"scale":1}`},
		{"a group first where its first key was, durations scaled", "Notifications",
			`{"Notifications":{"evenGaps":true,"timeout":5,"gapTop":1,"maxAgeDays":2}}`,
			`{"gaps":{"even":true,"top":1},"timeout":5000,"maxAge":172800000}`},
		{"a group where its earliest key was", "Notifications",
			`{"Notifications":{"enabled":true,"gapTop":1,"position":"top","evenGaps":true}}`,
			`{"enabled":true,"gaps":{"even":true,"top":1},"position":"top"}`},
		{"a renamed key in place", "Weather",
			`{"Weather":{"intervalMinutes":5,"location":"x"}}`,
			`{"interval":300000,"location":"x"}`},
		{"an empty edge left empty", "Launcher",
			`{"Launcher":{"edge":""}}`,
			`{"edge":"","providers":{"web":{},"clipboard":{}}}`},
		{"edges lowered, empty ones kept", "OSD",
			`{"OSD":{"osds":[{"edge":"Right","orientation":""}]}}`,
			`{"items":[{"edge":"right","orientation":"","screen":{"mode":"inherit","names":[]}}]}`},
		{"a fetched calendar's fields dropped, a local one's name kept", "Calendar",
			`{"Calendar":{"accounts":[{"kind":"local","calendars":[{"href":"a","name":"Mine","color":"#f00","enabled":true,"readOnly":false}]},{"kind":"caldav","calendars":[{"href":"b","name":"Work","color":"#0f0","enabled":false,"components":["VEVENT"]}]}]}}`,
			`{"items":[{"kind":"local","calendars":[{"href":"a","name":"Mine","color":"#f00","enabled":true}]},{"kind":"caldav","calendars":[{"href":"b","color":"#0f0","enabled":false}]}]}`},
		{"the cursor timeout in ms", "WindowBehaviour",
			`{"WindowBehaviour":{"cursorHideTimeout":3}}`,
			`{"cursorHideTimeout":3000}`},
		{"a greeter on every monitor is on the primary one", "Greeter",
			`{"Greeter":{"monitor":"*"}}`,
			`{"screen":{"mode":"primary","names":[]}}`},
		{"a greeter's named monitor", "Greeter",
			`{"Greeter":{"monitor":"DP-1"}}`,
			`{"screen":{"mode":"named","names":["DP-1"]}}`},
		{"edge menus: one screen, a layout, modules with and without properties", "EdgeMenus",
			`{"EdgeMenus":[{"monitor":"*","edge":"Left","fineGrid":true,"modules":[{"type":"CommandOutput","properties":{"interval":5}},{"type":"Clock"}],"openOnHover":true},{"monitor":"DP-1","edge":"Top"}]}`,
			`{"items":[{"screen":{"mode":"primary","names":[]},"edge":"left","layout":{"grid":{"fine":true},"modules":[{"id":"commandOutput","type":"CommandOutput","properties":{"interval":5000}},{"id":"clock","type":"Clock"}]},"open":{"onHover":true}},{"screen":{"mode":"named","names":["DP-1"]},"edge":"top"}]}`},
		{"a grid where its earliest key was", "Lockscreen",
			`{"Lockscreen":{"layout":{"columns":8,"background":"wallpaper","rows":4}}}`,
			`{"layout":{"grid":{"columns":8,"rows":4},"backdrop":{"source":"wallpaper"}}}`},
		{"custom animations' duration renamed, curves' not", "Compositor",
			`{"Hyprland":{"managed":{"curves":[{"durationMs":1}],"customAnimations":[{"name":"Fade In","durationMs":200}]}}}`,
			`{"hyprland":{"curves":[{"id":"curve","durationMs":1}],"customAnimations":[{"id":"fade-in","name":"Fade In","duration":200}]}}`},
		{"a custom page's layout where its grid or modules were", "Overlay",
			`{"Overlay":{"views":[{"fineGrid":true,"type":"Custom","name":"My Page","modules":[]},{"type":"Custom","modules":[],"name":"Q"},{"type":"Settings"}]}}`,
			`{"items":[{"id":"my-page","layout":{"grid":{"fine":true},"modules":[]},"type":"Custom","name":"My Page"},{"id":"q","type":"Custom","layout":{"modules":[]},"name":"Q"},{"id":"settings","type":"Settings"}]}`},
		{"monitor profiles get ids", "Monitors",
			`{"Monitors":{"profiles":[{"name":"Desk Setup"}]}}`,
			`{"items":[{"id":"desk-setup","name":"Desk Setup"}]}`},
		{"keybind presets and their binds get ids", "Keybinds",
			`{"Keybinds":{"presets":[{"name":"Vim","binds":[{"key":"SUPER + a"}]}]}}`,
			`{"presets":[{"id":"vim","name":"Vim","binds":[{"id":"super-a","key":"SUPER + a"}]}]}`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			in, err := jsonx.Unmarshal([]byte(c.in))
			if err != nil {
				t.Fatal(err)
			}
			var got any = convert.ToV2(in.(*jsonx.Object)).Config
			if c.section != "" {
				got = got.(*jsonx.Object).Value(c.section)
			}
			if s := string(jsonx.MarshalCompact(got)); s != c.want {
				t.Errorf("got  %s\nwant %s", s, c.want)
			}
		})
	}
}

// What a conversion did is listed for the log
func TestConvertNotesItsChanges(t *testing.T) {
	t.Parallel()
	got := convert.ToV2(jsonx.Obj("General", jsonx.NewObject())).Changes
	want := []string{"monitors settings became screen targets", "converted to config format 2 (version 76)"}
	if fmt.Sprint(got) != fmt.Sprint(want) {
		t.Errorf("changes %q, want %q", got, want)
	}
}
