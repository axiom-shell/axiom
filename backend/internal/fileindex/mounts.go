package fileindex

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"golang.org/x/sys/unix"
)

// mountinfo is the kernel's mount table as this process sees it
const mountinfo = "/proc/self/mountinfo"

// mounts is the mount table: each mount point's device and whether its
// filesystem is on the network. A read never stats a mount point, as
// stat-ing one whose server is gone (a stale sshfs or NFS mount) blocks
// in the kernel: the folders below a root on another device are left
// out by their path alone.
type mounts struct {
	points map[string]mount
}

type mount struct {
	dev     uint64
	network bool
}

// readMounts reads the mount table at path (empty when it can't be read:
// nothing is skipped by path then, only by device as before).
func readMounts(path string) mounts {
	data, err := os.ReadFile(path)
	if err != nil {
		return mounts{}
	}
	return parseMounts(string(data))
}

// parseMounts parses mountinfo lines ("36 35 98:0 / /mnt rw - ext4 …":
// field 3 the device, 5 the mount point, the first after "-" the type).
// A point mounted over keeps the last (topmost) mount.
func parseMounts(data string) mounts {
	m := mounts{points: map[string]mount{}}
	for line := range strings.SplitSeq(data, "\n") {
		fields := strings.Fields(line)
		sep := -1
		for i, f := range fields {
			if f == "-" && i >= 6 {
				sep = i
				break
			}
		}
		if sep < 0 || sep+1 >= len(fields) {
			continue
		}
		major, minor, ok := strings.Cut(fields[2], ":")
		if !ok {
			continue
		}
		ma, err1 := strconv.ParseUint(major, 10, 32)
		mi, err2 := strconv.ParseUint(minor, 10, 32)
		if err1 != nil || err2 != nil {
			continue
		}
		m.points[unescapeMount(fields[4])] = mount{dev: unix.Mkdev(uint32(ma), uint32(mi)), network: networkFS(fields[sep+1])}
	}
	return m
}

// unescapeMount undoes mountinfo's octal escapes (\040 a space, \011 a
// tab, \012 a newline, \134 a backslash).
func unescapeMount(s string) string {
	if !strings.Contains(s, `\`) {
		return s
	}
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == '\\' && i+4 <= len(s) {
			if n, err := strconv.ParseUint(s[i+1:i+4], 8, 8); err == nil {
				b.WriteByte(byte(n))
				i += 3
				continue
			}
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

// networkFS says whether a filesystem type is one whose files a server
// serves, which may stop answering: NFS, SMB, and every FUSE filesystem
// but a block device's (sshfs, rclone, gvfs; a local one such as
// gocryptfs too, as nothing tells them apart)
func networkFS(fstype string) bool {
	switch fstype {
	case "nfs", "nfs4", "cifs", "smb3", "smbfs", "ceph", "glusterfs", "afs", "9p", "davfs":
		return true
	}
	return strings.HasPrefix(fstype, "fuse.")
}

// foreign says whether path is a mount point of a device other than dev
// (left out unstat-ed: another device, maybe one that hangs).
func (m mounts) foreign(path string, dev uint64) bool {
	p, ok := m.points[path]
	return ok && p.dev != dev
}

// network says whether path is on a network filesystem: the mount
// holding it (the deepest mount point it's at or below) is one.
func (m mounts) network(path string) bool {
	best, net := -1, false
	for mp, p := range m.points {
		if len(mp) > best && within(path, mp) {
			best, net = len(mp), p.network
		}
	}
	return net
}

// networkRoot says whether root is on a network filesystem, following
// the links it is (root itself, not its folders) by readlink alone,
// which never stats the target, and never through a network mount: a
// root that is a link to a network mount is that mount's.
func (m mounts) networkRoot(root string) bool {
	path := root
	for range 8 {
		if m.network(path) {
			return true
		}
		target, err := os.Readlink(path)
		if err != nil {
			return false
		}
		if !strings.HasPrefix(target, "/") {
			target = join(filepath.Dir(path), target)
		}
		path = filepath.Clean(target)
	}
	return m.network(path)
}
