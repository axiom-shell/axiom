package legacy

import (
	"crypto/sha256"
	"encoding/hex"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// The cases recorded from the shell before ConfigMigration.qml went: the
// frozen code run here must still give V4's bytes exactly.
func TestFrozenMigrateCases(t *testing.T) {
	t.Parallel()
	for _, c := range testkit.Frozen(t, "migrate") {
		t.Run(c.Name, func(t *testing.T) {
			t.Parallel()
			res, err := Migrate(c.Input)
			if err != nil {
				t.Fatal(err)
			}
			changes := jsonx.Arr()
			for _, ch := range res.Changes {
				changes.Append(ch)
			}
			// legacy.js's secrets were always empty
			c.Check(t, jsonx.Obj("config", res.Config, "secrets", jsonx.NewObject(), "changes", changes, "migrated", res.Migrated))
		})
	}
}

// legacy.js is the shell's migrations converted once, and never edited.
func TestScriptIsFrozen(t *testing.T) {
	t.Parallel()
	const frozen = "9e1c4cdb9f0952ab1e3b82b4f5ee9c6f22321a057a74d85353b4f82bbd05f957"
	if sum := sha256.Sum256([]byte(source)); hex.EncodeToString(sum[:]) != frozen {
		t.Error("legacy.js changed: the format-1 migrations are frozen (docs/recipes/migration.md)")
	}
}

// The version-75 schema is the last format-1 one, as committed before the
// binary took over (main's eb39e97): frozen with the migrations.
func TestSchemaIsFrozen(t *testing.T) {
	t.Parallel()
	const frozen = "64f7fa83036167d915d7b231001a4cac598573d921ed59116e6f7712376d2b0d"
	if sum := sha256.Sum256(schemaV75); hex.EncodeToString(sum[:]) != frozen {
		t.Error("schema-v75.json changed: it's frozen with the format-1 migrations")
	}
	if Schema().Value("properties").(*jsonx.Object).Value("version").(*jsonx.Object).Value("default") != float64(LastVersion) {
		t.Error("schema-v75.json isn't version 75's")
	}
}
