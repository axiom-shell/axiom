// Package takeover makes a compositor's config axiom's for the managed mode,
// says what that would do, or gives it back when axiom leaves the mode
// (docs/dev/hyprland/managed-takeover.md). Every verb answers one word, the
// compositor manager reads:
//
//	ours                the file is already axiom's (its first line starts with the header)
//	blocked:link        the dir or its config is a symlink: never taken over
//	blocked:git:<repo>  the dir is in the git repository <repo>: never taken over
//
// check:
//
//	adopt     an existing config would be moved to user/
//	stock     the config is the compositor's example: it would only be backed up
//	released  the config is the fallback, as release wrote it: replaced, no backup
//	new       there's no config yet
//
// claim (leaving the config where it is, for the managed write to replace
// atomically: the compositor must never find it missing; a claim of the
// same file again reuses its copies):
//
//	adopted:<name>  copied to user/<name> (00-previous<ext>, or a dated name
//	                when that's taken) beside a dated backup; in the copy, the
//	                lines that start axiom or load its module are commented out
//	created         there was no config
//	replaced        the example config is kept only as the dated backup
//
// release:
//
//	notours              the config isn't axiom's (or is missing): nothing written
//	restored:<from>:<n>  what the claim set aside is back (user/<name>, its
//	                     lines enabled again, or the backup); <n> files in
//	                     user/ it doesn't load
//	written              nothing was set aside: the config is the fallback
package takeover

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/compositor/edit"
	"github.com/axiom-shell/axiom/backend/internal/compositor/luacheck"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
)

// Options is one takeover call.
type Options struct {
	Kind     *Kind
	Dir      string // the compositor's config dir (~/.config/hypr)
	Header   string // the first-line prefix of a file axiom wrote
	Fallback string // what release writes when nothing was set aside
	Getenv   func(string) string
	Now      func() time.Time // dated names (default time.Now)
	// Git is the repository dir is in, if any (default `git rev-parse`)
	Git func(ctx context.Context, dir string) (string, bool)
	Lua luacheck.Checker
	// Locked: the caller holds Dir's lock (edit.LockDir), as the compositor
	// manager does across a claim and the managed write after it; else
	// each verb takes it
	Locked bool
}

// lock takes Dir's lock unless the caller holds it; a missing Dir is made
// only to claim it (nothing else to keep apart there)
func (c *call) lock(ctx context.Context, create bool) (func(), error) {
	if c.Locked || (!create && !exists(c.Dir)) {
		return func() {}, nil
	}
	l, err := edit.LockDir(ctx, c.Dir)
	if err != nil {
		return nil, err
	}
	return func() { l.Release() }, nil
}

// call is one verb's working state.
type call struct {
	Options
	file, user string
}

func prepare(o Options, needFallback bool) (*call, error) {
	if o.Kind == nil || o.Dir == "" || o.Header == "" || (needFallback && o.Fallback == "") {
		return nil, axerr.New(axerr.BadRequest, "takeover needs a kind, a dir and a header (and release a fallback)")
	}
	if o.Getenv == nil {
		o.Getenv = os.Getenv
	}
	if o.Now == nil {
		o.Now = time.Now
	}
	if o.Git == nil {
		o.Git = edit.GitRepo
	}
	dir := strings.TrimSuffix(o.Dir, "/")
	if dir == "" {
		dir = "/"
	}
	o.Dir = dir
	return &call{Options: o, file: filepath.Join(dir, o.Kind.File), user: filepath.Join(dir, "user")}, nil
}

func (c *call) isOurs() bool {
	data, err := os.ReadFile(c.file)
	if err != nil || !fsx.IsFile(c.file) {
		return false
	}
	first, _, _ := strings.Cut(string(data), "\n")
	return strings.HasPrefix(first, c.Header)
}

// blocked is the refusal for a symlinked or git-tracked dir, or ""
func (c *call) blocked(ctx context.Context) string {
	if isLink(c.Dir) || isLink(c.file) {
		return "blocked:link"
	}
	if repo, ok := c.Git(ctx, c.Dir); ok {
		return "blocked:git:" + repo
	}
	return ""
}

// Check says what claim would do.
func Check(ctx context.Context, o Options) (string, error) {
	c, err := prepare(o, false)
	if err != nil {
		return "", err
	}
	unlock, err := c.lock(ctx, false)
	if err != nil {
		return "", err
	}
	defer unlock()
	if c.isOurs() {
		return "ours", nil
	}
	if b := c.blocked(ctx); b != "" {
		return b, nil
	}
	switch {
	case !fsx.IsFile(c.file):
		return "new", nil
	case c.isStock():
		return "stock", nil
	case c.isReleased():
		return "released", nil
	}
	return "adopt", nil
}

// Claim takes the config over.
func Claim(ctx context.Context, o Options) (string, error) {
	c, err := prepare(o, false)
	if err != nil {
		return "", err
	}
	unlock, err := c.lock(ctx, true)
	if err != nil {
		return "", err
	}
	defer unlock()
	if c.isOurs() {
		return "ours", nil
	}
	if b := c.blocked(ctx); b != "" {
		return b, nil
	}
	if err := os.MkdirAll(c.user, 0o755); err != nil {
		return "", err
	}
	if !fsx.IsFile(c.file) {
		return "created", c.setAside("", "")
	}
	stamp := c.Now().Format(edit.Stamp)
	backup := c.Kind.File + ".axiom-backup-" + stamp
	if c.isReleased() {
		return "replaced", c.setAside("", "")
	}
	// Already copied by a claim whose managed write never came (its edits
	// made again, in case they failed then: they change nothing twice).
	// Only as its record names it: a config released unchanged is the
	// newest backup's bytes too, and user/ may hold an older claim's copy
	if previous, last, ok := c.pending(); ok && sameBytes(c.file, filepath.Join(c.Dir, last)) {
		if previous == "" && c.isStock() {
			return "replaced", nil
		}
		if previous != "" {
			return "adopted:" + previous, c.adopt(ctx, filepath.Join(c.user, previous))
		}
	}
	if c.isStock() {
		if err := edit.Copy(c.file, filepath.Join(c.Dir, backup)); err != nil {
			return "", err
		}
		return "replaced", c.setAside("", backup)
	}
	name := "00-previous" + c.Kind.Ext
	if exists(filepath.Join(c.user, name)) {
		name = "00-previous-" + stamp + c.Kind.Ext
	}
	if err := edit.Copy(c.file, filepath.Join(c.Dir, backup)); err != nil {
		return "", err
	}
	if err := edit.Copy(c.file, filepath.Join(c.user, name)); err != nil {
		return "", err
	}
	if err := c.adopt(ctx, filepath.Join(c.user, name)); err != nil {
		return "", err
	}
	return "adopted:" + name, c.setAside(name, backup)
}

// Release gives the config back.
func Release(ctx context.Context, o Options) (string, error) {
	c, err := prepare(o, true)
	if err != nil {
		return "", err
	}
	unlock, err := c.lock(ctx, false)
	if err != nil {
		return "", err
	}
	defer unlock()
	if !c.isOurs() {
		return "notours", nil
	}
	if b := c.blocked(ctx); b != "" {
		return b, nil
	}
	previous, backup := c.setAsideNow()
	var from string
	switch {
	case previous != "":
		path := filepath.Join(c.user, previous)
		data, err := os.ReadFile(path)
		if err != nil {
			return "", err
		}
		info, err := os.Stat(path)
		if err != nil {
			return "", err
		}
		if err := edit.WriteMode(c.file, []byte(c.enable(ctx, string(data))), info.Mode().Perm()); err != nil {
			return "", err
		}
		if err := os.Remove(path); err != nil {
			return "", err
		}
		from = "user/" + previous
	case backup != "":
		if err := os.Rename(filepath.Join(c.Dir, backup), c.file); err != nil {
			return "", err
		}
		from = backup
	default:
		if err := edit.WriteMode(c.file, []byte(c.Fallback+"\n"), 0o644); err != nil {
			return "", err
		}
		c.forget()
		return "written", nil
	}
	c.forget()
	text, err := os.ReadFile(c.file)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("restored:%s:%d", from, c.Kind.left(string(text), c.user)), nil
}

// --- Comparing ---

// isStock: the example config, give or take whitespace, blank lines and
// the kind's stockSkip lines
func (c *call) isStock() bool {
	example := c.Getenv(c.Kind.exampleEnv)
	if example == "" {
		example = c.Kind.exampleDefault(c.Getenv)
	}
	if example == "" || !fsx.IsFile(example) {
		return false
	}
	mine, err1 := os.ReadFile(c.file)
	theirs, err2 := os.ReadFile(example)
	return err1 == nil && err2 == nil &&
		sameLines(diffLines(string(mine), c.Kind.stockSkip), diffLines(string(theirs), c.Kind.stockSkip))
}

// isReleased: the fallback as release wrote it, give or take whitespace,
// blank lines and the lines loading the included module (written for that
// mode): an edited one is the user's, and is adopted
func (c *call) isReleased() bool {
	if c.Fallback == "" {
		return false
	}
	mine, err := os.ReadFile(c.file)
	return err == nil &&
		sameLines(diffLines(string(mine), c.Kind.releasedSkip), diffLines(c.Fallback+"\n", c.Kind.releasedSkip))
}

var spaces = regexp.MustCompile(`[[:space:]]+`)

// diffLines is text's lines without skip's, each with its runs of
// whitespace as one space and none at the end, and no blank ones: what
// `diff -bB` compares
func diffLines(text string, skip *regexp.Regexp) []string {
	var out []string
	for _, line := range splitLines(text) {
		if skip.MatchString(line) {
			continue
		}
		if line = strings.TrimRight(spaces.ReplaceAllString(line, " "), " "); line != "" {
			out = append(out, line)
		}
	}
	return out
}

func sameLines(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// --- Editing the adopted copy ---

// adopt comments out the copy's lines that start axiom or load its module
// (the managed config does both now, and a second start would be a second
// shell) and makes its relative includes absolute (it's in user/ now)
func (c *call) adopt(ctx context.Context, path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	text := string(data)
	edited := mapLines(text, func(line string) string {
		if c.Kind.comment.MatchString(line) {
			return line
		}
		if c.Kind.axiomLine.MatchString(line) {
			return c.Kind.marker + line
		}
		if c.Kind.absInclude != nil {
			return c.Kind.absInclude(line, c.Dir)
		}
		return line
	})
	if edited == text || !c.keepsParsing(ctx, text, edited, edited) {
		return nil
	}
	return edit.WriteMode(path, []byte(edited), modeOf(path))
}

// enable undoes adopt's commenting out, unless that leaves it unparsable
func (c *call) enable(ctx context.Context, text string) string {
	enabled := mapLines(text, func(line string) string { return strings.TrimPrefix(line, c.Kind.marker) })
	if enabled == text || !c.keepsParsing(ctx, text, enabled, text) {
		return text
	}
	return enabled
}

// keepsParsing: after, the edit of before (lines commented out or back in),
// still parses where it must (the kind's parses). The checker decides when
// it reads before; when it can't (Lua 5.4's syntax, with gopher-lua
// standing in for luac), each changed line must be whole statements in
// commented, the side holding them as code
func (c *call) keepsParsing(ctx context.Context, before, after, commented string) bool {
	if !c.Kind.parses || c.Lua.Parses(ctx, after) {
		return true
	}
	if c.Lua.Parses(ctx, before) {
		return false
	}
	code := after
	if commented == after {
		code = before
	}
	return luacheck.WholeLines(code, changedLines(before, after))
}

// changedLines are the 1-based lines that differ between a and b (the same
// number of lines)
func changedLines(a, b string) []int {
	x, y := splitLines(a), splitLines(b)
	var out []int
	for i := range min(len(x), len(y)) {
		if x[i] != y[i] {
			out = append(out, i+1)
		}
	}
	return out
}

// splitLines is text's lines, without a last empty one after the final
// newline
func splitLines(text string) []string {
	if text == "" {
		return nil
	}
	return strings.Split(strings.TrimSuffix(text, "\n"), "\n")
}

// mapLines applies fn to each line, keeping the final newline (or its lack)
func mapLines(text string, fn func(string) string) string {
	lines := splitLines(text)
	for i, line := range lines {
		lines[i] = fn(line)
	}
	out := strings.Join(lines, "\n")
	if strings.HasSuffix(text, "\n") {
		out += "\n"
	}
	return out
}

// --- What was set aside ---

const recordName = ".axiom-claimed"

func (c *call) setAside(previous, backup string) error {
	return fsx.WriteFile(filepath.Join(c.Dir, recordName), fmt.Appendf(nil, "previous=%s\nbackup=%s\n", previous, backup), 0o644)
}

func (c *call) forget() { os.Remove(filepath.Join(c.Dir, recordName)) }

// setAsideNow is what release gives back: as the record names it (each
// only while it's still there); nothing without one (a claim from before
// records: the maintainer, 2026-11-01, "drop")
func (c *call) setAsideNow() (previous, backup string) {
	data, _ := os.ReadFile(filepath.Join(c.Dir, recordName))
	for _, line := range splitLines(string(data)) {
		if v, ok := strings.CutPrefix(line, "previous="); ok {
			previous = v
		} else if v, ok := strings.CutPrefix(line, "backup="); ok {
			backup = v
		}
	}
	if previous != "" && !fsx.IsFile(filepath.Join(c.user, previous)) {
		previous = ""
	}
	if backup != "" && !fsx.IsFile(filepath.Join(c.Dir, backup)) {
		backup = ""
	}
	return previous, backup
}

// pending is what a claim not yet followed by its managed write set aside:
// its record, naming the newest backup (and, adopted, a copy still in
// user/)
func (c *call) pending() (previous, backup string, ok bool) {
	last := c.newestBackup()
	if last == "" {
		return "", "", false
	}
	if !fsx.IsFile(filepath.Join(c.Dir, recordName)) {
		return "", "", false
	}
	previous, backup = c.setAsideNow()
	return previous, backup, backup == last
}

func (c *call) newestBackup() string {
	return newest(c.Dir, c.Kind.File+".axiom-backup-*")
}

// newest is the last name in dir matching pattern, by name (they're dated)
func newest(dir, pattern string) string {
	last := ""
	list, _ := os.ReadDir(dir) // sorted by name
	for _, e := range list {
		if ok, _ := filepath.Match(pattern, e.Name()); ok {
			last = e.Name()
		}
	}
	return last
}

// --- Files ---

func isLink(path string) bool {
	info, err := os.Lstat(path)
	return err == nil && info.Mode()&os.ModeSymlink != 0
}

func exists(path string) bool {
	_, err := os.Lstat(path)
	return err == nil
}

func modeOf(path string) os.FileMode {
	if info, err := os.Stat(path); err == nil {
		return info.Mode().Perm()
	}
	return 0o644
}

func sameBytes(a, b string) bool {
	x, err1 := os.ReadFile(a)
	y, err2 := os.ReadFile(b)
	return err1 == nil && err2 == nil && bytes.Equal(x, y)
}
