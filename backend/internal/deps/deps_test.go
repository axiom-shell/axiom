package deps

import (
	"os/exec"
	"slices"
	"testing"
)

func TestCheck(t *testing.T) {
	t.Parallel()
	installed := []string{"jq", "qalc", "wl-copy"}
	lookPath := func(c string) (string, error) {
		if slices.Contains(installed, c) {
			return "/usr/bin/" + c, nil
		}
		return "", exec.ErrNotFound
	}
	cases := []struct {
		name     string
		commands []string
		want     []string
	}{
		{"commands", []string{"qalc", "satty", "jq"}, []string{"qalc", "jq"}},
		{"invalid names are never looked up", []string{"rm -rf", "../jq", "py:gi", "wl-copy"}, []string{"wl-copy"}},
		{"repeats once", []string{"jq", "jq"}, []string{"jq"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := Check(tc.commands, Options{LookPath: lookPath}); !slices.Equal(got, tc.want) {
				t.Errorf("found %q, want %q", got, tc.want)
			}
		})
	}
}
