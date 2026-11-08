package filesearch

import (
	"slices"
	"sync"
	"sync/atomic"
)

// staleEvery is how many entries a shard scans between asking whether a
// newer query replaced its own
const staleEvery = 16 << 10

// Ranking: a match in a folder's name instead of the entry's own counts
// this much of it
const folderMatch = 0.6

// Query is one search of the index.
type Query struct {
	Pattern Pattern
	// Under keeps entries below this folder (NoEntry: every root)
	Under uint32
	// Hidden keeps hidden entries (always, below a hidden Under)
	Hidden bool
	Limit  int
	Now    int64 // nanoseconds since the epoch, for recency
	// Bonus is a use bonus by entry (UseBonus of its frecency)
	Bonus map[uint32]float64
	// Stale says a newer query replaced this one: the scan stops
	Stale func() bool
	// Shards is how many goroutines scan (GOMAXPROCS)
	Shards int
}

// Hit is one result.
type Hit struct {
	Entry uint32
	Score float64
	// Folder: the match was in a folder above it, not its own name
	Folder  bool
	nameLen uint16
}

// better orders hits: score, then the shorter name, then the earlier entry.
func better(a, b Hit) bool {
	if a.Score != b.Score {
		return a.Score > b.Score
	}
	if a.nameLen != b.nameLen {
		return a.nameLen < b.nameLen
	}
	return a.Entry < b.Entry
}

// scratch is one search's per-folder tables, indexed by entry (only a
// folder's slot is written, each before its children read it, so a reused
// table needs no clearing).
type scratch struct {
	cum   []uint32  // the folder's mask with its folders' (below the root)
	under []bool    // the folder is Under or below it
	anc   [][]uint8 // per token: the best Score of the folder or one above
	seg   [][]uint8 // per token: how many of its folder segments matched
}

// getScratch takes the spare tables (a sync.Pool would drop them at every
// collection, and a million entries' are megabytes); putScratch keeps them.
func (ix *Index) getScratch(tokens int) *scratch {
	ix.spareMu.Lock()
	s := ix.spare
	ix.spare = nil
	ix.spareMu.Unlock()
	if s == nil {
		s = &scratch{}
	}
	n := int(ix.n)
	if cap(s.cum) < n {
		size := n + n/4 + 1024
		s.cum, s.under = make([]uint32, size), make([]bool, size)
		s.anc, s.seg = nil, nil
	}
	s.cum, s.under = s.cum[:n], s.under[:n]
	for len(s.anc) < tokens {
		s.anc = append(s.anc, make([]uint8, cap(s.cum)))
		s.seg = append(s.seg, make([]uint8, cap(s.cum)))
	}
	return s
}

func (ix *Index) putScratch(s *scratch) {
	ix.spareMu.Lock()
	ix.spare = s
	ix.spareMu.Unlock()
}

// Search ranks the entries matching q, best first, at most q.Limit;
// stale reports the scan stopped for a newer query. The score is the
// match (Score, the mean of the tokens', a folder's match counting 0.6)
// less 1 per level below the root (at most 10), plus recency (10 within a
// day, 6 a week, 3 a month) and the use bonus, less 5 for a hidden entry.
func (ix *Index) Search(q Query) (hits []Hit, stale bool) {
	if q.Pattern.Empty() || q.Limit <= 0 || ix.n == 0 {
		return nil, false
	}
	if q.Under != NoEntry && ix.at(q.Under).flags&flagHidden != 0 {
		q.Hidden = true
	}
	toks := q.Pattern.tokens
	s := ix.getScratch(len(toks))
	defer ix.putScratch(s)
	ix.folderPass(q, s)

	shards := max(1, q.Shards)
	if int(ix.n) < shards*4096 {
		shards = 1
	}
	var stopped atomic.Bool
	results := make([][]Hit, shards)
	var wg sync.WaitGroup
	per := (int(ix.n) + shards - 1) / shards
	for k := range shards {
		lo, hi := k*per, min(int(ix.n), (k+1)*per)
		wg.Go(func() {
			results[k] = ix.scan(q, s, uint32(lo), uint32(hi), &stopped)
		})
	}
	wg.Wait()
	if stopped.Load() {
		return nil, true
	}
	for _, r := range results {
		hits = append(hits, r...)
	}
	slices.SortFunc(hits, func(a, b Hit) int {
		if better(a, b) {
			return -1
		}
		return 1
	})
	if len(hits) > q.Limit {
		hits = hits[:q.Limit]
	}
	return hits, false
}

// folderPass fills s for every folder, a parent before its children.
func (ix *Index) folderPass(q Query, s *scratch) {
	toks := q.Pattern.tokens
	var buf []byte
	for _, d := range ix.dirList {
		e := ix.at(d)
		if e.flags&flagRemoved != 0 {
			continue
		}
		if e.parent == NoEntry {
			s.cum[d] = 0
			s.under[d] = q.Under == NoEntry || q.Under == d
			for t := range toks {
				s.anc[t][d], s.seg[t][d] = 0, 0
			}
			continue
		}
		p := e.parent
		s.cum[d] = s.cum[p] | e.mask
		s.under[d] = s.under[p] || q.Under == d
		name := ix.name(e)
		lowered := false
		for t, tok := range toks {
			a := s.anc[t][p]
			if len(tok.text) > 0 && tok.mask&^e.mask == 0 && a < 100 {
				if !q.Pattern.cased && !lowered {
					buf, lowered = lowerInto(buf, name), true
				}
				n := name
				if lowered {
					n = buf
				}
				a = max(a, uint8(Score(n, tok.text)))
			}
			s.anc[t][d] = a
			g := s.seg[t][p]
			if int(g) < len(tok.dirs) && maskOf(tok.dirs[g])&^e.mask == 0 {
				if !q.Pattern.cased && !lowered {
					buf, lowered = lowerInto(buf, name), true
				}
				n := name
				if lowered {
					n = buf
				}
				if Score(n, tok.dirs[g]) > 0 {
					g++
				}
			}
			s.seg[t][d] = g
		}
	}
}

// scan ranks entries [lo, hi), keeping the best q.Limit.
func (ix *Index) scan(q Query, s *scratch, lo, hi uint32, stopped *atomic.Bool) []Hit {
	toks := q.Pattern.tokens
	need := q.Pattern.mask
	h := hitHeap{limit: q.Limit}
	var buf []byte
	const day = 86400 * 1e9
	for i := lo; i < hi; i++ {
		if (i-lo)%staleEvery == staleEvery-1 {
			if stopped.Load() {
				return nil
			}
			if q.Stale != nil && q.Stale() {
				stopped.Store(true)
				return nil
			}
		}
		e := ix.at(i)
		if e.flags&(flagRemoved|flagRoot) != 0 || !q.Hidden && e.flags&flagHidden != 0 {
			continue
		}
		p := e.parent
		if !s.under[p] || need&^(e.mask|s.cum[p]) != 0 {
			continue
		}
		name := ix.name(e)
		if !q.Pattern.cased {
			buf = lowerInto(buf, name)
			name = buf
		}
		total, folder := 0.0, false
		for t, tok := range toks {
			sc := 0.0
			if len(tok.dirs) > 0 {
				if int(s.seg[t][p]) < len(tok.dirs) {
					total = -1
					break
				}
				if len(tok.text) == 0 {
					sc = 50
				} else if tok.mask&^e.mask == 0 {
					sc = float64(Score(name, tok.text))
				}
			} else {
				if tok.mask&^e.mask == 0 {
					sc = float64(Score(name, tok.text))
				}
				if sc == 0 {
					sc, folder = folderMatch*float64(s.anc[t][p]), true
				}
			}
			if sc == 0 {
				total = -1
				break
			}
			total += sc
		}
		if total < 0 {
			continue
		}
		score := total / float64(len(toks))
		score -= float64(min(10, int(e.depth)-1))
		if e.mtime != 0 {
			switch age := q.Now - (int64(e.mtime)*1e9 + int64(e.nsec)); {
			case age < day:
				score += 10
			case age < 7*day:
				score += 6
			case age < 30*day:
				score += 3
			}
		}
		score += q.Bonus[i]
		if e.flags&flagHidden != 0 {
			score -= 5
		}
		h.push(Hit{Entry: i, Score: score, Folder: folder, nameLen: e.nameLen})
	}
	return h.items
}

// hitHeap keeps the best limit hits: a min-heap, the worst on top.
type hitHeap struct {
	items []Hit
	limit int
}

func (h *hitHeap) push(x Hit) {
	if len(h.items) < h.limit {
		h.items = append(h.items, x)
		for i := len(h.items) - 1; i > 0; {
			p := (i - 1) / 2
			if !better(h.items[p], h.items[i]) {
				break
			}
			h.items[p], h.items[i] = h.items[i], h.items[p]
			i = p
		}
		return
	}
	if !better(x, h.items[0]) {
		return
	}
	h.items[0] = x
	for i := 0; ; {
		l, r, worst := 2*i+1, 2*i+2, i
		if l < len(h.items) && better(h.items[worst], h.items[l]) {
			worst = l
		}
		if r < len(h.items) && better(h.items[worst], h.items[r]) {
			worst = r
		}
		if worst == i {
			return
		}
		h.items[i], h.items[worst] = h.items[worst], h.items[i]
		i = worst
	}
}
