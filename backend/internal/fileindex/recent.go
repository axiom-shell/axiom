package fileindex

import (
	"cmp"
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/filesearch"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
)

// historyCap is how many files the launcher's own history keeps (the
// least used go first)
const historyCap = 500

// history is the files opened from the launcher, with how often and when
// (~/.local/state/axiom/launcher-files.json, 0600): their use bonus in
// the ranking, and the recent files with recently-used.xbel's.
type history struct {
	path   string
	now    func() time.Time
	mu     sync.Mutex
	loaded bool
	uses   map[string]filesearch.Use
}

type historyFile struct {
	Files map[string]filesearch.Use `json:"files"`
}

func (h *history) load() {
	if h.loaded {
		return
	}
	h.loaded = true
	h.uses = map[string]filesearch.Use{}
	data, err := os.ReadFile(h.path)
	if err != nil {
		return
	}
	var f historyFile
	if json.Unmarshal(data, &f) == nil && f.Files != nil {
		h.uses = f.Files
	}
}

// snapshot is a copy of the records.
func (h *history) snapshot() map[string]filesearch.Use {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.load()
	out := make(map[string]filesearch.Use, len(h.uses))
	for k, v := range h.uses {
		out[k] = v
	}
	return out
}

// used records an opening of path and writes the file.
func (h *history) used(path string) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.load()
	now := h.now().UnixMilli()
	u := h.uses[path]
	h.uses[path] = filesearch.Use{Count: u.Count + 1, Last: now}
	if len(h.uses) > historyCap {
		type rec struct {
			path string
			f    float64
		}
		var all []rec
		for p, u := range h.uses {
			all = append(all, rec{p, filesearch.Frecency(u, now)})
		}
		slices.SortFunc(all, func(a, b rec) int { return cmp.Compare(a.f, b.f) })
		for _, r := range all[:len(h.uses)-historyCap] {
			delete(h.uses, r.path)
		}
	}
	data, err := json.Marshal(historyFile{Files: h.uses})
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(h.path), 0o700); err != nil {
		return err
	}
	return fsx.WriteFile(h.path, data, 0o600)
}

// recent merges recently-used.xbel's local files with the history, the
// newest first.
func recent(xbel string, uses map[string]filesearch.Use) []filesearch.Recent {
	last := map[string]filesearch.Recent{}
	if data, err := os.ReadFile(xbel); err == nil {
		for _, r := range filesearch.ParseXBEL(data) {
			if r.Time >= last[r.Path].Time {
				last[r.Path] = r
			}
		}
	}
	for p, u := range uses {
		if r := last[p]; u.Last > r.Time {
			last[p] = filesearch.Recent{Path: p, Time: u.Last, Mime: r.Mime}
		}
	}
	out := make([]filesearch.Recent, 0, len(last))
	for _, r := range last {
		out = append(out, r)
	}
	slices.SortFunc(out, func(a, b filesearch.Recent) int {
		if c := cmp.Compare(b.Time, a.Time); c != 0 {
			return c
		}
		return cmp.Compare(a.Path, b.Path)
	})
	return out
}
