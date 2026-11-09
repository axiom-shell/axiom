package fileindex

import (
	"cmp"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/filesearch"
)

// BrowseResult is a folder's listing.
type BrowseResult struct {
	Path  string `json:"path"`
	Items []Item `json:"items"`
	// Total is how many entries matched, Items the first Limit of them
	Total int `json:"total"`
}

// Browse lists the folder at path (absolute) from the disk, not the
// index: it works while the index builds, and for folders outside the
// roots. With query, the names matching it, best first; else folders
// first, then by name. Hidden entries only with hidden, or a query
// starting with ".".
func (s *Service) Browse(path, query string, limit int, hidden bool) (BrowseResult, error) {
	if !filepath.IsAbs(path) {
		return BrowseResult{}, axerr.New(axerr.BadRequest, "browse an absolute path")
	}
	path = filepath.Clean(path)
	for _, r := range s.networkRoots() {
		if within(path, r) {
			return s.browseNet(r, path, query, limit, hidden)
		}
	}
	return s.browse(path, query, limit, hidden)
}

// netBrowse is a network root's listing in flight: one at a time, and
// none while one is stuck (its server gone).
type netBrowse struct {
	sem chan struct{}
	// running: a listing is in flight; stuck: one passed its deadline
	// and still is
	running, stuck bool
}

var errUnreadable = axerr.New(axerr.Failed, "the folder can't be read")

// browseNet lists a folder of a network root within BrowseDeadline,
// which answers as an unreadable folder does when it passes. The listing
// then goes on in a goroutine nothing waits on (blocked on a dead server,
// it may never end), and the root's other listings answer at once until
// it does, so they never pile up.
func (s *Service) browseNet(root, path, query string, limit int, hidden bool) (BrowseResult, error) {
	s.browseMu.Lock()
	nb := s.browsing[root]
	if nb == nil {
		nb = &netBrowse{sem: make(chan struct{}, 1)}
		s.browsing[root] = nb
	}
	stuck := nb.stuck
	s.browseMu.Unlock()
	if stuck {
		return BrowseResult{}, errUnreadable
	}
	deadline := time.NewTimer(s.o.BrowseDeadline)
	defer deadline.Stop()
	select {
	case nb.sem <- struct{}{}:
	case <-deadline.C:
		return BrowseResult{}, errUnreadable
	}
	s.browseMu.Lock()
	nb.running = true
	s.browseMu.Unlock()
	type answer struct {
		res BrowseResult
		err error
	}
	done := make(chan answer, 1)
	go func() {
		res, err := s.browse(path, query, limit, hidden)
		s.browseMu.Lock()
		nb.running, nb.stuck = false, false
		s.browseMu.Unlock()
		<-nb.sem
		done <- answer{res, err}
	}()
	select {
	case a := <-done:
		return a.res, a.err
	case <-deadline.C:
		s.browseMu.Lock()
		nb.stuck = nb.running
		s.browseMu.Unlock()
		return BrowseResult{}, errUnreadable
	}
}

// browse lists the folder at path (absolute and clean) from the disk.
func (s *Service) browse(path, query string, limit int, hidden bool) (BrowseResult, error) {
	entries, err := s.readDir(path)
	if err != nil {
		if os.IsNotExist(err) {
			return BrowseResult{}, axerr.Wrap(axerr.NotFound, err, "no folder there")
		}
		return BrowseResult{}, axerr.Wrap(axerr.Failed, err, "the folder can't be read")
	}
	pattern := filesearch.ParsePattern(query)
	hidden = hidden || strings.HasPrefix(strings.TrimSpace(query), ".")
	type cand struct {
		e     os.DirEntry
		score float64
		dir   bool
	}
	var cands []cand
	for _, e := range entries {
		name := e.Name()
		// A name that isn't UTF-8: JSON would carry another path
		if !hidden && name[0] == '.' || !utf8.ValidString(name) {
			continue
		}
		c := cand{e: e, dir: e.IsDir()}
		if !pattern.Empty() {
			if c.score = pattern.MatchName(name); c.score == 0 {
				continue
			}
		}
		if e.Type()&os.ModeSymlink != 0 {
			if t, err := os.Stat(filepath.Join(path, name)); err == nil && t.IsDir() {
				c.dir = true
			}
		}
		cands = append(cands, c)
	}
	slices.SortFunc(cands, func(a, b cand) int {
		if c := cmp.Compare(b.score, a.score); c != 0 {
			return c
		}
		if a.dir != b.dir {
			if a.dir {
				return -1
			}
			return 1
		}
		if c := cmp.Compare(strings.ToLower(a.e.Name()), strings.ToLower(b.e.Name())); c != 0 {
			return c
		}
		return cmp.Compare(a.e.Name(), b.e.Name())
	})
	out := BrowseResult{Path: path, Items: []Item{}, Total: len(cands)}
	for _, c := range cands {
		if len(out.Items) >= limit {
			break
		}
		info, err := c.e.Info()
		if err != nil {
			continue
		}
		out.Items = append(out.Items, s.meta.fromInfo(filepath.Join(path, c.e.Name()), info))
	}
	return out, nil
}
