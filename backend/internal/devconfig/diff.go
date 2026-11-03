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
// rows: each config keeps its own. Nor are the takeover settings
// (takeover, share.TakeoverPaths of dev's schema; skipped): they're per
// machine, mirrored dev to live as they change (the daemon's onConfig),
// so they can never be copied.
func Rows(base, live, dev *jsonx.Object, install *schema.Schema, takeover [][]string) []Row {
	var rows []Row
	for _, op := range config.Diff(live, dev) {
		if skipped(op.Path, takeover) {
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
// fails it as a conflict. Like Rows, it leaves out the version, the
// format and the takeover settings.
func Merge(base, live, dev *jsonx.Object, takeover [][]string) []config.Op {
	if base == nil {
		return nil
	}
	var ops []config.Op
	for _, d := range config.Diff(live, dev) {
		if skipped(d.Path, takeover) || !differs(base, live, d.Path) || differs(base, dev, d.Path) {
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
// as it is, its version untouched. The same ops go to the base
// (ShiftBase), so the change isn't taken for live's own. Ops on the
// version or format are refused; so is anything that leaves live invalid,
// live unchanged.
func WriteLive(livePath, basePath string, ops []config.Op, install *schema.Schema) error {
	out, err := writeRaw(livePath, "live", install, func(cfg *jsonx.Object) error { return applyRaw(cfg, ops) })
	if err != nil {
		return err
	}
	return ShiftBase(basePath, ops, out)
}

// WriteDev applies ops to the dev config file as WriteLive does live (the
// install image's copy to dev, with the dev config's file not open): under
// its writer lock (refused while a dev store has it open), on its raw
// JSON, checked against dev (the dev tree's schema), its version
// untouched. Ops' bases, read from dev loaded, aren't checked against the
// raw file (it may leave a default out): the lock stands for them. The
// base is left alone.
func WriteDev(devPath string, ops []config.Op, dev *schema.Schema) error {
	unbased := make([]config.Op, len(ops))
	for i, op := range ops {
		op.Base = config.Op{}.Base
		unbased[i] = op
	}
	_, err := writeRaw(devPath, "dev", dev, func(cfg *jsonx.Object) error { return applyRaw(cfg, unbased) })
	return err
}

// ReplaceDev makes the dev config file cfg (live, in dev's shape) as
// WriteDev writes it, keeping the file's own version and format.
func ReplaceDev(devPath string, cfg *jsonx.Object, dev *schema.Schema) error {
	_, err := writeRaw(devPath, "dev", dev, func(raw *jsonx.Object) error {
		next := jsonx.Clone(cfg).(*jsonx.Object)
		for _, k := range []string{"format", "version"} {
			if v, has := raw.Get(k); has {
				next.Set(k, v)
			} else {
				next.Delete(k)
			}
		}
		*raw = *next
		return nil
	})
	return err
}

// writeRaw changes a config file (what names it in errors) under its
// writer lock, on its raw JSON: change's result is checked against s
// (defaults filled only for the check) and written as it is, unless it's
// unchanged. It returns the file's bytes after.
func writeRaw(path, what string, s *schema.Schema, change func(*jsonx.Object) error) ([]byte, error) {
	if !fsx.IsFile(path) {
		return nil, axerr.New(axerr.NotFound, "there is no %s config at %s", what, path)
	}
	lock, err := lockFor(path)
	if err != nil {
		return nil, err
	}
	defer lock.Release()
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, axerr.Wrap(axerr.Unavailable, err, "reading %s", path)
	}
	current, err := parse(raw)
	if err != nil {
		return nil, axerr.Wrap(axerr.InvalidConfig, err, "reading %s", path)
	}
	next := jsonx.Clone(current).(*jsonx.Object)
	if err := change(next); err != nil {
		return nil, err
	}
	if _, problems := (config.Pipeline{S: s}).Check(next); len(problems) > 0 {
		return nil, &axerr.Error{Kind: axerr.InvalidConfig, Message: "the change makes the " + what + " config invalid", Issues: axerr.IssuesFrom(problems)}
	}
	if jsonx.Equal(next, current) {
		return raw, nil
	}
	out := jsonx.Marshal(next)
	return out, writeFile(path, out)
}

// applyRaw applies ops to a raw config: the version and format refused, a
// delete of what the file leaves out (a default) skipped.
func applyRaw(cfg *jsonx.Object, ops []config.Op) error {
	var apply []config.Op
	for _, op := range ops {
		if len(op.Path) == 0 || ownKey(op.Path) {
			return axerr.New(axerr.BadRequest, "%q: each config keeps its own version and format", op.Path.String())
		}
		if _, has := config.Lookup(cfg, op.Path); op.Op == "delete" && !has {
			continue
		}
		apply = append(apply, op)
	}
	return config.ApplyOps(cfg, apply)
}

// ShiftBase applies ops to the base too (a copy to live), so the change
// isn't taken for live's own: the new live bytes when there is no base or
// the ops don't apply to it.
func ShiftBase(basePath string, ops []config.Op, live []byte) error {
	return writeFile(basePath, nextBase(basePath, ops, live))
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
	if err := applyRaw(base, ops); err != nil {
		return live
	}
	return jsonx.Marshal(base)
}

// ownKey says a path is a config's version or format, which dev and live
// each keep their own of.
func ownKey(path config.Path) bool {
	return len(path) > 0 && path[0].ID == "" && (path[0].Key == "version" || path[0].Key == "format")
}

// skipped says a path is never a row or merged: a config's version or
// format, a takeover setting, under one, or a section holding one (one
// side lacks it whole: loaded configs have every section, so it's rare).
func skipped(path config.Path, takeover [][]string) bool {
	if ownKey(path) {
		return true
	}
	for _, tp := range takeover {
		if p := config.Keys(tp...); under(path, p) || under(p, path) {
			return true
		}
	}
	return false
}

// under says path is prefix or under it.
func under(path, prefix config.Path) bool {
	if len(prefix) > len(path) {
		return false
	}
	for i, s := range prefix {
		if path[i] != s {
			return false
		}
	}
	return true
}

// differs says a and b don't hold the same value at path (one holding
// none counts).
func differs(a, b *jsonx.Object, path config.Path) bool {
	va, hasA := config.Lookup(a, path)
	vb, hasB := config.Lookup(b, path)
	return hasA != hasB || (hasA && !jsonx.Equal(va, vb))
}
