package config_test

import (
	"reflect"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/schema"
)

func parse(t *testing.T, text string) any {
	t.Helper()
	v, err := jsonx.Unmarshal([]byte(text))
	if err != nil {
		t.Fatal(err)
	}
	return v
}

// Every reason a value fails the schema, by its path: the one validator
// (the shell no longer validates).
func TestValidationErrors(t *testing.T) {
	t.Parallel()
	root := parse(t, `{"type": "object", "additionalProperties": false,
		"properties": {
			"size": {"type": "integer", "default": 10, "minimum": 1, "maximum": 20},
			"mode": {"type": "string", "default": "a", "enum": ["a", "b"]},
			"nested": {"type": "object", "additionalProperties": false, "properties": {"on": {"type": "boolean", "default": true}}},
			"widgets": {"type": "array", "default": [], "items": {"$ref": "#/definitions/Widget"}},
			"free": {"type": "object", "additionalProperties": {"type": "integer"}},
			"box": {"$ref": "#/definitions/Box", "default": {"items": ["a"]}}
		},
		"definitions": {
			"Widget": {"oneOf": [{"$ref": "#/definitions/Clock"}, {"$ref": "#/definitions/Label"}]},
			"Clock": {"type": "object", "additionalProperties": false, "required": ["type"], "properties": {"type": {"const": "Clock"}, "format": {"type": "string", "default": "HH:mm"}}},
			"Label": {"type": "object", "additionalProperties": false, "required": ["type", "text"], "properties": {"type": {"const": "Label"}, "text": {"type": "string"}}},
			"Box": {"type": "object", "additionalProperties": false, "properties": {"size": {"type": "integer", "default": 2}, "items": {"type": "array", "default": [], "items": {"type": "string"}}}}
		}}`)
	s := schema.New(root)
	for _, tc := range []struct {
		value string
		want  []string
	}{
		{`{}`, nil},
		{`{"widgets": [{"type": "Clock"}, {"type": "Label", "text": "hi"}]}`, nil},
		{`{"size": "big"}`, []string{"size: expected integer, got string"}},
		{`{"size": 1.5}`, []string{"size: expected integer, got number"}},
		{`{"nested": []}`, []string{"nested: expected object, got array"}},
		{`{"size": 0}`, []string{"size: value 0 is less than minimum 1"}},
		{`{"size": 21}`, []string{"size: value 21 is greater than maximum 20"}},
		{`{"mode": "c"}`, []string{`mode: value "c" not in allowed values [a, b]`}},
		{`{"stray": 1}`, []string{".stray: additional property not allowed"}},
		{`{"free": {"x": 1}}`, nil},
		{`{"free": {"x": "no"}}`, []string{"free.x: expected integer, got string"}},
		// A discriminated union reports why the matching option failed
		{`{"widgets": [{"type": "Label"}]}`, []string{"widgets[0].text: required field missing"}},
		{`{"widgets": [{"type": "Nope"}]}`, []string{"widgets[0]: value does not match any schema in oneOf"}},
	} {
		got := config.ValidationErrors(s, parse(t, tc.value), root)
		if len(got) == 0 {
			got = nil
		}
		if !reflect.DeepEqual(got, tc.want) {
			t.Errorf("%s: got %q, want %q", tc.value, got, tc.want)
		}
	}
	// Filled with its defaults (a oneOf's by its type, a $ref's own default
	// over its definition's), a value stays valid
	for _, value := range []string{`{}`, `{"widgets": [{"type": "Clock"}, {"type": "Label", "text": "hi"}]}`, `{"box": {"size": 5}}`} {
		filled, ok := config.ApplyDefaults(s, parse(t, value), true, root)
		if !ok {
			t.Fatalf("%s: no defaults", value)
		}
		if errs := config.ValidationErrors(s, filled, root); len(errs) > 0 {
			t.Errorf("%s filled: %q", value, errs)
		}
	}
}

// The real schema's defaults are a valid config, and so are every bar
// widget's, overlay module's, view's and edge menu's.
func TestSchemaDefaultsAreValid(t *testing.T) {
	t.Parallel()
	s := v2(t).S
	root := s.Root()
	fill := func(value any, node any) any {
		filled, ok := config.ApplyDefaults(s, value, true, node)
		if !ok {
			t.Fatalf("no defaults for %s", jsonx.MarshalCompact(value))
		}
		return filled
	}
	if errs := config.ValidationErrors(s, fill(jsonx.NewObject(), root), root); len(errs) > 0 {
		t.Errorf("the defaults: %q", errs)
	}
	defs := schema.Get(root, "definitions").(*jsonx.Object)
	check := func(name string, value *jsonx.Object) {
		ref := jsonx.Obj("$ref", "#/definitions/"+name)
		if errs := config.ValidationErrors(s, fill(value, ref), ref); len(errs) > 0 {
			t.Errorf("%s %s: %q", name, jsonx.MarshalCompact(value), errs)
		}
	}
	for _, union := range []string{"BarWidget", "OverlayModule", "OverlayView"} {
		for _, option := range schema.Get(defs.Value(union), "oneOf").(*jsonx.Array).Items {
			name := strings.TrimPrefix(schema.Get(option, "$ref").(string), "#/definitions/")
			typ, _ := schema.TypeConst(defs.Value(name))
			// Format 2's items carry a stable id
			check(union, jsonx.Obj("type", typ, "id", "test"))
		}
	}
	check("EdgeMenu", jsonx.Obj("id", "test"))
}
