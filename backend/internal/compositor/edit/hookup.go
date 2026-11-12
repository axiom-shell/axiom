package edit

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"time"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/footprint"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/hookup"
	"github.com/axiom-shell/axiom/backend/internal/theme/integrations"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// HookupOptions configure Hookups.
type HookupOptions struct {
	Getenv   func(string) string
	LookPath func(string) (string, error)
	// DataDir is the tree's data/ folder, which a copy target's From is
	// relative to
	DataDir string
	Now     func() time.Time
	// Ledger records the changes before they're made (nil: none)
	Ledger *footprint.Ledger
}

// Hookups check and apply hookup targets (package hookup) on the user's
// files: what the settings' hookup panels show, and their Apply.
type Hookups struct{ opts HookupOptions }

// NewHookups makes Hookups.
func NewHookups(opts HookupOptions) *Hookups {
	if opts.LookPath == nil {
		opts.LookPath = exec.LookPath
	}
	if opts.Now == nil {
		opts.Now = time.Now
	}
	return &Hookups{opts: opts}
}

// HookupResult is how Apply went for one target.
type HookupResult struct {
	Path    string `json:"path"`
	Changed bool   `json:"changed"`
	Backup  string `json:"backup"`
	// Error is "conflict" (a line already sets it, left alone) or what failed
	Error string `json:"error"`
}

// Status is what applying each target would do (its paths with $HOME as
// ~). profiles are the profiles.ini files ({home}, {config}) listing a
// PerProfile target's folders. An Accept that isn't a regexp is
// axerr.BadRequest.
func (h *Hookups) Status(targets []hookup.Target, profiles []string) ([]hookup.Row, error) {
	home := h.env().Dirs.Home
	rows := []hookup.Row{}
	for _, r := range h.resolve(targets, profiles) {
		p, _, err := h.plan(r)
		if err != nil {
			return nil, axerr.Wrap(axerr.BadRequest, err, "a hookup target")
		}
		p.Path, p.Resolved = hookup.Shown(p.Path, home), hookup.Shown(p.Resolved, home)
		rows = append(rows, p.Row)
	}
	return rows, nil
}

// Apply does each target that isn't done: the file changed is backed up
// beside it as <name>.axiom-bak-<date> (a link is followed and kept; a
// wrapped link is the backup), then replaced atomically. A file that can't
// be written is never touched, and nothing is deleted. Each change is
// recorded in the ledger first, with owner (the setting that asked for it).
func (h *Hookups) Apply(targets []hookup.Target, profiles []string, owner string) []HookupResult {
	home := h.env().Dirs.Home
	suffix := ".axiom-bak-" + h.opts.Now().Format(Stamp)
	results := []HookupResult{}
	for _, r := range h.resolve(targets, profiles) {
		result, err := h.apply(r, suffix, owner)
		if err != nil {
			result.Error = err.Error()
		}
		result.Path, result.Backup = hookup.Shown(result.Path, home), hookup.Shown(result.Backup, home)
		results = append(results, result)
	}
	return results
}

func (h *Hookups) apply(r hookup.Resolved, suffix, owner string) (HookupResult, error) {
	p, lines, err := h.plan(r)
	result := HookupResult{Path: p.Path}
	if err != nil || !p.Pending() {
		if len(p.Conflicts) > 0 {
			result.Error = "conflict"
		}
		return result, err
	}
	// Folders made for it are recorded first
	dirsDone, err := h.opts.Ledger.BeginDirs(filepath.Dir(p.Resolved), owner)
	if err != nil {
		return result, err
	}
	defer dirsDone()
	if err := os.MkdirAll(filepath.Dir(p.Resolved), 0o755); err != nil {
		return result, err
	}
	switch {
	case r.Place == hookup.Copy:
		data, err := os.ReadFile(filepath.Join(h.opts.DataDir, r.From))
		if err != nil {
			return result, err
		}
		sum := sha256.Sum256(data)
		prev, had := h.opts.Ledger.Get(footprint.ID(footprint.KindHookup, p.Resolved, ""))
		id, err := h.opts.Ledger.Begin(footprint.Row{Kind: footprint.KindHookup, Target: p.Resolved, Owner: owner,
			Hookup: &footprint.HookupRec{CreatedFile: !p.Exists, CopiedSHA256: hex.EncodeToString(sum[:])}}, footprint.PriorAbsent)
		if err != nil {
			return result, err
		}
		err = Replace(p.Resolved, data)
		result.Changed = err == nil
		h.finish(id, prev, had, err)
		return result, err
	case p.Wraps:
		// The link becomes the backup (still pointing where it did), and a
		// file of the user's takes its place
		link, err := os.Readlink(p.Path)
		if err != nil {
			return result, err
		}
		out, rec := hookup.Edit(r, p, lines)
		prev, had := h.opts.Ledger.Get(footprint.ID(footprint.KindHookup, p.Path, ""))
		id, err := h.opts.Ledger.Begin(footprint.Row{Kind: footprint.KindHookup, Target: p.Path, Owner: owner,
			Hookup: &footprint.HookupRec{Edit: rec, LinkTarget: link, Backup: p.Path + suffix}}, footprint.PriorAbsent)
		if err != nil {
			return result, err
		}
		if err := os.Symlink(link, p.Path+suffix); err != nil {
			h.finish(id, prev, had, err)
			return result, err
		}
		result.Backup = p.Path + suffix
		err = fsx.ReplaceLink(p.Path, []byte(hookup.Text(out)), 0o644)
		result.Changed = err == nil
		h.finish(id, prev, had, err)
		return result, err
	}
	out, rec := hookup.Edit(r, p, lines)
	row := footprint.Row{Kind: footprint.KindHookup, Target: p.Resolved, Owner: owner, Hookup: &footprint.HookupRec{Edit: rec, CreatedFile: !p.Exists}}
	// One backup per file and Apply, taken before its first target
	// (kdeglobals has two): one already there is never overwritten
	backup := p.Resolved + suffix
	if p.Exists {
		row.Hookup.Backup = backup
		if data, err := os.ReadFile(p.Resolved); err == nil && len(data) > 0 && data[len(data)-1] != '\n' {
			row.Hookup.NoFinalNewline = true
			row.Hookup.LastLine = lines[len(lines)-1]
		}
	}
	prev, had := h.opts.Ledger.Get(footprint.ID(footprint.KindHookup, p.Resolved, ""))
	id, err := h.opts.Ledger.Begin(row, footprint.PriorAbsent)
	if err != nil {
		return result, err
	}
	if p.Exists {
		if _, err := os.Lstat(backup); errors.Is(err, fs.ErrNotExist) {
			if err := Copy(p.Resolved, backup); err != nil {
				h.finish(id, prev, had, err)
				return result, err
			}
		}
		result.Backup = backup
	}
	err = Replace(p.Resolved, []byte(hookup.Text(out)))
	result.Changed = err == nil
	h.finish(id, prev, had, err)
	return result, err
}

// finish closes a row's write-ahead: done when the write was made; when it
// failed, a row Begin merged this edit's lines into goes back to what it
// held (a new row stays pending: its undo finds nothing to take out).
func (h *Hookups) finish(id string, prev footprint.Row, had bool, err error) {
	if err == nil {
		h.opts.Ledger.Done(id, nil)
		return
	}
	if had {
		_ = h.opts.Ledger.Amend(id, func(r *footprint.Row) { r.Hookup, r.State = prev.Hookup, prev.State })
	}
}

func (h *Hookups) env() hookup.Env {
	b := xdg.ResolveBases(h.opts.Getenv)
	return hookup.Env{
		Dirs:    integrations.Dirs{Home: b.Home, Config: b.Config, State: b.State, Data: b.Data},
		Shell:   h.opts.Getenv("SHELL"),
		ZDotDir: h.opts.Getenv("ZDOTDIR"),
		Exists:  func(path string) bool { _, err := os.Lstat(path); return err == nil },
	}
}

// resolve resolves the targets, a PerProfile one in each profile folder
// the profiles.ini files list (that exists, each once)
func (h *Hookups) resolve(targets []hookup.Target, profiles []string) []hookup.Resolved {
	env := h.env()
	var dirs []string
	if slices.ContainsFunc(targets, func(t hookup.Target) bool { return t.PerProfile }) {
		for _, ini := range profiles {
			ini = env.Dirs.Expand(ini)
			data, err := os.ReadFile(ini)
			if err != nil {
				continue
			}
			for _, dir := range integrations.ProfileDirs(ini, data) {
				if info, err := os.Stat(dir); err == nil && info.IsDir() && !slices.Contains(dirs, dir) {
					dirs = append(dirs, dir)
				}
			}
		}
	}
	return hookup.Resolve(targets, dirs, env)
}

// plan finds the facts about a target's file and decides; lines are the
// file's.
func (h *Hookups) plan(r hookup.Resolved) (hookup.Plan, []string, error) {
	var f hookup.Facts
	if r.Path != "" && r.Skipped == "" && r.Requires != "" {
		if _, err := h.opts.LookPath(r.Requires); err != nil {
			r.Skipped = hookup.SkipRequires
		}
	}
	if r.Path != "" && r.Skipped == "" {
		abs, _ := filepath.Abs(r.Path)
		f.Real = realPath(abs)
		info, err := os.Lstat(abs)
		isLink := err == nil && info.Mode()&fs.ModeSymlink != 0
		f.Link = isLink || f.Real != abs
		if info, err := os.Stat(f.Real); err == nil && info.Mode().IsRegular() {
			f.Exists = true
		}
		if f.Exists && r.Place != hookup.Copy {
			data, err := os.ReadFile(f.Real)
			if err != nil {
				return hookup.Plan{}, nil, err
			}
			f.Lines = hookup.Lines(string(data))
		}
		f.Writable = writable(f.Real)
		f.CanWrap = isLink && canWrite(filepath.Dir(abs))
	}
	p, err := hookup.Decide(r, f)
	return p, f.Lines, err
}

// realPath is path with every link followed, as far as they lead (a
// dangling link, or a missing file in a linked folder, names the file
// that would be created)
func realPath(path string) string {
	for range 40 {
		if real, err := filepath.EvalSymlinks(path); err == nil {
			return real
		}
		link, err := os.Readlink(path)
		if err != nil {
			break
		}
		if !filepath.IsAbs(link) {
			link = filepath.Join(filepath.Dir(path), link)
		}
		path = link
	}
	dir := filepath.Dir(path)
	if dir == path {
		return path
	}
	return filepath.Join(realPath(dir), filepath.Base(path))
}

// writable says whether path could be replaced atomically and backed up:
// the file and its folder, or the nearest existing folder when it's missing
func writable(path string) bool {
	if _, err := os.Lstat(path); err == nil {
		return canWrite(path) && canWrite(filepath.Dir(path))
	} else if !errors.Is(err, fs.ErrNotExist) {
		return false
	}
	for dir := filepath.Dir(path); ; dir = filepath.Dir(dir) {
		if info, err := os.Stat(dir); err == nil {
			return info.IsDir() && canWrite(dir)
		}
		if dir == "/" || dir == "." {
			return false
		}
	}
}

func canWrite(path string) bool { return unix.Access(path, unix.W_OK) == nil }
