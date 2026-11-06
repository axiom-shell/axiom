// Package camera is the `camera` topic: the processes holding a camera's
// V4L2 device (/dev/video*) open. Chromium and Electron apps (Vesktop,
// Discord) open the device themselves rather than through PipeWire, so
// the shell's PipeWire links never show them using it. The devices are
// watched with inotify (an open or a close by any process, and /dev for
// devices coming and going; no polling), and after each burst of events
// /proc is read for who holds one open. PipeWire and WirePlumber are left
// out: an app reading the camera through them shows as a link already.
package camera

import (
	"context"
	"errors"
	"log/slog"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unsafe"

	"golang.org/x/sys/unix"
)

// Options configure the service; the zero Dev is /dev, Proc /proc.
type Options struct {
	Dev  string
	Proc string
	// Settle is how long after an event the processes are read, so one
	// app opening every device at once is one read (default 150 ms)
	Settle time.Duration
	// OnChange is called with each new state
	OnChange func(State)
	Log      *slog.Logger
}

// State is what the topic pushes.
type State struct {
	// The apps holding a camera open, by Key
	Users []User `json:"users"`
}

// User is one app holding a camera open (its processes counted once).
type User struct {
	// The app's flatpak id, else its process name: what it's counted by
	Key string `json:"key"`
	// The flatpak's app id ("dev.vencord.Vesktop"), "" outside one
	App string `json:"app"`
	// The process name (/proc/<pid>/comm) of its first process seen
	Comm string `json:"comm"`
	PID  int    `json:"pid"`
}

// Service watches the devices; Run runs it.
type Service struct {
	o     Options
	mu    sync.Mutex
	state State
	// The devices' watches while Run runs
	w *watches
}

// Their own use is a PipeWire node the shell sees through its links
var skipped = map[string]bool{"pipewire": true, "wireplumber": true}

var deviceName = regexp.MustCompile(`^video[0-9]+$`)

// A flatpak app's processes run in its scope: app-flatpak-<id>-<n>.scope
var flatpakScope = regexp.MustCompile(`app-flatpak-([A-Za-z0-9_.-]+?)-[0-9]+\.scope`)

// New returns a service; Run runs it.
func New(o Options) *Service {
	if o.Dev == "" {
		o.Dev = "/dev"
	}
	if o.Proc == "" {
		o.Proc = "/proc"
	}
	if o.Settle == 0 {
		o.Settle = 150 * time.Millisecond
	}
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	return &Service{o: o, state: State{Users: []User{}}}
}

// State is the current state.
func (s *Service) State() State {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.state
}

// Run watches the devices until ctx ends. Without inotify it logs once
// and stays idle: no camera use is seen, as before.
func (s *Service) Run(ctx context.Context) error {
	fd, err := unix.InotifyInit1(unix.IN_NONBLOCK | unix.IN_CLOEXEC)
	if err != nil {
		s.o.Log.Warn("camera: inotify is unavailable: an app opening a camera itself isn't seen", "err", err)
		<-ctx.Done()
		return nil
	}
	// Non-blocking, so the runtime's poller reads it and Close ends a Read
	f := os.NewFile(uintptr(fd), "inotify")
	w := &watches{fd: fd, dev: s.o.Dev, byWd: map[int]string{}, byName: map[string]int{}}
	s.mu.Lock()
	s.w = w
	s.mu.Unlock()
	if _, err := unix.InotifyAddWatch(fd, s.o.Dev, unix.IN_CREATE|unix.IN_DELETE|unix.IN_MOVED_TO|unix.IN_MOVED_FROM); err != nil {
		s.o.Log.Warn("camera: can't watch the devices' folder: an app opening a camera itself isn't seen", "dev", s.o.Dev, "err", err)
		f.Close()
		<-ctx.Done()
		return nil
	}
	w.sync(s.o.Log)
	s.publish(s.scan())

	events := make(chan bool, 1) // true: a device came or went
	go func() {
		<-ctx.Done()
		f.Close()
	}()
	go s.read(ctx, f, w, events)

	timer := time.NewTimer(0)
	<-timer.C
	pending, resync := false, false
	for {
		select {
		case <-ctx.Done():
			timer.Stop()
			return nil
		case devices, ok := <-events:
			if !ok {
				timer.Stop()
				<-ctx.Done()
				return nil
			}
			resync = resync || devices
			if !pending {
				pending = true
				timer.Reset(s.o.Settle)
			}
		case <-timer.C:
			pending = false
			if resync {
				resync = false
				w.sync(s.o.Log)
			}
			s.publish(s.scan())
		}
	}
}

// read passes on each event until the file closes, then closes events.
func (s *Service) read(ctx context.Context, f *os.File, w *watches, events chan<- bool) {
	defer close(events)
	buf := make([]byte, 64*(unix.SizeofInotifyEvent+unix.NAME_MAX+1))
	for {
		n, err := f.Read(buf)
		if err != nil {
			if !errors.Is(err, os.ErrClosed) {
				s.o.Log.Warn("camera: reading the device events failed: an app opening a camera itself isn't seen", "err", err)
			}
			return
		}
		devices := false
		for off := 0; off+unix.SizeofInotifyEvent <= n; {
			ev := (*unix.InotifyEvent)(unsafe.Pointer(&buf[off]))
			name := ""
			if ev.Len > 0 {
				end := off + unix.SizeofInotifyEvent + int(ev.Len)
				name = strings.TrimRight(string(buf[off+unix.SizeofInotifyEvent:min(end, n)]), "\x00")
			}
			off += unix.SizeofInotifyEvent + int(ev.Len)
			if ev.Mask&(unix.IN_CREATE|unix.IN_DELETE|unix.IN_MOVED_TO|unix.IN_MOVED_FROM) != 0 {
				if !deviceName.MatchString(name) {
					continue
				}
				devices = true
			}
			if ev.Mask&unix.IN_IGNORED != 0 {
				// A device's watch went with it
				w.forget(int(ev.Wd))
				devices = true
			}
		}
		select {
		case events <- devices:
		case <-ctx.Done():
			return
		}
	}
}

// watches are the inotify watches on each video device.
type watches struct {
	fd     int
	dev    string
	mu     sync.Mutex
	byWd   map[int]string
	byName map[string]int
}

// sync watches every video device there is now.
func (w *watches) sync(log *slog.Logger) {
	entries, _ := os.ReadDir(w.dev)
	w.mu.Lock()
	defer w.mu.Unlock()
	for _, e := range entries {
		if !deviceName.MatchString(e.Name()) {
			continue
		}
		if _, ok := w.byName[e.Name()]; ok {
			continue
		}
		wd, err := unix.InotifyAddWatch(w.fd, filepath.Join(w.dev, e.Name()), unix.IN_OPEN|unix.IN_CLOSE_WRITE|unix.IN_CLOSE_NOWRITE)
		if err != nil {
			log.Debug("camera: can't watch a device", "name", e.Name(), "err", err)
			continue
		}
		// A device made again can reuse a removed one's wd
		if old, ok := w.byWd[wd]; ok {
			delete(w.byName, old)
		}
		w.byWd[wd] = e.Name()
		w.byName[e.Name()] = wd
	}
}

// watching: the device name has its watch.
func (w *watches) watching(name string) bool {
	w.mu.Lock()
	defer w.mu.Unlock()
	_, ok := w.byName[name]
	return ok
}

func (w *watches) forget(wd int) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if name, ok := w.byWd[wd]; ok {
		delete(w.byName, name)
		delete(w.byWd, wd)
	}
}

func (s *Service) publish(next State) {
	s.mu.Lock()
	same := reflect.DeepEqual(s.state, next)
	s.state = next
	s.mu.Unlock()
	if !same && s.o.OnChange != nil {
		s.o.OnChange(next)
	}
}

// scan lists the apps holding a video device open, read from every
// process's open files (only the user's own processes are readable).
func (s *Service) scan() State {
	procs, _ := os.ReadDir(s.o.Proc)
	devPrefix := filepath.Join(s.o.Dev, "video")
	byKey := map[string]User{}
	for _, p := range procs {
		pid, err := strconv.Atoi(p.Name())
		if err != nil || pid <= 0 {
			continue
		}
		dir := filepath.Join(s.o.Proc, p.Name())
		if !holdsDevice(filepath.Join(dir, "fd"), devPrefix) {
			continue
		}
		comm := readTrimmed(filepath.Join(dir, "comm"))
		if skipped[comm] {
			continue
		}
		app := FlatpakApp(readTrimmed(filepath.Join(dir, "cgroup")))
		key := app
		if key == "" {
			key = comm
		}
		if key == "" {
			continue
		}
		if have, ok := byKey[key]; !ok || pid < have.PID {
			byKey[key] = User{Key: key, App: app, Comm: comm, PID: pid}
		}
	}
	users := make([]User, 0, len(byKey))
	for _, u := range byKey {
		users = append(users, u)
	}
	sort.Slice(users, func(i, j int) bool { return users[i].Key < users[j].Key })
	return State{Users: users}
}

// holdsDevice: one of the open files in fdDir is a video device.
// Readlink doesn't open the device, so a scan never wakes the watch.
func holdsDevice(fdDir, devPrefix string) bool {
	fds, err := os.ReadDir(fdDir)
	if err != nil {
		return false
	}
	for _, fd := range fds {
		target, err := os.Readlink(filepath.Join(fdDir, fd.Name()))
		if err != nil {
			continue
		}
		if rest, ok := strings.CutPrefix(target, devPrefix); ok && rest != "" && strings.Trim(rest, "0123456789") == "" {
			return true
		}
	}
	return false
}

// FlatpakApp is the flatpak app id in a /proc/<pid>/cgroup's contents
// (its scope, app-flatpak-<id>-<n>.scope), or "".
func FlatpakApp(cgroup string) string {
	if m := flatpakScope.FindStringSubmatch(cgroup); m != nil {
		return m[1]
	}
	return ""
}

func readTrimmed(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}
