package logfile

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// A log that can't be opened is Unavailable, not a raw (Internal) error.
func TestOpenFailureIsUnavailable(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	blocker := filepath.Join(dir, "file")
	os.WriteFile(blocker, nil, 0o600)
	for name, path := range map[string]string{
		"folder is a file": filepath.Join(blocker, "log", "daemon.log"),
		"log is a folder":  dir,
	} {
		if _, err := Open(path, 1<<20); axerr.KindOf(err) != axerr.Unavailable {
			t.Errorf("%s: %v (%s)", name, err, axerr.KindOf(err))
		}
	}
	w, err := Open(filepath.Join(dir, "log", "daemon.log"), 1<<20)
	if err != nil {
		t.Fatal(err)
	}
	w.Close()
}
