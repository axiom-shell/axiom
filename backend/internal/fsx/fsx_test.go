package fsx

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

func TestWriteFileReplacesAndKeepsMode(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	path := filepath.Join(dir, "config.json")
	if err := WriteFile(path, []byte("one"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, 0o640); err != nil {
		t.Fatal(err)
	}
	if err := WriteFile(path, []byte("two"), 0o600); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(path)
	info, _ := os.Stat(path)
	if string(data) != "two" || info.Mode().Perm() != 0o640 {
		t.Errorf("got %q mode %v", data, info.Mode().Perm())
	}
	entries, _ := os.ReadDir(dir)
	if len(entries) != 1 {
		t.Errorf("left behind: %v", entries)
	}
}

// A config symlinked into a dotfiles repo: the file it names changes, the
// link stays a link
func TestWriteFileThroughSymlink(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	real := filepath.Join(dir, "dotfiles", "config.json")
	os.MkdirAll(filepath.Dir(real), 0o755)
	os.WriteFile(real, []byte("old"), 0o644)
	link := filepath.Join(dir, "config.json")
	if err := os.Symlink("dotfiles/config.json", link); err != nil {
		t.Fatal(err)
	}
	if err := WriteFile(link, []byte("new"), 0o600); err != nil {
		t.Fatal(err)
	}
	if info, _ := os.Lstat(link); info.Mode()&os.ModeSymlink == 0 {
		t.Error("the link was replaced by a file")
	}
	if data, _ := os.ReadFile(real); string(data) != "new" {
		t.Errorf("target holds %q", data)
	}
	if data, _ := os.ReadFile(link); string(data) != "new" {
		t.Errorf("link reads %q", data)
	}
}

func TestReplaceLinkReplacesTheLink(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	target := filepath.Join(dir, "theirs.css")
	if err := os.WriteFile(target, []byte("theirs\n"), 0o444); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(dir, "gtk.css")
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}
	if err := ReplaceLink(link, []byte("mine\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	info, err := os.Lstat(link)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm() != 0o644 {
		t.Fatalf("link not replaced by a 0644 file: %v %v", info, err)
	}
	if got, _ := os.ReadFile(link); string(got) != "mine\n" {
		t.Errorf("file %q", got)
	}
	// The file it named is untouched
	if got, _ := os.ReadFile(target); string(got) != "theirs\n" {
		t.Errorf("target %q", got)
	}
}

func TestWriteFileFailsCleanlyInAMissingDir(t *testing.T) {
	t.Parallel()
	err := WriteFile(filepath.Join(t.TempDir(), "nope", "x.json"), []byte("x"), 0o600)
	if err == nil || !strings.Contains(err.Error(), "temp file") {
		t.Errorf("err %v", err)
	}
	// A kind the CLI and the shell can branch on, not a raw Internal
	if axerr.KindOf(err) != axerr.Unavailable {
		t.Errorf("kind %s", axerr.KindOf(err))
	}
}

func TestNewFileGetsPerm(t *testing.T) {
	t.Parallel()
	path := filepath.Join(t.TempDir(), "secrets.json")
	if err := WriteFile(path, []byte("{}"), 0o600); err != nil {
		t.Fatal(err)
	}
	if info, _ := os.Stat(path); info.Mode().Perm() != 0o600 {
		t.Errorf("mode %v", info.Mode().Perm())
	}
}

func TestLockIsExclusiveAndNamesItsHolder(t *testing.T) {
	t.Parallel()
	path := filepath.Join(t.TempDir(), "daemon.lock")
	l, err := TryLock(path)
	if err != nil {
		t.Fatal(err)
	}
	_, err = TryLock(path)
	if err == nil || !strings.Contains(err.Error(), fmt.Sprint(os.Getpid())) {
		t.Fatalf("second lock: %v", err)
	}
	if Holder(path) != os.Getpid() {
		t.Error("holder not recorded")
	}
	l.Release()
	l2, err := TryLock(path)
	if err != nil {
		t.Fatalf("after release: %v", err)
	}
	l2.Release()
}

func TestLockRefusesSymlink(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	os.Symlink(filepath.Join(dir, "elsewhere"), filepath.Join(dir, "daemon.lock"))
	if _, err := TryLock(filepath.Join(dir, "daemon.lock")); err == nil {
		t.Error("locked through a symlink")
	}
	if _, err := os.Stat(filepath.Join(dir, "elsewhere")); err == nil {
		t.Error("created the symlink's target")
	}
}
