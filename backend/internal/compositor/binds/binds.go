// Package binds moves the binds in a managed compositor config's user/
// files into axiom (docs/dev/hyprland/bind-merge.md): extract reads what
// can move (as Keybinds.binds entries) and what stays and why; remove takes
// the moved ones out of the files after a dated backup. Every compositor
// answers the same JSON, so the compositor manager drives any of them:
//
//	extract: { binds, sites, kept, remapped, tracked, errors }
//	  binds     axiom binds for every bind that can move
//	  sites     [{ file, line, binds, … }]: where those are, for remove
//	  kept      [{ file, line, key, reason, detail }]: binds that stay
//	  remapped  [{ from, to, action }]: binds moved off a key axiom's
//	            defaults use (Hyprland's adopted example config)
//	  tracked   [file]: files read that are in a git repository
//	  errors    the files' own errors
//	remove: { removed, files, failed: [{ file, line, reason, detail }] }
//
// Reason codes (kept and failed): key (its key can't be read as axiom's),
// options (bind options axiom binds don't have: detail), function (it runs
// a Lua function), shared (made in a shared module), notOnly (not the only
// call on its line), statement (part of a larger statement), followed
// (something else follows it on its line), used (kept in a variable the
// file uses: detail), unclosed (the call isn't closed), continued (a sway
// line continued with \), block (inside a sway `bindsym { … }` block),
// changed (the file changed since extract), notUser (not one of user/'s
// files), syntax (the result doesn't parse: detail), io (it couldn't be
// read, backed up or written: detail).
package binds

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/compositor/edit"
	"github.com/axiom-shell/axiom/backend/internal/compositor/luacheck"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// Options is one merge call.
type Options struct {
	Kind   string // "hyprland", "sway" or "niri"
	Dir    string // the compositor's config dir (~/.config/hypr)
	Only   string // extract: just this file of user/ (the one a takeover adopted)
	Getenv func(string) string
	Now    func() time.Time // backup names (default time.Now)
	// Tracked: whether a file is in a git repository (default `git rev-parse`)
	Tracked func(ctx context.Context, path string) bool
	Lua     luacheck.Checker
	// Timeout: how long Hyprland's files may run (default 30 s)
	Timeout time.Duration
	// Locked: the caller holds Dir's lock (edit.LockDir); else Remove
	// takes it
	Locked bool
	// Isolate: the axiom binary to read Hyprland's files in, a child
	// limited to MemoryLimit (the daemon's own, /proc/self/exe); "" reads
	// them in this process
	Isolate string
}

func (o *Options) defaults() error {
	if o.Dir == "" {
		return axerr.New(axerr.BadRequest, "a bind merge needs a dir")
	}
	// A file name in user/, never a path out of it
	if o.Only != "" && (o.Only != filepath.Base(o.Only) || o.Only == "." || o.Only == "..") {
		return axerr.New(axerr.BadRequest, "only names a file in user/, not %q", o.Only)
	}
	if o.Getenv == nil {
		o.Getenv = os.Getenv
	}
	if o.Now == nil {
		o.Now = time.Now
	}
	if o.Tracked == nil {
		o.Tracked = inGit
	}
	if o.Timeout == 0 {
		o.Timeout = 30 * time.Second
	}
	return nil
}

func inGit(ctx context.Context, path string) bool {
	return exec.CommandContext(ctx, "git", "-C", filepath.Dir(path), "rev-parse", "--show-toplevel").Run() == nil
}

// Extract reads what can move.
func Extract(ctx context.Context, o Options) (*jsonx.Object, error) {
	if err := o.defaults(); err != nil {
		return nil, err
	}
	switch o.Kind {
	case "hyprland":
		// The only one that runs the user's files
		if o.Isolate != "" {
			return extractIsolated(ctx, o)
		}
		return extractHypr(ctx, o)
	case "sway":
		return extractSway(ctx, o), nil
	case "niri":
		return extractNiri(ctx, o), nil
	}
	return nil, axerr.New(axerr.BadRequest, "unknown compositor %q", o.Kind)
}

// Remove takes the sites extract named out of their files, holding the
// config dir's lock.
func Remove(ctx context.Context, o Options, sites *jsonx.Array) (*jsonx.Object, error) {
	if err := o.defaults(); err != nil {
		return nil, err
	}
	if !o.Locked {
		l, err := edit.LockDir(ctx, o.Dir)
		if err != nil {
			return nil, err
		}
		defer l.Release()
	}
	switch o.Kind {
	case "hyprland":
		return removeHypr(ctx, o, sites)
	case "sway":
		return removeMarked(o, sites, swayMark, false)
	case "niri":
		return removeMarked(o, sites, niriMark, true)
	}
	return nil, axerr.New(axerr.BadRequest, "unknown compositor %q", o.Kind)
}

func emptyResult() *jsonx.Object {
	return jsonx.Obj("binds", jsonx.Arr(), "sites", jsonx.Arr(), "kept", jsonx.Arr(), "remapped", jsonx.Arr(),
		"tracked", jsonx.Arr(), "errors", jsonx.Arr())
}

func keptEntry(file string, line int, key, reason, detail string) *jsonx.Object {
	return jsonx.Obj("file", file, "line", float64(line), "key", key, "reason", reason, "detail", detail)
}

func failedEntry(file string, line int, reason, detail string) *jsonx.Object {
	return jsonx.Obj("file", file, "line", float64(line), "reason", reason, "detail", detail)
}

func push(result *jsonx.Object, key string, items ...any) {
	result.Value(key).(*jsonx.Array).Append(items...)
}

// site is one site of remove's input
type site struct {
	file string
	line int
	col  int
	text string
	// hasText: the line as extract read it is known, so a changed one is
	// left
	hasText bool
}

func readSites(sites *jsonx.Array) []site {
	var out []site
	for _, v := range sites.Items {
		o, ok := jsonx.AsObject(v)
		if !ok {
			continue
		}
		s := site{}
		s.file, _ = o.Value("file").(string)
		line, _ := o.Value("line").(float64)
		col, _ := o.Value("col").(float64)
		s.line, s.col = int(line), int(col)
		s.text, s.hasText = o.Value("text").(string)
		out = append(out, s)
	}
	return out
}

// backup copies path to dir as <name>.axiom-backup-<date>
func backup(o Options, path, dir string) error {
	return edit.Copy(path, filepath.Join(dir, filepath.Base(path)+".axiom-backup-"+o.Now().Format(edit.Stamp)))
}

func isFile(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}

// realPath is path with its links followed (Path.resolve)
func realPath(path string) string {
	abs, err := filepath.Abs(path)
	if err != nil {
		return path
	}
	if real, err := filepath.EvalSymlinks(abs); err == nil {
		return real
	}
	return abs
}
