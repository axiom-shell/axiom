// Package devconfig is the dev config's logic: dev mode runs on a config
// of its own ($XDG_CONFIG_HOME/axiom/dev/config.json), which the install
// never reads. Prepare seeds it from the live config and keeps its
// takeover settings the live ones (one per machine); Rows and Merge
// compare dev and live three ways against the base (the live bytes at the
// last sync, $XDG_STATE_HOME/axiom/dev/base.json); WriteLive copies chosen
// changes back to live without ever migrating it: ops on its raw JSON,
// checked against the install tree's schema, its version untouched.
package devconfig

import (
	"bytes"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/migrate/convert"
	"github.com/axiom-shell/axiom/backend/internal/migrate/steps"
	"github.com/axiom-shell/axiom/backend/internal/share"
)

// Files are the three files the dev config is kept with.
type Files struct {
	Live string // the install's config.json ($XDG_CONFIG_HOME/axiom/config.json)
	Dev  string // the dev config ($XDG_CONFIG_HOME/axiom/dev/config.json)
	Base string // live's raw bytes at the last sync ($XDG_STATE_HOME/axiom/dev/base.json)
}

// Prepared is what Prepare did and found, for DevState.config.
type Prepared struct {
	// Seeded: the dev config was made now
	Seeded bool `json:"seeded"`
	// LiveChanged: live differs from the base (each loaded through the dev
	// pipeline in memory, so a migration or a reformat isn't a change)
	LiveChanged bool `json:"liveChanged"`
	// Patched is the takeover settings dev took from live ("Idle.enabled")
	Patched []string `json:"patched,omitempty"`
	// Note says why the dev config isn't live's copy, or why its takeover
	// settings aren't live's (English, as logged); "" when nothing to say
	Note string `json:"note,omitempty"`
}

// Prepare readies the dev config before the dev image's store opens it,
// holding its writer lock meanwhile. Without a dev config, it's live's raw
// bytes (live's version too: the dev store migrates it on open), and the
// base is too; a live config newer than devPipe's migrations seeds the
// defaults plus live's takeover settings instead, with a note. Without a
// base, the base is live. Then dev's takeover settings are set to live's,
// and LiveChanged says whether live moved on since the base. Live is only
// read.
func Prepare(f Files, devPipe config.Pipeline) (Prepared, error) {
	if err := os.MkdirAll(filepath.Dir(f.Dev), 0o700); err != nil {
		return Prepared{}, axerr.Wrap(axerr.Unavailable, err, "making %s", filepath.Dir(f.Dev))
	}
	lock, err := lockFor(f.Dev)
	if err != nil {
		return Prepared{}, err
	}
	defer lock.Release()

	liveRaw, err := readOptional(f.Live)
	if err != nil {
		return Prepared{}, err
	}
	devRaw, err := readOptional(f.Dev)
	if err != nil {
		return Prepared{}, err
	}
	baseRaw, err := readOptional(f.Base)
	if err != nil {
		return Prepared{}, err
	}

	var p Prepared
	if devRaw == nil {
		p.Seeded = true
		seed, note := seedFrom(liveRaw, devPipe)
		p.Note = note
		if err := writeFile(f.Dev, seed); err != nil {
			return p, err
		}
		if liveRaw != nil {
			return p, writeFile(f.Base, liveRaw)
		}
		return p, nil
	}
	if liveRaw == nil {
		// No live config to follow (the install never ran): dev stands alone
		return p, nil
	}
	if baseRaw == nil {
		if err := writeFile(f.Base, liveRaw); err != nil {
			return p, err
		}
		baseRaw = liveRaw
	}
	patched, paths, note := patchTakeovers(devRaw, liveRaw, devPipe)
	p.Patched, p.Note = paths, note
	if patched != nil {
		if err := writeFile(f.Dev, patched); err != nil {
			return p, err
		}
	}
	p.LiveChanged = changed(liveRaw, baseRaw, devPipe)
	return p, nil
}

// seedFrom is the first dev config: live's bytes, or the defaults when
// there is no live config or it is newer than devPipe's migrations (with
// live's takeover settings, when they fit).
func seedFrom(liveRaw []byte, devPipe config.Pipeline) ([]byte, string) {
	if liveRaw == nil {
		return jsonx.Marshal(devPipe.Defaults()), "there was no live config: the dev config starts from the defaults"
	}
	parsed, err := parse(liveRaw)
	if err != nil {
		// Copied as it is: the dev store blocks saves until it's fixed, as
		// the live one does
		return liveRaw, ""
	}
	version, newer := newerThanMigrations(parsed)
	if !newer {
		return liveRaw, ""
	}
	note := fmt.Sprintf("the live config (version %v) is newer than this dev tree's migrations (%d): the dev config starts from the defaults", jsonx.ToString(version), steps.Current())
	defaults := devPipe.Defaults()
	withTakeovers, _ := share.KeepTakeovers(defaults, parsed, share.TakeoverPaths(devPipe.Schema())).(*jsonx.Object)
	if _, problems := devPipe.Check(withTakeovers); len(problems) > 0 {
		return jsonx.Marshal(defaults), note + " (live's takeover settings don't fit its schema)"
	}
	return jsonx.Marshal(withTakeovers), note + ", with live's takeover settings"
}

// newerThanMigrations says a format-2 config is of a version this binary's
// steps don't reach (its version, for the note).
func newerThanMigrations(cfg *jsonx.Object) (any, bool) {
	version, _ := cfg.Get("version")
	v, ok := version.(float64)
	return version, ok && cfg.Value("format") == float64(convert.Format) && v > float64(steps.Current())
}

// patchTakeovers sets dev's takeover settings to live's, in dev's raw
// JSON: the new bytes (nil when nothing changed), the paths changed, and a
// note when live's values were left out. Both are compared loaded through
// devPipe in memory where they load (live newer or invalid: its raw
// values), so a value left to its default isn't a difference.
func patchTakeovers(devRaw, liveRaw []byte, devPipe config.Pipeline) ([]byte, []string, string) {
	dev, err := parse(devRaw)
	if err != nil {
		return nil, nil, "" // the dev store reports it
	}
	live, err := parse(liveRaw)
	if err != nil {
		return nil, nil, ""
	}
	if loaded, ok := load(devPipe, live); ok {
		live = loaded
	}
	devLoaded, devLoads := load(devPipe, dev)
	current := dev
	if devLoads {
		current = devLoaded
	}
	next := jsonx.Clone(dev).(*jsonx.Object)
	var paths []string
	for _, path := range share.TakeoverPaths(devPipe.Schema()) {
		want, ok := lookup(live, path)
		if !ok {
			continue
		}
		if have, has := lookup(current, path); has && jsonx.Equal(have, want) {
			continue
		}
		putAt(next, path, jsonx.Clone(want))
		paths = append(paths, config.Keys(path...).String())
	}
	if len(paths) == 0 {
		return nil, nil, ""
	}
	if _, ok := load(devPipe, next); devLoads && !ok {
		return nil, nil, "live's takeover settings don't fit the dev schema: the dev config keeps its own"
	}
	return jsonx.Marshal(next), paths, ""
}

// changed says live moved on since base: their bytes differ and, loaded
// through devPipe in memory, so do the configs (either not loading: the
// bytes decide).
func changed(liveRaw, baseRaw []byte, devPipe config.Pipeline) bool {
	if bytes.Equal(liveRaw, baseRaw) {
		return false
	}
	live, err1 := InShape(devPipe, liveRaw)
	base, err2 := InShape(devPipe, baseRaw)
	if err1 != nil || err2 != nil {
		return true
	}
	return !jsonx.Equal(live, base)
}

// LiveChanged says whether live moved on since the base (Prepared's
// LiveChanged, asked again after a copy or a pull): no live config is no
// change, no base is one.
func LiveChanged(f Files, devPipe config.Pipeline) (bool, error) {
	liveRaw, err := readOptional(f.Live)
	if err != nil || liveRaw == nil {
		return false, err
	}
	baseRaw, err := readOptional(f.Base)
	if err != nil {
		return false, err
	}
	return baseRaw == nil || changed(liveRaw, baseRaw, devPipe), nil
}

// SyncBase makes the base liveRaw (live's bytes, as read for a pull): from
// now on, only what live changes after it counts as live's.
func SyncBase(f Files, liveRaw []byte) error {
	return writeFile(f.Base, liveRaw)
}

// ReadOptional is a file's bytes, nil when there is none.
func ReadOptional(path string) ([]byte, error) { return readOptional(path) }

// InShape is raw config bytes loaded through pipe in memory (migrated,
// pruned, filled with defaults): how Rows and Merge compare live and the
// base with dev. Nothing is written; a config that doesn't load is an
// InvalidConfig error with its issues.
func InShape(pipe config.Pipeline, raw []byte) (*jsonx.Object, error) {
	parsed, err := parse(raw)
	if err != nil {
		return nil, err
	}
	loaded, err := pipe.Load(parsed)
	if err != nil {
		return nil, err
	}
	if len(loaded.Errors) > 0 {
		return nil, &axerr.Error{Kind: axerr.InvalidConfig, Message: "the config doesn't load", Issues: issues(loaded.Errors)}
	}
	return loaded.Config, nil
}

// load is cfg loaded through pipe, on a copy (a load migrates and prunes
// in place); ok only when it loads clean.
func load(pipe config.Pipeline, cfg *jsonx.Object) (*jsonx.Object, bool) {
	loaded, err := pipe.Load(jsonx.Clone(cfg))
	if err != nil || len(loaded.Errors) > 0 {
		return nil, false
	}
	return loaded.Config, true
}

// parse reads config bytes (a byte-order mark allowed, as the store does).
func parse(raw []byte) (*jsonx.Object, error) {
	v, err := jsonx.Unmarshal(bytes.TrimPrefix(raw, []byte("\xef\xbb\xbf")))
	if err != nil {
		return nil, axerr.Wrap(axerr.InvalidConfig, err, "not JSON")
	}
	obj, ok := v.(*jsonx.Object)
	if !ok {
		return nil, axerr.New(axerr.InvalidConfig, "a config must hold an object")
	}
	return obj, nil
}

// readOptional is a file's bytes, nil when there is none.
func readOptional(path string) ([]byte, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, axerr.Wrap(axerr.Unavailable, err, "reading %s", path)
	}
	return data, nil
}

func writeFile(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "making %s", filepath.Dir(path))
	}
	if err := fsx.WriteFile(path, data, 0o600); err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "writing %s", path)
	}
	return nil
}

// lockFor takes the writer lock of a config file: the one the store holds
// for it (store.Open's <dir>/config.json.lock), so nothing writes it while
// a store has it open.
func lockFor(path string) (*fsx.Lock, error) {
	lock, err := fsx.TryLock(path + ".lock")
	if axerr.KindOf(err) == axerr.Running {
		return nil, &axerr.Error{Kind: axerr.Running, Message: "another axiom is writing " + path, Err: err}
	}
	return lock, err
}

func lookup(cfg *jsonx.Object, path []string) (any, bool) {
	return config.Lookup(cfg, config.Keys(path...))
}

// putAt sets v at path, making the objects on the way; a non-object on
// the way is left alone (validation reports it).
func putAt(o *jsonx.Object, path []string, v any) {
	for _, k := range path[:len(path)-1] {
		child, has := o.Get(k)
		if !has {
			child = jsonx.NewObject()
			o.Set(k, child)
		}
		next, ok := child.(*jsonx.Object)
		if !ok {
			return
		}
		o = next
	}
	o.Set(path[len(path)-1], v)
}

// issues is validation's "path: message" lines as issues.
func issues(lines []string) []axerr.Issue {
	out := make([]axerr.Issue, 0, len(lines))
	for _, l := range lines {
		path, msg, ok := cut(l)
		if !ok {
			path, msg = "", l
		}
		out = append(out, axerr.Issue{Path: path, Message: msg})
	}
	return out
}

func cut(line string) (string, string, bool) {
	for i := 0; i+1 < len(line); i++ {
		if line[i] == ':' && line[i+1] == ' ' {
			return line[:i], line[i+2:], true
		}
	}
	return "", "", false
}
