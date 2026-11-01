package config

import (
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/migrate/legacy"
	"github.com/axiom-shell/axiom/backend/internal/schema"
)

// Loaded is a parsed config.json after the whole load: migrated, pruned,
// filled with defaults and validated.
type Loaded struct {
	Config  *jsonx.Object
	Removed []string // unknown keys dropped (logged as warnings)
	Changes []string // what the migrations did (logged)
	Errors  []string // why it is invalid; empty when it is valid
	// Migrated says the file was of an older version (written back once)
	Migrated bool
	// FromFormat1 says it was converted from format 1: the file as it was
	// is kept beside it before it's written back (config.format1.json)
	FromFormat1 bool
}

// LoadLegacy runs what the shell's ConfigManager did with a parsed
// format-1 config.json: migrate to v75, prune unknown keys, fill defaults,
// validate, all against s (the v75 schema).
func LoadLegacy(s *schema.Schema, parsed any) (Loaded, error) {
	migration, err := legacy.Migrate(parsed)
	if err != nil {
		return Loaded{}, err
	}
	removed := Prune(s, migration.Config, s.Root())
	filled, _ := ApplyDefaults(s, migration.Config, true, s.Root())
	obj, _ := filled.(*jsonx.Object)
	return Loaded{
		Config:   obj,
		Removed:  removed,
		Changes:  migration.Changes,
		Errors:   ValidationErrors(s, filled, s.Root()),
		Migrated: migration.Migrated,
	}, nil
}
