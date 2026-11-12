package yamlsrc

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"testing/fstest"

	"github.com/axiom-shell/axiom/backend/internal/compositor/actions"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// The repo's own source assembles: index, sections, shared definitions and
// every type folder.
func TestRepoSchemaAssembles(t *testing.T) {
	t.Parallel()
	root, err := Assemble(os.DirFS(filepath.Join(testkit.RepoRoot(), "qml")))
	if err != nil {
		t.Fatal(err)
	}
	defs := root.Value("definitions").(*jsonx.Object)
	for _, name := range []string{"BarWidget", "WeatherWidget", "WeatherOverlayModule", "SettingsOverlayView"} {
		if !defs.Has(name) {
			t.Errorf("no definition %s", name)
		}
	}
	if root.Has("kinds") {
		t.Error("kinds leaked into the schema")
	}
}

// Each kind's type folders are definitions <Type><suffix>; lowercase
// folders and folders without schema.yaml aren't types.
func TestTypeFolders(t *testing.T) {
	t.Parallel()
	fsys := fstest.MapFS{
		IndexFile:                              {Data: []byte("type: object\nproperties: {}\nsections: [S]\nkinds:\n  W: {root: ui/widgets, suffix: Widget}\n")},
		SectionsDir + "/S.yaml":                {Data: []byte("type: object\n")},
		AnnotationsFile:                        {Data: []byte("x-known: \"\"\nx-order: \"\"\n")},
		DefinitionsDir + "/common/Shared.yaml": {Data: []byte("type: object\n")},
		"ui/widgets/Clock/schema.yaml":         {Data: []byte("type: object\n")},
		"ui/widgets/Clock/Clock.qml":           {Data: []byte("")},
		"ui/widgets/Popout/Popout.qml":         {Data: []byte("")},
		"ui/widgets/base/schema.yaml":          {Data: []byte("type: object\n")},
	}
	root, err := Assemble(fsys)
	if err != nil {
		t.Fatal(err)
	}
	got := root.Value("definitions").(*jsonx.Object).Keys()
	if strings.Join(got, ",") != "Shared,ClockWidget" {
		t.Errorf("definitions = %v", got)
	}

	fsys[IndexFile] = &fstest.MapFile{Data: []byte("type: object\nproperties: {}\nsections: [S]\ndefinitions: [Shared]\nkinds: {W: {root: ui/widgets}}\n")}
	_, err = Assemble(fsys)
	for _, want := range []string{"definitions are found, not listed", "a kind is"} {
		if err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("missing %q in %v", want, err)
		}
	}
}

func TestStrictRefusals(t *testing.T) {
	t.Parallel()
	cases := map[string]string{
		"a: &x 1\nb: *x\n":      "anchors",
		"a: {<<: {b: 1}}\n":     "merge keys",
		"a: !custom 1\n":        "values aren't allowed",
		"a: !!binary aGk=\n":    "values aren't allowed",
		"a: 2001-12-14\n":       "timestamp",
		"a: on\n":               "YAML 1.1",
		"a: yes\n":              "YAML 1.1",
		"off: 1\n":              "quote the key",
		"a:\n":                  "missing value",
		"a: ~\n":                "missing value",
		"a: True\n":             "true or false",
		"a: 0x1F\n":             "decimal",
		"a: 1_000\n":            "decimal",
		"a: .inf\n":             "decimal",
		"a: .nan\n":             "decimal",
		"a: 9007199254740993\n": "too large",
		"a: 1\na: 2\n":          "duplicate",
		"1: a\n":                "must be a string",
		"a: 1\n---\nb: 2\n":     "more than one",
		"":                      "empty",
	}
	for in, want := range cases {
		_, err := Parse("t.yaml", []byte(in))
		if err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("Parse(%q) = %v, want an error about %q", in, err, want)
		}
	}
}

func TestStrictAccepts(t *testing.T) {
	t.Parallel()
	in := "a: \"on\"\nb: [1, 2.5, -0.000001, 1e+21]\nc: null\nd: true\ne: |\n  two\n  lines\n\"off\": x\n"
	v, err := Parse("t.yaml", []byte(in))
	if err != nil {
		t.Fatal(err)
	}
	want := `{"a":"on","b":[1,2.5,-0.000001,1e+21],"c":null,"d":true,"e":"two\nlines\n","off":"x"}`
	if got := string(jsonx.MarshalCompact(v)); got != want {
		t.Errorf("got %s", got)
	}
}

func TestCheckRefusesTyposAndBadRefs(t *testing.T) {
	t.Parallel()
	fsys := fstest.MapFS{
		IndexFile:               {Data: []byte("type: object\nproperties: {}\nsections: [A]\n")},
		AnnotationsFile:         {Data: []byte("x-known: \"\"\n")},
		SectionsDir + "/A.yaml": {Data: []byte("type: object\ndefualt: {}\nx-unknwon: 1\nx-known: 1\nproperties:\n  b: {$ref: \"#/definitions/Nope\"}\n  c: {type: strin}\n  d: {type: string, pattern: \"(?<=a)b\"}\n")},
		SectionsDir + "/B.yaml": {Data: []byte("type: object\n")},
	}
	_, err := Assemble(fsys)
	if err == nil {
		t.Fatal("accepted")
	}
	for _, want := range []string{`unknown keyword "defualt"`, "unknown annotation x-unknwon", `names no definition`, "type strin", "doesn't compile", "B.yaml: not listed", "sections/A.yaml:2:1"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("missing %q in:\n%v", want, err)
		}
	}
}

// A list's items may require only fields with a default, or `id` (a new
// item gets one free in its list): anything else makes the settings
// list's + add an item the config refuses.
func TestCheckRefusesRequiredFieldsWithoutDefaults(t *testing.T) {
	t.Parallel()
	section := `type: object
properties:
  bad:
    type: array
    default: []
    items: {$ref: "#/definitions/Item"}
  good:
    type: array
    default: []
    items:
      type: object
      required: [id, kind]
      properties:
        id: {type: string}
        kind: {type: string, default: a}
`
	fsys := fstest.MapFS{
		IndexFile:                     {Data: []byte("type: object\nproperties: {}\nsections: [A]\n")},
		AnnotationsFile:               {Data: []byte("x-order: \"\"\n")},
		SectionsDir + "/A.yaml":       {Data: []byte(section)},
		DefinitionsDir + "/Item.yaml": {Data: []byte("type: object\nrequired: [id, name]\nproperties:\n  id: {type: string}\n  name: {type: string}\n")},
	}
	_, err := Assemble(fsys)
	if err == nil {
		t.Fatal("accepted")
	}
	if !strings.Contains(err.Error(), `bad: the items require "name"`) {
		t.Errorf("missing the refusal of bad.name in:\n%v", err)
	}
	if strings.Contains(err.Error(), "good") || strings.Contains(err.Error(), `"id"`) {
		t.Errorf("refused a defaulted field or id:\n%v", err)
	}
}

// A type's schema.yaml expands into its kind's base: its label, settings,
// parts and annotations, the kind's oneOf generated.
func TestKindExpansion(t *testing.T) {
	t.Parallel()
	fsys := fstest.MapFS{
		IndexFile:                   {Data: []byte("type: object\nproperties: {}\nsections: [Clock]\nkinds:\n  Widget: {root: w, suffix: W, base: WBase}\n")},
		SectionsDir + "/Clock.yaml": {Data: []byte("type: object\n")},
		AnnotationsFile:             {Data: []byte("x-icon: \"\"\nx-hosts: \"\"\nx-link: \"\"\nx-order: \"\"\nx-libraryGroup: \"\"\n")},
		DefinitionsDir + "/WBase.yaml": {Data: []byte(`type: object
x-hosts: [overlay]
x-settingsAt: /properties/properties/properties
x-parts:
  popout:
    own:
      showPopout: {type: boolean, default: true, title: Popout}
properties:
  id: {type: string}
  properties:
    type: object
    properties: {}
`)},
		"w/Clock/schema.yaml": {Data: []byte(`label: Clock
icon: schedule
group: Time
hosts: [lockscreen]
popout: {variant: own, showPopout: {description: Open the calendar.}}
settings:
  seconds: {type: boolean, default: false}
`)},
	}
	root, err := Assemble(fsys)
	if err != nil {
		t.Fatal(err)
	}
	defs := root.Value("definitions").(*jsonx.Object)
	got := string(jsonx.MarshalCompact(defs))
	want := `{"ClockW":{"type":"object","x-hosts":["overlay","lockscreen"],"properties":{"id":{"type":"string"},` +
		`"properties":{"type":"object","properties":{"seconds":{"type":"boolean","default":false},` +
		`"showPopout":{"type":"boolean","default":true,"title":"Popout","description":"Open the calendar."}},"x-order":["seconds","showPopout"]},` +
		`"type":{"const":"Clock","description":"Clock"}},"x-icon":"schedule","x-libraryGroup":"Time","x-link":{"setting":"Clock"},"x-order":["id","properties","type"]},` +
		`"Widget":{"type":"object","required":["type"],"oneOf":[{"$ref":"#/definitions/ClockW"}]}}`
	if got != want {
		t.Errorf("got  %s\nwant %s", got, want)
	}
}

// A part's override reaching into a setting that $refs a definition
// inlines that definition, so a type narrows one of its fields.
func TestPartOverrideInlinesRef(t *testing.T) {
	t.Parallel()
	fsys := fstest.MapFS{
		IndexFile:                        {Data: []byte("type: object\nproperties: {}\nsections: [S]\nkinds:\n  Widget: {root: w, suffix: W, base: WBase}\n")},
		SectionsDir + "/S.yaml":          {Data: []byte("type: object\n")},
		AnnotationsFile:                  {Data: []byte("x-order: \"\"\nx-inline: \"\"\n")},
		DefinitionsDir + "/Display.yaml": {Data: []byte("type: object\nx-inline: true\nproperties:\n  style: {type: string, enum: [label, ring, ticker], default: label}\n")},
		DefinitionsDir + "/WBase.yaml": {Data: []byte(`type: object
x-settingsAt: /properties/properties/properties
x-parts:
  display:
    value:
      display: {$ref: '#/definitions/Display', title: Display}
properties:
  properties:
    type: object
    properties: {}
`)},
		"w/Battery/schema.yaml": {Data: []byte("label: Battery\ndisplay: {variant: value, style: {enum: [label, ring], default: ring}}\n")},
		"w/Window/schema.yaml":  {Data: []byte("label: Window\ndisplay: value\n")},
	}
	root, err := Assemble(fsys)
	if err != nil {
		t.Fatal(err)
	}
	defs := root.Value("definitions").(*jsonx.Object)
	setting := func(name string) string {
		return string(jsonx.MarshalCompact(defs.Value(name).(*jsonx.Object).Value("properties").(*jsonx.Object).Value("properties").(*jsonx.Object).Value("properties").(*jsonx.Object).Value("display")))
	}
	if got, want := setting("BatteryW"), `{"type":"object","properties":{"style":{"type":"string","enum":["label","ring"],"default":"ring"}},"title":"Display"}`; got != want {
		t.Errorf("Battery's display = %s, want %s", got, want)
	}
	// Without an override it's inlined later, as any x-inline definition
	if got, want := setting("WindowW"), `{"type":"object","properties":{"style":{"type":"string","enum":["label","ring","ticker"],"default":"label"}},"title":"Display"}`; got != want {
		t.Errorf("Window's display = %s, want %s", got, want)
	}
}

// x-inherit on a $ref makes the definition's inheriting copy: every
// setting null by default, naming where its value comes from.
func TestInherit(t *testing.T) {
	t.Parallel()
	fsys := fstest.MapFS{
		IndexFile:       {Data: []byte("type: object\nproperties: {}\nsections: [Bars]\n")},
		AnnotationsFile: {Data: []byte("x-inherit: \"\"\nx-order: \"\"\n")},
		SectionsDir + "/Bars.yaml": {Data: []byte(`type: object
properties:
  style: {$ref: '#/definitions/Style'}
  items:
    type: array
    items:
      type: object
      properties:
        style: {$ref: '#/definitions/Style', x-inherit: Bars.style}
`)},
		DefinitionsDir + "/Style.yaml": {Data: []byte("type: object\nproperties:\n  radius: {type: integer, default: 6}\n  shadow:\n    type: object\n    properties:\n      size: {type: integer, default: 4}\n")},
	}
	root, err := Assemble(fsys)
	if err != nil {
		t.Fatal(err)
	}
	defs := root.Value("definitions").(*jsonx.Object)
	got := string(jsonx.MarshalCompact(defs.Value("StyleInherited")))
	want := `{"type":"object","properties":{"radius":{"type":"integer","default":null,"x-inherit":"Bars.style.radius"},` +
		`"shadow":{"type":"object","properties":{"size":{"type":"integer","default":null,"x-inherit":"Bars.style.shadow.size"}}}},"x-order":["radius","shadow"]}`
	if got != want {
		t.Errorf("got  %s\nwant %s", got, want)
	}
	item := root.Value("properties").(*jsonx.Object).Value("Bars").(*jsonx.Object).Value("properties").(*jsonx.Object).Value("items").(*jsonx.Object).Value("items").(*jsonx.Object)
	if ref := item.Value("properties").(*jsonx.Object).Value("style"); string(jsonx.MarshalCompact(ref)) != `{"$ref":"#/definitions/StyleInherited"}` {
		t.Errorf("ref = %s", jsonx.MarshalCompact(ref))
	}
}

// A $ref with x-properties is the definition inlined, its properties
// adjusted: added, replaced, removed with null.
func TestExtension(t *testing.T) {
	t.Parallel()
	fsys := fstest.MapFS{
		IndexFile:       {Data: []byte("type: object\nproperties: {}\nsections: [S]\n")},
		AnnotationsFile: {Data: []byte("x-order: \"\"\n")},
		SectionsDir + "/S.yaml": {Data: []byte(`type: object
properties:
  screen: {$ref: '#/definitions/Screen'}
  trigger: {$ref: '#/definitions/Trigger', title: Edge, x-properties: {length: null}}
`)},
		DefinitionsDir + "/Trigger.yaml": {Data: []byte("type: object\nrequired: [size, length]\nproperties:\n  size: {type: integer}\n  length: {type: integer}\n")},
		DefinitionsDir + "/Layout.yaml":  {Data: []byte("type: object\nproperties:\n  modules: {type: array}\n")},
		DefinitionsDir + "/Screen.yaml":  {Data: []byte("$ref: '#/definitions/Layout'\nx-properties:\n  backdrop: {type: string}\n")},
	}
	root, err := Assemble(fsys)
	if err != nil {
		t.Fatal(err)
	}
	props := root.Value("properties").(*jsonx.Object).Value("S").(*jsonx.Object).Value("properties").(*jsonx.Object)
	if got, want := string(jsonx.MarshalCompact(props.Value("trigger"))), `{"type":"object","required":["size"],"properties":{"size":{"type":"integer"}},"title":"Edge"}`; got != want {
		t.Errorf("trigger = %s, want %s", got, want)
	}
	screen := root.Value("definitions").(*jsonx.Object).Value("Screen")
	if got, want := string(jsonx.MarshalCompact(screen)), `{"type":"object","properties":{"modules":{"type":"array"},"backdrop":{"type":"string"}},"x-order":["modules","backdrop"]}`; got != want {
		t.Errorf("Screen = %s, want %s", got, want)
	}
}

// x-order is written from the properties' order, unless the author wrote
// one (annotations.yaml: the keys shown first).
func TestOrderKeysKeepsAnAuthorsOrder(t *testing.T) {
	t.Parallel()
	fsys := fstest.MapFS{
		IndexFile:                  {Data: []byte("type: object\nproperties: {}\nsections: [A, B]\n")},
		AnnotationsFile:            {Data: []byte("x-order: \"\"\n")},
		SectionsDir + "/A.yaml":    {Data: []byte("type: object\nproperties:\n  first: {type: integer}\n  second: {type: integer}\n")},
		DefinitionsDir + "/D.yaml": {Data: []byte("type: object\n")},
		SectionsDir + "/B.yaml":    {Data: []byte("type: object\nx-order: [second]\nproperties:\n  first: {type: integer}\n  second: {type: integer}\n")},
	}
	root, err := Assemble(fsys)
	if err != nil {
		t.Fatal(err)
	}
	props := root.Value("properties").(*jsonx.Object)
	for section, want := range map[string]string{"A": `["first","second"]`, "B": `["second"]`} {
		if got := string(jsonx.MarshalCompact(props.Value(section).(*jsonx.Object).Value("x-order"))); got != want {
			t.Errorf("%s x-order = %s, want %s", section, got, want)
		}
	}
}

// A type's `order:` sets the final order of its settings, interleaving its
// own with its parts'; an unknown, repeated or missing key fails the build.
func TestTypeOrder(t *testing.T) {
	t.Parallel()
	build := func(order string) (*jsonx.Object, error) {
		fsys := fstest.MapFS{
			IndexFile:                   {Data: []byte("type: object\nproperties: {}\nsections: [Clock]\nkinds:\n  Widget: {root: w, suffix: W, base: WBase}\n")},
			SectionsDir + "/Clock.yaml": {Data: []byte("type: object\n")},
			AnnotationsFile:             {Data: []byte("x-order: \"\"\nx-link: \"\"\n")},
			DefinitionsDir + "/WBase.yaml": {Data: []byte(`type: object
x-settingsAt: /properties/properties/properties
x-parts:
  popout:
    own:
      showPopout: {type: boolean, default: true}
properties:
  properties:
    type: object
    properties: {}
`)},
			"w/Clock/schema.yaml": {Data: []byte("label: Clock\npopout: own\n" + order + "settings:\n  seconds: {type: boolean, default: false}\n  format: {type: string, default: ''}\n")},
		}
		root, err := Assemble(fsys)
		if err != nil {
			return nil, err
		}
		return root.Value("definitions").(*jsonx.Object).Value("ClockW").(*jsonx.Object), nil
	}
	def, err := build("order: [format, showPopout, seconds]\n")
	if err != nil {
		t.Fatal(err)
	}
	inner := def.Value("properties").(*jsonx.Object).Value("properties").(*jsonx.Object)
	if got, want := string(jsonx.MarshalCompact(inner.Value("x-order"))), `["format","showPopout","seconds"]`; got != want {
		t.Errorf("x-order = %s, want %s", got, want)
	}
	if def.Has("x-order") && strings.Contains(string(jsonx.MarshalCompact(def.Value("x-order"))), "format") {
		t.Error("order leaked into the type's own x-order")
	}
	for order, want := range map[string]string{
		"order: [format, nope, showPopout, seconds]\n":   "nope",
		"order: [format, seconds, format, showPopout]\n": "twice",
		"order: [format, seconds]\n":                     "leaves out showPopout",
		"order: [type, format, seconds, showPopout]\n":   "type",
	} {
		if _, err := build(order); err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("order %q: error %v, want one naming %q", order, err, want)
		}
	}
}

// x-axiomActions fills a hot corner's action from the bind actions table:
// its ipcActions less those left out, then exec, with the Keybinds page's
// labels and the table's icons and sections, and where its argument and
// call show; the mark goes.
func TestAxiomActions(t *testing.T) {
	t.Parallel()
	root, err := Assemble(os.DirFS(filepath.Join(testkit.RepoRoot(), "qml")))
	if err != nil {
		t.Fatal(err)
	}
	tables, err := actions.Tables()
	if err != nil {
		t.Fatal(err)
	}
	ipc := tables.Value("ipcActions").(*jsonx.Object)
	calls := tables.Value("calls").(*jsonx.Object)
	icons := tables.Value("icons").(*jsonx.Object)
	binds := pointer(root, "/definitions/Keybind/properties/action").Value("x-enumLabels").(*jsonx.Object)
	item := pointer(root, "/properties/HotCorners/properties/items/items/properties")
	action := item.Value("action").(*jsonx.Object)
	if action.Has("x-axiomActions") {
		t.Error("the mark stayed in the built schema")
	}
	var enum, argument, call []string
	for _, v := range action.Value("enum").(*jsonx.Array).Items {
		enum = append(enum, v.(string))
	}
	for _, name := range append(ipc.Keys(), "exec") {
		if !slices.Contains(enum, name) {
			continue
		}
		if name == "exec" || strings.Contains(ipc.Value(name).(*jsonx.Array).Items[0].(string), "{0}") {
			argument = append(argument, name)
		}
		if calls.Has(name) {
			call = append(call, name)
		}
		if got, want := pointer(action, "/x-enumLabels").Value(name), binds.Value(name); got != want {
			t.Errorf("%s's label = %v, want the Keybinds page's %v", name, got, want)
		}
		if name == "exec" {
			continue
		}
		if got, want := pointer(action, "/x-enumIcons").Value(name), icons.Value(name); got != want {
			t.Errorf("%s's icon = %v, want the table's %v", name, got, want)
		}
		if got, want := pointer(action, "/x-enumGroups").Value(name), ipc.Value(name).(*jsonx.Array).Items[2]; got != want {
			t.Errorf("%s's group = %v, want the table's section %v", name, got, want)
		}
	}
	left := []string{"clearNotifications", "moveWindowStep", "moveWindowStepSilent", "moveWindowNth", "moveWindowNthSilent", "stopwatchReset", "timerReset", "pomodoroStop", "reboot", "poweroff"}
	if got, want := len(enum), ipc.Len()-len(left)+1; got != want || enum[len(enum)-1] != "exec" || slices.ContainsFunc(left, func(s string) bool { return slices.Contains(enum, s) }) {
		t.Errorf("enum = %v: want the %d ipcActions but %v, then exec", enum, want-1, left)
	}
	for key, want := range map[string][]string{"argument": argument, "call": call} {
		got := string(jsonx.MarshalCompact(pointer(item, "/"+key+"/x-showIf")))
		if w := string(jsonx.MarshalCompact(jsonx.Obj("action", jsonx.Arr(anys(want)...)))); got != w {
			t.Errorf("%s x-showIf = %s, want %s", key, got, w)
		}
	}

	// Leaving out what isn't an IPC action, or an action the Keybinds page
	// has no label for, is refused
	fsys := fstest.MapFS{
		IndexFile:                        {Data: []byte("type: object\nproperties: {}\nsections: [S]\n")},
		AnnotationsFile:                  {Data: []byte("x-axiomActions: \"\"\nx-order: \"\"\nx-enumLabels: \"\"\nx-showIf: \"\"\n")},
		SectionsDir + "/S.yaml":          {Data: []byte("type: object\nproperties:\n  action: {type: string, x-axiomActions: {except: [closeWindow]}}\n")},
		DefinitionsDir + "/Keybind.yaml": {Data: []byte("type: object\nproperties:\n  action: {type: string, x-enumLabels: {launcher: App launcher}}\n")},
	}
	_, err = Assemble(fsys)
	for _, want := range []string{"except names closeWindow", "no label for overlay"} {
		if err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("missing %q in %v", want, err)
		}
	}
}

func anys(s []string) []any {
	out := make([]any, len(s))
	for i, v := range s {
		out[i] = v
	}
	return out
}
