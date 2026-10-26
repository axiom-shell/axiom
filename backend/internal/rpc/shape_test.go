package rpc

import (
	"context"
	"encoding/json"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"
)

// render writes a shape compactly: {name:kind, omitted?:kind}, [elem],
// map[elem].
func render(s Shape) string {
	switch s.Kind {
	case "object":
		parts := make([]string, 0, len(s.Fields))
		for _, f := range s.Fields {
			opt := ""
			if f.OmitEmpty {
				opt = "?"
			}
			parts = append(parts, f.Name+opt+":"+render(f.Shape))
		}
		return "{" + strings.Join(parts, ",") + "}"
	case "array":
		return "[" + render(*s.Elem) + "]"
	case "map":
		return "map[" + render(*s.Elem) + "]"
	}
	return s.Kind
}

type shapeLeaf struct {
	A string `json:"a"`
}

type shapeInner struct {
	In  int `json:"in"`
	Dup string
}

type shapeOther struct {
	Dup  string
	Tie  int
	Deep string `json:"deep"`
}

type shapeTie struct {
	Tie bool
}

type shapeTagged struct {
	X string `json:"Name"`
}

type shapeUntagged struct {
	Name string
}

type shapeText int

func (shapeText) MarshalText() ([]byte, error) { return []byte("t"), nil }

type shapeOwn struct{}

func (shapeOwn) MarshalJSON() ([]byte, error) { return []byte("1"), nil }

type shapePtrOwn struct{}

func (*shapePtrOwn) MarshalJSON() ([]byte, error) { return []byte("1"), nil }

type shapeList struct {
	Next *shapeList `json:"next,omitempty"`
	V    int        `json:"v"`
}

type shapeName string

type shapeAll struct {
	Plain    string  `json:"plain"`
	Omit     int     `json:"omit,omitempty"`
	Zero     bool    `json:"zero,omitzero"`
	Untagged float64 // the Go name
	Skipped  string  `json:"-"`
	Quoted   int     `json:"quoted,string"`
	//lint:ignore U1000 an unexported field is not encoded
	unexport  string
	Ptr       *string               `json:"ptr"`
	Bytes     []byte                `json:"bytes"`
	Array     [2]uint8              `json:"array"`
	List      []shapeLeaf           `json:"list"`
	Map       map[string][]int      `json:"map"`
	Nested    shapeLeaf             `json:"nested"`
	Raw       json.RawMessage       `json:"raw"`
	Any       any                   `json:"any"`
	Time      time.Time             `json:"time"`
	Own       shapeOwn              `json:"own"`
	PtrOwn    shapePtrOwn           `json:"ptrOwn"`
	Text      shapeText             `json:"text"`
	TextMap   map[shapeText]string  `json:"textMap"`
	Named     shapeName             `json:"named"`
	Func      func()                `json:"-"`
	Recursive shapeList             `json:"recursive"`
	Anon      struct{ B bool }      `json:"anon"`
	Empty     struct{}              `json:"empty"`
	PtrMap    *map[string]shapeLeaf `json:"ptrMap"`
}

type shapeEmbeds struct {
	shapeInner               // inlined although unexported: its fields are exported
	shapeOther               // Dup ties with shapeInner's: neither is encoded
	shapeLeaf  `json:"leaf"` // a tag names it: a field, not inlined
	Own        string        `json:"own"`
}

// encoding/json writes nothing for a nil embedded pointer, but its
// fields are the struct's all the same
type shapeEmbedsPtr struct {
	*shapeLeaf
}

type shapeConflicts struct {
	shapeTie
	shapeOther        // Tie ties with shapeTie's at one depth: neither is encoded
	shapeTagged       // Name, tagged: wins over shapeUntagged's
	shapeUntagged     //
	Deep          int `json:"deep"` // shallower than shapeOther's deep
}

func TestShapeOf(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name string
		typ  reflect.Type
		want string
	}{
		{"nil", nil, "opaque"},
		{"string", reflect.TypeFor[string](), "string"},
		{"named string", reflect.TypeFor[shapeName](), "string"},
		{"number", reflect.TypeFor[uint16](), "number"},
		{"bool pointer", reflect.TypeFor[**bool](), "bool"},
		{"empty struct", reflect.TypeFor[struct{}](), "{}"},
		{"raw message", reflect.TypeFor[json.RawMessage](), "opaque"},
		{"any", reflect.TypeFor[any](), "opaque"},
		{"slice of any", reflect.TypeFor[[]any](), "[opaque]"},
		{"bytes", reflect.TypeFor[[]byte](), "string"},
		{"map", reflect.TypeFor[map[string]bool](), "map[bool]"},
		{"map by number", reflect.TypeFor[map[int]bool](), "map[bool]"},
		{"map by text", reflect.TypeFor[map[shapeText]bool](), "map[bool]"},
		{"map by struct", reflect.TypeFor[map[struct{}]bool](), "opaque"},
		{"recursive", reflect.TypeFor[shapeList](), "{next?:opaque,v:number}"},
		{"every field rule", reflect.TypeFor[shapeAll](), "{plain:string,omit?:number,zero?:bool,Untagged:number,quoted:string," +
			"ptr:string,bytes:string,array:[number],list:[{a:string}],map:map[[number]],nested:{a:string},raw:opaque,any:opaque," +
			"time:opaque,own:opaque,ptrOwn:opaque,text:string,textMap:map[string],named:string,recursive:{next?:opaque,v:number}," +
			"anon:{B:bool},empty:{},ptrMap:map[{a:string}]}"},
		{"embedded", reflect.TypeFor[shapeEmbeds](), "{in:number,Tie:number,deep:string,leaf:{a:string},own:string}"},
		{"embedded pointer", reflect.TypeFor[shapeEmbedsPtr](), "{a:string}"},
		{"conflicts", reflect.TypeFor[shapeConflicts](), "{Dup:string,Name:string,deep:number}"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got := ShapeOf(tc.typ)
			if r := render(got); r != tc.want {
				t.Errorf("ShapeOf = %s\nwant      %s", r, tc.want)
			}
			// An object's members are the keys encoding/json writes for
			// its zero value (the omitted ones aside, and a nil embedded
			// pointer's)
			if got.Kind == "object" && tc.name != "embedded pointer" {
				var want []string
				for _, f := range got.Fields {
					if !f.OmitEmpty {
						want = append(want, f.Name)
					}
				}
				data, err := json.Marshal(reflect.New(tc.typ).Interface())
				if err != nil {
					t.Fatal(err)
				}
				keys := topKeys(t, data)
				slices.Sort(want)
				slices.Sort(keys)
				if !slices.Equal(keys, want) {
					t.Errorf("encoding/json writes %v, the shape has %v", keys, want)
				}
			}
		})
	}
}

// topKeys are a JSON object's own keys.
func topKeys(t *testing.T, data []byte) []string {
	t.Helper()
	var obj map[string]json.RawMessage
	if err := json.Unmarshal(data, &obj); err != nil {
		t.Fatal(err)
	}
	keys := make([]string, 0, len(obj))
	for k := range obj {
		keys = append(keys, k)
	}
	return keys
}

func TestRegistryTypes(t *testing.T) {
	t.Parallel()
	reg := NewRegistry()
	Handle(reg, "echo", func(ctx context.Context, c *Conn, p echoParams) ([]echoParams, error) { return nil, nil })
	params, result, ok := reg.Types("echo")
	if !ok || params != reflect.TypeFor[echoParams]() || result != reflect.TypeFor[[]echoParams]() {
		t.Fatalf("Types(echo) = %v, %v, %v", params, result, ok)
	}
	if _, _, ok := reg.Types("missing"); ok {
		t.Error("Types(missing) found a method")
	}
}

func TestRegistryAndPushShapes(t *testing.T) {
	t.Parallel()
	reg := NewRegistry()
	Handle(reg, "b", func(ctx context.Context, c *Conn, p struct{}) (bool, error) { return false, nil })
	Handle(reg, "a", func(ctx context.Context, c *Conn, p echoParams) (string, error) { return "", nil })
	got := reg.Shapes()
	if len(got) != 2 || got[0].Method != "a" || got[1].Method != "b" {
		t.Fatalf("Shapes() = %+v", got)
	}
	if got[0].Params.Kind != "object" || got[0].Result.Kind != "string" || got[1].Result.Kind != "bool" {
		t.Errorf("Shapes() = %+v", got)
	}
	push := Push[echoParams]{Method: "x.state", Latest: true}.Shape()
	if push.Method != "x.state" || !push.Latest || push.Params.Kind != "object" {
		t.Errorf("Push.Shape() = %+v", push)
	}
}
