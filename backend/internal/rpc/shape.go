package rpc

import (
	"encoding"
	"encoding/json"
	"reflect"
	"strings"
)

// Shape is what a Go type looks like as JSON, by encoding/json's rules:
// what a method's params and result, or a push's params, carry on the
// wire. It describes types, never values.
type Shape struct {
	// Kind is object, array, map, string, number, bool, or opaque (any,
	// json.RawMessage, a type with its own MarshalJSON, a type that
	// refers back to itself, or one encoding/json can't encode)
	Kind string `json:"kind"`
	// Type names a named Go type ("daemon.HelloResult"), for reading
	Type string `json:"type,omitempty"`
	// Fields are an object's members, in the order they're encoded
	Fields []Field `json:"fields,omitempty"`
	// Elem is an array's element or a map's value
	Elem *Shape `json:"elem,omitempty"`
}

// Field is one member of an object.
type Field struct {
	Name      string `json:"name"`
	OmitEmpty bool   `json:"omitempty,omitempty"`
	Shape     Shape  `json:"shape"`
}

// ShapeOf walks t into its Shape. A nil type (no params) is opaque.
func ShapeOf(t reflect.Type) Shape {
	return shapeOf(t, map[reflect.Type]bool{})
}

func shapeOf(t reflect.Type, walking map[reflect.Type]bool) Shape {
	if t == nil {
		return Shape{Kind: "opaque"}
	}
	for t.Kind() == reflect.Pointer {
		if marshals(t) {
			break
		}
		t = t.Elem()
	}
	name := ""
	if t.Name() != "" && t.PkgPath() != "" {
		name = t.String()
	}
	switch {
	case implements(t, reflect.TypeFor[json.Marshaler]()):
		return Shape{Kind: "opaque", Type: name}
	case implements(t, reflect.TypeFor[encoding.TextMarshaler]()):
		return Shape{Kind: "string", Type: name}
	}
	if walking[t] {
		return Shape{Kind: "opaque", Type: name}
	}
	switch t.Kind() {
	case reflect.String:
		return Shape{Kind: "string", Type: name}
	case reflect.Bool:
		return Shape{Kind: "bool", Type: name}
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64,
		reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64, reflect.Uintptr,
		reflect.Float32, reflect.Float64:
		return Shape{Kind: "number", Type: name}
	case reflect.Slice, reflect.Array:
		// []byte is a base64 string (an array of bytes is not)
		if t.Kind() == reflect.Slice && t.Elem().Kind() == reflect.Uint8 && !marshals(t.Elem()) && !marshals(reflect.PointerTo(t.Elem())) {
			return Shape{Kind: "string", Type: name}
		}
		walking[t] = true
		defer delete(walking, t)
		elem := shapeOf(t.Elem(), walking)
		return Shape{Kind: "array", Type: name, Elem: &elem}
	case reflect.Map:
		// keys are strings, integers or TextMarshalers, else it doesn't encode
		switch t.Key().Kind() {
		case reflect.String, reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64,
			reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64, reflect.Uintptr:
		default:
			if !t.Key().Implements(reflect.TypeFor[encoding.TextMarshaler]()) {
				return Shape{Kind: "opaque", Type: name}
			}
		}
		walking[t] = true
		defer delete(walking, t)
		elem := shapeOf(t.Elem(), walking)
		return Shape{Kind: "map", Type: name, Elem: &elem}
	case reflect.Struct:
		walking[t] = true
		defer delete(walking, t)
		fields := []Field{}
		for _, f := range structFields(t) {
			s := shapeOf(f.typ, walking)
			if f.quoted && (s.Kind == "number" || s.Kind == "bool" || s.Kind == "string") {
				s = Shape{Kind: "string", Type: s.Type}
			}
			fields = append(fields, Field{Name: f.name, OmitEmpty: f.omitEmpty, Shape: s})
		}
		return Shape{Kind: "object", Type: name, Fields: fields}
	}
	// interfaces (any) hold whatever is put in them; chans, funcs and
	// complex numbers don't encode
	return Shape{Kind: "opaque", Type: name}
}

// marshals: t's own method set has MarshalJSON or MarshalText.
func marshals(t reflect.Type) bool {
	return t.Implements(reflect.TypeFor[json.Marshaler]()) || t.Implements(reflect.TypeFor[encoding.TextMarshaler]())
}

// implements: a value of t encodes through iface, by the method on t or
// (encoding/json takes the address of a field) on *t.
func implements(t, iface reflect.Type) bool {
	return t.Implements(iface) || (t.Kind() != reflect.Pointer && reflect.PointerTo(t).Implements(iface))
}

type jsonField struct {
	name              string
	typ               reflect.Type
	omitEmpty, quoted bool
	tagged            bool
	depth             int
}

// structFields lists t's encoded fields as encoding/json picks them:
// exported fields under their tag's name, "-" skipped, untagged embedded
// structs inlined, and of several fields with one name the shallowest
// (then the one tagged) kept, or none when that leaves a tie.
func structFields(t reflect.Type) []jsonField {
	var all []jsonField
	var walk func(t reflect.Type, depth int, seen map[reflect.Type]bool)
	walk = func(t reflect.Type, depth int, seen map[reflect.Type]bool) {
		if seen[t] {
			return
		}
		seen[t] = true
		defer delete(seen, t)
		for i := range t.NumField() {
			sf := t.Field(i)
			ft := sf.Type
			if sf.Anonymous {
				if ft.Kind() == reflect.Pointer {
					ft = ft.Elem()
				}
				if !sf.IsExported() && ft.Kind() != reflect.Struct {
					continue
				}
			} else if !sf.IsExported() {
				continue
			}
			tag := sf.Tag.Get("json")
			if tag == "-" {
				continue
			}
			name, opts, _ := strings.Cut(tag, ",")
			if sf.Anonymous && name == "" && ft.Kind() == reflect.Struct {
				walk(ft, depth+1, seen)
				continue
			}
			f := jsonField{name: name, typ: sf.Type, tagged: name != "", depth: depth}
			if f.name == "" {
				f.name = sf.Name
			}
			for o := range strings.SplitSeq(opts, ",") {
				switch o {
				case "omitempty", "omitzero":
					f.omitEmpty = true
				case "string":
					f.quoted = true
				}
			}
			all = append(all, f)
		}
	}
	walk(t, 0, map[reflect.Type]bool{})

	byName := map[string][]int{}
	for i, f := range all {
		byName[f.name] = append(byName[f.name], i)
	}
	out := make([]jsonField, 0, len(all))
	for i, f := range all {
		if dominant(all, byName[f.name]) == i {
			out = append(out, f)
		}
	}
	return out
}

// dominant is which of the fields sharing a name is encoded, or -1.
func dominant(all []jsonField, idx []int) int {
	best := []int{}
	for _, i := range idx {
		switch {
		case len(best) == 0 || all[i].depth < all[best[0]].depth:
			best = []int{i}
		case all[i].depth == all[best[0]].depth:
			best = append(best, i)
		}
	}
	if len(best) == 1 {
		return best[0]
	}
	tagged := -1
	for _, i := range best {
		if all[i].tagged {
			if tagged >= 0 {
				return -1
			}
			tagged = i
		}
	}
	return tagged
}
