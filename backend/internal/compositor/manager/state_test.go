package manager

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func TestApprovalsCorruptFileIsLoggedAndEmpty(t *testing.T) {
	t.Parallel()
	path := filepath.Join(t.TempDir(), "ui", "takeover.json")
	var logged []string
	a := approvals{path: path, logf: func(f string, args ...any) { logged = append(logged, fmt.Sprintf(f, args...)) }}
	if got := a.list(); got != nil || len(logged) != 0 {
		t.Fatalf("missing: %v %v", got, logged)
	}
	if err := a.add("sway"); err != nil {
		t.Fatal(err)
	}
	if !a.has("sway") {
		t.Fatal("not saved")
	}
	if err := os.WriteFile(path, []byte("{oops"), 0o600); err != nil {
		t.Fatal(err)
	}
	if got := a.list(); got != nil || len(logged) != 1 {
		t.Errorf("corrupt: %v %v", got, logged)
	}
}

func TestLoadStateCorruptIsFresh(t *testing.T) {
	t.Parallel()
	path := filepath.Join(t.TempDir(), "state.json")
	if err := os.WriteFile(path, []byte("[1]"), 0o600); err != nil {
		t.Fatal(err)
	}
	var logged int
	s := loadState(path, "sway:a", func(string, ...any) { logged++ })
	if s.Instance != "sway:a" || s.AppliedMode != "" || logged != 1 {
		t.Errorf("%+v logged %d", s, logged)
	}
}
