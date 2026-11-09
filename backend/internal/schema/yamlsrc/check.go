package yamlsrc

import (
	"fmt"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/schema"
)

// The draft-07 keywords axiom's schema uses (and its validator reads);
// any other non-annotation key in a schema node is a mistake.
var keywords = map[string]string{
	"$schema": "string", "$ref": "ref", "title": "string", "description": "string",
	"type": "type", "default": "data", "const": "data", "enum": "list",
	"properties": "schemas", "definitions": "schemas",
	"additionalProperties": "boolOrSchema", "required": "strings", "items": "schema",
	"oneOf": "schemaList", "minimum": "number", "maximum": "number",
	"exclusiveMinimum": "number", "exclusiveMaximum": "number", "multipleOf": "number",
	"minItems": "count", "maxItems": "count", "pattern": "pattern",
}

var types = map[string]bool{"object": true, "array": true, "string": true, "integer": true, "number": true, "boolean": true, "null": true}

// Check walks an assembled root schema: every key of a schema node is a
// known keyword (with a value of the right kind) or a registered x-*
// annotation, every $ref names a definition, every pattern compiles, every
// preset (`x-presets`) is valid values of its node.
func Check(root *jsonx.Object, annotations map[string]bool, pos Positions) Errors {
	c := &checker{root: root, annotations: annotations, pos: pos}
	if root == nil {
		return Errors{{File: IndexFile, Msg: "no root schema"}}
	}
	c.node(root, "", true)
	return c.errs
}

type checker struct {
	root        *jsonx.Object
	annotations map[string]bool
	pos         Positions
	errs        Errors
}

func (c *checker) fail(obj *jsonx.Object, key, where, format string, args ...any) {
	msg := fmt.Sprintf(format, args...)
	if where != "" {
		msg = where + ": " + msg
	}
	c.errs = append(c.errs, c.pos.At(obj, key, IndexFile, msg))
}

func (c *checker) node(v any, where string, isRoot bool) {
	if _, ok := v.(bool); ok {
		return // true / false are schemas too
	}
	obj, ok := v.(*jsonx.Object)
	if !ok {
		c.errs = append(c.errs, &Error{File: IndexFile, Msg: where + ": a schema must be a mapping"})
		return
	}
	c.listItems(obj, where)
	for _, key := range obj.Keys() {
		val := obj.Value(key)
		at := join(where, key)
		if strings.HasPrefix(key, "x-") {
			if !c.annotations[key] {
				c.fail(obj, key, where, "unknown annotation %s (add it to %s, and to docs/dev/core/schema-annotations.md)", key, AnnotationsFile)
			}
			if key == "x-presets" {
				c.presets(obj, where, val)
			}
			continue
		}
		kind, known := keywords[key]
		if !known {
			c.fail(obj, key, where, "unknown keyword %q", key)
			continue
		}
		if (key == "definitions" || key == "$schema") && !isRoot {
			c.fail(obj, key, where, "%s belongs at the root only", key)
		}
		switch kind {
		case "string":
			if _, ok := val.(string); !ok {
				c.fail(obj, key, where, "%s must be a string", key)
			}
		case "ref":
			ref, _ := val.(string)
			name, ok := strings.CutPrefix(ref, "#/definitions/")
			defs, _ := c.root.Value("definitions").(*jsonx.Object)
			if !ok || defs == nil || !defs.Has(name) {
				c.fail(obj, key, where, "$ref %q names no definition", ref)
			}
		case "type":
			if s, ok := val.(string); !ok || !types[s] {
				c.fail(obj, key, where, "type %v isn't one of object, array, string, integer, number, boolean, null", jsonx.ToString(val))
			}
		case "list":
			if _, ok := val.(*jsonx.Array); !ok {
				c.fail(obj, key, where, "%s must be a list", key)
			}
		case "strings":
			arr, ok := val.(*jsonx.Array)
			if !ok {
				c.fail(obj, key, where, "%s must be a list of names", key)
				break
			}
			for _, x := range arr.Items {
				if _, ok := x.(string); !ok {
					c.fail(obj, key, where, "%s must be a list of names", key)
				}
			}
		case "number":
			if _, ok := val.(float64); !ok {
				c.fail(obj, key, where, "%s must be a number", key)
			}
		case "count":
			if f, ok := val.(float64); !ok || f < 0 || !jsonx.IsInteger(f) {
				c.fail(obj, key, where, "%s must be a whole number", key)
			}
		case "pattern":
			c.pattern(obj, key, where, val)
		case "schema":
			c.node(val, at, false)
		case "boolOrSchema":
			if _, ok := val.(bool); !ok {
				c.node(val, at, false)
			}
		case "schemaList":
			arr, ok := val.(*jsonx.Array)
			if !ok {
				c.fail(obj, key, where, "%s must be a list of schemas", key)
				break
			}
			for i, x := range arr.Items {
				c.node(x, fmt.Sprintf("%s[%d]", at, i), false)
			}
		case "schemas":
			m, ok := val.(*jsonx.Object)
			if !ok {
				c.fail(obj, key, where, "%s must be a mapping", key)
				break
			}
			for _, name := range m.Keys() {
				c.node(m.Value(name), join(at, name), false)
			}
		}
	}
}

// listItems checks a list of objects with declared properties (the ones
// the generic settings list draws; oneOf items have their own pickers):
// every field its items require has a
// default, so a new item (a settings list's +, SchemaValidation.newItem)
// is valid as made. `id` is the exception: newItem gives it one free in
// its list.
func (c *checker) listItems(obj *jsonx.Object, where string) {
	if obj.Value("type") != "array" {
		return
	}
	items := c.resolve(obj.Value("items"))
	if items == nil {
		return
	}
	req, _ := items.Value("required").(*jsonx.Array)
	props, _ := items.Value("properties").(*jsonx.Object)
	if req == nil || props == nil {
		return
	}
	for _, r := range req.Items {
		key, _ := r.(string)
		if key == "id" {
			continue
		}
		if prop := c.resolve(props.Value(key)); prop == nil || !prop.Has("default") {
			c.fail(obj, "items", where, "the items require %q, which has no default: a new item would be refused (give it a default)", key)
		}
	}
}

// resolve follows a $ref, keys beside it over the definition's (as
// SchemaValidation resolves them); nil for a non-object or a missing
// definition
func (c *checker) resolve(v any) *jsonx.Object {
	obj, _ := v.(*jsonx.Object)
	for range 10 {
		if obj == nil {
			return nil
		}
		ref, ok := obj.Value("$ref").(string)
		if !ok {
			return obj
		}
		defs, _ := c.root.Value("definitions").(*jsonx.Object)
		name, _ := strings.CutPrefix(ref, "#/definitions/")
		var def *jsonx.Object
		if defs != nil {
			def, _ = defs.Value(name).(*jsonx.Object)
		}
		if def == nil {
			return nil
		}
		merged := jsonx.NewObject()
		for _, k := range def.Keys() {
			merged.Set(k, def.Value(k))
		}
		for _, k := range obj.Keys() {
			if k != "$ref" {
				merged.Set(k, obj.Value(k))
			}
		}
		obj = merged
	}
	return nil
}

// presets checks an object's `x-presets` ([{ label, values }]): each a
// label, once, and values the object itself takes (config.ValidationErrors:
// its keys, their types, enums and bounds), so a renamed key or a value
// out of its enum fails the build
func (c *checker) presets(obj *jsonx.Object, where string, val any) {
	list, ok := val.(*jsonx.Array)
	if !ok || len(list.Items) == 0 {
		c.fail(obj, "x-presets", where, "x-presets must be a list of { label, values }")
		return
	}
	labels := map[string]bool{}
	for i, item := range list.Items {
		at := fmt.Sprintf("x-presets[%d]", i)
		preset, _ := item.(*jsonx.Object)
		var label string
		var values *jsonx.Object
		if preset != nil {
			label, _ = preset.Value("label").(string)
			values, _ = preset.Value("values").(*jsonx.Object)
		}
		if preset == nil || preset.Len() != 2 || label == "" || values == nil || values.Len() == 0 {
			c.fail(obj, "x-presets", where, "%s must be { label, values }: a label and the values it sets", at)
			continue
		}
		if labels[label] {
			c.fail(obj, "x-presets", where, "%s: the label %q is taken", at, label)
		}
		labels[label] = true
		for _, msg := range config.ValidationErrors(schema.New(c.root), values, obj) {
			c.fail(obj, "x-presets", where, "%s %q: %s", at, label, strings.TrimPrefix(msg, "."))
		}
	}
}

// pattern checks that a pattern compiles as the validators read it
// (schema.CompilePattern: RE2, a subset of the JS syntax the shell uses,
// with JS's \s)
func (c *checker) pattern(obj *jsonx.Object, key, where string, val any) {
	p, ok := val.(string)
	if !ok {
		c.fail(obj, key, where, "a pattern must be a string")
		return
	}
	if _, err := schema.CompilePattern(p); err != nil {
		c.fail(obj, key, where, "pattern %q doesn't compile: %v", p, err)
	}
}

func join(where, key string) string {
	if where == "" {
		return key
	}
	return where + "." + key
}
