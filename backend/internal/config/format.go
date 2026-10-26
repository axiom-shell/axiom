package config

import (
	"fmt"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/migrate/convert"
	"github.com/axiom-shell/axiom/backend/internal/migrate/legacy"
	"github.com/axiom-shell/axiom/backend/internal/migrate/steps"
	"github.com/axiom-shell/axiom/backend/internal/schema"
)

// Pipeline is what the config store does to a file it reads and to a
// config it is asked to write, for one config format.
type Pipeline interface {
	// Load brings a parsed config.json to the current shape: migrated,
	// pruned of unknown keys, filled with defaults and validated (Errors
	// non-empty when invalid). Migrated says it changed shape, so it is
	// written back (Loaded.Migrated).
	Load(parsed any) (Loaded, error)
	// Check fills defaults into a config about to be written and returns
	// it, or the reasons it's invalid. Unknown keys are errors here: a
	// write never silently drops what it was asked to write.
	Check(cfg *jsonx.Object) (*jsonx.Object, []string)
	// Defaults is the config of an empty file.
	Defaults() *jsonx.Object
	// Schema is the schema the pipeline validates against.
	Schema() *schema.Schema
}

// V2Pipeline is format 2 (docs/dev/core/config-v2.md), against the tree's
// schema. It reads format 1 too: such a file goes through the frozen
// migrations to version 75 (against the frozen v75 schema), is converted,
// then loads as format 2 (Loaded.FromFormat1). A format-2 file older than
// steps.Current runs the steps newer than it.
type V2Pipeline struct {
	S *schema.Schema
}

func (p V2Pipeline) Schema() *schema.Schema { return p.S }

func (p V2Pipeline) Load(parsed any) (Loaded, error) {
	obj, ok := parsed.(*jsonx.Object)
	if !ok {
		return Loaded{}, axerr.New(axerr.InvalidConfig, "config.json must hold an object")
	}
	version, _ := obj.Value("version").(float64)
	format, hasFormat := obj.Get("format")
	switch {
	case !hasFormat && version > legacy.LastVersion:
		// Format 1 ends at 75, and format 2 says its format: neither
		return Loaded{Config: obj, Errors: []string{fmt.Sprintf(
			"version: %v without a format: not a config axiom reads (format 1 ends at %d; format 2 says \"format\": %d)", version, legacy.LastVersion, convert.Format)}}, nil
	case !hasFormat:
		old, err := LoadLegacy(schema.New(legacy.Schema()), obj)
		if err != nil {
			return Loaded{}, err
		}
		if len(old.Errors) > 0 {
			// Invalid as format 1: left as it is until it's fixed
			return old, nil
		}
		converted := convert.ToV2(old.Config)
		stepped, _ := steps.Migrate(converted.Config)
		l := p.normalize(converted.Config)
		// The keys format 1's own pass dropped too, so they're logged
		l.Removed = append(old.Removed, l.Removed...)
		l.Changes = append(append(old.Changes, converted.Changes...), stepped...)
		l.Migrated, l.FromFormat1 = true, true
		return l, nil
	case format == 1.0:
		// Format 1 is read by its missing "format", never by a 1
		return Loaded{Config: obj, Errors: []string{fmt.Sprintf(
			"format: 1 isn't written in a config (format 1 has no \"format\" key; format 2 says \"format\": %d)", convert.Format)}}, nil
	case format != float64(convert.Format):
		return Loaded{Config: obj, Errors: []string{fmt.Sprintf(
			"format: %s isn't one this axiom reads (it reads format 1, without a \"format\" key, and \"format\": %d)", jsonx.MarshalCompact(format), convert.Format)}}, nil
	case version > float64(steps.Current()):
		return Loaded{Config: obj, Errors: []string{fmt.Sprintf("version: %v is newer than this axiom knows (%d): update axiom", version, steps.Current())}}, nil
	}
	stepped, migrated := steps.Migrate(obj)
	l := p.normalize(obj)
	l.Changes, l.Migrated = stepped, migrated
	return l, nil
}

// normalize prunes unknown keys, fills defaults and validates.
func (p V2Pipeline) normalize(cfg *jsonx.Object) Loaded {
	removed := Prune(p.S, cfg, p.S.Root())
	filled, _ := ApplyDefaults(p.S, cfg, true, p.S.Root())
	obj, _ := filled.(*jsonx.Object)
	return Loaded{Config: obj, Removed: removed, Errors: ValidationErrors(p.S, filled, p.S.Root())}
}

func (p V2Pipeline) Check(cfg *jsonx.Object) (*jsonx.Object, []string) {
	filled, _ := ApplyDefaults(p.S, cfg, true, p.S.Root())
	obj, _ := filled.(*jsonx.Object)
	if errs := ValidationErrors(p.S, obj, p.S.Root()); len(errs) > 0 {
		return nil, errs
	}
	return obj, nil
}

func (p V2Pipeline) Defaults() *jsonx.Object {
	filled, _ := ApplyDefaults(p.S, jsonx.NewObject(), true, p.S.Root())
	return filled.(*jsonx.Object)
}
