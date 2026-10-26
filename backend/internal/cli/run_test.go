package cli

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"slices"
	"syscall"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// SIGHUP (the terminal of a --dev daemon closed) ends a command cleanly,
// unless it was ignored at the start (nohup), which stays so.
func TestShutdownSignals(t *testing.T) {
	t.Parallel()
	for _, ignored := range []bool{false, true} {
		sigs := shutdownSignals(func(s os.Signal) bool { return ignored && s == syscall.SIGHUP })
		if !slices.Contains(sigs, os.Interrupt) || !slices.Contains(sigs, os.Signal(syscall.SIGTERM)) {
			t.Errorf("ignored %v: %v", ignored, sigs)
		}
		if slices.Contains(sigs, os.Signal(syscall.SIGHUP)) == ignored {
			t.Errorf("ignored %v: SIGHUP handled %v", ignored, !ignored)
		}
	}
}

// `daemon logs` without a log is NotFound, not a raw (Internal) error.
func TestDaemonLogsKinds(t *testing.T) {
	t.Parallel()
	state := t.TempDir()
	logs := func() (string, error) {
		var out bytes.Buffer
		e := &Env{Stdout: &out, Stderr: &bytes.Buffer{}, Getenv: func(k string) string {
			if k == "XDG_STATE_HOME" {
				return state
			}
			return ""
		}}
		err := dispatch(context.Background(), Root(), []string{"axiom"}, []string{"daemon", "logs"}, e)
		return out.String(), err
	}
	if _, err := logs(); axerr.KindOf(err) != axerr.NotFound {
		t.Errorf("no log: %v (%s)", err, axerr.KindOf(err))
	}
	os.MkdirAll(filepath.Join(state, "axiom", "log"), 0o700)
	os.WriteFile(filepath.Join(state, "axiom", "log", "daemon.log"), []byte("line\n"), 0o600)
	if out, err := logs(); err != nil || out != "line\n" {
		t.Errorf("log: %q %v", out, err)
	}
}
