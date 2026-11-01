package fsx

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// Lock is a held flock on a lock file of its own. It lasts until Release
// or the process ends (the kernel drops it with the last descriptor, so a
// crash never leaves a stale lock).
type Lock struct {
	f *os.File
}

// TryLock takes the exclusive lock on path without waiting, creating the
// file (0600, never through a symlink). When another process holds it, the
// error is axerr.Running naming that process (its pid, written into the
// file by whoever holds it).
func TryLock(path string) (*Lock, error) {
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0o600)
	if err != nil {
		return nil, axerr.Wrap(axerr.Unavailable, err, "opening the lock %s", path)
	}
	if err := unix.Flock(int(f.Fd()), unix.LOCK_EX|unix.LOCK_NB); err != nil {
		holder := readPID(f)
		f.Close()
		if errors.Is(err, unix.EWOULDBLOCK) {
			if holder > 0 {
				return nil, &axerr.Error{Kind: axerr.Running, Message: fmt.Sprintf("held by process %d", holder)}
			}
			return nil, &axerr.Error{Kind: axerr.Running, Message: "held by another process"}
		}
		return nil, axerr.Wrap(axerr.Unavailable, err, "locking %s", path)
	}
	// Say who holds it, for the error the next one gets
	if err := f.Truncate(0); err == nil {
		f.WriteAt([]byte(strconv.Itoa(os.Getpid())+"\n"), 0)
	}
	return &Lock{f: f}, nil
}

func readPID(f *os.File) int {
	buf := make([]byte, 32)
	n, _ := f.ReadAt(buf, 0)
	pid, _ := strconv.Atoi(strings.TrimSpace(string(buf[:n])))
	return pid
}

// File is the lock's descriptor, for handing to a re-exec'd image.
func (l *Lock) File() *os.File { return l.f }

// Adopt takes over a lock inherited as an open descriptor (across
// re-exec), checking it is still held on path.
func Adopt(f *os.File, path string) (*Lock, error) {
	var a, b unix.Stat_t
	if err := unix.Fstat(int(f.Fd()), &a); err != nil {
		return nil, err
	}
	if err := unix.Stat(path, &b); err != nil || a.Ino != b.Ino || a.Dev != b.Dev {
		return nil, axerr.New(axerr.Refused, "the inherited lock isn't %s", path)
	}
	// Taking it again on our own descriptor is a no-op when we hold it, and
	// fails if we don't
	if err := unix.Flock(int(f.Fd()), unix.LOCK_EX|unix.LOCK_NB); err != nil {
		return nil, axerr.Wrap(axerr.Refused, err, "the inherited lock isn't held")
	}
	// It crossed the exec without close-on-exec: set again, or every child
	// started from now on (the shell, and what it starts) would hold the
	// lock too, and keep it past this process
	unix.CloseOnExec(int(f.Fd()))
	return &Lock{f: f}, nil
}

// Release drops the lock.
func (l *Lock) Release() error {
	if l == nil || l.f == nil {
		return nil
	}
	err := l.f.Close()
	l.f = nil
	return err
}

// LockDir takes the exclusive lock on a directory itself (flock on the
// directory, its links followed), waiting while another process holds it,
// until ctx ends. For a folder of the user's (a compositor's config dir)
// that two processes may change at once: it adds no file to it, and a
// rename inside it never replaces the inode the lock is on.
func LockDir(ctx context.Context, dir string) (*Lock, error) {
	f, err := os.OpenFile(dir, os.O_RDONLY|unix.O_DIRECTORY|unix.O_CLOEXEC, 0)
	if err != nil {
		return nil, axerr.Wrap(axerr.Unavailable, err, "opening %s to lock it", dir)
	}
	for {
		err := unix.Flock(int(f.Fd()), unix.LOCK_EX|unix.LOCK_NB)
		if err == nil {
			return &Lock{f: f}, nil
		}
		if !errors.Is(err, unix.EWOULDBLOCK) {
			f.Close()
			return nil, axerr.Wrap(axerr.Unavailable, err, "locking %s", dir)
		}
		select {
		case <-ctx.Done():
			f.Close()
			return nil, axerr.Wrap(axerr.Running, ctx.Err(), "%s is being changed by another axiom", dir)
		case <-time.After(50 * time.Millisecond):
		}
	}
}
