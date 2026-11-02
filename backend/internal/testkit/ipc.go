package testkit

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

var ipcFunction = regexp.MustCompile("^- `([A-Za-z]+)\\(([^)]*)\\)")

// ShellFunctions reads every IPC function from docs/dev/generated/ipc.md
// (generated from the shell's IpcTargets): "target.fn" → its argument
// count. The named commands' and the keybind actions' tests check their
// calls against it.
func ShellFunctions(t testing.TB) map[string]int {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(RepoRoot(), "docs", "dev", "generated", "ipc.md"))
	if err != nil {
		t.Fatal(err)
	}
	functions := map[string]int{}
	target := ""
	for _, line := range strings.Split(string(data), "\n") {
		if name, ok := strings.CutPrefix(line, "## "); ok {
			target = strings.TrimSpace(name)
			continue
		}
		if m := ipcFunction.FindStringSubmatch(line); m != nil && target != "" {
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
	return functions
}
