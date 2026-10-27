package cli

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// Every named command calls a function the shell has, with as many
// arguments as it takes (docs/dev/generated/ipc.md is generated from the
// IpcTargets).
func TestNamedCommandsMatchTheShellsTargets(t *testing.T) {
	t.Parallel()
	data, err := os.ReadFile(filepath.Join(testkit.RepoRoot(), "docs", "dev", "generated", "ipc.md"))
	if err != nil {
		t.Fatal(err)
	}
	functions := map[string]int{} // "target.fn" → argument count
	target := ""
	fn := regexp.MustCompile("^- `([A-Za-z]+)\\(([^)]*)\\)")
	for _, line := range strings.Split(string(data), "\n") {
		if name, ok := strings.CutPrefix(line, "## "); ok {
			target = strings.TrimSpace(name)
			continue
		}
		if m := fn.FindStringSubmatch(line); m != nil && target != "" {
			n := 0
			if strings.TrimSpace(m[2]) != "" {
				n = strings.Count(m[2], ",") + 1
			}
			functions[target+"."+m[1]] = n
		}
	}
	if len(functions) < 50 {
		t.Fatalf("read only %d functions from ipc.md", len(functions))
	}
	names := map[string]bool{}
	for _, c := range Root().Subs {
		names[c.Name] = true
	}
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
