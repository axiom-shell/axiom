// Package edit is how axiom changes a user's own config files (the
// takeover's copies, the bind merge's edits, the hookups' lines that load
// axiom's files): atomic replacement keeping a file's mode, dated backups
// that keep its mode and modification time, and the config dir's lock.
package edit

import (
	"context"
	"os"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/fsx"
)

// lockWait is how long a change waits for another process changing the dir
const lockWait = 10 * time.Second

// LockDir takes a compositor config dir's lock, which the takeover's verbs
// and the bind merge's removal hold while they read and change it, so the
// daemon and a command line never interleave (an axerr.Running error after
// 10 s of waiting). dir is made when missing.
func LockDir(ctx context.Context, dir string) (*fsx.Lock, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(ctx, lockWait)
	defer cancel()
	return fsx.LockDir(ctx, dir)
}

// Stamp is the layout of the dates in backup names (20261024-120000).
const Stamp = "20060102-150405"

// Replace replaces path's content atomically, keeping its mode (a new file
// gets 0644). A symlink is written through, so a file kept in a dotfiles
// repo stays there.
func Replace(path string, data []byte) error {
	return fsx.WriteFile(path, data, 0o644)
}

// WriteMode replaces path atomically, leaving it with mode.
func WriteMode(path string, data []byte, mode os.FileMode) error {
	if err := fsx.WriteFile(path, data, mode); err != nil {
		return err
	}
	return os.Chmod(path, mode)
}

// Copy copies src to dst with its mode and modification time (cp -p).
func Copy(src, dst string) error {
	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	info, err := os.Stat(src)
	if err != nil {
		return err
	}
	if err := WriteMode(dst, data, info.Mode().Perm()); err != nil {
		return err
	}
	return os.Chtimes(dst, info.ModTime(), info.ModTime())
}
