package cli

import (
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// Every named command calls a function the shell has, with as many
// arguments as it takes (docs/dev/generated/ipc.md is generated from the
// IpcTargets).
func TestNamedCommandsMatchTheShellsTargets(t *testing.T) {
	t.Parallel()
	functions := testkit.ShellFunctions(t)
	for _, n := range namedCommands {
		for _, v := range n.verbs {
			want, ok := functions[n.target+"."+v.function]
			if !ok {
				t.Errorf("axiom %s %s calls %s.%s, which the shell doesn't have", n.name, v.name, n.target, v.function)
			} else if want != v.nargs {
				t.Errorf("axiom %s %s passes %d arguments, %s.%s takes %d", n.name, v.name, v.nargs, n.target, v.function, want)
			}
		}
	}
}

// axiom message passes osd.message as many arguments as it takes.
func TestMessageMatchesTheShellsTarget(t *testing.T) {
	t.Parallel()
	args := messageArgs("", "", "info", "text")
	if n, ok := testkit.ShellFunctions(t)["osd.message"]; !ok || n != len(args) {
		t.Errorf("axiom message passes %d arguments, osd.message takes %d (the shell has it: %v)", len(args), n, ok)
	}
}

func TestCommandNamesAreUnique(t *testing.T) {
	t.Parallel()
	seen := map[string]bool{}
	for _, c := range Root().Subs {
		if seen[c.Name] {
			t.Errorf("two commands named %s", c.Name)
		}
		seen[c.Name] = true
	}
}
