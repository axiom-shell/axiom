package cli

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/tree"
)

// `schema check` fails while config/json/config.schema.json is missing or
// stale, and passes once it's built.
func TestSchemaCheckNeedsTheBuiltSchema(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	for name, content := range map[string]string{
		"shell.qml":                        "",
		"config/schema/index.yaml":         "type: object\nproperties: {}\nsections: [S]\n",
		"config/schema/annotations.yaml":   "x-order: \"\"\n",
		"config/schema/sections/S.yaml":    "type: object\nproperties:\n  a: {type: integer}\n",
		"config/schema/definitions/D.yaml": "type: object\n",
	} {
		path := filepath.Join(dir, name)
		os.MkdirAll(filepath.Dir(path), 0o755)
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	check := func() error {
		e := &Env{Stdout: &bytes.Buffer{}, Stderr: &bytes.Buffer{}, Getenv: func(string) string { return "" }}
		return dispatch(context.Background(), Root(), []string{"axiom"}, []string{"schema", "check", "--tree", dir}, e)
	}
	if err := check(); axerr.KindOf(err) != axerr.NotFound {
		t.Errorf("missing: %v", err)
	}
	built := filepath.Join(dir, tree.SchemaJSON)
	os.MkdirAll(filepath.Dir(built), 0o755)
	os.WriteFile(built, []byte("{}\n"), 0o644)
	if err := check(); axerr.KindOf(err) != axerr.InvalidConfig {
		t.Errorf("stale: %v", err)
	}
	data, err := tree.BuildSchema(dir)
	if err != nil {
		t.Fatal(err)
	}
	os.WriteFile(built, data, 0o644)
	if err := check(); err != nil {
		t.Errorf("fresh: %v", err)
	}
}
