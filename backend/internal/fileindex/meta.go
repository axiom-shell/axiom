package fileindex

import (
	"os"
	"path/filepath"
	"sync"

	"github.com/axiom-shell/axiom/backend/internal/mimeapps"
)

// Item is one file or folder as the launcher shows it.
type Item struct {
	Path string `json:"path"`
	Name string `json:"name"`
	Dir  bool   `json:"dir"` // a folder, or a link to one
	Link bool   `json:"link"`
	Mime string `json:"mime"`
	// Icons are its type's icon names, most specific first
	// (FileSearchManager falls back from them to a generic icon)
	Icons []string `json:"icons"`
	Size  int64    `json:"size"`
	Mtime int64    `json:"mtime"` // ms
	Score float64  `json:"score"` // 0 for a listing or the recent files
}

// meta fills in an item from the disk: its type (by name, through
// shared-mime-info's globs, read once), icons, size and time.
type meta struct {
	globs func() *mimeapps.Globs
}

func newMeta(dataDirs []string) *meta {
	return &meta{globs: sync.OnceValue(func() *mimeapps.Globs { return mimeapps.LoadGlobs(dataDirs) })}
}

// item is path's item, ok false when it's gone. A link is described by
// its name, a link to a folder as a folder (the launcher lists into it).
func (m *meta) item(path string) (Item, bool) {
	info, err := os.Lstat(path)
	if err != nil {
		return Item{}, false
	}
	return m.fromInfo(path, info), true
}

func (m *meta) fromInfo(path string, info os.FileInfo) Item {
	it := Item{Path: path, Name: filepath.Base(path), Size: info.Size(), Mtime: info.ModTime().UnixMilli()}
	it.Link = info.Mode()&os.ModeSymlink != 0
	it.Dir = info.IsDir()
	if it.Link {
		if t, err := os.Stat(path); err == nil && t.IsDir() {
			it.Dir = true
		}
	}
	if it.Dir {
		it.Mime, it.Size = "inode/directory", 0
	} else {
		it.Mime = m.globs().TypeOfName(it.Name)
	}
	it.Icons = m.globs().IconOf(it.Mime)
	if it.Icons == nil {
		it.Icons = []string{}
	}
	return it
}
