// Package filesearch is the launcher's file index and its search: the
// names under the user's roots kept in flat tables with no pointers (one
// byte arena of names, fixed-size entries pointing at their parent folder,
// so a million files cost the garbage collector nothing to scan), the
// typed pattern (smart case, every token matching, fzf-style folder
// segments), the ranking (Search.score's tiers, recency and use), the
// on-disk cache's format, the excludes, and the recent files' xbel.
// fileindex fills and watches it; the daemon's filesearch part answers
// from it. Docs: docs/dev/features/file-search.md.
//
// Pure: no I/O; the edge packages hand it what they read.
package filesearch

import (
	"bytes"
	"slices"
	"strings"
	"sync"
)

// NoEntry is no entry: a root's parent, an empty child list, a search
// over every root.
const NoEntry = ^uint32(0)

// Entries and names are kept in chunks, so growing the index never copies
// what it holds (a copy of a 30 MB table would hold the write lock for
// milliseconds)
const (
	chunkBits = 16
	chunkSize = 1 << chunkBits
	// nameChunk is one names chunk's size; a name never spans two
	nameChunkBits = 20
	nameChunk     = 1 << nameChunkBits
)

// Flags of an entry
const (
	flagDir uint8 = 1 << iota
	// flagHidden: its name, or a folder's between it and its root,
	// starts with "."
	flagHidden
	flagRoot
	flagRemoved
	// flagWatched: fileindex holds an inotify watch on the folder
	flagWatched
	// flagLink: a symbolic link, indexed by its name and never followed
	flagLink
	// flagLeftOut: a folder whose last read left entries out at the cap
	flagLeftOut
)

// entry is one file or folder: 32 bytes, no pointers.
type entry struct {
	nameOff uint32 // name chunk << nameChunkBits | offset
	nameLen uint16
	flags   uint8
	depth   uint8  // 0 for a root, capped at 255
	parent  uint32 // NoEntry for a root
	child   uint32 // a folder's first child
	next    uint32 // the next child of the same folder
	mask    uint32 // the name's character classes (maskOf)
	mtime   uint32 // seconds since the epoch (to 2106)
	nsec    uint32 // and its nanoseconds: a folder's change within a second
}

// Child is one entry of a folder as read from the disk.
type Child struct {
	Name  []byte
	Dir   bool
	Link  bool
	Mtime int64 // nanoseconds since the epoch
}

// Change is what ReplaceDir did.
type Change struct {
	// NewDirs are the folders it added, their contents not read yet
	NewDirs []uint32
	// GoneWatched are the removed folders that were watched (still
	// readable by Path until the index is compacted)
	GoneWatched []uint32
	Added       int
	Removed     int
	// Truncated: entries were left out at the index's cap (the folder
	// is marked: LeftOut)
	Truncated bool
}

// Index is the file index. It isn't safe for concurrent use: one writer
// changes it under its owner's write lock, readers search it under the
// read lock.
type Index struct {
	entries [][]entry
	n       uint32 // entries used, removed ones included
	removed uint32
	folders uint32 // folders not removed, roots included
	leftOut uint32 // folders marked flagLeftOut, not removed
	names   [][]byte
	// The folders by their path's hash (no strings for the collector to
	// scan); collide holds the rare path whose hash another took
	dirs    map[uint64]uint32
	collide map[string]uint32
	// dirList is every folder ever added, in order: a parent always
	// comes before its children (an entry is never moved, only removed
	// and added anew)
	dirList []uint32
	roots   []uint32
	// spare is a search's tables, kept for the next
	spareMu sync.Mutex
	spare   *scratch
}

// New is an empty index.
func New() *Index {
	return &Index{dirs: map[uint64]uint32{}, collide: map[string]uint32{}}
}

func (ix *Index) at(i uint32) *entry { return &ix.entries[i>>chunkBits][i&(chunkSize-1)] }

func (ix *Index) name(e *entry) []byte {
	c := ix.names[e.nameOff>>nameChunkBits]
	off := e.nameOff & (nameChunk - 1)
	return c[off : off+uint32(e.nameLen)]
}

// Len is the number of entries, roots included, removed ones not.
func (ix *Index) Len() int { return int(ix.n - ix.removed) }

// Folders is the number of folders, roots included (counted as they're
// added and removed: the state reads it for every folder a crawl sends).
func (ix *Index) Folders() int { return int(ix.folders) }

// LeftOut is the number of folders whose last read left entries out at
// the cap (LeftOutDir).
func (ix *Index) LeftOut() int { return int(ix.leftOut) }

// LeftOutDir says whether folder d's last read left entries out at the
// cap: its time is the one read, so only a forced read finds them.
func (ix *Index) LeftOutDir(d uint32) bool { return ix.at(d).flags&flagLeftOut != 0 }

// ClearLeftOut unmarks folder d (LeftOutDir): it can't be read, so a
// refill would ask for it again and again.
func (ix *Index) ClearLeftOut(d uint32) {
	if e := ix.at(d); e.flags&flagLeftOut != 0 {
		e.flags &^= flagLeftOut
		ix.leftOut--
	}
}

// Roots are the roots' entries, in the order added.
func (ix *Index) Roots() []uint32 { return ix.roots }

// Name is an entry's name (a root's is its whole path).
func (ix *Index) Name(i uint32) string { return string(ix.name(ix.at(i))) }

// IsDir says whether an entry is a folder.
func (ix *Index) IsDir(i uint32) bool { return ix.at(i).flags&flagDir != 0 }

// IsRoot says whether an entry is a root.
func (ix *Index) IsRoot(i uint32) bool { return ix.at(i).flags&flagRoot != 0 }

// Removed says whether an entry was removed.
func (ix *Index) Removed(i uint32) bool { return ix.at(i).flags&flagRemoved != 0 }

// Mtime is an entry's modification time, in nanoseconds since the epoch
// (0 for a folder whose contents weren't read yet).
func (ix *Index) Mtime(i uint32) int64 {
	e := ix.at(i)
	return int64(e.mtime)*1e9 + int64(e.nsec)
}

// SetMtime sets a file's modification time (a write seen by a watch).
func (ix *Index) SetMtime(i uint32, ns int64) { setMtime(ix.at(i), ns) }

// Watched says whether a folder is marked watched.
func (ix *Index) Watched(i uint32) bool { return ix.at(i).flags&flagWatched != 0 }

// SetWatched marks a folder watched or not.
func (ix *Index) SetWatched(i uint32, on bool) {
	e := ix.at(i)
	if on {
		e.flags |= flagWatched
	} else {
		e.flags &^= flagWatched
	}
}

// Path is an entry's whole path.
func (ix *Index) Path(i uint32) string {
	var stack [64][]byte
	parts := stack[:0]
	size := 0
	for j := i; j != NoEntry; {
		e := ix.at(j)
		n := ix.name(e)
		parts = append(parts, n)
		size += len(n) + 1
		j = e.parent
	}
	var b strings.Builder
	b.Grow(size)
	for k := len(parts) - 1; k >= 0; k-- {
		b.Write(parts[k])
		if k > 0 && !bytes.HasSuffix(parts[k], []byte("/")) {
			b.WriteByte('/')
		}
	}
	return b.String()
}

// EachDir calls fn with every folder that wasn't removed, a parent before
// its children.
func (ix *Index) EachDir(fn func(i uint32)) {
	for _, d := range ix.dirList {
		if ix.at(d).flags&flagRemoved == 0 {
			fn(d)
		}
	}
}

// Lookup is the folder at path (a root, or a folder under one).
func (ix *Index) Lookup(path string) (uint32, bool) {
	if i, ok := ix.collide[path]; ok {
		return i, true
	}
	i, ok := ix.dirs[hashString(path)]
	if !ok || ix.Path(i) != path {
		return NoEntry, false
	}
	return i, true
}

// FindAll is the entries at paths, file or folder, those found by path: each
// folder's entries are walked once, however many of its names are asked
// (a walk per path would cost the folder's size each).
func (ix *Index) FindAll(paths []string) map[string]uint32 {
	out := make(map[string]uint32, len(paths))
	byDir := map[string]map[string]string{}
	for _, p := range paths {
		if i, ok := ix.Lookup(p); ok {
			out[p] = i
			continue
		}
		cut := strings.LastIndexByte(p, '/')
		if cut < 0 {
			continue
		}
		dir := p[:cut]
		if dir == "" {
			dir = "/"
		}
		if byDir[dir] == nil {
			byDir[dir] = map[string]string{}
		}
		byDir[dir][p[cut+1:]] = p
	}
	for dir, names := range byDir {
		d, ok := ix.Lookup(dir)
		if !ok {
			continue
		}
		for c := ix.at(d).child; c != NoEntry && len(names) > 0; c = ix.at(c).next {
			name := ix.name(ix.at(c))
			if p, ok := names[string(name)]; ok {
				out[p] = c
				delete(names, string(name))
			}
		}
	}
	return out
}

// Children are a folder's entries.
func (ix *Index) Children(d uint32) []uint32 {
	var out []uint32
	for c := ix.at(d).child; c != NoEntry; c = ix.at(c).next {
		out = append(out, c)
	}
	return out
}

// AddRoot adds a root folder (an absolute, clean path), or finds it.
func (ix *Index) AddRoot(path string) uint32 {
	if i, ok := ix.Lookup(path); ok && ix.IsRoot(i) {
		return i
	}
	i := ix.add([]byte(path), NoEntry, flagDir|flagRoot, 0, 0)
	ix.registerDir(i, hashString(path))
	ix.roots = append(ix.roots, i)
	return i
}

func (ix *Index) add(name []byte, parent uint32, flags uint8, depth uint8, mtime int64) uint32 {
	if int(ix.n) == len(ix.entries)*chunkSize {
		ix.entries = append(ix.entries, make([]entry, chunkSize))
	}
	i := ix.n
	ix.n++
	off := ix.storeName(name)
	e := ix.at(i)
	*e = entry{nameOff: off, nameLen: uint16(len(name)), flags: flags, depth: depth, parent: parent,
		child: NoEntry, next: NoEntry, mask: maskOf(name)}
	setMtime(e, mtime)
	if flags&flagDir != 0 {
		ix.dirList = append(ix.dirList, i)
		ix.folders++
	}
	if flags&flagLeftOut != 0 {
		ix.leftOut++
	}
	return i
}

func setMtime(e *entry, ns int64) {
	if ns < 0 {
		ns = 0
	}
	e.mtime, e.nsec = uint32(ns/1e9), uint32(ns%1e9)
}

func (ix *Index) storeName(name []byte) uint32 {
	last := len(ix.names) - 1
	if last < 0 || len(ix.names[last])+len(name) > nameChunk {
		ix.names = append(ix.names, make([]byte, 0, nameChunk))
		last++
	}
	off := uint32(len(ix.names[last]))
	ix.names[last] = append(ix.names[last], name...)
	return uint32(last)<<nameChunkBits | off
}

// registerDir files folder i (already linked to its parent) under h.
func (ix *Index) registerDir(i uint32, h uint64) {
	if old, taken := ix.dirs[h]; taken && old != i && ix.at(old).flags&flagRemoved == 0 {
		ix.collide[ix.Path(i)] = i
		return
	}
	ix.dirs[h] = i
}

func (ix *Index) unregisterDir(i uint32, h uint64) {
	if ix.dirs[h] == i {
		delete(ix.dirs, h)
		return
	}
	if len(ix.collide) > 0 {
		delete(ix.collide, ix.Path(i))
	}
}

// ReplaceDir sets folder d's contents (its path, as Path has it, and its
// modification time as read with them) to kids: entries no longer there
// are removed with what they hold, new ones added (while the index holds
// fewer than max entries; 0 is no cap), files' times updated. A folder
// already there keeps its contents and time: only reading it sets them.
// A folder that left entries out is marked (LeftOutDir) until a read of
// it fits.
func (ix *Index) ReplaceDir(d uint32, path string, mtime int64, kids []Child, max int) Change {
	var ch Change
	de := ix.at(d)
	setMtime(de, mtime)
	dh := hashString(path)

	old := ix.Children(d)
	slices.SortFunc(old, func(a, b uint32) int { return bytes.Compare(ix.name(ix.at(a)), ix.name(ix.at(b))) })
	sorted := make([]int, len(kids))
	for k := range sorted {
		sorted[k] = k
	}
	slices.SortFunc(sorted, func(a, b int) int { return bytes.Compare(kids[a].Name, kids[b].Name) })

	keep := make([]uint32, 0, len(kids))
	oi := 0
	for _, k := range sorted {
		kid := kids[k]
		if len(kid.Name) == 0 || len(kid.Name) > 0xffff {
			continue
		}
		for oi < len(old) && bytes.Compare(ix.name(ix.at(old[oi])), kid.Name) < 0 {
			ix.removeTree(old[oi], dh, &ch)
			oi++
		}
		if oi < len(old) && bytes.Equal(ix.name(ix.at(old[oi])), kid.Name) {
			e := ix.at(old[oi])
			if (e.flags&flagDir != 0) == kid.Dir && (e.flags&flagLink != 0) == kid.Link {
				if !kid.Dir {
					setMtime(e, kid.Mtime)
				}
				keep = append(keep, old[oi])
				oi++
				continue
			}
			ix.removeTree(old[oi], dh, &ch)
			oi++
		}
		if max > 0 && ix.Len() >= max {
			ch.Truncated = true
			continue
		}
		keep = append(keep, ix.addChild(d, dh, kid, &ch))
	}
	for ; oi < len(old); oi++ {
		ix.removeTree(old[oi], dh, &ch)
	}
	de = ix.at(d)
	if was := de.flags&flagLeftOut != 0; was != ch.Truncated {
		if ch.Truncated {
			de.flags |= flagLeftOut
			ix.leftOut++
		} else {
			de.flags &^= flagLeftOut
			ix.leftOut--
		}
	}
	// Relink the list, in name order
	de.child = NoEntry
	for k := len(keep) - 1; k >= 0; k-- {
		ix.at(keep[k]).next = de.child
		de.child = keep[k]
	}
	return ch
}

func (ix *Index) addChild(d uint32, dh uint64, kid Child, ch *Change) uint32 {
	pe := ix.at(d)
	flags := uint8(0)
	if pe.flags&flagHidden != 0 || kid.Name[0] == '.' {
		flags |= flagHidden
	}
	if kid.Link {
		flags |= flagLink
	} else if kid.Dir {
		flags |= flagDir
	}
	depth := pe.depth
	if depth < 255 {
		depth++
	}
	mtime := kid.Mtime
	if flags&flagDir != 0 {
		// Unread: its time comes with its contents
		mtime = 0
	}
	i := ix.add(kid.Name, d, flags, depth, mtime)
	ch.Added++
	if flags&flagDir != 0 {
		ix.registerDir(i, childHash(dh, ix.isSlashRoot(d), kid.Name))
		ch.NewDirs = append(ch.NewDirs, i)
	}
	return i
}

// isSlashRoot: the folder's path ends in "/" (the root "/"), so a child's
// path adds no separator
func (ix *Index) isSlashRoot(d uint32) bool {
	n := ix.name(ix.at(d))
	return len(n) > 0 && n[len(n)-1] == '/'
}

// removeTree removes entry i with everything under it; dh is its parent's
// path hash.
func (ix *Index) removeTree(i uint32, dh uint64, ch *Change) {
	type item struct {
		i uint32
		h uint64
	}
	stack := []item{{i, childHash(dh, ix.isSlashRoot(ix.at(i).parent), ix.name(ix.at(i)))}}
	for len(stack) > 0 {
		it := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		e := ix.at(it.i)
		if e.flags&flagRemoved != 0 {
			continue
		}
		if e.flags&flagDir != 0 {
			for c := e.child; c != NoEntry; c = ix.at(c).next {
				stack = append(stack, item{c, childHash(it.h, false, ix.name(ix.at(c)))})
			}
			if e.flags&flagWatched != 0 {
				ch.GoneWatched = append(ch.GoneWatched, it.i)
			}
			ix.unregisterDir(it.i, it.h)
			ix.folders--
			if e.flags&flagLeftOut != 0 {
				ix.leftOut--
			}
		}
		e.flags |= flagRemoved
		ix.removed++
		ch.Removed++
	}
}

// NeedsCompact: removed entries passed a quarter of the index.
func (ix *Index) NeedsCompact() bool { return ix.n > 1024 && ix.removed*4 > ix.n }

// Compact is a copy of the index without its removed entries (the
// original is only read, so searches may go on in it meanwhile).
func (ix *Index) Compact() *Index {
	out := New()
	remap := make([]uint32, ix.n)
	for _, r := range ix.roots {
		if ix.at(r).flags&flagRemoved != 0 {
			continue
		}
		path := ix.Path(r)
		nr := out.AddRoot(path)
		out.at(nr).flags |= ix.at(r).flags & flagWatched
		if ix.LeftOutDir(r) {
			out.at(nr).flags |= flagLeftOut
			out.leftOut++
		}
		setMtime(out.at(nr), ix.Mtime(r))
		remap[r] = nr
		queue := []uint32{r}
		for len(queue) > 0 {
			d := queue[0]
			queue = queue[1:]
			nd := remap[d]
			var last uint32 = NoEntry
			for c := ix.at(d).child; c != NoEntry; c = ix.at(c).next {
				e := ix.at(c)
				ni := out.add(ix.name(e), nd, e.flags, e.depth, 0)
				ne := out.at(ni)
				ne.mtime, ne.nsec = e.mtime, e.nsec
				if last == NoEntry {
					out.at(nd).child = ni
				} else {
					out.at(last).next = ni
				}
				last = ni
				remap[c] = ni
				if e.flags&flagDir != 0 {
					queue = append(queue, c)
				}
			}
		}
	}
	out.rehash()
	return out
}

// rehash registers every folder's path hash, a parent's before its
// children's (dirList's order).
func (ix *Index) rehash() {
	clear(ix.dirs)
	clear(ix.collide)
	hashes := make(map[uint32]uint64, len(ix.dirList))
	for _, d := range ix.dirList {
		e := ix.at(d)
		var h uint64
		if e.parent == NoEntry {
			h = hashString(string(ix.name(e)))
		} else {
			h = childHash(hashes[e.parent], ix.isSlashRoot(e.parent), ix.name(e))
		}
		hashes[d] = h
		if e.flags&flagRemoved == 0 {
			ix.registerDir(d, h)
		}
	}
}

// FNV-1a, 64 bits: a path's hash continues its folder's
const (
	fnvOffset = 14695981039346656037
	fnvPrime  = 1099511628211
)

func hashString(s string) uint64 {
	h := uint64(fnvOffset)
	for i := 0; i < len(s); i++ {
		h = (h ^ uint64(s[i])) * fnvPrime
	}
	return h
}

func childHash(parent uint64, slashRoot bool, name []byte) uint64 {
	h := parent
	if !slashRoot {
		h = (h ^ '/') * fnvPrime
	}
	for _, c := range name {
		h = (h ^ uint64(c)) * fnvPrime
	}
	return h
}
