package yamlsrc

import (
	"fmt"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/schema"
)

// The draft-07 keywords axiom's schema uses (and its validator reads);
// any other non-annotation key in a schema node is a mistake.
var keywords = map[string]string{
	"$schema": "string", "$ref": "ref", "title": "string", "description": "string",
	"type": "type", "default": "data", "const": "data", "enum": "list",
	"properties": "schemas", "definitions": "schemas", "patternProperties": "patterns",
	"additionalProperties": "boolOrSchema", "required": "strings", "items": "schema",
	"oneOf": "schemaList", "minimum": "number", "maximum": "number",
	"exclusiveMinimum": "number", "exclusiveMaximum": "number", "multipleOf": "number",
	"minItems": "count", "maxItems": "count", "pattern": "pattern",
}

var types = map[string]bool{"object": true, "array": true, "string": true, "integer": true, "number": true, "boolean": true, "null": true}

// Check walks an assembled root schema: every key of a schema node is a
// known keyword (with a value of the right kind) or a registered x-*
// annotation, every $ref names a definition, every pattern compiles.
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
	for _, key := range obj.Keys() {
		val := obj.Value(key)
		at := join(where, key)
		if strings.HasPrefix(key, "x-") {
			if !c.annotations[key] {
				c.fail(obj, key, where, "unknown annotation %s (add it to %s, and to docs/dev/core/schema-annotations.md)", key, AnnotationsFile)
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
		case "schemas", "patterns":
			m, ok := val.(*jsonx.Object)
			if !ok {
				c.fail(obj, key, where, "%s must be a mapping", key)
				break
			}
			for _, name := range m.Keys() {
				if kind == "patterns" {
					c.pattern(m, name, at, name)
				}
				c.node(m.Value(name), join(at, name), false)
			}
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
