package session

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/compositor/edit"
	"github.com/axiom-shell/axiom/backend/internal/hookup"
)

// The niri portal line: where, in which section, and what it says. The
// only place these are written (the shell's ScreenShareSources no longer
// carries a niri target).
const (
	PortalFile    = "xdg-desktop-portal/niri-portals.conf" // under $XDG_CONFIG_HOME
	PortalSection = "preferred"
	PortalText    = "org.freedesktop.impl.portal.ScreenCast=axiom"
	// PortalDescriptor is axiom's own backend's .portal file
	PortalDescriptor = "axiom.portal"
)

// Portal line states (screenShare.portalLine)
const (
	LineOn      = "on"
	LineOff     = "off"
	LineLink    = "link"    // the file is a link: the user adds the line by hand
	LineMissing = "missing" // axiom.portal isn't installed
	LineFailed  = "failed"
)

var sectionHeader = regexp.MustCompile(`^\s*\[\s*([^\[\]"]+?)\s*\]\s*(?:[#;].*)?$`)

const commentedPrefix = "# axiom: "

// PortalEnv is where the portal config is, and how it is written.
type PortalEnv struct {
	Config   string   // $XDG_CONFIG_HOME
	DataDirs []string // where xdg-desktop-portal looks for portals/*.portal
	// Write replaces a file with a mode (default edit.WriteMode)
	Write func(path string, data []byte, mode os.FileMode) error
}

// Path is the config file.
func (p PortalEnv) Path() string { return filepath.Join(p.Config, PortalFile) }

// Available: axiom's portal descriptor is installed.
func (p PortalEnv) Available() bool {
	for _, d := range p.DataDirs {
		if _, err := os.Stat(filepath.Join(d, "xdg-desktop-portal", "portals", PortalDescriptor)); err == nil {
			return true
		}
	}
	return false
}

func (p PortalEnv) write(path string, data []byte, mode os.FileMode) error {
	if p.Write != nil {
		return p.Write(path, data, mode)
	}
	return edit.WriteMode(path, data, mode)
}

func isLink(path string) bool {
	info, err := os.Lstat(path)
	return err == nil && info.Mode()&fs.ModeSymlink != 0
}

// linked: the file, or the folder holding it, is a link
func (p PortalEnv) linked() bool {
	path := p.Path()
	return isLink(path) || isLink(filepath.Dir(path)) || isLink(p.Config)
}

// writable: the file (when there) and its nearest existing folder
func writableFile(path string) bool {
	if _, err := os.Lstat(path); err == nil && unix.Access(path, unix.W_OK) != nil {
		return false
	}
	for dir := filepath.Dir(path); ; dir = filepath.Dir(dir) {
		if info, err := os.Stat(dir); err == nil {
			return info.IsDir() && unix.Access(dir, unix.W_OK) == nil
		}
		if dir == "/" || dir == "." {
			return false
		}
	}
}

func entryFor(st *State, display, path string) int {
	return slices.IndexFunc(st.Lines, func(l PortalLine) bool { return l.Display == display && l.Path == path })
}

// Has says whether the state record holds this display's line.
func (p PortalEnv) Has(store Store, display string) bool {
	st := store.Read()
	return st != nil && entryFor(st, display, p.Path()) >= 0
}

// Sync makes the file hold axiom's line when want, else not, for display,
// and says the state it is in and whether the file changed. It never
// touches a link, a file it may not write, or a setup without axiom's
// portal. The change is written ahead: the record holds the planned entry
// before the file is edited, so a crash in between is healed by the undo
// (which treats "already gone" as done).
func (p PortalEnv) Sync(store Store, display string, want bool) (state string, changed bool, err error) {
	path := p.Path()
	if !want {
		var line *PortalLine
		err = store.Update(func(st *State) error {
			if i := entryFor(st, display, path); i >= 0 {
				l := st.Lines[i]
				line = &l
				st.Lines = slices.Delete(st.Lines, i, i+1)
			}
			return nil
		})
		if err != nil || line == nil {
			return LineOff, false, err
		}
		changed, err = p.Remove(*line)
		return LineOff, changed, err
	}
	if !p.Available() {
		return LineMissing, false, nil
	}
	if p.linked() {
		return LineLink, false, nil
	}
	if !writableFile(path) {
		return LineFailed, false, errors.New(filepath.Dir(path) + " isn't writable")
	}
	var text string
	exists := false
	if data, err := os.ReadFile(path); err == nil {
		text, exists = string(data), true
	} else if !errors.Is(err, fs.ErrNotExist) {
		return LineFailed, false, err
	}
	lines := hookup.Lines(text)
	r := hookup.Resolved{Target: hookup.Target{Text: PortalText, Place: hookup.Section, Section: PortalSection, Comment: "#"}, Path: path}
	plan, err := hookup.Decide(r, hookup.Facts{Real: path, Exists: exists, Lines: lines, Writable: true})
	if err != nil {
		return LineFailed, false, err
	}
	if plan.Done {
		// Present: ours (a record) or an earlier persistent hookup's
		return LineOn, false, store.Update(func(st *State) error {
			if entryFor(st, display, path) >= 0 {
				return nil
			}
			e := PortalLine{Display: display, Path: path, Line: PortalText, Adopted: true}
			start, end, found := sectionRange(lines)
			if found {
				for _, l := range lines[start:end] {
					if strings.HasPrefix(l, commentedPrefix) {
						e.Commented = append(e.Commented, strings.TrimSpace(strings.TrimPrefix(l, commentedPrefix)))
					}
				}
			}
			st.Lines = append(st.Lines, e)
			return nil
		})
	}
	if !plan.Pending() {
		return LineFailed, false, errors.New("the portal config can't be edited: " + strings.Join(plan.Conflicts, "; "))
	}
	e := PortalLine{Display: display, Path: path, Line: PortalText, Commented: plan.Replaces,
		CreatedSection: plan.CreatesSection, CreatedFile: !exists}
	if plan.CreatesSection && len(lines) > 0 && strings.TrimSpace(lines[len(lines)-1]) != "" {
		e.BlankAdded = true
	}
	edited := hookup.Edit(r, plan, lines)
	if crlf(lines) {
		for i, l := range edited {
			if !strings.HasSuffix(l, "\r") {
				edited[i] = l + "\r"
			}
		}
	}
	// Written ahead
	if err := store.Update(func(st *State) error {
		if i := entryFor(st, display, path); i >= 0 {
			st.Lines = slices.Delete(st.Lines, i, i+1)
		}
		st.Lines = append(st.Lines, e)
		return nil
	}); err != nil {
		return LineFailed, false, err
	}
	mode := os.FileMode(0o644)
	if info, err := os.Stat(path); err == nil {
		mode = info.Mode().Perm()
	}
	err = os.MkdirAll(filepath.Dir(path), 0o755)
	if err == nil {
		err = p.write(path, []byte(hookup.Text(edited)), mode)
	}
	if err != nil {
		store.Update(func(st *State) error {
			if i := entryFor(st, display, path); i >= 0 {
				st.Lines = slices.Delete(st.Lines, i, i+1)
			}
			return nil
		})
		return LineFailed, false, err
	}
	return LineOn, true, nil
}

func crlf(lines []string) bool {
	any := false
	for _, l := range lines {
		if l == "" {
			continue
		}
		if !strings.HasSuffix(l, "\r") {
			return false
		}
		any = true
	}
	return any
}

// sectionRange is [start, end) of the lines inside [preferred].
func sectionRange(lines []string) (start, end int, found bool) {
	for i, l := range lines {
		if m := sectionHeader.FindStringSubmatch(strings.TrimRight(l, "\r")); m != nil && m[1] == PortalSection {
			end = len(lines)
			for j := i + 1; j < len(lines); j++ {
				if strings.HasPrefix(strings.TrimSpace(lines[j]), "[") {
					end = j
					break
				}
			}
			return i + 1, end, true
		}
	}
	return 0, 0, false
}

// Remove undoes an entry exactly: the first line equal to its Line inside
// [preferred] goes, each "# axiom: <text>" of Commented is as it was, the
// section it made goes when empty, and the file it made when empty. Gone
// already counts as done; a link or a missing file is left alone.
func (p PortalEnv) Remove(l PortalLine) (changed bool, err error) {
	if isLink(l.Path) || isLink(filepath.Dir(l.Path)) {
		return false, nil
	}
	data, err := os.ReadFile(l.Path)
	if errors.Is(err, fs.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	lines := hookup.Lines(string(data))
	orig := slices.Clone(lines)
	if start, end, found := sectionRange(lines); found {
		for i := start; i < end; i++ {
			if strings.TrimSpace(lines[i]) == l.Line {
				lines = slices.Delete(lines, i, i+1)
				break
			}
		}
		start, end, _ = sectionRange(lines)
		for i := start; i < end; i++ {
			if rest, ok := strings.CutPrefix(lines[i], commentedPrefix); ok && slices.Contains(l.Commented, strings.TrimSpace(rest)) {
				lines[i] = rest
			}
		}
		if l.CreatedSection {
			start, end, _ = sectionRange(lines)
			empty := true
			for _, x := range lines[start:end] {
				if strings.TrimSpace(x) != "" {
					empty = false
				}
			}
			if empty {
				from := start - 1
				if l.BlankAdded && from > 0 && strings.TrimSpace(lines[from-1]) == "" {
					from--
				}
				lines = slices.Delete(lines, from, end)
			}
		}
	}
	if slices.Equal(lines, orig) {
		return false, nil
	}
	if l.CreatedFile && strings.TrimSpace(strings.Join(lines, "")) == "" {
		return true, os.Remove(l.Path)
	}
	mode := os.FileMode(0o644)
	if info, err := os.Stat(l.Path); err == nil {
		mode = info.Mode().Perm()
	}
	text := ""
	if len(lines) > 0 {
		text = hookup.Text(lines)
	}
	return true, p.write(l.Path, []byte(text), mode)
}
