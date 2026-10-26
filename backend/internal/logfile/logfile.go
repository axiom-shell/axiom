// Package logfile is the daemon's log: a file that keeps the last couple
// of megabytes ($XDG_STATE_HOME/axiom/log/daemon.log, the previous one as
// daemon.log.1), so a long session never fills the disk.
package logfile

import (
	"os"
	"path/filepath"
	"sync"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// Writer appends to a file, starting it over (the old one kept as .1)
// once it passes Max bytes.
type Writer struct {
	path string
	max  int64

	mu   sync.Mutex
	f    *os.File
	size int64
}

// Open opens (creating) path for appending; a failure is
// axerr.Unavailable.
func Open(path string, max int64) (*Writer, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, axerr.Wrap(axerr.Unavailable, err, "creating the log folder")
	}
	w := &Writer{path: path, max: max}
	if err := w.open(); err != nil {
		return nil, axerr.Wrap(axerr.Unavailable, err, "opening the log")
	}
	return w, nil
}

func (w *Writer) open() error {
	f, err := os.OpenFile(w.path, os.O_WRONLY|os.O_APPEND|os.O_CREATE, 0o600)
	if err != nil {
		return err
	}
	info, err := f.Stat()
	if err != nil {
		f.Close()
		return err
	}
	w.f, w.size = f, info.Size()
	return nil
}

func (w *Writer) Write(p []byte) (int, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.size+int64(len(p)) > w.max && w.size > 0 {
		w.f.Close()
		os.Rename(w.path, w.path+".1")
		if err := w.open(); err != nil {
			return 0, err
		}
	}
	n, err := w.f.Write(p)
	w.size += int64(n)
	return n, err
}

// Close closes the file.
func (w *Writer) Close() error {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.f.Close()
}
