package filesearch

import (
	"bufio"
	"encoding/binary"
	"errors"
	"fmt"
	"hash/crc32"
	"io"
)

// The cache's format: a header (magic, version, the settings' key, the
// entry count), the entries in breadth-first order (each its parent's
// position, flags, time and name), and a CRC32 of all of it at the end.
const (
	snapshotMagic   = "AXFI"
	snapshotVersion = 1
	headerSize      = 4 + 4 + 8 + 4
)

// Errors decoding a snapshot: each means the index is built again.
var (
	ErrBadSnapshot   = errors.New("filesearch: the cache is damaged")
	ErrOldSnapshot   = errors.New("filesearch: the cache is of another version")
	ErrOtherSettings = errors.New("filesearch: the cache was made for other roots or excludes")
)

// persisted flags (watching is the running daemon's; a folder left out
// at the cap is kept so a later run reads it again once there's room)
const savedFlags = flagDir | flagHidden | flagRoot | flagLink | flagLeftOut

// Encode writes the index as the cache keeps it, made for settings key,
// to w through a small buffer: nothing the index's size is allocated.
// The caller keeps the index from changing meanwhile (a read lock will
// do: Encode only reads).
func (ix *Index) Encode(w io.Writer, key uint64) error {
	sum := crc32.NewIEEE()
	bw := bufio.NewWriterSize(io.MultiWriter(w, sum), 64<<10)
	count := uint32(ix.Len())
	head := make([]byte, headerSize)
	copy(head, snapshotMagic)
	binary.LittleEndian.PutUint32(head[4:], snapshotVersion)
	binary.LittleEndian.PutUint64(head[8:], key)
	binary.LittleEndian.PutUint32(head[16:], count)
	bw.Write(head)
	// A folder's position travels with it in the queue; a parent always
	// comes before its children
	type queued struct{ d, pos uint32 }
	var queue []queued
	written := uint32(0)
	rec := make([]byte, 4+1+4+4+2)
	put := func(i, parent uint32) {
		e := ix.at(i)
		name := ix.name(e)
		binary.LittleEndian.PutUint32(rec[0:], parent)
		rec[4] = e.flags & savedFlags
		binary.LittleEndian.PutUint32(rec[5:], e.mtime)
		binary.LittleEndian.PutUint32(rec[9:], e.nsec)
		binary.LittleEndian.PutUint16(rec[13:], uint16(len(name)))
		bw.Write(rec)
		bw.Write(name)
		if e.flags&flagDir != 0 {
			queue = append(queue, queued{i, written})
		}
		written++
	}
	for _, r := range ix.roots {
		if ix.Removed(r) {
			continue
		}
		queue = queue[:0]
		put(r, NoEntry)
		for k := 0; k < len(queue); k++ {
			q := queue[k]
			for c := ix.at(q.d).child; c != NoEntry; c = ix.at(c).next {
				put(c, q.pos)
			}
		}
	}
	if err := bw.Flush(); err != nil {
		return err
	}
	if written != count {
		// Every entry not removed hangs off a root: never happens
		return fmt.Errorf("filesearch: encoded %d entries of %d", written, count)
	}
	_, err := w.Write(binary.LittleEndian.AppendUint32(nil, sum.Sum32()))
	return err
}

// Decode reads a cache Encode wrote for settings key.
func Decode(data []byte, key uint64) (*Index, error) {
	if len(data) < headerSize+4 || string(data[:4]) != snapshotMagic {
		return nil, ErrBadSnapshot
	}
	body, sum := data[:len(data)-4], binary.LittleEndian.Uint32(data[len(data)-4:])
	if crc32.ChecksumIEEE(body) != sum {
		return nil, ErrBadSnapshot
	}
	if binary.LittleEndian.Uint32(data[4:]) != snapshotVersion {
		return nil, ErrOldSnapshot
	}
	if binary.LittleEndian.Uint64(data[8:]) != key {
		return nil, ErrOtherSettings
	}
	count := binary.LittleEndian.Uint32(data[16:])
	ix := New()
	last := map[uint32]uint32{} // a folder's last child so far
	rest := body[headerSize:]
	for k := uint32(0); k < count; k++ {
		if len(rest) < 15 {
			return nil, ErrBadSnapshot
		}
		parent := binary.LittleEndian.Uint32(rest[0:])
		flags := rest[4] & savedFlags
		mtime, nsec := binary.LittleEndian.Uint32(rest[5:]), binary.LittleEndian.Uint32(rest[9:])
		n := int(binary.LittleEndian.Uint16(rest[13:]))
		if len(rest) < 15+n || n == 0 {
			return nil, ErrBadSnapshot
		}
		name := rest[15 : 15+n]
		rest = rest[15+n:]
		var i uint32
		if parent == NoEntry {
			if flags&flagRoot == 0 {
				return nil, ErrBadSnapshot
			}
			i = ix.add(name, NoEntry, flags, 0, 0)
			ix.roots = append(ix.roots, i)
		} else {
			if parent >= k || !ix.IsDir(parent) || flags&flagRoot != 0 {
				return nil, ErrBadSnapshot
			}
			pe := ix.at(parent)
			depth := pe.depth
			if depth < 255 {
				depth++
			}
			i = ix.add(name, parent, flags, depth, 0)
			if l, ok := last[parent]; ok {
				ix.at(l).next = i
			} else {
				pe.child = i
			}
			last[parent] = i
		}
		e := ix.at(i)
		e.mtime, e.nsec = mtime, nsec
	}
	if len(rest) != 0 {
		return nil, ErrBadSnapshot
	}
	ix.rehash()
	return ix, nil
}
