// Package schema reads axiom's config schema (config/json/config.schema.json,
// a draft-07 subset with x-* annotations): resolving $refs with their
// sibling overrides, telling the options of a `type`-discriminated oneOf
// apart, and walking it. It reproduces SchemaValidation.qml's reading
// exactly, which the shared fixtures check. Pure: no I/O.
package schema

import (
	"strings"
	"sync"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// Schema is a root schema document; $refs resolve against its definitions.
type Schema struct {
	root any
	defs *jsonx.Object
	// The compiled `pattern`s, by source: validating reads the same few
	// patterns for every value, and they live as long as the schema does
	patterns sync.Map // string → *regexp.Regexp or error
}

// New wraps a parsed root schema.
func New(root any) *Schema {
	s := &Schema{root: root}
	if o, ok := root.(*jsonx.Object); ok {
		s.defs, _ = o.Value("definitions").(*jsonx.Object)
	}
	return s
}

// Root is the root schema node.
func (s *Schema) Root() any { return s.root }

// Get is node[key] for an object node, nil otherwise (JS's optional
// chaining, node?.[key]).
func Get(node any, key string) any {
	if o, ok := node.(*jsonx.Object); ok {
		return o.Value(key)
	}
	return nil
}

// Has reports whether node is an object holding key.
func Has(node any, key string) bool {
	if o, ok := node.(*jsonx.Object); ok {
		return o.Has(key)
	}
	return false
}

// Resolve is a $ref's definition, with any keys beside the $ref (a
// `default`, `title`, …) over it, so one definition can serve with
// different defaults. A node without a $ref, or one naming no definition,
// is returned as is.
func (s *Schema) Resolve(node any) any {
	o, ok := node.(*jsonx.Object)
	if !ok {
		return node
	}
	ref, ok := o.Value("$ref").(string)
	if !ok || ref == "" {
		return node
	}
	name := strings.Replace(ref, "#/definitions/", "", 1)
	if s.defs == nil {
		return node
	}
	def, ok := s.defs.Get(name)
	if !ok || !jsonx.Truthy(def) {
		return node
	}
	extra := false
	for _, k := range o.Keys() {
		if k != "$ref" {
			extra = true
			break
		}
	}
	if !extra {
		return def
	}
	// Object.assign({}, definition), then the siblings over it
	merged := jsonx.NewObject()
	if d, ok := def.(*jsonx.Object); ok {
		for _, k := range d.Keys() {
			merged.Set(k, d.Value(k))
		}
	}
	for _, k := range o.Keys() {
		if k != "$ref" {
			merged.Set(k, o.Value(k))
		}
	}
	return merged
}

// TypeConst is an option's `properties.type.const`, the discriminator of
// a oneOf, and whether it has one.
func TypeConst(option any) (any, bool) {
	typ, ok := Get(Get(option, "properties"), "type").(*jsonx.Object)
	if !ok {
		return nil, false
	}
	return typ.Get("const")
}

// Discriminate is the option of node's oneOf whose `type` const equals
// value.type (resolved), or nil when value isn't an object or none
// matches.
func (s *Schema) Discriminate(value, node any) any {
	obj, ok := value.(*jsonx.Object)
	if !ok {
		return nil
	}
	options, ok := Get(node, "oneOf").(*jsonx.Array)
	if !ok {
		return nil
	}
	typ, hasType := obj.Get("type")
	for _, option := range options.Items {
		resolved := s.Resolve(option)
		if c, ok := TypeConst(resolved); ok && hasType && jsonx.StrictEqual(c, typ) {
			return resolved
		}
	}
	return nil
}
