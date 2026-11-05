package mimeapps

import (
	"reflect"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/schema"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
	axtree "github.com/axiom-shell/axiom/backend/internal/tree"
)

func TestOverridesFrom(t *testing.T) {
	t.Parallel()
	cfg, err := jsonx.Unmarshal([]byte(`{"Apps":{"commands":{"browser":" librewolf ","terminal":"","pdf":"zathura","nope":"x"}}}`))
	if err != nil {
		t.Fatal(err)
	}
	got := OverridesFrom(cfg.(*jsonx.Object))
	want := Overrides{"browser": "librewolf", "pdf": "zathura"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("OverridesFrom = %v; want %v", got, want)
	}
	if got := OverridesFrom(nil); len(got) != 0 {
		t.Errorf("no config: %v", got)
	}
}

// Apps.commands has a command for each role and nothing else, so every
// picker's Custom command… has a setting
func TestRolesMatchTheSchema(t *testing.T) {
	t.Parallel()
	data, err := axtree.BuildSchema(testkit.RepoRoot())
	if err != nil {
		t.Fatal(err)
	}
	root, err := jsonx.Unmarshal(data)
	if err != nil {
		t.Fatal(err)
	}
	s := schema.New(root)
	apps := s.Resolve(schema.Get(schema.Get(s.Root(), "properties"), "Apps"))
	commands := s.Resolve(schema.Get(schema.Get(apps, "properties"), "commands"))
	props, _ := schema.Get(commands, "properties").(*jsonx.Object)
	if props == nil {
		t.Fatal("no Apps.commands properties in the schema")
	}
	var ids []string
	for _, r := range Roles {
		ids = append(ids, r.ID)
	}
	if !reflect.DeepEqual(props.Keys(), ids) {
		t.Errorf("Apps.commands' keys %v; the roles %v", props.Keys(), ids)
	}
}
