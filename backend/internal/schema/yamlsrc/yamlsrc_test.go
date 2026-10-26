package yamlsrc

import (
	"os"
	"strings"
	"testing"
	"testing/fstest"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// The repo's own source assembles: index, sections, shared definitions and
// every type folder.
func TestRepoSchemaAssembles(t *testing.T) {
	t.Parallel()
	root, err := Assemble(os.DirFS(testkit.RepoRoot()))
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
