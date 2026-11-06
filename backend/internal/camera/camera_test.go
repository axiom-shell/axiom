package camera

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// fakeProc is a /proc with processes whose open files point where asked.
type fakeProc struct {
	t    *testing.T
	root string
}

func newFakeProc(t *testing.T) fakeProc {
	return fakeProc{t: t, root: t.TempDir()}
}

// add makes process pid, named comm, in cgroup, holding targets open.
func (p fakeProc) add(pid int, comm, cgroup string, targets ...string) {
	dir := filepath.Join(p.root, strconv.Itoa(pid))
	must(p.t, os.MkdirAll(filepath.Join(dir, "fd"), 0o755))
	must(p.t, os.WriteFile(filepath.Join(dir, "comm"), []byte(comm+"\n"), 0o644))
	must(p.t, os.WriteFile(filepath.Join(dir, "cgroup"), []byte(cgroup+"\n"), 0o644))
	for i, target := range targets {
		must(p.t, os.Symlink(target, filepath.Join(dir, "fd", strconv.Itoa(i+3))))
	}
}

func (p fakeProc) remove(pid int) {
	must(p.t, os.RemoveAll(filepath.Join(p.root, strconv.Itoa(pid))))
}

func must(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
}

const vesktopCgroup = "0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-flatpak-dev.vencord.Vesktop-123456.scope"

func TestScan(t *testing.T) {
	t.Parallel()
	proc := newFakeProc(t)
	// Two of Vesktop's processes: one user, its first pid
	proc.add(200, "vesktop", vesktopCgroup, "/dev/video0", "socket:[1]")
	proc.add(150, "vesktop", vesktopCgroup, "/dev/video2")
	proc.add(300, "cheese", "0::/user.slice/app.slice/app-niri-cheese-9.scope", "/dev/null", "/dev/video1")
	// PipeWire's own use shows through its links
	proc.add(400, "pipewire", "0::/user.slice/app.slice/pipewire.service", "/dev/video0")
	proc.add(500, "wireplumber", "0::/", "/dev/video0")
	// Not a camera
	proc.add(600, "foo", "0::/", "/dev/video", "/dev/videoX", "/dev/media0", "/dev/video0-not")
	must(t, os.MkdirAll(filepath.Join(proc.root, "self"), 0o755))

	s := New(Options{Dev: "/dev", Proc: proc.root})
	got := s.scan()
	want := State{Users: []User{
		{Key: "cheese", App: "", Comm: "cheese", PID: 300},
		{Key: "dev.vencord.Vesktop", App: "dev.vencord.Vesktop", Comm: "vesktop", PID: 150},
	}}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("scan = %+v, want %+v", got, want)
	}
}

func TestScanNothing(t *testing.T) {
	t.Parallel()
	got := New(Options{Dev: "/dev", Proc: newFakeProc(t).root}).scan()
	if got.Users == nil || len(got.Users) != 0 {
		t.Errorf("scan = %#v, want an empty, non-nil list", got)
	}
}

func TestFlatpakApp(t *testing.T) {
	t.Parallel()
	for _, c := range []struct{ cgroup, want string }{
		{vesktopCgroup, "dev.vencord.Vesktop"},
		{"0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-flatpak-com.discordapp.Discord-98.scope", "com.discordapp.Discord"},
		{"0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-flatpak-org.my_app.Some-Thing-7.scope", "org.my_app.Some-Thing"},
		{"0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-niri-vesktop-12.scope", ""},
		{"0::/user.slice/user-1000.slice/session-2.scope", ""},
		{"", ""},
	} {
		if got := FlatpakApp(c.cgroup); got != c.want {
			t.Errorf("FlatpakApp(%q) = %q, want %q", c.cgroup, got, c.want)
		}
	}
}

// The watch: a device made after the start is watched, and its open and
// close are each a new state.
func TestRunFollowsOpens(t *testing.T) {
	t.Parallel()
	dev := t.TempDir()
	proc := newFakeProc(t)
	var mu sync.Mutex
	var states []State
	s := New(Options{Dev: dev, Proc: proc.root, Settle: 10 * time.Millisecond, OnChange: func(st State) {
		mu.Lock()
		states = append(states, st)
		mu.Unlock()
	}})
	last := func() (State, int) {
		mu.Lock()
		defer mu.Unlock()
		if len(states) == 0 {
			return State{}, 0
		}
		return states[len(states)-1], len(states)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- s.Run(ctx) }()
	t.Cleanup(func() {
		cancel()
		select {
		case <-done:
		case <-time.After(testkit.Bound(5 * time.Second)):
			t.Error("Run didn't end with its context")
		}
	})
	// Started: the first read finds nobody, the state it starts with
	if !testkit.Eventually(func() bool { s.mu.Lock(); defer s.mu.Unlock(); return s.w != nil }) {
		t.Fatal("Run never started watching")
	}

	video := filepath.Join(dev, "video0")
	must(t, os.WriteFile(video, nil, 0o644))
	// A device coming isn't a change by itself: it gets its watch (an
	// open before that isn't seen, but a real device is there before any
	// app opens it)
	if !testkit.Eventually(func() bool { return s.watching("video0") }) {
		t.Fatal("the new device was never watched")
	}
	proc.add(42, "vesktop", vesktopCgroup, video)
	f, err := os.Open(video)
	must(t, err)
	want := []User{{Key: "dev.vencord.Vesktop", App: "dev.vencord.Vesktop", Comm: "vesktop", PID: 42}}
	if !testkit.Eventually(func() bool { st, _ := last(); return reflect.DeepEqual(st.Users, want) }) {
		st, _ := last()
		t.Fatalf("after the open: %+v, want %+v", st.Users, want)
	}

	proc.remove(42)
	must(t, f.Close())
	if !testkit.Eventually(func() bool { st, n := last(); return n >= 2 && len(st.Users) == 0 }) {
		st, _ := last()
		t.Fatalf("after the close: %+v, want nobody", st.Users)
	}
	if s.State().Users == nil {
		t.Error("State's Users is nil, want an empty list")
	}
}

// watching: Run watches the device name.
func (s *Service) watching(name string) bool {
	s.mu.Lock()
	w := s.w
	s.mu.Unlock()
	return w != nil && w.watching(name)
}

// A device plugged in is root-only until udev grants the seat access:
// its watch fails then, and is made once its access changes.
func TestRunWatchesOnceReadable(t *testing.T) {
	t.Parallel()
	if os.Geteuid() == 0 {
		t.Skip("root reads every file: a device is never unreadable")
	}
	dev := t.TempDir()
	s := New(Options{Dev: dev, Proc: newFakeProc(t).root, Settle: 10 * time.Millisecond})
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- s.Run(ctx) }()
	t.Cleanup(func() {
		cancel()
		select {
		case <-done:
		case <-time.After(testkit.Bound(5 * time.Second)):
			t.Error("Run didn't end with its context")
		}
	})
	if !testkit.Eventually(func() bool { s.mu.Lock(); defer s.mu.Unlock(); return s.w != nil }) {
		t.Fatal("Run never started watching")
	}

	video := filepath.Join(dev, "video0")
	must(t, os.WriteFile(video, nil, 0o000))
	// Its creation is read, and its watch refused
	time.Sleep(testkit.Bound(50 * time.Millisecond))
	if s.watching("video0") {
		t.Fatal("an unreadable device was watched")
	}
	must(t, os.Chmod(video, 0o644))
	if !testkit.Eventually(func() bool { return s.watching("video0") }) {
		t.Fatal("the device was never watched once readable")
	}
}
