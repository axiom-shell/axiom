package fileindex

import (
	"errors"
	"os"
	"strconv"
	"strings"
	"unsafe"

	"golang.org/x/sys/unix"
)

// The events a watched folder reports: entries made, removed, renamed in
// or out, a file written; the folder itself removed or moved. Never
// through a link (IN_DONT_FOLLOW; but a root, which the user named), only
// folders (IN_ONLYDIR).
const watchMask = unix.IN_CREATE | unix.IN_DELETE | unix.IN_MOVED_FROM | unix.IN_MOVED_TO |
	unix.IN_CLOSE_WRITE | unix.IN_DELETE_SELF | unix.IN_MOVE_SELF |
	unix.IN_ONLYDIR | unix.IN_DONT_FOLLOW | unix.IN_EXCL_UNLINK

// The watch budget: a quarter of the user's inotify watches (shared with
// editors, syncthing and the rest), at most this many
const maxWatches = 64 << 10

// watchBudget is how many folders to watch, read from the kernel's limit.
func watchBudget() int {
	data, err := os.ReadFile("/proc/sys/fs/inotify/max_user_watches")
	if err != nil {
		return 0
	}
	n, err := strconv.Atoi(strings.TrimSpace(string(data)))
	if err != nil {
		return 0
	}
	return min(maxWatches, n/4)
}

// event is one inotify event: its watch, the entry's name in it, its mask
// (wd -1 with IN_Q_OVERFLOW: events were lost).
type event struct {
	wd   int32
	mask uint32
	name string
}

// watcher is the inotify instance and its watches by descriptor and path.
// Only the service's loop touches the maps.
type watcher struct {
	fd     int
	file   *os.File
	byWd   map[int32]string
	byPath map[string]int32
	// followed are the roots watched through a link (follow): the folder
	// each led to, which a link leading elsewhere now doesn't report
	followed map[string]fileID
	budget   int
	// events are what read reads; stop ends it
	events chan []event
	stop   chan struct{}
}

func newWatcher(budget int) (*watcher, error) {
	fd, err := unix.InotifyInit1(unix.IN_NONBLOCK | unix.IN_CLOEXEC)
	if err != nil {
		return nil, err
	}
	// Non-blocking, so the runtime's poller reads it and Close ends a Read
	return &watcher{fd: fd, file: os.NewFile(uintptr(fd), "inotify"), byWd: map[int32]string{}, byPath: map[string]int32{}, followed: map[string]fileID{}, budget: budget,
		events: make(chan []event, 16), stop: make(chan struct{})}, nil
}

// add watches the folder at path, unless the budget is spent; stolen is
// the path the folder was watched under until now (it moved here, or
// another root reaches it through a link), "" for none. follow watches
// a link's folder (a root that is a link).
func (w *watcher) add(path string, follow bool) (ok bool, stolen string) {
	if _, ok := w.byPath[path]; ok {
		return true, ""
	}
	if len(w.byPath) >= w.budget {
		return false, ""
	}
	mask := uint32(watchMask)
	if follow {
		mask &^= unix.IN_DONT_FOLLOW
	}
	wd, err := unix.InotifyAddWatch(w.fd, path, mask)
	if err != nil {
		return false, ""
	}
	if old, ok := w.byWd[int32(wd)]; ok {
		delete(w.byPath, old)
		delete(w.followed, old)
		stolen = old
	}
	w.byWd[int32(wd)] = path
	w.byPath[path] = int32(wd)
	if follow {
		w.followed[path] = idOf(path)
	}
	return true, stolen
}

// fileID is a folder's device and inode (zero when it can't be read).
type fileID struct{ dev, ino uint64 }

func idOf(path string) fileID {
	var st unix.Stat_t
	if unix.Stat(path, &st) != nil {
		return fileID{}
	}
	return fileID{st.Dev, st.Ino}
}

// moved are the roots watched through a link that leads elsewhere now
// (or nowhere): their watch is on the folder it led to.
func (w *watcher) moved() []string {
	var out []string
	for path, id := range w.followed {
		if idOf(path) != id {
			out = append(out, path)
		}
	}
	return out
}

// remove stops watching path.
func (w *watcher) remove(path string) {
	wd, ok := w.byPath[path]
	if !ok {
		return
	}
	delete(w.byPath, path)
	delete(w.byWd, wd)
	delete(w.followed, path)
	unix.InotifyRmWatch(w.fd, uint32(wd))
}

// forget drops a watch the kernel removed (IN_IGNORED).
func (w *watcher) forget(wd int32) {
	if path, ok := w.byWd[wd]; ok {
		delete(w.byWd, wd)
		if w.byPath[path] == wd {
			delete(w.byPath, path)
			delete(w.followed, path)
		}
	}
}

func (w *watcher) close() {
	close(w.stop)
	w.file.Close()
}

// read sends each read's events on w.events until the watcher closes.
func (w *watcher) read() {
	out := w.events
	buf := make([]byte, 64*(unix.SizeofInotifyEvent+unix.NAME_MAX+1))
	for {
		n, err := w.file.Read(buf)
		if err != nil {
			if !errors.Is(err, os.ErrClosed) {
				select {
				case out <- []event{{wd: -1, mask: unix.IN_Q_OVERFLOW}}:
				case <-w.stop:
				}
			}
			return
		}
		var evs []event
		for off := 0; off+unix.SizeofInotifyEvent <= n; {
			raw := (*unix.InotifyEvent)(unsafe.Pointer(&buf[off]))
			name := ""
			if raw.Len > 0 {
				end := min(off+unix.SizeofInotifyEvent+int(raw.Len), n)
				name = strings.TrimRight(string(buf[off+unix.SizeofInotifyEvent:end]), "\x00")
			}
			off += unix.SizeofInotifyEvent + int(raw.Len)
			evs = append(evs, event{wd: raw.Wd, mask: raw.Mask, name: name})
		}
		select {
		case out <- evs:
		case <-w.stop:
			return
		}
	}
}
