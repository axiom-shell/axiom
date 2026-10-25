// Package deps tells which of the tools axiom's features use are
// installed (`deps.check`, the shell's DependencyManager): commands on
// $PATH, and python modules ("py:<module>") through python3's importlib,
// all of them in one python3 run.
package deps

import (
	"bytes"
	"context"
	"os/exec"
	"regexp"
	"slices"
	"strings"
	"time"
)

// A name is a command or "py:<module>"; anything else is never looked up
var valid = regexp.MustCompile(`^(py:)?[\w.+-]+$`)

// findModules prints each module of its arguments that python can import
const findModules = `import importlib.util, sys
for m in sys.argv[1:]:
    try:
        found = importlib.util.find_spec(m) is not None
    except Exception:
        found = False
    if found:
        print(m)
`

// Options are how the checks run; zero values are the real ones.
type Options struct {
	LookPath func(file string) (string, error)
	// Python runs python3 (at bin) with args and returns its stdout
	Python func(ctx context.Context, bin string, args ...string) []byte
}

// Check returns the names of commands that are installed, in their order.
func Check(ctx context.Context, commands []string, o Options) []string {
	if o.LookPath == nil {
		o.LookPath = exec.LookPath
	}
	if o.Python == nil {
		o.Python = python
	}
	installed := map[string]bool{}
	var modules []string
	for _, c := range commands {
		if !valid.MatchString(c) {
			continue
		}
		if m, ok := strings.CutPrefix(c, "py:"); ok {
			modules = append(modules, m)
		} else if _, err := o.LookPath(c); err == nil {
			installed[c] = true
		}
	}
	if len(modules) > 0 {
		if bin, err := o.LookPath("python3"); err == nil {
			for _, m := range strings.Fields(string(o.Python(ctx, bin, append([]string{"-c", findModules}, modules...)...))) {
				installed["py:"+m] = true
			}
		}
	}
	var found []string
	for _, c := range commands {
		if installed[c] && !slices.Contains(found, c) {
			found = append(found, c)
		}
	}
	return found
}

func python(ctx context.Context, bin string, args ...string) []byte {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	var out bytes.Buffer
	cmd := exec.CommandContext(ctx, bin, args...)
	cmd.Stdout = &out
	cmd.WaitDelay = time.Second
	cmd.Run()
	return out.Bytes()
}
