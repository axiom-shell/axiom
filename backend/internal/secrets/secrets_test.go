package secrets

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// secretTool is one fake secret-tool for every test, written by TestMain
// before any test forks (a program written while another test forks
// can't be run: "text file busy"). It keeps each secret in the file
// <the path it ran as>.keys/<scope>.<id>, so each test links it with its
// own keyring.
var secretTool string

func TestMain(m *testing.M) {
	dir, err := os.MkdirTemp("", "secrets-tools-")
	if err != nil {
		panic(err)
	}
	secretTool = filepath.Join(dir, "secret-tool")
	script := `#!/bin/sh
cmd=$1; shift; [ "$cmd" = store ] && shift
d="$0.keys"
case $cmd in
lookup) exec cat "$d/$3.$4" 2>/dev/null ;;
store) cat > "$d/$3.$4" ;;
clear) rm -f "$d/$3.$4" ;;
esac
`
	if err := os.WriteFile(secretTool, []byte(script), 0o755); err != nil {
		panic(err)
	}
	code := m.Run()
	os.RemoveAll(dir)
	os.Exit(code)
}

// newStore is a store whose file holds `file`, with a keyring holding
// `keyring` (by "<scope>.<id>"), or none when keyring is nil
func newStore(t *testing.T, file string, keyring map[string]string) (*Store, string) {
	t.Helper()
	dir := t.TempDir()
	if file != "" {
		if err := os.WriteFile(filepath.Join(dir, "secrets.json"), []byte(file), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	tool := filepath.Join(dir, "no-secret-tool")
	if keyring != nil {
		tool = filepath.Join(dir, "secret-tool")
		if err := os.Symlink(secretTool, tool); err != nil {
			t.Fatal(err)
		}
		if err := os.Mkdir(tool+".keys", 0o700); err != nil {
			t.Fatal(err)
		}
		for name, v := range keyring {
			if err := os.WriteFile(filepath.Join(tool+".keys", name), []byte(v+"\n"), 0o600); err != nil {
				t.Fatal(err)
			}
		}
	}
	return New(Options{StateDir: dir, SecretTool: tool}), dir
}

func TestLookup(t *testing.T) {
	t.Parallel()
	s, _ := newStore(t, `{"filed": " from-file ", "calendar:filed": "cal-file", "both": "file-loses"}`, map[string]string{"provider.ring": "from-ring", "provider.both": "ring-wins", "calendar.ring": "cal-ring"})
	tests := []struct {
		scope, id, value, source string
	}{
		{"provider", "ring", "from-ring", SourceKeyring},
		{"provider", "both", "ring-wins", SourceKeyring},
		{"provider", "filed", "from-file", SourceFile},
		{"calendar", "filed", "cal-file", SourceFile},
		{"calendar", "ring", "cal-ring", SourceKeyring},
		{"calendar", "both", "", SourceNone},
		{"provider", "missing", "", SourceNone},
	}
	for _, tc := range tests {
		v, source, err := s.Lookup(context.Background(), tc.scope, tc.id)
		if err != nil || v != tc.value || source != tc.source {
			t.Errorf("%s %s: got %q %q %v, want %q %q", tc.scope, tc.id, v, source, err, tc.value, tc.source)
		}
	}
	if !s.Keyring(context.Background()) {
		t.Error("the fake keyring doesn't answer the probe")
	}
}

// Without secret-tool installed the file holds everything, mode 600
func TestWithoutKeyring(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	s, dir := newStore(t, `{"other": "kept"}`, nil)
	if s.Keyring(ctx) {
		t.Error("a missing secret-tool answers the probe")
	}
	if source, err := s.Set(ctx, "calendar", "acc", "Work calendar", " pw "); err != nil || source != SourceFile {
		t.Fatalf("Set: %q %v", source, err)
	}
	if v, source, _ := s.Lookup(ctx, "calendar", "acc"); v != "pw" || source != SourceFile {
		t.Errorf("Lookup after Set: %q %q", v, source)
	}
	path := filepath.Join(dir, "secrets.json")
	if info, err := os.Stat(path); err != nil || info.Mode().Perm() != 0o600 {
		t.Errorf("secrets.json mode %v %v", info.Mode().Perm(), err)
	}
	if source, err := s.Set(ctx, "calendar", "acc", "", ""); err != nil || source != SourceNone {
		t.Errorf("Set empty: %q %v", source, err)
	}
	if data, _ := os.ReadFile(path); string(data) != "{\n  \"other\": \"kept\"\n}" {
		t.Errorf("after clearing: %s", data)
	}
}

// A keyring that takes a secret holds its only copy
func TestKeyringStore(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	s, dir := newStore(t, `{"p": "old"}`, map[string]string{})
	if source, err := s.Set(ctx, "provider", "p", "P", "new"); err != nil || source != SourceKeyring {
		t.Fatalf("Set: %q %v", source, err)
	}
	if data, _ := os.ReadFile(filepath.Join(dir, "secrets.json")); string(data) != "{}" {
		t.Errorf("the file kept its copy: %s", data)
	}
	if v, source, _ := s.Lookup(ctx, "provider", "p"); v != "new" || source != SourceKeyring {
		t.Errorf("Lookup: %q %q", v, source)
	}
	if err := s.Clear(ctx, "provider", "p"); err != nil {
		t.Fatal(err)
	}
	if _, source, _ := s.Lookup(ctx, "provider", "p"); source != SourceNone {
		t.Errorf("after Clear: %q", source)
	}
}

func TestRefusals(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	s, dir := newStore(t, `not json`, nil)
	if _, err := s.Set(ctx, "calendar", "acc", "", "pw"); axerr.KindOf(err) != axerr.Unavailable {
		t.Errorf("Set over a broken file: %v", err)
	}
	if data, _ := os.ReadFile(filepath.Join(dir, "secrets.json")); string(data) != "not json" {
		t.Errorf("the broken file was replaced: %s", data)
	}
	// The keyring still takes one
	ring, _ := newStore(t, `not json`, map[string]string{})
	if source, err := ring.Set(ctx, "calendar", "acc", "", "pw"); err != nil || source != SourceKeyring {
		t.Errorf("Set to the keyring beside a broken file: %q %v", source, err)
	}
	for _, c := range [][2]string{{"other", "x"}, {"calendar", ""}} {
		if _, err := s.Set(ctx, c[0], c[1], "", "v"); axerr.KindOf(err) != axerr.BadRequest {
			t.Errorf("Set %v: %v", c, err)
		}
		if err := s.Clear(ctx, c[0], c[1]); axerr.KindOf(err) != axerr.BadRequest {
			t.Errorf("Clear %v: %v", c, err)
		}
	}
}
