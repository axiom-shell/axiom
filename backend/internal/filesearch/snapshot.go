package filesearch

import (
	"encoding/binary"
	"errors"
	"hash/crc32"
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

// persisted flags (watching is the running daemon's)
const savedFlags = flagDir | flagHidden | flagRoot | flagLink

// Encode is the index as the cache keeps it, made for settings key.
func (ix *Index) Encode(key uint64) []byte {
	out := make([]byte, headerSize, headerSize+ix.Len()*20)
	copy(out, snapshotMagic)
	binary.LittleEndian.PutUint32(out[4:], snapshotVersion)
	binary.LittleEndian.PutUint64(out[8:], key)
	pos := make(map[uint32]uint32, ix.Folders())
	count := uint32(0)
	put := func(i, parent uint32) {
		e := ix.at(i)
		name := ix.name(e)
		var rec [4 + 1 + 4 + 4 + 2]byte
		binary.LittleEndian.PutUint32(rec[0:], parent)
		rec[4] = e.flags & savedFlags
		binary.LittleEndian.PutUint32(rec[5:], e.mtime)
		binary.LittleEndian.PutUint32(rec[9:], e.nsec)
		binary.LittleEndian.PutUint16(rec[13:], uint16(len(name)))
		out = append(out, rec[:]...)
		out = append(out, name...)
		if e.flags&flagDir != 0 {
			pos[i] = count
		}
		count++
	}
	for _, r := range ix.roots {
		if ix.Removed(r) {
			continue
		}
		put(r, NoEntry)
		queue := []uint32{r}
		for len(queue) > 0 {
			d := queue[0]
			queue = queue[1:]
			for c := ix.at(d).child; c != NoEntry; c = ix.at(c).next {
				put(c, pos[d])
				if ix.IsDir(c) {
					queue = append(queue, c)
				}
			}
		}
	}
	binary.LittleEndian.PutUint32(out[16:], count)
	return binary.LittleEndian.AppendUint32(out, crc32.ChecksumIEEE(out))
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
