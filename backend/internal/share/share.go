// Package share decides what travels when a config is shared: what an
// exported file or example holds (Pick), how one is applied onto the
// running config (Apply), what a saved snapshot holds and restores, and
// the takeover settings loading never changes. Each setting's `x-scope`
// in the schema says whether it belongs to the look of a desktop or to the
// PC and person it runs for (inherited from the nearest ancestor that sets
// one; the root is machine):
//
//	look      how the desktop looks and is laid out
//	personal  preferences, keybinds and apps: travel only when asked for
//	commands  anything that runs as you: travel only when asked for
//	machine   what only means something here: monitors, wallpapers, accounts
//
// An array item can have a scope of its own by what it holds (`x-scopeIf:
// {when, scope}`). Pure: no I/O.
package share

import (
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/schema"
)

// Everything is what a snapshot carries besides the look.
var Everything = []string{"personal", "commands"}

// Monitors are the user's monitors by place, left to right then top to
// bottom (the daemon's own list, wayland/outputs); nil while it has none
// to give, which leaves monitor fields as they are.
type Monitors []string

type context struct {
	s        *schema.Schema
	kept     []string
	monitors Monitors
	// dropped, when not nil, collects what pick leaves out (Dropped)
	dropped *[]Drop
}

// Drop is a value a pick leaves out: its path (keys joined by dots, a
// list's item as [its id or name], else its index) and why, by its scope
// ("personal", "commands", "machine"), or "takeover" for an x-takeover
// setting.
type Drop struct {
	Path  string `json:"path"`
	Scope string `json:"scope"`
}

func (c *context) drop(path, scope string) {
	if c.dropped != nil {
		*c.dropped = append(*c.dropped, Drop{Path: path, Scope: scope})
	}
}

func newContext(s *schema.Schema, carry []string, monitors Monitors) *context {
	return &context{s: s, kept: append([]string{"look"}, carry...), monitors: monitors}
}

func (c *context) keeps(scope string) bool {
	for _, k := range c.kept {
		if k == scope {
			return true
		}
	}
	return false
}

// Pick is the part of config a shared file holds: the look, and the scopes
// in carry ("personal", "commands"), never a takeover setting. With
// monitors, each monitor a per-monitor part names (x-monitorRef) is written
// by its place: "#1" the leftmost, "@primary" the primary, "*" all.
func Pick(s *schema.Schema, cfg any, carry []string, monitors Monitors) *jsonx.Object {
	ctx := newContext(s, carry, monitors)
	if v, ok := ctx.pick(cfg, true, s.Root(), "machine", ""); ok && v != nil {
		if obj, ok := v.(*jsonx.Object); ok {
			return obj
		}
	}
	return jsonx.NewObject()
}

// Dropped is what Pick(s, cfg, carry, monitors) leaves out, each value at
// the highest place it's left out from: pass a Sparse config, so a value
// that is only its default isn't reported. The format and version aren't:
// a shared file's head carries its own.
func Dropped(s *schema.Schema, cfg any, carry []string, monitors Monitors) []Drop {
	var dropped []Drop
	ctx := newContext(s, carry, monitors)
	ctx.dropped = &dropped
	ctx.pick(cfg, true, s.Root(), "machine", "")
	out := []Drop{}
	for _, d := range dropped {
		if d.Path != "format" && d.Path != "version" {
			out = append(out, d)
		}
	}
	return out
}

// Apply is a copy of current with the example's parts in place of its own.
// Both are whole configs of the same version. A part replaces the current
// one outright; inside it, what isn't taken stays the user's, from the same
// item: by id or name, or else (machine values only) by position. With no
// such item it is the default. A monitor written by its place is the
// user's monitor in that place; a part for one the user doesn't have is
// turned off (x-monitorRef "off") or left out ("drop").
func Apply(s *schema.Schema, current, example any, carry []string, monitors Monitors) any {
	ctx := newContext(s, carry, monitors)
	v, _ := ctx.merge(current, true, example, true, s.Root(), "machine", true)
	return v
}

// KeepMovedKeys is a copy of cfg (a file of version, loaded) with each of
// movedKeys newer than the file as it is in current, unless the file holds
// it: held is the file migrated but not filled.
func KeepMovedKeys(cfg, held, current any, version any) any {
	result := clone(cfg, true)
	for _, moved := range movedKeys {
		if jsonx.GreaterOrEqual(version, moved.version) {
			continue
		}
		for _, dotted := range moved.paths {
			path := strings.Split(dotted, ".")
			value, ok := at(current, path)
			if !ok {
				continue
			}
			if _, inHeld := at(held, path); inHeld {
				continue
			}
			if parent, ok := at(result, path[:len(path)-1]); ok && isObject(parent) {
				setAt(result, path, clone(value, true))
			}
		}
	}
	return result
}

// Sparse is cfg without what loading fills back in: each key whose value is
// the one it would get if it were missing (never `type`, which picks a
// oneOf's option).
func Sparse(s *schema.Schema, cfg any) any {
	return sparse(s, cfg, s.Root())
}

// KeepTakeovers is a copy of cfg with every x-takeover setting as it is in
// current: loading a saved config or the defaults never changes them.
func KeepTakeovers(cfg, current any, paths [][]string) any {
	result := clone(cfg, true)
	for _, path := range paths {
		if len(path) == 0 {
			continue
		}
		from, to := current, result
		for i := 0; i < len(path)-1 && isObject(from) && isObject(to); i++ {
			from = schema.Get(from, path[i])
			to = schema.Get(to, path[i])
		}
		key := path[len(path)-1]
		f, fok := from.(*jsonx.Object)
		t, tok := to.(*jsonx.Object)
		if fok && tok {
			if v, has := f.Get(key); has {
				t.Set(key, clone(v, true))
			}
		}
	}
	return result
}

// Snapshot is what a saved snapshot holds: the look, the personal parts
// and the commands, and the x-snapshot settings (the wallpaper setup).
func Snapshot(s *schema.Schema, cfg any) *jsonx.Object {
	result := Pick(s, cfg, Everything, nil)
	for _, path := range SnapshotPaths(s) {
		if value, ok := at(cfg, path); ok {
			setAt(result, path, clone(value, true))
		}
	}
	return result
}

// SnapshotFiles is the files (absolute paths, each once) the x-snapshot
// settings of cfg name as file:// URLs.
func SnapshotFiles(s *schema.Schema, cfg any) []string {
	var urls []string
	var collect func(v any)
	collect = func(v any) {
		switch t := v.(type) {
		case string:
			if strings.HasPrefix(t, "file://") {
				urls = append(urls, t)
			}
		case *jsonx.Object:
			for _, k := range t.Keys() {
				collect(t.Value(k))
			}
		}
	}
	for _, path := range SnapshotPaths(s) {
		if v, ok := at(cfg, path); ok {
			collect(v)
		}
	}
	var paths []string
	seen := map[string]bool{}
	for _, u := range urls {
		p := FilePath(u)
		if strings.HasPrefix(p, "/") && !seen[p] {
			seen[p] = true
			paths = append(paths, p)
		}
	}
	return paths
}

// WithSnapshot is a copy of cfg with the x-snapshot settings of saved. A
// file URL comes back only when its file is in existing (SnapshotFiles'
// paths that exist), and a wallpaper is never blanked. Objects merge by
// key.
func WithSnapshot(s *schema.Schema, cfg, saved any, existing []string) any {
	result := clone(cfg, true)
	exists := map[string]bool{}
	for _, e := range existing {
		exists[e] = true
	}
	var restore func(current any, curOK bool, value any) (any, bool)
	restore = func(current any, curOK bool, value any) (any, bool) {
		if str, ok := value.(string); ok {
			if strings.HasPrefix(str, "file://") {
				if exists[FilePath(str)] {
					return str, true
				}
				return current, curOK
			}
			if cs, ok := current.(string); ok && curOK && str == "" && strings.HasPrefix(cs, "file://") {
				return current, true
			}
			return str, true
		}
		obj, ok := value.(*jsonx.Object)
		if !ok {
			return clone(value, true), true
		}
		var merged *jsonx.Object
		if c, ok := current.(*jsonx.Object); ok && curOK {
			merged = clone(c, true).(*jsonx.Object)
		} else {
			merged = jsonx.NewObject()
		}
		for _, k := range obj.Keys() {
			old, has := merged.Get(k)
			if r, ok := restore(old, has, obj.Value(k)); ok {
				merged.Set(k, r)
			}
		}
		return merged, true
	}
	for _, path := range SnapshotPaths(s) {
		value, ok := at(saved, path)
		if !ok {
			continue
		}
		current, curOK := at(result, path)
		restored, rok := restore(current, curOK, value)
		// _setAt makes the objects on the way even when the value it sets
		// is undefined, which JSON then leaves out
		parent := makeParents(result, path)
		if rok && parent != nil {
			parent.Set(path[len(path)-1], restored)
		}
	}
	return result
}

// TakeoverPaths is the paths of the x-takeover settings, through objects.
func TakeoverPaths(s *schema.Schema) [][]string { return annotated(s, "x-takeover") }

// SnapshotPaths is the paths of the x-snapshot settings, through objects.
func SnapshotPaths(s *schema.Schema) [][]string { return annotated(s, "x-snapshot") }

func annotated(s *schema.Schema, annotation string) [][]string {
	paths := [][]string{}
	var walk func(node any, path []string, depth int)
	walk = func(node any, path []string, depth int) {
		node = s.Resolve(node)
		if !jsonx.Truthy(node) || depth > 20 {
			return
		}
		if schema.Get(node, annotation) == true && len(path) > 0 {
			paths = append(paths, path)
			return
		}
		if props, ok := schema.Get(node, "properties").(*jsonx.Object); ok {
			for _, k := range props.Keys() {
				next := append(append([]string{}, path...), k)
				walk(props.Value(k), next, depth+1)
			}
		}
	}
	walk(s.Root(), nil, 0)
	return paths
}

// FilePath is a file:// URL's path, decoded as decodeURIComponent does
// ("" when it can't be).
func FilePath(u string) string {
	p, ok := decodeURIComponent(strings.TrimPrefix(u, "file://"))
	if !ok {
		return ""
	}
	return p
}

// decodeURIComponent decodes every %XX; malformed escapes or bytes that
// aren't UTF-8 are an error, as in JS.
func decodeURIComponent(s string) (string, bool) {
	if !strings.Contains(s, "%") {
		return s, true
	}
	var b []byte
	for i := 0; i < len(s); i++ {
		if s[i] != '%' {
			b = append(b, s[i])
			continue
		}
		if i+2 >= len(s) {
			return "", false
		}
		n, err := strconv.ParseUint(s[i+1:i+3], 16, 8)
		if err != nil {
			return "", false
		}
		b = append(b, byte(n))
		i += 2
	}
	if !utf8.Valid(b) {
		return "", false
	}
	return string(b), true
}

// --- the walk ---

// node is a value's place in the schema: the $ref resolved, the oneOf
// option for its type (nil when none matches), its scope, and whether that
// scope is the item's own (x-scopeIf).
type node struct {
	schema any
	scope  string
	own    bool
}

func (c *context) node(value any, present bool, n any, scope string) node {
	resolved := c.s.Resolve(n)
	if sc, ok := schema.Get(resolved, "x-scope").(string); ok {
		scope = sc
	}
	if jsonx.Truthy(schema.Get(resolved, "oneOf")) {
		resolved = c.s.Discriminate(value, resolved)
	}
	own, isOwn := ownScope(value, present, resolved)
	result := node{schema: resolved, own: isOwn, scope: scope}
	if isOwn {
		result.scope = own
	} else if sc, ok := schema.Get(resolved, "x-scope").(string); ok {
		result.scope = sc
	}
	return result
}

// ownScope is the scope an item has by what it holds (x-scopeIf).
func ownScope(value any, present bool, n any) (string, bool) {
	rule := schema.Get(n, "x-scopeIf")
	obj, ok := value.(*jsonx.Object)
	if !jsonx.Truthy(rule) || !ok || !present {
		return "", false
	}
	holds := schema.Holds(schema.Get(rule, "when"), func(key string) (any, bool) { return obj.Get(key) })
	if !holds {
		return "", false
	}
	scope, _ := schema.Get(rule, "scope").(string)
	return scope, true
}

// ownNotKept: an item of items with a scope of its own that isn't kept,
// left out of a pick and the user's kept on apply.
func (c *context) ownNotKept(item any, items any, scope string) bool {
	n := c.node(item, true, items, scope)
	return n.own && !c.keeps(n.scope)
}

// child is the schema of key under n: its property, else an object
// additionalProperties.
func child(n any, key string) any {
	if p := schema.Get(schema.Get(n, "properties"), key); jsonx.Truthy(p) {
		return p
	}
	if ap, ok := n.(*jsonx.Object); ok {
		if v, has := ap.Get("additionalProperties"); has && jsonx.TypeOf(v) == "object" {
			return v
		}
	}
	return nil
}

// carries: whether anything at or under n has a kept scope.
func (c *context) carries(n any, scope string, depth int) bool {
	resolved := c.s.Resolve(n)
	if !jsonx.Truthy(resolved) || depth > 40 {
		return false
	}
	if sc, ok := schema.Get(resolved, "x-scope").(string); ok {
		scope = sc
	}
	if c.keeps(scope) {
		return true
	}
	var children []any
	if oneOf, ok := schema.Get(resolved, "oneOf").(*jsonx.Array); ok {
		children = append(children, oneOf.Items...)
	}
	if props, ok := schema.Get(resolved, "properties").(*jsonx.Object); ok {
		for _, k := range props.Keys() {
			children = append(children, props.Value(k))
		}
	}
	if items := schema.Get(resolved, "items"); jsonx.Truthy(items) {
		children = append(children, items)
	}
	if obj, ok := resolved.(*jsonx.Object); ok {
		if ap, has := obj.Get("additionalProperties"); has && jsonx.TypeOf(ap) == "object" {
			children = append(children, ap)
		}
	}
	for _, ch := range children {
		if c.carries(ch, scope, depth+1) {
			return true
		}
	}
	return false
}

// pick is value (at path, for Dropped) with only its kept parts (ok false
// for none). A takeover setting is never kept.
func (c *context) pick(value any, present bool, n any, scope, path string) (any, bool) {
	nd := c.node(value, present, n, scope)
	if schema.Get(nd.schema, "x-takeover") == true {
		c.drop(path, "takeover")
		return nil, false
	}
	if jsonx.Truthy(schema.Get(nd.schema, "x-monitorRef")) && c.monitors != nil {
		switch v := value.(type) {
		case string:
			token, ok := monitorToken(v, c.monitors)
			if !ok {
				c.drop(path, "machine")
			}
			return token, ok
		case *jsonx.Array:
			// A list of monitors (a ScreenTarget's names): each by its
			// place, the ones not connected left out
			out := jsonx.Arr()
			for i, item := range v.Items {
				if name, ok := item.(string); ok {
					if token, ok := monitorToken(name, c.monitors); ok {
						out.Append(token)
						continue
					}
				}
				c.drop(itemPath(path, item, i), "machine")
			}
			return out, true
		}
	}
	keep := c.keeps(nd.scope)
	switch v := value.(type) {
	case *jsonx.Array:
		if !keep {
			c.drop(path, nd.scope)
			return nil, false
		}
		items := schema.Get(nd.schema, "items")
		if !jsonx.Truthy(items) {
			return clone(v, true), true
		}
		out := jsonx.Arr()
		for i, item := range v.Items {
			if c.ownNotKept(item, items, nd.scope) {
				c.drop(itemPath(path, item, i), c.node(item, true, items, nd.scope).scope)
				continue
			}
			if picked, ok := c.pick(item, true, items, nd.scope, itemPath(path, item, i)); ok {
				out.Append(picked)
			}
		}
		return out, true
	case *jsonx.Object:
		if jsonx.Truthy(nd.schema) {
			result := jsonx.NewObject()
			for _, k := range v.Keys() {
				var picked any
				var ok bool
				if ch := child(nd.schema, k); jsonx.Truthy(ch) {
					picked, ok = c.pick(v.Value(k), true, ch, nd.scope, keyPath(path, k))
				} else if keep {
					picked, ok = clone(v.Value(k), true), true
				} else {
					c.drop(keyPath(path, k), nd.scope)
				}
				if ok {
					result.Set(k, picked)
				}
			}
			if keep || result.Len() > 0 {
				return result, true
			}
			return nil, false
		}
	}
	if keep {
		return clone(value, present), true
	}
	c.drop(path, nd.scope)
	return nil, false
}

func keyPath(path, key string) string {
	if path == "" {
		return key
	}
	return path + "." + key
}

// itemPath is a list item's path: [its id or name], else its index.
func itemPath(path string, item any, index int) string {
	for _, key := range []string{"id", "name"} {
		if v, ok := schema.Get(item, key).(string); ok && v != "" {
			return path + "[" + v + "]"
		}
	}
	return path + "[" + strconv.Itoa(index) + "]"
}

// merge is the applied value at one place. strict: current is the
// example's item by id or name all the way up, so a personal value not
// taken carries over from it.
func (c *context) merge(current any, curOK bool, example any, exOK bool, n any, scope string, strict bool) (any, bool) {
	value, valueOK := current, curOK
	if exOK {
		value, valueOK = example, true
	}
	nd := c.node(value, valueOK, n, scope)
	if exOK && jsonx.Truthy(schema.Get(nd.schema, "x-monitorRef")) {
		if isMonitorToken(example) {
			return monitorName(example.(string), c.monitors), true
		}
		if list, ok := example.(*jsonx.Array); ok && allTokens(list) {
			// Places to this PC's monitors, those it hasn't left out
			out := jsonx.Arr()
			for _, token := range list.Items {
				if name := monitorName(token.(string), c.monitors); name != "" {
					out.Append(name)
				}
			}
			return out, true
		}
	}
	if !c.keeps(nd.scope) {
		return c.keep(current, curOK, example, exOK, nd, strict)
	}
	if !exOK {
		return clone(current, curOK), true
	}
	switch ex := example.(type) {
	case *jsonx.Array:
		items := schema.Get(nd.schema, "items")
		if !jsonx.Truthy(items) {
			return clone(ex, true), true
		}
		var taken []any
		for _, item := range ex.Items {
			if !c.ownNotKept(item, items, nd.scope) {
				taken = append(taken, item)
			}
		}
		var own []any
		if cur, ok := current.(*jsonx.Array); ok && curOK {
			for _, item := range cur.Items {
				if c.ownNotKept(item, items, nd.scope) {
					own = append(own, item)
				}
			}
		}
		out := jsonx.Arr()
		for i, item := range taken {
			m := match(current, curOK, item, i, taken)
			merged, mok := c.merge(m.item, m.ok, item, true, items, nd.scope, strict && m.strict)
			switch c.monitorMissing(item, items) {
			case "drop":
				continue
			case "off":
				if obj, ok := merged.(*jsonx.Object); ok {
					obj.Set("enabled", false)
				}
			}
			if mok {
				out.Append(merged)
			}
		}
		for _, item := range own {
			out.Append(clone(item, true))
		}
		return out, true
	case *jsonx.Object:
		if jsonx.Truthy(nd.schema) {
			// An item of another type has none of this one's values
			if cur, ok := current.(*jsonx.Object); ok && curOK {
				ct, cHas := cur.Get("type")
				et, eHas := ex.Get("type")
				if cHas != eHas || (cHas && !jsonx.StrictEqual(ct, et)) {
					current, curOK = nil, false
				}
			}
			result := jsonx.NewObject()
			for _, k := range ex.Keys() {
				var merged any
				var ok bool
				if ch := child(nd.schema, k); jsonx.Truthy(ch) {
					cv, cok := getIfObject(current, curOK, k)
					merged, ok = c.merge(cv, cok, ex.Value(k), true, ch, nd.scope, strict)
				} else {
					merged, ok = clone(ex.Value(k), true), true
				}
				if ok {
					result.Set(k, merged)
				}
			}
			return result, true
		}
	}
	return clone(example, true), true
}

// keep is a part not taken from the example: the user's (a personal one
// only from a strict match), or else its default. Its kept parts are still
// taken.
func (c *context) keep(current any, curOK bool, example any, exOK bool, nd node, strict bool) (any, bool) {
	usable := curOK && (nd.scope == "machine" || strict)
	cur, cIsObj := current.(*jsonx.Object)
	ex, eIsObj := example.(*jsonx.Object)
	if cIsObj && curOK && eIsObj && exOK && jsonx.Truthy(nd.schema) && c.carries(nd.schema, nd.scope, 0) {
		// Object.keys(Object.assign({}, current, example))
		union := jsonx.NewObject()
		for _, k := range cur.Keys() {
			union.Set(k, true)
		}
		for _, k := range ex.Keys() {
			union.Set(k, true)
		}
		result := jsonx.NewObject()
		for _, k := range union.Keys() {
			var merged any
			var ok bool
			if ch := child(nd.schema, k); jsonx.Truthy(ch) {
				var cv any
				var cok bool
				if usable {
					cv, cok = cur.Get(k)
				}
				ev, eok := ex.Get(k)
				merged, ok = c.merge(cv, cok, ev, eok, ch, nd.scope, strict)
			} else if usable {
				v, has := cur.Get(k)
				merged, ok = clone(v, has), true
			} else {
				v, has := ex.Get(k)
				merged, ok = clone(v, has), true
			}
			if ok {
				result.Set(k, merged)
			}
		}
		return result, true
	}
	if usable {
		return clone(current, true), true
	}
	if jsonx.Truthy(nd.schema) {
		return config.ApplyDefaults(c.s, nil, false, nd.schema)
	}
	return nil, false
}

type matched struct {
	item   any
	ok     bool
	strict bool
}

// match is the item of list that item (at index in its own list) stands
// for: strict when found by id or name, or for a typed item with neither
// as the same nth of its type.
func match(list any, listOK bool, item any, index int, own []any) matched {
	arr, ok := list.(*jsonx.Array)
	if !ok || !listOK {
		return matched{}
	}
	for _, key := range []string{"id", "name"} {
		value, ok := schema.Get(item, key).(string)
		if !ok || value == "" {
			continue
		}
		for _, other := range arr.Items {
			if v, ok := schema.Get(other, key).(string); ok && v == value {
				return matched{item: other, ok: true, strict: true}
			}
		}
	}
	if typ, ok := schema.Get(item, "type").(string); ok && typ != "" {
		nth := 0
		for _, other := range own[:index] {
			if t, ok := schema.Get(other, "type").(string); ok && t == typ {
				nth++
			}
		}
		var same []any
		for _, other := range arr.Items {
			if t, ok := schema.Get(other, "type").(string); ok && t == typ {
				same = append(same, other)
			}
		}
		if nth < len(same) {
			return matched{item: same[nth], ok: true, strict: true}
		}
		return matched{}
	}
	if index < len(arr.Items) {
		return matched{item: arr.Items[index], ok: true}
	}
	return matched{}
}

var placeToken = regexp.MustCompile(`^#[1-9][0-9]*$`)

// monitorToken is a monitor name as its place, or not ok for one that
// isn't connected. A place stays itself (a shared file picked again).
func monitorToken(name string, monitors Monitors) (any, bool) {
	switch {
	case name == "":
		return "@primary", true
	case isMonitorToken(name):
		return name, true
	}
	for i, m := range monitors {
		if m == name {
			return "#" + strconv.Itoa(i+1), true
		}
	}
	return nil, false
}

func isMonitorToken(v any) bool {
	s, ok := v.(string)
	return ok && (s == "@primary" || s == "*" || placeToken.MatchString(s))
}

// allTokens: a non-empty list of monitor places
func allTokens(list *jsonx.Array) bool {
	for _, v := range list.Items {
		if !isMonitorToken(v) {
			return false
		}
	}
	return list.Len() > 0
}

// monitorName is the user's monitor for a place, "" (the primary) for one
// they don't have.
func monitorName(token string, monitors Monitors) any {
	switch token {
	case "@primary":
		return ""
	case "*":
		return token
	}
	n, _ := strconv.Atoi(token[1:])
	if n-1 >= 0 && n-1 < len(monitors) {
		return monitors[n-1]
	}
	return ""
}

// monitorMissing is what becomes of item when it names only places the
// user has no monitor for: its field's x-monitorRef ("off" or "drop"),
// else "". The field is the item's own (a monitor name), or one of an
// object of it (a ScreenTarget's names).
func (c *context) monitorMissing(item any, items any) string {
	nd := c.node(item, true, items, "")
	return c.missingIn(item, nd.schema, 1)
}

func (c *context) missingIn(value any, n any, depth int) string {
	obj, ok := value.(*jsonx.Object)
	props, pok := schema.Get(n, "properties").(*jsonx.Object)
	if !ok || !pok {
		return ""
	}
	for _, key := range props.Keys() {
		prop := c.s.Resolve(props.Value(key))
		v, has := obj.Get(key)
		if !has || v == nil {
			continue
		}
		rule, _ := schema.Get(prop, "x-monitorRef").(string)
		if rule != "" {
			var places []string
			switch t := v.(type) {
			case string:
				places = []string{t}
			case *jsonx.Array:
				for _, x := range t.Items {
					if s, ok := x.(string); ok {
						places = append(places, s)
					}
				}
			}
			if len(places) > 0 && c.allMissing(places) {
				return rule
			}
			continue
		}
		if depth > 0 {
			if r := c.missingIn(v, prop, depth-1); r != "" {
				return r
			}
		}
	}
	return ""
}

// allMissing: every one of places is a place past the user's monitors
func (c *context) allMissing(places []string) bool {
	for _, p := range places {
		if !placeToken.MatchString(p) {
			return false
		}
		if n, _ := strconv.Atoi(p[1:]); n <= len(c.monitors) {
			return false
		}
	}
	return true
}

func sparse(s *schema.Schema, value any, n any) any {
	ctx := &context{s: s}
	nd := ctx.node(value, true, n, "").schema
	switch v := value.(type) {
	case *jsonx.Array:
		out := jsonx.Arr()
		items := schema.Get(nd, "items")
		for _, item := range v.Items {
			if jsonx.Truthy(items) {
				out.Append(sparse(s, item, items))
			} else {
				out.Append(clone(item, true))
			}
		}
		return out
	case *jsonx.Object:
		if !jsonx.Truthy(nd) {
			return clone(v, true)
		}
		result := jsonx.NewObject()
		for _, k := range v.Keys() {
			ch := child(nd, k)
			if jsonx.Truthy(ch) && k != "type" {
				if def, ok := config.ApplyDefaults(s, nil, false, ch); ok && jsonx.Equal(v.Value(k), def) {
					continue
				}
			}
			if jsonx.Truthy(ch) {
				result.Set(k, sparse(s, v.Value(k), ch))
			} else {
				result.Set(k, clone(v.Value(k), true))
			}
		}
		return result
	}
	return clone(value, true)
}

// --- helpers ---

func isObject(v any) bool {
	_, ok := v.(*jsonx.Object)
	return ok
}

// clone is Utils.clone: a deep copy, null for undefined (present false).
func clone(v any, present bool) any {
	if !present {
		return nil
	}
	return jsonx.Clone(v)
}

// getIfObject is current?.[key] for an object current.
func getIfObject(current any, curOK bool, key string) (any, bool) {
	if obj, ok := current.(*jsonx.Object); ok && curOK {
		return obj.Get(key)
	}
	return nil, false
}

// at is the value at path through objects, not ok when it isn't there.
func at(value any, path []string) (any, bool) {
	for _, key := range path {
		obj, ok := value.(*jsonx.Object)
		if !ok {
			return nil, false
		}
		if value, ok = obj.Get(key); !ok {
			return nil, false
		}
	}
	return value, true
}

// setAt sets the value at path, making the objects on the way.
func setAt(target any, path []string, value any) {
	if parent := makeParents(target, path); parent != nil {
		parent.Set(path[len(path)-1], value)
	}
}

// makeParents makes the objects on the way to path's last key and returns
// the one that holds it.
func makeParents(target any, path []string) *jsonx.Object {
	obj, ok := target.(*jsonx.Object)
	if !ok {
		return nil
	}
	for _, key := range path[:len(path)-1] {
		next, ok := obj.Value(key).(*jsonx.Object)
		if !ok {
			next = jsonx.NewObject()
			obj.Set(key, next)
		}
		obj = next
	}
	return obj
}
