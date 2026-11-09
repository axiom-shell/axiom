package fileindex

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

func TestParseMounts(t *testing.T) {
	t.Parallel()
	m := parseMounts(`22 1 259:2 / / rw,relatime shared:1 - ext4 /dev/nvme0n1p2 rw
40 22 0:50 / /home/u/remote rw,nosuid shared:9 - fuse.sshfs u@host: rw
41 22 0:51 / /mnt/nas rw shared:10 master:3 - nfs4 nas:/ rw
42 22 0:52 / /home/u/my\040disk rw - btrfs /dev/sda1 rw
43 41 0:53 / /mnt/nas rw - tmpfs tmpfs rw
44 22 8:17 / /home/u/usb rw - fuseblk /dev/sdb1 rw
not a mount line
`)
	cases := []struct {
		path    string
		dev     uint64
		mounted bool
		network bool
	}{
		{"/", unix.Mkdev(259, 2), true, false},
		{"/home/u/remote", unix.Mkdev(0, 50), true, true},
		{"/home/u/remote/x/y", 0, false, true},
		// mounted over: the topmost
		{"/mnt/nas", unix.Mkdev(0, 53), true, false},
		{"/home/u/my disk", unix.Mkdev(0, 52), true, false},
		// a disk's FUSE driver isn't a network's
		{"/home/u/usb", unix.Mkdev(8, 17), true, false},
		{"/home/u", 0, false, false},
	}
	for _, c := range cases {
		p, ok := m.points[c.path]
		if ok != c.mounted || ok && p.dev != c.dev {
			t.Errorf("%s: mount %+v %v, want dev %d %v", c.path, p, ok, c.dev, c.mounted)
		}
		if got := m.network(c.path); got != c.network {
			t.Errorf("%s: network %v, want %v", c.path, got, c.network)
		}
	}
}

// fakeMounts writes a mount table naming the given points (each on a
// network filesystem when asked) and returns its path
func fakeMounts(t *testing.T, network bool, points ...string) string {
	t.Helper()
	data := ""
	fstype := "ext4"
	if network {
		fstype = "fuse.sshfs"
	}
	for i, p := range points {
		data += fmt.Sprintf("%d 1 0:%d / %s rw - %s src rw\n", 100+i, 900+i, p, fstype)
	}
	path := filepath.Join(t.TempDir(), "mountinfo")
	if err := os.WriteFile(path, []byte(data), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

// A mount point of another device is left out by its path, never
// stat-ed (one whose server is gone blocks); the root's own device's
// mount points (a bind mount) are kept
func TestReadSkipsMountPointsByPath(t *testing.T) {
	t.Parallel()
	root := tree(t, "a/x", "m/y", "same/z", "f")
	var st unix.Stat_t
	if err := unix.Stat(root, &st); err != nil {
		t.Fatal(err)
	}
	f := newFilter([]string{root}, nil, nil, false)
	m := parseMounts(fmt.Sprintf("1 1 0:999 / %s/m rw - fuse.sshfs h: rw\n", root))
	m.points[root+"/same"] = mount{dev: st.Dev}
	f.setMounts(m)
	fo, err := f.read(root, root)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, k := range fo.kids {
		names = append(names, string(k.Name))
	}
	if len(names) != 3 || !slices.Contains(names, "a") || !slices.Contains(names, "same") || !slices.Contains(names, "f") {
		t.Errorf("read %v", names)
	}
}

// A root on a network filesystem, or a link to one, is never read or
// watched by the daemon itself: its changes wait for the stat pass, in
// the idle child
func TestNetworkRootLeftToTheChild(t *testing.T) {
	t.Parallel()
	base := tree(t, "nas/a/x", "home/b/y")
	nas, home := base+"/nas", base+"/home"
	link := base + "/link"
	if err := os.Symlink(nas, link); err != nil {
		t.Fatal(err)
	}
	m := parseMounts(fmt.Sprintf("1 1 0:999 / %s rw - nfs4 nas:/ rw\n", nas))
	f := newFilter([]string{link, home}, nil, nil, false)
	f.setMounts(m)
	if !f.onNetwork(link+"/a") || f.onNetwork(home+"/b") {
		t.Fatalf("network roots %v", f.netRoots)
	}

	now := time.Now()
	l := loopOn(t, link, &now)
	l.s.o.Mountinfo = fakeMounts(t, true, nas)
	l.refreshMounts()
	w, err := newWatcher(100)
	if err != nil {
		t.Fatal(err)
	}
	defer w.close()
	l.w = w
	fo, err := l.f.read(link, link+"/a")
	if err != nil {
		t.Fatal(err)
	}
	l.applyDir(link+"/a", fo.mtime, fo.kids, false)
	if len(w.byPath) != 0 {
		t.Errorf("a network root's folder watched: %v", w.byPath)
	}
	// A change asked of the loop isn't read there
	n := l.ix().Len()
	os.WriteFile(nas+"/a/new", nil, 0o600)
	l.changedDir(link + "/a")
	l.flush()
	if l.ix().Len() != n {
		t.Errorf("the loop read a network root's folder: %d entries, had %d", l.ix().Len(), n)
	}
}

// A root below a link to a network mount (~/nas/docs, ~/nas -> /mnt/nas)
// is that mount's too, found by readlink alone
func TestNetworkRootBelowALink(t *testing.T) {
	t.Parallel()
	base := tree(t, "nas/docs/x", "home/y")
	link := base + "/home/nas"
	if err := os.Symlink("../nas", link); err != nil {
		t.Fatal(err)
	}
	m := parseMounts(fmt.Sprintf("1 1 0:999 / %s rw - nfs4 nas:/ rw\n", base+"/nas"))
	if !m.networkRoot(link+"/docs") || m.networkRoot(base+"/home") {
		t.Errorf("a root below a link to a network mount")
	}
}

// A share mounted over a watched root drops its folders' watches (they
// sat on what was there before) and asks the child's stat pass
func TestShareMountedOverAWatchedRoot(t *testing.T) {
	t.Parallel()
	root := tree(t, "a/x")
	now := time.Now()
	l := loopOn(t, root, &now)
	l.s.o.Mountinfo = fakeMounts(t, false)
	w, err := newWatcher(100)
	if err != nil {
		t.Fatal(err)
	}
	defer w.close()
	l.w = w
	l.refreshMounts()
	l.readDir(t, root+"/a")
	if len(w.byPath) == 0 {
		t.Fatal("nothing watched")
	}
	l.s.o.Mountinfo = fakeMounts(t, true, root)
	l.refreshMounts()
	if len(w.byPath) != 0 || !l.statUnwatched {
		t.Errorf("watches %v, stat pass asked %v", w.byPath, l.statUnwatched)
	}
	ix := l.ix()
	if d, ok := ix.Lookup(root + "/a"); !ok || ix.Watched(d) {
		t.Errorf("a network root's folder still marked watched")
	}
}
