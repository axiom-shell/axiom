package uninstall

import (
	"context"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
)

// stopBound is how long Stop waits for a daemon and its guard to end.
const stopBound = 15 * time.Second

// runtimeRoot is <runtime folder>/axiom ("" without a runtime folder).
func (o Options) runtimeRoot() string {
	if rt := o.runtimeDir(); rt != "" {
		return filepath.Join(rt, "axiom")
	}
	return ""
}

// displays are the names of the display folders in the runtime root.
func (o Options) displays() []string {
	root := o.runtimeRoot()
	if root == "" {
		return nil
	}
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil
	}
	var out []string
	for _, e := range entries {
		if e.IsDir() {
			out = append(out, e.Name())
		}
	}
	return out
}

// running are the displays a daemon runs on (it holds the display's
// daemon.lock), or a guard still runs for (guard.lock), but the one the plan
// is made by.
func (o Options) running() []string {
	return o.stillHeldBut(o.displays(), o.ExcludeDisplay)
}

// stillHeld are the displays whose daemon.lock or guard.lock is held.
func (o Options) stillHeld(displays []string) []string { return o.stillHeldBut(displays, "") }

func (o Options) stillHeldBut(displays []string, but string) []string {
	var out []string
	for _, d := range displays {
		if d == but {
			continue
		}
		dir := filepath.Join(o.runtimeRoot(), d)
		if fsx.Held(filepath.Join(dir, "daemon.lock")) || fsx.Held(filepath.Join(dir, "guard.lock")) {
			out = append(out, d)
		}
	}
	return out
}

// RunningError is the refusal when axiom runs.
func RunningError(displays []string) error { return runningError(displays) }

func runningError(displays []string) error {
	return axerr.New(axerr.Running, "axiom runs on %s: quit it, or pass --stop", strings.Join(displays, ", "))
}

// Stop quits the daemons that run (Options.Shutdown, on each display's
// socket), then waits for them and their guards to let go of their locks
// (a daemon runs its teardown first), up to 15 s.
func Stop(ctx context.Context, o Options) error {
	o = o.withDefaults()
	displays := o.running()
	if len(displays) == 0 {
		return nil
	}
	if o.Shutdown == nil {
		return runningError(displays)
	}
	for _, d := range displays {
		socket := filepath.Join(o.runtimeRoot(), d, "axiom.sock")
		if err := o.Shutdown(ctx, socket); err != nil {
			// A daemon that doesn't answer may still be on its way out
			o.Log.Warn("uninstall: asking axiom on "+d+" to quit", "err", err)
		}
	}
	deadline := time.Now().Add(stopBound)
	for {
		held := o.stillHeld(displays)
		if len(held) == 0 {
			return nil
		}
		if time.Now().After(deadline) || ctx.Err() != nil {
			slices.Sort(held)
			return axerr.New(axerr.Running, "axiom on %s didn't stop in %s", strings.Join(held, ", "), stopBound)
		}
		select {
		case <-ctx.Done():
		case <-time.After(50 * time.Millisecond):
		}
	}
}
