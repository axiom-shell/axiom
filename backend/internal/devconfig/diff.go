package devconfig

import (
	"encoding/json"
	"os"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/schema"
)

// The sides of a Row: where the setting changed since the base
const (
	SideDev  = "dev"
	SideLive = "live"
	SideBoth = "both"
)

// Row is one setting dev and live disagree on.
type Row struct {
	Path config.Path
	// Side is SideDev, SideLive or SideBoth: which of them changed it since
	// the base
	Side string
	// The values in each (Has false: the key isn't there)
	Dev, Live       any
	HasDev, HasLive bool
	// DevOnly: the install's schema has no such setting, so it can't go
	// to live
	DevOnly bool
}

// MarshalJSON writes a row for the shell: a missing value is left out.
func (r Row) MarshalJSON() ([]byte, error) {
	m := map[string]any{"path": r.Path, "side": r.Side, "devOnly": r.DevOnly}
	if r.HasDev {
		m["dev"] = json.RawMessage(jsonx.MarshalCompact(r.Dev))
	}
	if r.HasLive {
		m["live"] = json.RawMessage(jsonx.MarshalCompact(r.Live))
	}
	return json.Marshal(m)
}

// Rows is every setting dev and live differ on, base, live and dev all in
// dev's shape (InShape through the dev pipeline): config.Diff's paths (a
// list whole, objects followed down to what changed), each with the side
// that changed it since the base (a nil base: both) and whether install
// (the install tree's schema) lacks it. The version and format are never
// rows: each config keeps its own.
func Rows(base, live, dev *jsonx.Object, install *schema.Schema) []Row {
	var rows []Row
	for _, op := range config.Diff(live, dev) {
		if ownKey(op.Path) {
			continue
		}
		d, hasD := config.Lookup(dev, op.Path)
		l, hasL := config.Lookup(live, op.Path)
		row := Row{Path: op.Path, Dev: d, HasDev: hasD, Live: l, HasLive: hasL}
		devChanged, liveChanged := true, true
		if base != nil {
			devChanged, liveChanged = differs(base, dev, op.Path), differs(base, live, op.Path)
		}
		switch {
		case devChanged && liveChanged:
			row.Side = SideBoth
		case liveChanged:
			row.Side = SideLive
		default:
			row.Side = SideDev
		}
		// dev's values tell the schema's oneOf options apart: it's dev's
		// value that would go to live
		_, known := config.NodeAt(install, dev, op.Path)
		row.DevOnly = !known
		rows = append(rows, row)
	}
	return rows
}

// Merge is the ops that bring live's changes since the base into dev
// where dev left the setting as the base had it: the non-conflicting half
// of a three-way merge (a setting changed on both sides is left alone).
// Each carries dev's value as its base, so a dev edit made meanwhile
// fails it as a conflict.
func Merge(base, live, dev *jsonx.Object) []config.Op {
	if base == nil {
		return nil
	}
	var ops []config.Op
	for _, d := range config.Diff(live, dev) {
		if ownKey(d.Path) || !differs(base, live, d.Path) || differs(base, dev, d.Path) {
			continue
		}
		var op config.Op
		if l, has := config.Lookup(live, d.Path); has {
			op = config.SetValue(d.Path, jsonx.Clone(l))
		} else {
			op = config.Op{Op: "delete", Path: d.Path}
		}
		if v, has := config.Lookup(dev, d.Path); has {
			op = op.WithBase(jsonx.Clone(v))
		}
		ops = append(ops, op)
	}
	return ops
}

// WriteLive applies ops to the live config file under its writer lock
// (refused while a store has it open: dev isn't active), on its raw JSON,
// never loaded or migrated: the result is checked against install (the
// install tree's schema, defaults filled only for the check) and written
// as it is, its version untouched. The same ops go to the base, so the
// change isn't taken for live's own. Ops on the version or format are
// refused; so is anything that leaves live invalid, live unchanged.
func WriteLive(livePath, basePath string, ops []config.Op, install *schema.Schema) error {
	for _, op := range ops {
		if len(op.Path) == 0 || ownKey(op.Path) {
			return axerr.New(axerr.BadRequest, "%q: the live config keeps its own version and format", op.Path.String())
		}
	}
	if !fsx.IsFile(livePath) {
		return axerr.New(axerr.NotFound, "there is no live config at %s", livePath)
	}
	lock, err := lockFor(livePath)
	if err != nil {
		return err
	}
	defer lock.Release()
	raw, err := os.ReadFile(livePath)
	if err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "reading %s", livePath)
	}
	live, err := parse(raw)
	if err != nil {
		return axerr.Wrap(axerr.InvalidConfig, err, "reading %s", livePath)
	}
	next := jsonx.Clone(live).(*jsonx.Object)
	if err := config.ApplyOps(next, ops); err != nil {
		return err
	}
	if _, problems := (config.Pipeline{S: install}).Check(next); len(problems) > 0 {
		return &axerr.Error{Kind: axerr.InvalidConfig, Message: "the change makes the live config invalid", Issues: axerr.IssuesFrom(problems)}
	}
	out := jsonx.Marshal(next)
	if !jsonx.Equal(next, live) {
		if err := writeFile(livePath, out); err != nil {
			return err
		}
	}
	return writeFile(basePath, nextBase(basePath, ops, out))
}

// nextBase is the base with ops applied, or the new live bytes when there
// is no base or the ops don't apply to it.
func nextBase(basePath string, ops []config.Op, live []byte) []byte {
	raw, err := os.ReadFile(basePath)
	if err != nil {
		return live
	}
	base, err := parse(raw)
	if err != nil {
		return live
	}
	if err := config.ApplyOps(base, ops); err != nil {
		return live
	}
	return jsonx.Marshal(base)
}

// ownKey says a path is a config's version or format, which dev and live
// each keep their own of.
func ownKey(path config.Path) bool {
	return len(path) > 0 && path[0].ID == "" && (path[0].Key == "version" || path[0].Key == "format")
}

// differs says a and b don't hold the same value at path (one holding
// none counts).
func differs(a, b *jsonx.Object, path config.Path) bool {
	va, hasA := config.Lookup(a, path)
	vb, hasB := config.Lookup(b, path)
	return hasA != hasB || (hasA && !jsonx.Equal(va, vb))
}
