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

// runtimeRoot is $XDG_RUNTIME_DIR/axiom ("" without a runtime folder).
func (o Options) runtimeRoot() string {
	rt := o.Getenv("XDG_RUNTIME_DIR")
	if !filepath.IsAbs(rt) {
		return ""
	}
	return filepath.Join(rt, "axiom")
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
// daemon.lock), but the one the plan is made by.
func (o Options) running() []string {
	var out []string
	for _, d := range o.displays() {
		if d != o.ExcludeDisplay && fsx.Held(filepath.Join(o.runtimeRoot(), d, "daemon.lock")) {
			out = append(out, d)
		}
	}
	return out
}

// stillHeld are the displays whose daemon.lock or guard.lock is held.
func (o Options) stillHeld(displays []string) []string {
	var out []string
	for _, d := range displays {
		dir := filepath.Join(o.runtimeRoot(), d)
		if fsx.Held(filepath.Join(dir, "daemon.lock")) || fsx.Held(filepath.Join(dir, "guard.lock")) {
			out = append(out, d)
		}
	}
	return out
}

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
