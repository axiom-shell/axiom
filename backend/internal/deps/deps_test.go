package deps

import (
	"context"
	"os/exec"
	"slices"
	"strings"
	"testing"
)

func TestCheck(t *testing.T) {
	t.Parallel()
	installed := []string{"jq", "qalc", "python3", "wl-copy"}
	lookPath := func(c string) (string, error) {
		if slices.Contains(installed, c) {
			return "/usr/bin/" + c, nil
		}
		return "", exec.ErrNotFound
	}
	cases := []struct {
		name     string
		commands []string
		modules  string // what the fake python finds
		want     []string
		python   bool // python3 is run
	}{
		{"commands", []string{"qalc", "satty", "jq"}, "", []string{"qalc", "jq"}, false},
		{"modules in one run", []string{"py:numpy", "jq", "py:PIL", "py:icalendar"}, "numpy\nicalendar\n", []string{"py:numpy", "jq", "py:icalendar"}, true},
		{"invalid names are never looked up", []string{"rm -rf", "../jq", "py:", "wl-copy"}, "", []string{"wl-copy"}, false},
		{"repeats once", []string{"jq", "jq"}, "", []string{"jq"}, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ran := false
			got := Check(context.Background(), tc.commands, Options{LookPath: lookPath,
				Python: func(ctx context.Context, bin string, args ...string) []byte {
					ran = true
					if bin != "/usr/bin/python3" || args[0] != "-c" {
						t.Errorf("python run as %s %q", bin, args)
					}
					return []byte(tc.modules)
				}})
			if !slices.Equal(got, tc.want) {
				t.Errorf("found %q, want %q", got, tc.want)
			}
			if ran != tc.python {
				t.Errorf("python ran: %v", ran)
			}
		})
	}
}

// Without python3, no module is found (and nothing is run).
func TestCheckWithoutPython(t *testing.T) {
	t.Parallel()
	got := Check(context.Background(), []string{"py:numpy"}, Options{
		LookPath: func(string) (string, error) { return "", exec.ErrNotFound },
		Python: func(context.Context, string, ...string) []byte {
			t.Error("ran python")
			return nil
		}})
	if len(got) != 0 {
		t.Errorf("found %q", got)
	}
}

// The script itself, where python3 is installed: a module that exists
// and one that doesn't, and a dotted name whose parent is missing.
func TestFindModulesScript(t *testing.T) {
	t.Parallel()
	bin, err := exec.LookPath("python3")
	if err != nil {
		t.Skip("no python3")
	}
	out := python(context.Background(), bin, "-c", findModules, "json", "nope_not_a_module", "nope.child")
	if got := strings.Fields(string(out)); !slices.Equal(got, []string{"json"}) {
		t.Errorf("found %q", got)
	}
}
