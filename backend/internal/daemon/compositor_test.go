package daemon

import (
	"encoding/json"
	"testing"
)

// compositor.layerRules replies {"ordered": …}, the shell's
// supports.layerOrder
func TestLayerRulesResultShape(t *testing.T) {
	t.Parallel()
	for ordered, want := range map[bool]string{true: `{"ordered":true}`, false: `{"ordered":false}`} {
		got, err := json.Marshal(layerRulesResult{Ordered: ordered})
		if err != nil || string(got) != want {
			t.Errorf("ordered %v: %s, %v; want %s", ordered, got, err, want)
		}
	}
}
