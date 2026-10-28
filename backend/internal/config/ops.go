package config

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// Op is one change to the config: set a value, delete a key, or reorder
// a list's items. Paths name keys, and items of a list by their id
// (a segment {"id": "…"}): never by position, which a concurrent edit
// shifts. With Base, the op only applies while the value there still is
// Base (else a conflict, and the editor reloads).
type Op struct {
	Op    string    `json:"op"` // "set" | "delete" | "order"
	Path  Path      `json:"path"`
	Value jsonValue `json:"value"`
	Base  jsonValue `json:"base"`
}

// MarshalJSON leaves out what isn't given: a base of null means "expect
// null", so an absent one must stay absent.
func (o Op) MarshalJSON() ([]byte, error) {
	m := map[string]any{"op": o.Op, "path": o.Path}
	if o.Value.Set {
		m["value"] = o.Value
	}
	if o.Base.Set {
		m["base"] = o.Base
	}
	return json.Marshal(m)
}

// Segment is one step of a path: a key, or an item of a list by id.
type Segment struct {
	Key string
	ID  string
}

func (s Segment) String() string {
	if s.ID != "" {
		return "{id:" + s.ID + "}"
	}
	return s.Key
}

// Path is a list of segments.
type Path []Segment

func (p Path) String() string {
	parts := make([]string, len(p))
	for i, s := range p {
		parts[i] = s.String()
	}
	return strings.Join(parts, ".")
}

// UnmarshalJSON reads ["Bars", "items", {"id": "main"}, "location"].
func (p *Path) UnmarshalJSON(data []byte) error {
	var raw []json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return fmt.Errorf("a path is a list of keys and {id} selectors")
	}
	out := make(Path, 0, len(raw))
	for _, r := range raw {
		var key string
		if err := json.Unmarshal(r, &key); err == nil {
			out = append(out, Segment{Key: key})
			continue
		}
		var sel struct {
			ID *string `json:"id"`
		}
		if err := json.Unmarshal(r, &sel); err == nil && sel.ID != nil && *sel.ID != "" {
			out = append(out, Segment{ID: *sel.ID})
			continue
		}
		return fmt.Errorf("path segment %s is neither a key nor {\"id\": …} (positions aren't accepted)", r)
	}
	*p = out
	return nil
}

// MarshalJSON writes the path back as keys and {id} selectors.
func (p Path) MarshalJSON() ([]byte, error) {
	out := make([]any, len(p))
	for i, s := range p {
		if s.ID != "" {
			out[i] = map[string]string{"id": s.ID}
		} else {
			out[i] = s.Key
		}
	}
	return json.Marshal(out)
}

// jsonValue is a JSON value read into the ordered tree, remembering
// whether it was given at all.
type jsonValue struct {
	V   any
	Set bool
}

func (j *jsonValue) UnmarshalJSON(data []byte) error {
	v, err := jsonx.Unmarshal(data)
	if err != nil {
		return err
	}
	j.V, j.Set = v, true
	return nil
}

func (j jsonValue) MarshalJSON() ([]byte, error) {
	if !j.Set {
		return []byte("null"), nil
	}
	return jsonx.MarshalCompact(j.V), nil
}

// SetValue is an Op setting path to v.
func SetValue(path Path, v any) Op {
	return Op{Op: "set", Path: path, Value: jsonValue{V: v, Set: true}}
}

// Keys is a path of plain keys.
func Keys(keys ...string) Path {
	p := make(Path, len(keys))
	for i, k := range keys {
		p[i] = Segment{Key: k}
	}
	return p
}

// ApplyOps applies ops to cfg in place, in order. Any failure leaves cfg
// partly changed: apply to a copy.
func ApplyOps(cfg *jsonx.Object, ops []Op) error {
	for i, op := range ops {
		if err := applyOp(cfg, op); err != nil {
			return fmt.Errorf("op %d (%s %s): %w", i, op.Op, op.Path, err)
		}
	}
	return nil
}

func applyOp(cfg *jsonx.Object, op Op) error {
	if len(op.Path) == 0 {
		return axerr.New(axerr.BadRequest, "an empty path")
	}
	parent, err := walk(cfg, op.Path[:len(op.Path)-1], op.Op == "set")
	if err != nil {
		return err
	}
	last := op.Path[len(op.Path)-1]
	current, has := get(parent, last)
	if op.Base.Set && (!has || !jsonx.Equal(current, op.Base.V)) {
		return axerr.New(axerr.Conflict, "changed since it was read")
	}
	switch op.Op {
	case "set":
		if !op.Value.Set {
			return axerr.New(axerr.BadRequest, "set needs a value")
		}
		return set(parent, last, jsonx.Clone(op.Value.V))
	case "delete":
		if !has {
			return nil
		}
		return remove(parent, last)
	case "order":
		list, ok := current.(*jsonx.Array)
		if !has || !ok {
			return axerr.New(axerr.BadRequest, "order applies to a list")
		}
		ids, ok := op.Value.V.(*jsonx.Array)
		if !op.Value.Set || !ok {
			return axerr.New(axerr.BadRequest, "order needs the list's ids, in their new order")
		}
		return reorder(list, ids)
	}
	return axerr.New(axerr.BadRequest, "unknown op %q", op.Op)
}

// walk follows path from cfg, making missing objects when create.
func walk(cfg *jsonx.Object, path Path, create bool) (any, error) {
	var node any = cfg
	for _, seg := range path {
		next, has := get(node, seg)
		if !has {
			if !create || seg.ID != "" {
				return nil, axerr.New(axerr.NotFound, "%s isn't there", seg)
			}
			obj, ok := node.(*jsonx.Object)
			if !ok {
				return nil, axerr.New(axerr.BadRequest, "%s: not an object", seg)
			}
			next = jsonx.NewObject()
			obj.Set(seg.Key, next)
		}
		node = next
	}
	return node, nil
}

func get(node any, seg Segment) (any, bool) {
	if seg.ID != "" {
		list, ok := node.(*jsonx.Array)
		if !ok {
			return nil, false
		}
		i := indexOf(list, seg.ID)
		if i < 0 {
			return nil, false
		}
		return list.Items[i], true
	}
	obj, ok := node.(*jsonx.Object)
	if !ok {
		return nil, false
	}
	return obj.Get(seg.Key)
}

func set(parent any, seg Segment, v any) error {
	if seg.ID != "" {
		list, ok := parent.(*jsonx.Array)
		if !ok {
			return axerr.New(axerr.BadRequest, "%s: not a list", seg)
		}
		if item, ok := v.(*jsonx.Object); !ok || item.Value("id") != seg.ID {
			return axerr.New(axerr.BadRequest, "an item set by id must be an object with that id")
		}
		if i := indexOf(list, seg.ID); i >= 0 {
			list.Items[i] = v
		} else {
			list.Append(v)
		}
		return nil
	}
	obj, ok := parent.(*jsonx.Object)
	if !ok {
		return axerr.New(axerr.BadRequest, "%s: not an object", seg)
	}
	obj.Set(seg.Key, v)
	return nil
}

func remove(parent any, seg Segment) error {
	if seg.ID != "" {
		list := parent.(*jsonx.Array)
		i := indexOf(list, seg.ID)
		list.Items = append(list.Items[:i:i], list.Items[i+1:]...)
		return nil
	}
	parent.(*jsonx.Object).Delete(seg.Key)
	return nil
}

func reorder(list *jsonx.Array, ids *jsonx.Array) error {
	if len(ids.Items) != len(list.Items) {
		return axerr.New(axerr.Conflict, "the list has %d items, the order names %d", len(list.Items), len(ids.Items))
	}
	out := make([]any, 0, len(list.Items))
	used := map[string]bool{}
	for _, v := range ids.Items {
		id, _ := v.(string)
		i := indexOf(list, id)
		if i < 0 || used[id] {
			return axerr.New(axerr.Conflict, "the order names %q, which isn't in the list once", id)
		}
		used[id] = true
		out = append(out, list.Items[i])
	}
	list.Items = out
	return nil
}

func indexOf(list *jsonx.Array, id string) int {
	for i, item := range list.Items {
		if obj, ok := item.(*jsonx.Object); ok && obj.Value("id") == id {
			return i
		}
	}
	return -1
}

// Diff is the ops that turn before into after: a set for each value that
// differs (a list whole, never by id) and a delete for each key gone,
// objects followed down to what changed. Applied to before, they give
// after (its key order apart).
func Diff(before, after *jsonx.Object) []Op {
	return diff(nil, before, after, nil)
}

func diff(path Path, before, after *jsonx.Object, ops []Op) []Op {
	for _, key := range before.Keys() {
		if !after.Has(key) {
			ops = append(ops, Op{Op: "delete", Path: appendKey(path, key)})
		}
	}
	for _, key := range after.Keys() {
		next := after.Value(key)
		prev, has := before.Get(key)
		prevObj, wasObj := prev.(*jsonx.Object)
		nextObj, isObj := next.(*jsonx.Object)
		switch {
		case has && wasObj && isObj:
			ops = diff(appendKey(path, key), prevObj, nextObj, ops)
		case !has || !jsonx.Equal(prev, next):
			ops = append(ops, SetValue(appendKey(path, key), jsonx.Clone(next)))
		}
	}
	return ops
}

// appendKey is path and key, in a new slice (ops keep their paths).
func appendKey(path Path, key string) Path {
	return append(append(make(Path, 0, len(path)+1), path...), Segment{Key: key})
}
