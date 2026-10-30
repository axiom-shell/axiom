package cli

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// `config share` answers what the community setups' checks read: the file
// as Export writes it (any format in, the header kept), what it left out
// by scope, or invalid_config with the problems (exit 1).
func TestConfigShare(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name, file string
		places     bool
		code       int
		dropped    []string
		theme      string
	}{
		{"look only", `{"format": 2, "version": 76, "meta": {"title": "T", "description": "D"},
			"Appearance": {"theme": {"name": "nord"}}, "Apps": {"terminal": "foot"}, "Compositor": {"mode": "managed"}}`,
			false, 0, []string{"commands Apps.terminal", "takeover Compositor.mode"}, "nord"},
		{"places", `{"format": 2, "version": 76, "meta": {"title": "T", "description": "D"},
			"Bars": {"items": [{"id": "side", "screen": {"mode": "named", "names": ["#2", "HDMI-A-1"]}}]}}`,
			true, 0, []string{"machine Bars.items[side].screen.names[1]"}, ""},
		{"format 1", `{"_example": {"title": "T", "description": "D"}, "version": 74, "Appearance": {"theme": "nord"}}`,
			false, 0, []string{}, "nord"},
		{"invalid", `{"format": 2, "version": 76, "Bars": {"items": "x"}}`, false, 1, nil, ""},
		{"no version", `{"Appearance": {}}`, false, 1, nil, ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			file := filepath.Join(t.TempDir(), "setup.json")
			if err := os.WriteFile(file, []byte(tc.file), 0o644); err != nil {
				t.Fatal(err)
			}
			args := []string{"config", "share", "--json", "--tree", testkit.RepoRoot(), file}
			if tc.places {
				args = append(args, "--places")
			}
			code, stdout, stderr := run(t, Root(), args...)
			if code != tc.code {
				t.Fatalf("exit %d, want %d: %s %s", code, tc.code, stdout, stderr)
			}
			var answer struct {
				Valid  bool `json:"valid"`
				Format int  `json:"format"`
				Config struct {
					Meta struct {
						Title string `json:"title"`
					} `json:"meta"`
					Appearance struct {
						Theme struct {
							Name string `json:"name"`
						} `json:"theme"`
					} `json:"Appearance"`
				} `json:"config"`
				Dropped []struct{ Path, Scope string } `json:"dropped"`
				Error   struct {
					Kind   string `json:"kind"`
					Issues []any  `json:"issues"`
				} `json:"error"`
			}
			if err := json.Unmarshal([]byte(stdout), &answer); err != nil {
				t.Fatalf("not JSON: %v: %s", err, stdout)
			}
			if tc.code != 0 {
				if answer.Error.Kind != "invalid_config" || len(answer.Error.Issues) == 0 && tc.name == "invalid" {
					t.Errorf("error %+v", answer.Error)
				}
				return
			}
			if !answer.Valid || answer.Format != 2 || answer.Config.Meta.Title != "T" || answer.Config.Appearance.Theme.Name != tc.theme {
				t.Errorf("answer %s", stdout)
			}
			got := []string{}
			for _, d := range answer.Dropped {
				got = append(got, d.Scope+" "+d.Path)
			}
			if !reflect.DeepEqual(got, tc.dropped) {
				t.Errorf("dropped %v, want %v", got, tc.dropped)
			}
		})
	}
}
