// Package deps tells which of the tools axiom's features use are
// installed (`deps.check`, the shell's DependencyManager): commands on
// $PATH.
package deps

import (
	"os/exec"
	"regexp"
	"slices"
)

// A name is a command; anything else is never looked up
var valid = regexp.MustCompile(`^[\w.+-]+$`)

// Options are how the checks run; zero values are the real ones.
type Options struct {
	LookPath func(file string) (string, error)
}

// Check returns the names of commands that are installed, in their order.
func Check(commands []string, o Options) []string {
	if o.LookPath == nil {
		o.LookPath = exec.LookPath
	}
	var found []string
	for _, c := range commands {
		if !valid.MatchString(c) || slices.Contains(found, c) {
			continue
		}
		if _, err := o.LookPath(c); err == nil {
			found = append(found, c)
		}
	}
	return found
}
