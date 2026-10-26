package edit

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

func write(t *testing.T, path, data string, mode os.FileMode) {
	t.Helper()
	if err := os.WriteFile(path, []byte(data), mode); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, mode); err != nil {
		t.Fatal(err)
	}
}

func check(t *testing.T, path, data string, mode os.FileMode) {
	t.Helper()
	got, err := os.ReadFile(path)
	if err != nil || string(got) != data {
		t.Errorf("%s holds %q (%v), want %q", filepath.Base(path), got, err, data)
	}
	if info, err := os.Stat(path); err != nil || info.Mode().Perm() != mode {
		t.Errorf("%s has mode %v (%v), want %v", filepath.Base(path), info.Mode().Perm(), err, mode)
	}
}

// only is the dir's entries: an atomic write leaves no temp file behind
func only(t *testing.T, dir string, want ...string) {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, e := range entries {
		names = append(names, e.Name())
	}
	if len(names) != len(want) {
		t.Fatalf("%s holds %v, want %v", dir, names, want)
	}
	for i := range want {
		if names[i] != want[i] {
			t.Fatalf("%s holds %v, want %v", dir, names, want)
		}
	}
}

// Replace keeps a file's mode (a new one is 0644), writes through a
// symlink so a file kept in a dotfiles repo stays there, and leaves no
// temp file
func TestReplace(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	fresh := filepath.Join(dir, "fresh.conf")
	if err := Replace(fresh, []byte("new")); err != nil {
		t.Fatal(err)
	}
	check(t, fresh, "new", 0o644)

	private := filepath.Join(dir, "private.conf")
	write(t, private, "old", 0o600)
	if err := Replace(private, []byte("changed")); err != nil {
		t.Fatal(err)
	}
	check(t, private, "changed", 0o600)

	repo := t.TempDir()
	target := filepath.Join(repo, "binds.lua")
	write(t, target, "old", 0o640)
	link := filepath.Join(dir, "binds.lua")
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}
	if err := Replace(link, []byte("through")); err != nil {
		t.Fatal(err)
	}
	if info, err := os.Lstat(link); err != nil || info.Mode()&os.ModeSymlink == 0 {
		t.Errorf("the symlink was replaced by a file (%v)", err)
	}
	check(t, target, "through", 0o640)
	only(t, dir, "binds.lua", "fresh.conf", "private.conf")
	only(t, repo, "binds.lua")
}

// WriteMode leaves the mode asked for, whatever the file had
func TestWriteMode(t *testing.T) {
	t.Parallel()
	path := filepath.Join(t.TempDir(), "run.sh")
	write(t, path, "old", 0o600)
	if err := WriteMode(path, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	check(t, path, "#!/bin/sh\n", 0o755)
}

// A dated backup (Copy to a name with Stamp) keeps the original's mode
// and modification time, and leaves the original as it was
func TestDatedBackup(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	src := filepath.Join(dir, "hyprland.lua")
	write(t, src, "user's", 0o600)
	when := time.Date(2025, 3, 4, 5, 6, 7, 0, time.Local)
	if err := os.Chtimes(src, when, when); err != nil {
		t.Fatal(err)
	}
	stamp := time.Date(2026, 10, 24, 12, 0, 0, 0, time.Local).Format(Stamp)
	if stamp != "20261024-120000" {
		t.Errorf("Stamp formats as %q", stamp)
	}
	backup := src + ".axiom-backup-" + stamp
	if err := Copy(src, backup); err != nil {
		t.Fatal(err)
	}
	check(t, backup, "user's", 0o600)
	check(t, src, "user's", 0o600)
	if info, err := os.Stat(backup); err != nil || !info.ModTime().Equal(when) {
		t.Errorf("the backup's time is %v (%v), want %v", info.ModTime(), err, when)
	}
	if err := Copy(filepath.Join(dir, "missing"), backup+"2"); err == nil {
		t.Error("copied a file that doesn't exist")
	}
	only(t, dir, "hyprland.lua", "hyprland.lua.axiom-backup-20261024-120000")
}

// LockDir makes a missing dir; a second holder waits, and is told the dir
// is being changed (Running) when its context ends first
func TestLockDir(t *testing.T) {
	t.Parallel()
	dir := filepath.Join(t.TempDir(), "hypr")
	held, err := LockDir(context.Background(), dir)
	if err != nil {
		t.Fatal(err)
	}
	if info, err := os.Stat(dir); err != nil || !info.IsDir() {
		t.Fatalf("the dir wasn't made: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 150*time.Millisecond)
	defer cancel()
	if _, err := LockDir(ctx, dir); axerr.KindOf(err) != axerr.Running {
		t.Errorf("a second lock: %v, want Running", err)
	}
	if err := held.Release(); err != nil {
		t.Fatal(err)
	}
	again, err := LockDir(context.Background(), dir)
	if err != nil {
		t.Fatalf("after the release: %v", err)
	}
	again.Release()
	only(t, dir)
}
