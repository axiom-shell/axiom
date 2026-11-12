// Package fsx is how axiom touches files it owns: atomic replacement and
// lock files. Rules (docs/dev/backend/README.md › Security): a write never
// leaves a half-written file and never follows a symlink planted where its
// temp file goes; a lock is held on a file of its own, never on the file it
// guards (a rename replaces that file's inode).
package fsx

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"syscall"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// IsFile is whether path is a regular file, a symlink followed.
func IsFile(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}

// WriteFile replaces path's content atomically: a temp file in the same
// directory (created exclusively, never through a symlink), written,
// fsynced, renamed over path, then the directory fsynced. When path is a
// symlink (a config kept in a dotfiles repo), the file it points at is
// replaced and the link stays. An existing file keeps its mode; a new one
// gets perm. A failure is axerr.Unavailable (the disk or the folder
// refused it), its message the step that failed.
func WriteFile(path string, data []byte, perm fs.FileMode) error {
	if err := writeFile(path, data, perm); err != nil {
		return &axerr.Error{Kind: axerr.Unavailable, Err: err}
	}
	return nil
}

func writeFile(path string, data []byte, perm fs.FileMode) error {
	return writeWith(path, perm, true, writeAll(data))
}

// writeWith is WriteFile's work, with what to write as fill and sync
// whether to fsync.
func writeWith(path string, perm fs.FileMode, sync bool, fill func(io.Writer) error) error {
	target, err := Resolve(path)
	if err != nil {
		return err
	}
	mode := perm
	if info, err := os.Stat(target); err == nil {
		mode = info.Mode().Perm()
	}
	return replaceWith(target, mode, sync, fill)
}

func writeAll(data []byte) func(io.Writer) error {
	return func(w io.Writer) error {
		_, err := w.Write(data)
		return err
	}
}

// ReplaceLink is WriteFile for a symlink that is to become a file of its
// own (one naming a file the user can't write): the link itself is
// replaced, never followed, and the file gets perm.
func ReplaceLink(path string, data []byte, perm fs.FileMode) error {
	if err := replace(path, data, perm); err != nil {
		return &axerr.Error{Kind: axerr.Unavailable, Err: err}
	}
	return nil
}

// WriteCache is WriteFile for a file whose loss costs only its rebuild (a
// cache that checks itself as it loads): fill streams the content into
// the temp file, and nothing is fsynced, so the write stalls no other
// writer. The rename is still atomic: a crash may leave the old file or
// a short new one, never another's half. A failure (fill's too) is
// axerr.Unavailable, and leaves the old file.
func WriteCache(path string, perm fs.FileMode, fill func(io.Writer) error) error {
	if err := writeWith(path, perm, false, fill); err != nil {
		return &axerr.Error{Kind: axerr.Unavailable, Err: err}
	}
	return nil
}

// replace puts data at target atomically, with mode.
func replace(target string, data []byte, mode fs.FileMode) error {
	return replaceWith(target, mode, true, writeAll(data))
}

// replaceWith puts what fill writes at target atomically, with mode;
// with sync, fsynced (the file, then its folder).
func replaceWith(target string, mode fs.FileMode, sync bool, fill func(io.Writer) error) error {
	dir := filepath.Dir(target)
	tmp, err := createTemp(dir, filepath.Base(target), mode)
	if err != nil {
		return err
	}
	name := tmp.Name()
	ok := false
	defer func() {
		if !ok {
			tmp.Close()
			os.Remove(name)
		}
	}()
	if err := fill(tmp); err != nil {
		return fmt.Errorf("writing %s: %w", name, err)
	}
	// The umask may have narrowed the mode the file was created with
	if err := tmp.Chmod(mode); err != nil {
		return err
	}
	if sync {
		if err := tmp.Sync(); err != nil {
			return fmt.Errorf("syncing %s: %w", name, err)
		}
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Rename(name, target); err != nil {
		return fmt.Errorf("replacing %s: %w", target, err)
	}
	ok = true
	if !sync {
		return nil
	}
	return syncDir(dir)
}

// Resolve follows a symlink at path to the file it names (relative links
// from the link's directory); any other path is itself.
func Resolve(path string) (string, error) {
	info, err := os.Lstat(path)
	if errors.Is(err, fs.ErrNotExist) {
		return path, nil
	}
	if err != nil {
		return "", err
	}
	if info.Mode()&fs.ModeSymlink == 0 {
		return path, nil
	}
	target, err := filepath.EvalSymlinks(path)
	if errors.Is(err, fs.ErrNotExist) {
		// A dangling link: create what it names
		link, err := os.Readlink(path)
		if err != nil {
			return "", err
		}
		if !filepath.IsAbs(link) {
			link = filepath.Join(filepath.Dir(path), link)
		}
		return link, nil
	}
	return target, err
}

func createTemp(dir, base string, mode fs.FileMode) (*os.File, error) {
	for range 10 {
		var b [8]byte
		if _, err := rand.Read(b[:]); err != nil {
			return nil, err
		}
		name := filepath.Join(dir, "."+base+".tmp-"+hex.EncodeToString(b[:]))
		f, err := os.OpenFile(name, os.O_WRONLY|os.O_CREATE|os.O_EXCL|syscall.O_NOFOLLOW|syscall.O_CLOEXEC, mode)
		if errors.Is(err, fs.ErrExist) {
			continue
		}
		if err != nil {
			return nil, fmt.Errorf("creating a temp file in %s: %w", dir, err)
		}
		return f, nil
	}
	return nil, fmt.Errorf("creating a temp file in %s: names kept colliding", dir)
}

func syncDir(dir string) error {
	d, err := os.Open(dir)
	if err != nil {
		return err
	}
	defer d.Close()
	if err := d.Sync(); err != nil && !errors.Is(err, syscall.EINVAL) {
		return fmt.Errorf("syncing %s: %w", dir, err)
	}
	return nil
}
