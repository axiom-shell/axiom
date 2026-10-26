package unixmsg

import (
	"errors"
	"io"
	"net"
	"os"
	"testing"

	"golang.org/x/sys/unix"
)

// pair is a connected pair of Conns over a socketpair.
func pair(t *testing.T) (*Conn, *Conn) {
	t.Helper()
	fds, err := unix.Socketpair(unix.AF_UNIX, unix.SOCK_STREAM|unix.SOCK_CLOEXEC, 0)
	if err != nil {
		t.Fatal(err)
	}
	conn := func(fd int) *Conn {
		f := os.NewFile(uintptr(fd), "sock")
		nc, err := net.FileConn(f)
		f.Close()
		if err != nil {
			t.Fatal(err)
		}
		c := New(nc.(*net.UnixConn))
		t.Cleanup(func() { c.Close() })
		return c
	}
	return conn(fds[0]), conn(fds[1])
}

// tempFile is a file holding text.
func tempFile(t *testing.T, text string) *os.File {
	t.Helper()
	f, err := os.CreateTemp(t.TempDir(), "fd")
	if err != nil {
		t.Fatal(err)
	}
	f.WriteString(text)
	t.Cleanup(func() { f.Close() })
	return f
}

func contents(t *testing.T, f *os.File) string {
	t.Helper()
	if _, err := f.Seek(0, io.SeekStart); err != nil {
		t.Fatal(err)
	}
	b, err := io.ReadAll(f)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestDescriptorsArriveInOrderAndCloseOnExec(t *testing.T) {
	t.Parallel()
	a, b := pair(t)
	one, two, three := tempFile(t, "one"), tempFile(t, "two"), tempFile(t, "three")
	if err := a.WriteMsg([]byte("ab"), []int{int(one.Fd()), int(two.Fd())}); err != nil {
		t.Fatal(err)
	}
	if err := a.WriteMsg([]byte("c"), []int{int(three.Fd())}); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 3)
	if _, err := io.ReadFull(b, buf); err != nil {
		t.Fatal(err)
	}
	if string(buf) != "abc" {
		t.Fatalf("read %q", buf)
	}
	for _, want := range []string{"one", "two", "three"} {
		f, err := b.TakeFD()
		if err != nil {
			t.Fatal(err)
		}
		flags, err := unix.FcntlInt(f.Fd(), unix.F_GETFD, 0)
		if err != nil || flags&unix.FD_CLOEXEC == 0 {
			t.Errorf("%s: not close-on-exec (flags %d, %v)", want, flags, err)
		}
		if got := contents(t, f); got != want {
			t.Errorf("got %q, want %q", got, want)
		}
		f.Close()
	}
	if _, err := b.TakeFD(); !errors.Is(err, ErrNoFD) {
		t.Errorf("an empty queue gave %v", err)
	}
}

// Not parallel: it checks a descriptor number, which another test could
// reuse once closed
func TestCloseClosesUntakenDescriptors(t *testing.T) {
	a, b := pair(t)
	f := tempFile(t, "x")
	if err := a.WriteMsg([]byte("x"), []int{int(f.Fd())}); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 1)
	if _, err := b.Read(buf); err != nil {
		t.Fatal(err)
	}
	b.mu.Lock()
	fd := b.fds[0]
	b.mu.Unlock()
	b.Close()
	if _, err := unix.FcntlInt(uintptr(fd), unix.F_GETFD, 0); !errors.Is(err, unix.EBADF) {
		t.Errorf("the untaken descriptor is still open (%v)", err)
	}
}

func TestReadEOF(t *testing.T) {
	t.Parallel()
	a, b := pair(t)
	a.Close()
	if _, err := b.Read(make([]byte, 4)); !errors.Is(err, io.EOF) {
		t.Errorf("got %v, want EOF", err)
	}
}

func TestWriteRefusesTooManyDescriptors(t *testing.T) {
	t.Parallel()
	a, _ := pair(t)
	if err := a.WriteMsg([]byte("x"), make([]int, maxFDs+1)); err == nil {
		t.Error("too many descriptors were accepted")
	}
}
