// Package config is the config pipeline: filling in schema defaults,
// pruning keys the schema doesn't allow, validating, and the whole load
// (migrate, prune, defaults, validate) the shell's ConfigManager did. Each
// step reproduces SchemaValidation.qml exactly, error messages included;
// the shared fixtures check it byte for byte. Pure: no I/O.
package config

import (
	"fmt"
	"regexp"
	"strings"
	"sync"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/schema"
)

// ApplyDefaults returns a deep copy of value with every missing key that
// has a schema `default` filled in, recursing into objects and array
// items. Objects with declared properties are created when missing, so
// nested defaults always resolve. A oneOf whose options are told apart by
// a `type` const uses the matching option; any other oneOf is left as is.
// present says whether there is a value at all (JS undefined when false);
// the result's ok is the same for the output.
func ApplyDefaults(s *schema.Schema, value any, present bool, node any) (any, bool) {
	if present {
		value = jsonx.Clone(value)
	}
	return applyDefaults(s, value, present, node)
}

func applyDefaults(s *schema.Schema, value any, present bool, node any) (any, bool) {
	node = s.Resolve(node)
	if jsonx.Truthy(schema.Get(node, "oneOf")) {
		node = s.Discriminate(value, node)
	}
	if !jsonx.Truthy(node) {
		return value, present
	}
	if def, ok := node.(*jsonx.Object); ok {
		if d, has := def.Get("default"); !present && has {
			value, present = jsonx.Clone(d), true
		}
	}
	typ := schema.Get(node, "type")
	if typ == "object" && jsonx.Truthy(schema.Get(node, "properties")) {
		if !present {
			value, present = jsonx.NewObject(), true
		}
		if obj, ok := value.(*jsonx.Object); ok {
			if props, ok := schema.Get(node, "properties").(*jsonx.Object); ok {
				for _, key := range props.Keys() {
					current, has := obj.Get(key)
					if filled, ok := applyDefaults(s, current, has, props.Value(key)); ok {
						obj.Set(key, filled)
					}
				}
			}
		}
	}
	if typ == "array" {
		if arr, ok := value.(*jsonx.Array); ok && jsonx.Truthy(schema.Get(node, "items")) {
			items := schema.Get(node, "items")
			for i := range arr.Items {
				arr.Items[i], _ = applyDefaults(s, arr.Items[i], true, items)
			}
		}
	}
	return value, present
}

// Prune removes the keys node doesn't allow (additionalProperties: false)
// from value in place and returns their paths ("a.b[2].c"). A oneOf item
// whose `type` matches no option is left alone (validation reports it).
func Prune(s *schema.Schema, value any, node any) []string {
	removed := []string{}
	prune(s, value, node, "", &removed)
	return removed
}

func prune(s *schema.Schema, value any, node any, path string, removed *[]string) {
	node = s.Resolve(node)
	if jsonx.Truthy(schema.Get(node, "oneOf")) {
		node = s.Discriminate(value, node)
	}
	if !jsonx.Truthy(node) {
		return
	}
	switch v := value.(type) {
	case *jsonx.Array:
		if items := schema.Get(node, "items"); jsonx.Truthy(items) {
			for i, item := range v.Items {
				prune(s, item, items, fmt.Sprintf("%s[%d]", path, i), removed)
			}
		}
	case *jsonx.Object:
		n, ok := node.(*jsonx.Object)
		if !ok {
			return
		}
		props, _ := n.Value("properties").(*jsonx.Object)
		additional, hasAdditional := n.Get("additionalProperties")
		for _, key := range v.Keys() {
			propPath := key
			if path != "" {
				propPath = path + "." + key
			}
			var prop any
			if props != nil {
				prop = props.Value(key)
			}
			switch {
			case jsonx.Truthy(prop):
				prune(s, v.Value(key), prop, propPath, removed)
			case hasAdditional && additional == false:
				*removed = append(*removed, propPath)
				v.Delete(key)
			case hasAdditional && jsonx.TypeOf(additional) == "object":
				prune(s, v.Value(key), additional, propPath, removed)
			}
		}
	}
}

// ValidationErrors is every reason value fails node, as "path: message"
// lines (empty when valid), in SchemaValidation's order and wording.
func ValidationErrors(s *schema.Schema, value any, node any) []string {
	errs := []string{}
	validate(s, value, node, "", &errs)
	return errs
}

func validate(s *schema.Schema, value any, node any, path string, errs *[]string) {
	if !jsonx.Truthy(node) {
		return
	}
	node = s.Resolve(node)
	n, _ := node.(*jsonx.Object)
	get := func(key string) (any, bool) {
		if n == nil {
			return nil, false
		}
		return n.Get(key)
	}
	// An inheriting setting is null while it takes its value from elsewhere
	if inherit, _ := get("x-inherit"); value == nil && jsonx.Truthy(inherit) {
		return
	}

	if typ, _ := get("type"); jsonx.Truthy(typ) {
		if !validateType(value, typ, path, errs) {
			return
		}
	}
	if oneOf, _ := get("oneOf"); jsonx.Truthy(oneOf) {
		validateOneOf(s, value, oneOf, path, errs)
		return
	}
	if enum, _ := get("enum"); jsonx.Truthy(enum) {
		if arr, ok := enum.(*jsonx.Array); ok && !includes(arr, value) {
			*errs = append(*errs, fmt.Sprintf(`%s: value "%s" not in allowed values [%s]`, path, jsonx.ToString(value), jsonx.Join(arr, ", ")))
		}
	}
	if min, ok := get("minimum"); ok && jsonx.LessThan(value, min) {
		*errs = append(*errs, fmt.Sprintf("%s: value %s is less than minimum %s", path, jsonx.ToString(value), jsonx.ToString(min)))
	}
	if max, ok := get("maximum"); ok && jsonx.GreaterThan(value, max) {
		*errs = append(*errs, fmt.Sprintf("%s: value %s is greater than maximum %s", path, jsonx.ToString(value), jsonx.ToString(max)))
	}
	if min, ok := get("exclusiveMinimum"); ok && jsonx.LessOrEqual(value, min) {
		*errs = append(*errs, fmt.Sprintf("%s: value %s must be greater than %s", path, jsonx.ToString(value), jsonx.ToString(min)))
	}
	if max, ok := get("exclusiveMaximum"); ok && jsonx.GreaterOrEqual(value, max) {
		*errs = append(*errs, fmt.Sprintf("%s: value %s must be less than %s", path, jsonx.ToString(value), jsonx.ToString(max)))
	}
	if pattern, _ := get("pattern"); jsonx.Truthy(pattern) {
		if str, ok := value.(string); ok {
			p := jsonx.ToString(pattern)
			re, err := compilePattern(p)
			switch {
			case err != nil:
				*errs = append(*errs, fmt.Sprintf("%s: invalid pattern %s in the schema", path, p))
			case !re.MatchString(str):
				*errs = append(*errs, fmt.Sprintf(`%s: value "%s" does not match pattern %s`, path, str, p))
			}
		}
	}
	typ, _ := get("type")
	if obj, ok := value.(*jsonx.Object); ok && typ == "object" {
		validateObject(s, obj, n, path, errs)
	}
	if arr, ok := value.(*jsonx.Array); ok && typ == "array" {
		validateArray(s, arr, n, path, errs)
	}
}

// validateType checks value against a `type`, reporting it as JS does:
// `typeof` for integers, null and arrays named for the others.
func validateType(value any, expected any, path string, errs *[]string) bool {
	actual := jsonx.TypeOf(value)
	if value == nil {
		actual = "null"
	} else if _, ok := value.(*jsonx.Array); ok {
		actual = "array"
	}
	switch expected {
	case "integer":
		if !jsonx.IsInteger(value) {
			*errs = append(*errs, fmt.Sprintf("%s: expected integer, got %s", path, jsonx.TypeOf(value)))
			return false
		}
	case "array":
		if _, ok := value.(*jsonx.Array); !ok {
			*errs = append(*errs, fmt.Sprintf("%s: expected array, got %s", path, actual))
			return false
		}
	case "object":
		if _, ok := value.(*jsonx.Object); !ok {
			*errs = append(*errs, fmt.Sprintf("%s: expected object, got %s", path, actual))
			return false
		}
	default:
		if exp, ok := expected.(string); !ok || actual != exp {
			*errs = append(*errs, fmt.Sprintf("%s: expected %s, got %s", path, jsonx.ToString(expected), actual))
			return false
		}
	}
	return true
}

func validateObject(s *schema.Schema, value *jsonx.Object, n *jsonx.Object, path string, errs *[]string) {
	if req, ok := n.Value("required").(*jsonx.Array); ok {
		for _, r := range req.Items {
			key := jsonx.ToString(r)
			if !value.Has(key) {
				prefix := ""
				if path != "" {
					prefix = path + "."
				}
				*errs = append(*errs, fmt.Sprintf("%s%s: required field missing", prefix, key))
			}
		}
	}
	props, _ := n.Value("properties").(*jsonx.Object)
	if jsonx.Truthy(n.Value("properties")) && props != nil {
		for _, key := range value.Keys() {
			if prop := props.Value(key); jsonx.Truthy(prop) {
				validate(s, value.Value(key), prop, childPath(path, key), errs)
			}
		}
	}
	if additional, ok := n.Get("additionalProperties"); ok {
		for _, key := range value.Keys() {
			if props != nil && props.Has(key) {
				continue
			}
			if additional == false {
				*errs = append(*errs, fmt.Sprintf("%s.%s: additional property not allowed", path, key))
			} else if jsonx.TypeOf(additional) == "object" {
				validate(s, value.Value(key), additional, childPath(path, key), errs)
			}
		}
	}
	if patterns, ok := n.Value("patternProperties").(*jsonx.Object); ok {
		for _, key := range value.Keys() {
			for _, p := range patterns.Keys() {
				if re, err := compilePattern(p); err == nil && re.MatchString(key) {
					validate(s, value.Value(key), patterns.Value(p), childPath(path, key), errs)
				}
			}
		}
	}
}

func validateArray(s *schema.Schema, value *jsonx.Array, n *jsonx.Object, path string, errs *[]string) {
	if items := n.Value("items"); jsonx.Truthy(items) {
		for i, item := range value.Items {
			validate(s, item, items, fmt.Sprintf("%s[%d]", path, i), errs)
		}
	}
	length := float64(len(value.Items))
	if min, ok := n.Get("minItems"); ok && jsonx.LessThan(length, min) {
		*errs = append(*errs, fmt.Sprintf("%s: array has %d items, minimum is %s", path, len(value.Items), jsonx.ToString(min)))
	}
	if max, ok := n.Get("maxItems"); ok && jsonx.GreaterThan(length, max) {
		*errs = append(*errs, fmt.Sprintf("%s: array has %d items, maximum is %s", path, len(value.Items), jsonx.ToString(max)))
	}
}

func validateOneOf(s *schema.Schema, value any, oneOf any, path string, errs *[]string) {
	options, _ := oneOf.(*jsonx.Array)
	if options == nil {
		*errs = append(*errs, fmt.Sprintf("%s: value does not match any schema in oneOf", path))
		return
	}
	var matching []string
	// Errors from options whose `type` const matched, so a discriminated
	// union reports why the right option failed instead of just "no match"
	var typed []string
	valueType, hasType := schema.Get(value, "type"), schema.Has(value, "type")
	for i, option := range options.Items {
		resolved := s.Resolve(option)
		c, isTyped := schema.TypeConst(resolved)
		if isTyped && !(hasType && jsonx.StrictEqual(valueType, c)) {
			continue
		}
		var sub []string
		validate(s, value, resolved, path, &sub)
		if len(sub) == 0 {
			matching = append(matching, fmt.Sprint(i))
		} else if isTyped {
			typed = append(typed, sub...)
		}
	}
	switch {
	case len(matching) == 0 && len(typed) > 0:
		*errs = append(*errs, typed...)
	case len(matching) == 0:
		*errs = append(*errs, fmt.Sprintf("%s: value does not match any schema in oneOf", path))
	case len(matching) > 1:
		*errs = append(*errs, fmt.Sprintf("%s: value matches multiple schemas in oneOf (indices: %s)", path, strings.Join(matching, ", ")))
	}
}

func includes(arr *jsonx.Array, v any) bool {
	for _, x := range arr.Items {
		if jsonx.SameValueZero(x, v) {
			return true
		}
	}
	return false
}

func childPath(path, key string) string {
	if path == "" {
		return key
	}
	return path + "." + key
}

var patterns sync.Map // string → *regexp.Regexp or error

// compilePattern compiles a schema `pattern` as JS reads it
// (schema.CompilePattern; the YAML schema check refuses one it can't).
func compilePattern(p string) (*regexp.Regexp, error) {
	if v, ok := patterns.Load(p); ok {
		if re, ok := v.(*regexp.Regexp); ok {
			return re, nil
		}
		return nil, v.(error)
	}
	re, err := schema.CompilePattern(p)
	if err != nil {
		patterns.Store(p, err)
		return nil, err
	}
	patterns.Store(p, re)
	return re, nil
}
