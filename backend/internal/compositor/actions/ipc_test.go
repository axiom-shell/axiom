package actions

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// Every action's IPC call, with each of its calls, is a function the shell
// has, with as many arguments as it takes (docs/dev/generated/ipc.md is
// generated from the IpcTargets), as named_test checks the named commands.
func TestIPCActionsMatchTheShellsTargets(t *testing.T) {
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
	tables, err := Tables()
	if err != nil {
		t.Fatal(err)
	}
	ipc, _ := tables.Value("ipcActions").(*jsonx.Object)
	calls, _ := tables.Value("calls").(*jsonx.Object)
	for _, action := range ipc.Keys() {
		entry, _ := ipc.Value(action).(*jsonx.Array)
		words := strings.Fields(entry.Items[0].(string))
		fns := []string{words[1]}
		if words[1] == "{call}" {
			fns = []string{"toggle"}
			if own, _ := calls.Value(action).(*jsonx.Object); own != nil {
				for _, k := range own.Keys() {
					fns = append(fns, own.Value(k).(string))
				}
			}
		}
		for _, f := range fns {
			want, ok := functions[words[0]+"."+f]
			if !ok {
				t.Errorf("%s calls %s.%s, which the shell doesn't have", action, words[0], f)
			} else if got := len(words) - 2; got != want {
				t.Errorf("%s passes %d arguments, %s.%s takes %d", action, got, words[0], f, want)
			}
		}
	}
}
