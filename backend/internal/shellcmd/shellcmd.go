// Package shellcmd runs a command line the user wrote (a lock command,
// an idle listener's), through sh -c as their config tools would: in a
// process group of its own, so signals meant for the daemon don't reach
// it, with no stdio, reaped when it exits.
package shellcmd

import (
	"context"
	"os/exec"
	"syscall"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// Start starts line and returns once it runs; goFn runs the wait that
// reaps it on a goroutine its owner stops (nil: a plain goroutine).
func Start(line string, goFn func(func(context.Context))) error {
	cmd := exec.Command("sh", "-c", line)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "running %q", line)
	}
	if goFn == nil {
		go cmd.Wait()
	} else {
		goFn(func(context.Context) { cmd.Wait() })
	}
	return nil
}
