package daemon

import (
	"encoding/json"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/schema"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"github.com/axiom-shell/axiom/backend/internal/tree"
	"github.com/axiom-shell/axiom/backend/internal/windowrules"
)

// compositor.checkRules fills a partial draft with the schema's defaults
// before checking it: a new rule's `enabled` is true and its condition's
// `op` is `is` only after that, so it has no issue and is usable
func TestFillWindowRules(t *testing.T) {
	t.Parallel()
	data, err := tree.BuildSchema(testkit.RepoRoot())
	if err != nil {
		t.Fatal(err)
	}
	parsed, err := jsonx.Unmarshal(data)
	if err != nil {
		t.Fatal(err)
	}
	s := schema.New(parsed)
	draft := json.RawMessage(`{"rules":[{"id":"a","windows":[{"conditions":[{"field":"appId","value":"x"}]}],"window":{"float":true}}]}`)
	filled, err := fillWindowRules(s, draft)
	if err != nil {
		t.Fatal(err)
	}
	cfg := windowrules.Parse(filled)
	issues := windowrules.Validate(cfg, windowrules.Context{})
	if len(issues) != 0 {
		t.Errorf("issues: %+v", issues)
	}
	if usable := windowrules.Usable(cfg, issues); len(usable) != 1 || !usable[0].Enabled || usable[0].Kinds[0].Conditions[0].Op != "is" {
		t.Errorf("usable: %+v", usable)
	}
	if _, err := fillWindowRules(s, json.RawMessage(`{`)); err == nil {
		t.Error("a broken section was taken")
	}
}
