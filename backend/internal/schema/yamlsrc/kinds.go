package yamlsrc

import (
	"fmt"
	"sort"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// A type's schema.yaml writes only what's particular to it; its kind's
// base definition (index.yaml's `kinds: {<Kind>: {base}}`, an ordinary
// definition) supplies the rest. Expanding one:
//
//   - the base, less its builder keys (x-settingsAt, x-parts), is copied;
//   - `properties.type` becomes {const: <Type>, description: <label>};
//   - the type's `settings` go where the base's x-settingsAt points (a JSON
//     pointer), then each part it picks: `<part>: <variant>` (or
//     `<part>: {variant, <key>: {override}…}`) adds x-parts.<part>.<variant>'s
//     settings, each overridden key merged over its template (null drops
//     a template's key);
//   - every other key becomes the annotation x-<key> (`group`: the
//     library's, x-libraryGroup); a list the base has too (x-hosts) is the
//     base's followed by the type's additions;
//   - a type naming a section of its own name links to it (x-link) unless
//     it says `link` or the section isn't on the settings page.
//
// The kind's own definition is generated: a oneOf of every type, by name.

// Keys of a type's schema.yaml the builder reads itself (the rest become
// annotations)
var typeKeys = map[string]bool{"label": true, "settings": true}

func (a *assembler) expandKinds(kinds []Kind, defs, sections *jsonx.Object) {
	for _, k := range kinds {
		if k.Base == "" {
			continue
		}
		base, ok := defs.Value(k.Base).(*jsonx.Object)
		if !ok {
			a.errs = append(a.errs, &Error{File: IndexFile, Msg: fmt.Sprintf("kinds.%s.base: no definition %s", k.Name, k.Base)})
			continue
		}
		// The base is a template, not a definition of its own
		defs.Delete(k.Base)
		types, _ := typeFolders(a.fsys, k)
		oneOf := jsonx.Arr()
		for _, t := range types {
			name := t + k.Suffix
			src, ok := defs.Value(name).(*jsonx.Object)
			if !ok {
				continue // didn't read: already reported
			}
			file := k.Root + "/" + t + "/" + TypeFile
			defs.Set(name, a.expand(file, t, src, base, sections, defs))
			oneOf.Items = append(oneOf.Items, jsonx.Obj("$ref", "#/definitions/"+name))
		}
		if defs.Has(k.Name) {
			a.errs = append(a.errs, &Error{File: IndexFile, Msg: fmt.Sprintf("kinds.%s: the kind's definition is generated, so no file may define %s", k.Name, k.Name)})
			continue
		}
		defs.Set(k.Name, jsonx.Obj("type", "object", "required", jsonx.Arr("type"), "oneOf", oneOf))
	}
}

func (a *assembler) expand(file, typeName string, src, base, sections, defs *jsonx.Object) *jsonx.Object {
	fail := func(key, format string, args ...any) {
		a.errs = append(a.errs, a.pos.At(src, key, file, fmt.Sprintf(format, args...)))
	}
	def := jsonx.Clone(base).(*jsonx.Object)
	at, _ := def.Value("x-settingsAt").(string)
	parts, _ := def.Value("x-parts").(*jsonx.Object)
	def.Delete("x-settingsAt")
	def.Delete("x-parts")

	label, ok := src.Value("label").(string)
	if !ok || label == "" {
		a.errs = append(a.errs, &Error{File: file, Msg: "needs a label (the type's name in the libraries)"})
	}
	props, _ := def.Value("properties").(*jsonx.Object)
	if props == nil {
		props = jsonx.NewObject()
		def.Set("properties", props)
	}
	props.Set("type", jsonx.Obj("const", typeName, "description", label))

	slot := pointer(def, at)
	settings, _ := src.Value("settings").(*jsonx.Object)
	if src.Has("settings") && settings == nil {
		fail("settings", "settings must be a mapping of setting names")
	}
	if settings != nil {
		if slot == nil {
			fail("settings", "this kind's base has no x-settingsAt for settings")
		} else {
			for _, key := range settings.Keys() {
				if slot.Has(key) {
					fail("settings", "%s is already one of every %s's settings", key, typeName)
					continue
				}
				slot.Set(key, settings.Value(key))
			}
		}
	}

	var used []string
	for _, key := range src.Keys() {
		if typeKeys[key] {
			continue
		}
		if parts != nil && parts.Has(key) {
			used = append(used, key)
			continue
		}
		name := "x-" + key
		if renamed, ok := annotationNames[key]; ok {
			name = renamed
		}
		value := src.Value(key)
		// {only: [...]} replaces the base's list instead of adding to it
		if only, ok := value.(*jsonx.Object); ok && only.Len() == 1 && only.Has("only") {
			def.Set(name, only.Value("only"))
			continue
		}
		if prior, ok := def.Value(name).(*jsonx.Array); ok {
			add, ok := value.(*jsonx.Array)
			if !ok {
				fail(key, "%s adds to the base's list, so it's a list", key)
				continue
			}
			merged := jsonx.Clone(prior).(*jsonx.Array)
			for _, v := range add.Items {
				if !contains(merged, v) {
					merged.Items = append(merged.Items, v)
				}
			}
			def.Set(name, merged)
			continue
		}
		def.Set(name, value)
	}
	// Parts in the base's order, after the type's own settings
	for _, part := range orderedParts(parts, used) {
		a.addPart(file, src, part, parts.Value(part).(*jsonx.Object), slot, defs)
	}

	if !src.Has("link") && sections != nil && onSettingsPage(sections.Value(typeName)) && !def.Has("x-link") {
		def.Set("x-link", jsonx.Obj("setting", typeName))
	}
	// A kind whose settings sit in an object of their own (a widget's
	// `properties`) leaves that object out when the type has none
	if slot != nil && slot.Len() == 0 {
		parts := strings.Split(strings.TrimPrefix(at, "/"), "/")
		if len(parts) >= 3 && parts[len(parts)-1] == "properties" {
			if holder := pointer(def, "/"+strings.Join(parts[:len(parts)-2], "/")); holder != nil {
				holder.Delete(parts[len(parts)-2])
			}
		}
	}
	return def
}

func orderedParts(parts *jsonx.Object, used []string) []string {
	if parts == nil {
		return nil
	}
	in := map[string]bool{}
	for _, u := range used {
		in[u] = true
	}
	var out []string
	for _, k := range parts.Keys() {
		if in[k] {
			out = append(out, k)
		}
	}
	return out
}

// addPart adds a picked part's settings: `<part>: <variant>`, or
// `<part>: {variant: <variant>, <setting>: {overrides}}`.
func (a *assembler) addPart(file string, src *jsonx.Object, part string, variants *jsonx.Object, slot, defs *jsonx.Object) {
	fail := func(format string, args ...any) {
		a.errs = append(a.errs, a.pos.At(src, part, file, fmt.Sprintf(format, args...)))
	}
	var variant string
	overrides := jsonx.NewObject()
	switch v := src.Value(part).(type) {
	case string:
		variant = v
	case *jsonx.Object:
		variant, _ = v.Value("variant").(string)
		for _, k := range v.Keys() {
			if k != "variant" {
				overrides.Set(k, v.Value(k))
			}
		}
	}
	tmpl, ok := variants.Value(variant).(*jsonx.Object)
	if !ok {
		fail("%s is one of %s", part, strings.Join(variants.Keys(), ", "))
		return
	}
	if slot == nil {
		fail("this kind's base has no x-settingsAt for %s", part)
		return
	}
	added := jsonx.NewObject()
	for _, key := range tmpl.Keys() {
		added.Set(key, jsonx.Clone(tmpl.Value(key)))
	}
	// An override names one of the part's settings, or a field of one
	// that's an object (`popout: {variant: own, enabled: {…}}` reaches
	// popout.enabled), or of the definition one $refs (`appearance:
	// {variant: value, style: {…}}` reaches BarDisplay's style)
	for _, key := range overrides.Keys() {
		o, ok := overrides.Value(key).(*jsonx.Object)
		if !ok {
			fail("%s: an override is a mapping of schema keys", key)
			continue
		}
		if added.Has(key) {
			added.Set(key, merge(added.Value(key), o))
			continue
		}
		found := false
		for _, s := range added.Keys() {
			setting := inlineRef(added.Value(s), key, defs)
			if setting == nil {
				continue
			}
			added.Set(s, setting)
			if inner, ok := setting.Value("properties").(*jsonx.Object); ok && inner.Has(key) {
				inner.Set(key, merge(inner.Value(key), o))
				found = true
				break
			}
		}
		if !found {
			fail("%s %s has no setting %s to override (it has %s)", part, variant, key, strings.Join(tmpl.Keys(), ", "))
		}
	}
	for _, key := range added.Keys() {
		if slot.Has(key) {
			fail("%s's setting %s is already a setting", part, key)
			continue
		}
		slot.Set(key, added.Value(key))
	}
}

// inlineRef: a part's setting that's a $ref to a definition with the
// property key (a widget's `appearance`, BarDisplay), as a copy of that
// definition with the $ref's sibling keys over it, so an override can
// reach into it; the setting as it is otherwise.
func inlineRef(v any, key string, defs *jsonx.Object) *jsonx.Object {
	setting, _ := v.(*jsonx.Object)
	if setting == nil || defs == nil {
		return setting
	}
	ref, ok := setting.Value("$ref").(string)
	if !ok {
		return setting
	}
	target, ok := defs.Value(strings.TrimPrefix(ref, "#/definitions/")).(*jsonx.Object)
	if !ok {
		return setting
	}
	if props, ok := target.Value("properties").(*jsonx.Object); !ok || !props.Has(key) {
		return setting
	}
	inlined := jsonx.Clone(target).(*jsonx.Object)
	inlined.Delete("x-inline")
	for _, k := range setting.Keys() {
		if k != "$ref" {
			inlined.Set(k, jsonx.Clone(setting.Value(k)))
		}
	}
	return inlined
}

// merge lays over's keys over base, recursing into objects both have.
func merge(base any, over *jsonx.Object) any {
	b, ok := base.(*jsonx.Object)
	if !ok {
		return jsonx.Clone(over)
	}
	for _, k := range over.Keys() {
		ov := over.Value(k)
		if ov == nil {
			b.Delete(k) // null takes the template's key away
			continue
		}
		if oo, ok := ov.(*jsonx.Object); ok && b.Has(k) {
			b.Set(k, merge(b.Value(k), oo))
			continue
		}
		b.Set(k, jsonx.Clone(ov))
	}
	return b
}

// pointer resolves a JSON pointer ("/properties/properties/properties")
// to the object there, nil when there's none.
func pointer(root *jsonx.Object, at string) *jsonx.Object {
	if at == "" {
		return nil
	}
	cur := root
	for _, part := range strings.Split(strings.TrimPrefix(at, "/"), "/") {
		next, ok := cur.Value(part).(*jsonx.Object)
		if !ok {
			return nil
		}
		cur = next
	}
	return cur
}

func contains(arr *jsonx.Array, v any) bool {
	for _, x := range arr.Items {
		if jsonx.Equal(x, v) {
			return true
		}
	}
	return false
}

// deriveInherits makes, for every `$ref` carrying `x-inherit: <path>`, the
// inheriting copy of the definition it names: each setting in it may be
// null and is by default, meaning "the value at <path>.<key>". The $ref
// is pointed at the copy (named <Definition>Inherited) and loses x-inherit.
func (a *assembler) deriveInherits(root *jsonx.Object) {
	defs, _ := root.Value("definitions").(*jsonx.Object)
	if defs == nil {
		return
	}
	made := map[string]string{} // definition → its inherit path
	var walk func(v any, where string)
	walk = func(v any, where string) {
		switch t := v.(type) {
		case *jsonx.Object:
			if ref, ok := t.Value("$ref").(string); ok {
				if path, ok := t.Value("x-inherit").(string); ok {
					name := strings.TrimPrefix(ref, "#/definitions/")
					target, ok := defs.Value(name).(*jsonx.Object)
					if !ok {
						a.errs = append(a.errs, &Error{File: where, Msg: "x-inherit on a $ref to no definition: " + ref})
						return
					}
					copyName := name + "Inherited"
					if prior, done := made[name]; done && prior != path {
						a.errs = append(a.errs, &Error{File: where, Msg: fmt.Sprintf("%s inherits from both %s and %s", name, prior, path)})
						return
					} else if !done {
						made[name] = path
						defs.Set(copyName, inheriting(jsonx.Clone(target), path, defs))
					}
					t.Set("$ref", "#/definitions/"+copyName)
					t.Delete("x-inherit")
				}
			}
			keys := t.Keys()
			sort.Strings(keys)
			for _, k := range keys {
				walk(t.Value(k), where+"/"+k)
			}
		case *jsonx.Array:
			for _, x := range t.Items {
				walk(x, where)
			}
		}
	}
	walk(root, "")
}

// inheriting turns a definition's settings into inheriting ones: an
// object's properties recursively, a leaf to default null with x-inherit.
func inheriting(v any, path string, defs *jsonx.Object) any {
	obj, ok := v.(*jsonx.Object)
	if !ok {
		return v
	}
	if ref, ok := obj.Value("$ref").(string); ok && defs != nil {
		// A setting that's a definition (a bar's shadow): inherit each of
		// its keys, not the whole
		if target, ok := defs.Value(strings.TrimPrefix(ref, "#/definitions/")).(*jsonx.Object); ok {
			inlined := jsonx.Clone(target).(*jsonx.Object)
			for _, k := range obj.Keys() {
				if k != "$ref" {
					inlined.Set(k, obj.Value(k))
				}
			}
			obj = inlined
		}
	}
	if props, ok := obj.Value("properties").(*jsonx.Object); ok && obj.Value("type") == "object" {
		obj.Delete("default")
		for _, k := range props.Keys() {
			props.Set(k, inheriting(props.Value(k), path+"."+k, defs))
		}
		return obj
	}
	obj.Set("default", nil)
	obj.Set("x-inherit", path)
	return obj
}

// inlineExtensions replaces every `$ref` carrying `x-properties` with a
// copy of the definition it names, its sibling keys laid over the copy
// and x-properties adjusting its properties: a schema there replaces (or
// adds, at the end) a property, null removes one. A definition may itself
// be such an extension of another (ScreenLayout of Layout).
func (a *assembler) inlineExtensions(root *jsonx.Object) {
	defs, _ := root.Value("definitions").(*jsonx.Object)
	if defs == nil {
		return
	}
	resolving := map[string]bool{}
	// Known before any is expanded: an inline definition may itself be an
	// extension (ScreenGrid of Grid), which loses the mark on the way
	inlined := map[string]bool{}
	for _, k := range defs.Keys() {
		if d, ok := defs.Value(k).(*jsonx.Object); ok && d.Value("x-inline") == true {
			inlined[k] = true
		}
	}
	var extend func(node *jsonx.Object, where string) any
	var walk func(v any, where string) any
	extend = func(node *jsonx.Object, where string) any {
		ref, _ := node.Value("$ref").(string)
		name := strings.TrimPrefix(ref, "#/definitions/")
		target, ok := defs.Value(name).(*jsonx.Object)
		if !ok {
			a.errs = append(a.errs, &Error{File: where, Msg: "x-properties on a $ref to no definition: " + ref})
			return node
		}
		if resolving[name] {
			a.errs = append(a.errs, &Error{File: where, Msg: "x-properties extends " + name + " from inside itself"})
			return node
		}
		resolving[name] = true
		base := walk(jsonx.Clone(target), where).(*jsonx.Object)
		resolving[name] = false
		adjust, ok := node.Value("x-properties").(*jsonx.Object)
		if !ok {
			a.errs = append(a.errs, &Error{File: where, Msg: "x-properties is a mapping of property names to a schema or null"})
			return node
		}
		for _, k := range node.Keys() {
			if k != "$ref" && k != "x-properties" {
				base.Set(k, node.Value(k))
			}
		}
		base.Delete("x-inline")
		props, _ := base.Value("properties").(*jsonx.Object)
		if props == nil {
			if adjust.Len() > 0 {
				a.errs = append(a.errs, &Error{File: where, Msg: name + " has no properties to adjust"})
			}
			return base
		}
		for _, k := range adjust.Keys() {
			v := adjust.Value(k)
			if v == nil {
				if !props.Delete(k) {
					a.errs = append(a.errs, &Error{File: where, Msg: fmt.Sprintf("x-properties removes %s, which %s doesn't have", k, name)})
				}
				continue
			}
			props.Set(k, walk(v, where))
		}
		if req, ok := base.Value("required").(*jsonx.Array); ok {
			kept := jsonx.Arr()
			for _, r := range req.Items {
				if s, ok := r.(string); ok && props.Has(s) {
					kept.Items = append(kept.Items, r)
				}
			}
			base.Set("required", kept)
		}
		return base
	}
	inline := func(t *jsonx.Object) bool {
		ref, _ := t.Value("$ref").(string)
		return inlined[strings.TrimPrefix(ref, "#/definitions/")]
	}
	walk = func(v any, where string) any {
		switch t := v.(type) {
		case *jsonx.Object:
			if t.Has("$ref") && (t.Has("x-properties") || inline(t)) {
				if !t.Has("x-properties") {
					t.Set("x-properties", jsonx.NewObject())
				}
				return extend(t, where)
			}
			for _, k := range t.Keys() {
				t.Set(k, walk(t.Value(k), where+"/"+k))
			}
		case *jsonx.Array:
			for i, x := range t.Items {
				t.Items[i] = walk(x, where)
			}
		}
		return v
	}
	walk(root, "")
	for k := range inlined {
		defs.Delete(k)
	}
}

// orderKeys gives every object with properties its `x-order`: the order
// its properties are written in (QML reads the schema as a map, whose keys
// come out sorted). One its author wrote is kept.
func orderKeys(v any) {
	switch t := v.(type) {
	case *jsonx.Object:
		if props, ok := t.Value("properties").(*jsonx.Object); ok && t.Value("type") == "object" && props.Len() > 1 && !t.Has("x-order") {
			order := jsonx.Arr()
			for _, k := range props.Keys() {
				order.Items = append(order.Items, k)
			}
			t.Set("x-order", order)
		}
		for _, k := range t.Keys() {
			orderKeys(t.Value(k))
		}
	case *jsonx.Array:
		for _, x := range t.Items {
			orderKeys(x)
		}
	}
}

// onSettingsPage: a section the settings page shows (not one marked
// x-settings: false, which its own page edits)
func onSettingsPage(section any) bool {
	o, ok := section.(*jsonx.Object)
	return ok && o.Value("x-settings") != false
}

// annotationNames: type keys whose annotation isn't x-<key>
var annotationNames = map[string]string{
	"group": "x-libraryGroup",
}
