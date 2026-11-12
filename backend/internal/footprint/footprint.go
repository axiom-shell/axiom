// Package footprint is the ledger of what axiom changes outside its own
// folders (docs/dev/backend/footprint.md): a file of a theme integration, a
// line in an app's config, a gsettings key, a default app, an input method
// setting. Every change is recorded before it happens, with what was there
// (Prior) and what axiom wrote (Wrote), so it can be listed and undone
// exactly: only axiom's own change is taken out, a value that changed
// since is left, and no whole-file backup is ever put back. The recording
// points are the packages that make the changes (they Begin and Done a Row
// and register the Undoer of their kind); the ledger holds the file, its
// lock, the order of an undo, and the kinds that are plain files, folders,
// gsettings, marked blocks and rebuilds.
package footprint

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/hookup"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// Version is the ledger file's format: another version is read-only.
const Version = 1

// The kinds of a Row.
const (
	KindFile        = "file"         // a file axiom owns outright
	KindDir         = "dir"          // a folder axiom made
	KindHookup      = "hookup"       // lines in an app's own config (package hookup)
	KindGSetting    = "gsetting"     // a gsettings key
	KindINIGroups   = "ini-groups"   // keys in an ini file shared with the user (kdeglobals)
	KindMarkedBlock = "marked-block" // the lines between two markers
	KindFcitxConfig = "fcitx-config" // fcitx5's config at a uri
	KindFcitxGroup  = "fcitx-group"  // fcitx5's input method group
	KindMimeapps    = "mimeapps"     // a default app
	KindRebuild     = "rebuild"      // a command to run once the files are out
)

// kindOrder is the order an undo goes in: settings first, so a cursor
// theme is restored before its companion folder is deleted.
var kindOrder = []string{KindGSetting, KindFcitxConfig, KindFcitxGroup, KindMimeapps, KindINIGroups,
	KindMarkedBlock, KindHookup, KindFile, KindDir, KindRebuild}

// Row states.
const (
	StatePending = "pending" // written ahead, the change may not have happened
	StateApplied = "applied"
)

// Row is one change axiom made outside its folders.
type Row struct {
	// ID is Kind + ":" + Target (+ ":" + Key): a repeated write updates one row
	ID    string `json:"id"`
	Kind  string `json:"kind"`
	Owner string `json:"owner"` // a setting path ("ThemeIntegrations.gtk"), or "" (compositor include/autostart)
	// Target is a path, "<schema> <key>", a fcitx uri, a mimeapps path
	Target string `json:"target"`
	Key    string `json:"key,omitempty"`
	State  string `json:"state"`
	// Inferred: found by the backfill, without a record of writing it
	Inferred bool `json:"inferred,omitempty"`
	// System: the system's own choice (default apps, input method engines):
	// left by Undo all and uninstall unless picked
	System bool `json:"system,omitempty"`
	// Prior is set on the first Begin only; {"absent":true} when nothing was there
	Prior json.RawMessage `json:"prior,omitempty"`
	// Wrote is the last value axiom wrote (Done)
	Wrote   json.RawMessage `json:"wrote,omitempty"`
	Hookup  *HookupRec      `json:"hookup,omitempty"`
	Created int64           `json:"created"`
	Updated int64           `json:"updated"`
}

// HookupRec is what a hookup row records beyond the edit.
type HookupRec struct {
	Edit        hookup.EditRecord `json:"edit"`
	CreatedFile bool              `json:"createdFile,omitempty"`
	// LinkTarget is the link a WrapLink file replaced
	LinkTarget string `json:"linkTarget,omitempty"`
	// CopiedSHA256 is a Copy target's file, as copied
	CopiedSHA256 string `json:"copiedSha256,omitempty"`
	// NoFinalNewline: the file had no newline ending it (Apply adds one)
	NoFinalNewline bool `json:"noFinalNewline,omitempty"`
	// Backup is the .axiom-bak-<stamp> beside the file: listed, never put back
	Backup string `json:"backup,omitempty"`
}

// Status of a row against the system.
const (
	StatusPresent = "present"
	StatusChanged = "changed" // what axiom wrote is no longer there as written
	StatusGone    = "gone"
)

// RowStatus is a Row with its Status.
type RowStatus struct {
	Row
	Status string `json:"status"`
}

// Outcomes of an undo.
const (
	OutcomeDone         = "done"
	OutcomeGone         = "gone" // nothing left to undo
	OutcomeChanged      = "changed"
	OutcomeNeedsRunning = "needsRunning"
	OutcomeRefused      = "refused"
	OutcomeFailed       = "failed"
)

// Result is how undoing one row went. done and gone remove the row.
type Result struct {
	ID      string `json:"id"`
	Outcome string `json:"outcome"`
	Detail  string `json:"detail,omitempty"`
}

// UndoOptions say which rows an undo may touch.
type UndoOptions struct {
	// Force allows an inferred row
	Force bool `json:"force"`
	// IncludeSystem: Undo all takes the system's own choices too (an id
	// named is always undone)
	IncludeSystem bool `json:"includeSystem"`
	// DryRun changes nothing and says what would happen
	DryRun bool `json:"dryRun"`
}

// An Undoer takes one row's change out. gone: nothing left to take out.
// An undoer that put some of it back and left the rest (changed) shrinks
// the row to what's left; the ledger keeps it.
type Undoer func(ctx context.Context, row *Row) (outcome, detail string)

// A Checker says whether a row's change is still there as written.
type Checker func(ctx context.Context, row Row) string

// Options configure a Ledger.
type Options struct {
	Dirs xdg.Dirs
	Now  func() time.Time
	Log  func(format string, args ...any)
	// GSettings runs gsettings (the gsetting kind); nil: a gsetting row is
	// failed
	GSettings func(ctx context.Context, args ...string) (string, error)
	// Run runs a rebuild's command; default runs it
	Run func(ctx context.Context, argv []string) error
	// OnChange is called after a row changed or was removed
	OnChange func()
}

// Ledger is $XDG_STATE_HOME/axiom/footprint.json. Every read-modify-write
// holds a flock on footprint.lock, so the daemon and the command line
// agree.
type Ledger struct {
	o    Options
	path string

	mu       sync.Mutex
	undoers  map[string]Undoer
	checkers map[string]Checker
}

type file struct {
	Version    int   `json:"version"`
	Backfilled int   `json:"backfilled"`
	Rows       []Row `json:"rows"`
}

// New makes a Ledger with the generic kinds registered.
func New(o Options) *Ledger {
	if o.Now == nil {
		o.Now = time.Now
	}
	if o.Run == nil {
		o.Run = func(ctx context.Context, argv []string) error {
			ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
			defer cancel()
			return exec.CommandContext(ctx, argv[0], argv[1:]...).Run()
		}
	}
	l := &Ledger{o: o, path: filepath.Join(o.Dirs.State, "footprint.json"),
		undoers: map[string]Undoer{}, checkers: map[string]Checker{}}
	l.registerGeneric()
	return l
}

func (l *Ledger) log(format string, args ...any) {
	if l.o.Log != nil {
		l.o.Log(format, args...)
	}
}

// Register sets the Undoer and Checker of a kind.
func (l *Ledger) Register(kind string, u Undoer, c Checker) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.undoers[kind], l.checkers[kind] = u, c
}

// ID is the id of a row of kind for target (and key).
func ID(kind, target, key string) string {
	id := kind + ":" + target
	if key != "" {
		id += ":" + key
	}
	return id
}

func (l *Ledger) lockPath() string { return filepath.Join(filepath.Dir(l.path), "footprint.lock") }

const lockWait = 5 * time.Second

func (l *Ledger) lock() (release func(), err error) {
	if err := os.MkdirAll(filepath.Dir(l.path), 0o700); err != nil {
		return nil, err
	}
	f, err := os.OpenFile(l.lockPath(), os.O_RDWR|os.O_CREATE|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0o600)
	if err != nil {
		return nil, err
	}
	deadline := time.Now().Add(lockWait)
	for {
		err := unix.Flock(int(f.Fd()), unix.LOCK_EX|unix.LOCK_NB)
		if err == nil {
			return func() { unix.Flock(int(f.Fd()), unix.LOCK_UN); f.Close() }, nil
		}
		if !errors.Is(err, unix.EWOULDBLOCK) || time.Now().After(deadline) {
			f.Close()
			return nil, err
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// read is the file; readOnly is true for one of another version (its rows
// are still listed).
func (l *Ledger) read() (f *file, readOnly bool) {
	f = &file{Version: Version}
	data, err := os.ReadFile(l.path)
	if err != nil {
		return f, false
	}
	var got file
	if err := json.Unmarshal(data, &got); err != nil {
		l.log("footprint: %s isn't readable: %v", l.path, err)
		return f, false
	}
	if got.Version != Version {
		l.log("footprint: %s is version %d, not %d: read only", l.path, got.Version, Version)
		return &got, true
	}
	return &got, false
}

func (l *Ledger) write(f *file) error {
	f.Version = Version
	data, err := json.Marshal(f)
	if err != nil {
		return err
	}
	return fsx.WriteFile(l.path, data, 0o600)
}

// update reads the file under its lock, lets fn change it, and writes it
// when fn says so.
func (l *Ledger) update(fn func(f *file) (changed bool, err error)) error {
	release, err := l.lock()
	if err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "the footprint ledger")
	}
	defer release()
	f, readOnly := l.read()
	if readOnly {
		return axerr.New(axerr.Refused, "the footprint ledger is of another version: left as it is")
	}
	changed, err := fn(f)
	if err != nil {
		return err
	}
	if changed {
		if err := l.write(f); err != nil {
			return axerr.Wrap(axerr.Unavailable, err, "writing the footprint ledger")
		}
	}
	return nil
}

func (l *Ledger) changed() {
	if l.o.OnChange != nil {
		l.o.OnChange()
	}
}

// pathKinds are the kinds whose Target is a path.
var pathKinds = []string{KindFile, KindDir, KindHookup, KindMarkedBlock, KindINIGroups}

// own says whether a path is under axiom's own folders (never recorded).
func (l *Ledger) own(kind, target string) bool {
	if !slices.Contains(pathKinds, kind) {
		return false
	}
	for _, d := range []string{l.o.Dirs.Config, l.o.Dirs.State, l.o.Dirs.Data, l.o.Dirs.Cache} {
		if d != "" && (target == strings.TrimRight(d, "/") || strings.HasPrefix(target, d)) {
			return true
		}
	}
	return false
}

// Begin records a change before it's made: a row for it, pending, with
// Prior from prior (called only when the row is new). A row already
// applied is left as it is (its write costs nothing). It returns "" for
// a path under axiom's own folders, or on a nil Ledger: Done then does
// nothing. A ledger that can't be written is an error, and the change
// should not be made.
func (l *Ledger) Begin(row Row, prior func() (json.RawMessage, error)) (string, error) {
	if l == nil {
		return "", nil
	}
	if l.own(row.Kind, row.Target) {
		return "", nil
	}
	row.ID = ID(row.Kind, row.Target, row.Key)
	err := l.update(func(f *file) (bool, error) {
		now := l.o.Now().Unix()
		i := slices.IndexFunc(f.Rows, func(r Row) bool { return r.ID == row.ID })
		if i >= 0 {
			have := &f.Rows[i]
			if have.State == StateApplied && have.Owner == row.Owner && row.Hookup == nil {
				return false, nil
			}
			have.State = StatePending
			have.Updated = now
			if row.Owner != "" {
				have.Owner = row.Owner
			}
			have.Hookup = mergeHookup(have.Hookup, row.Hookup)
			return true, nil
		}
		row.Created, row.Updated, row.State = now, now, StatePending
		if prior != nil {
			p, err := prior()
			if err != nil {
				return false, err
			}
			row.Prior = p
		}
		f.Rows = append(f.Rows, row)
		return true, nil
	})
	if err != nil {
		return "", err
	}
	return row.ID, nil
}

// mergeHookup is a second edit of a file added to the first's record: the
// first's backup, link and creation stay (they're what was there before
// axiom), the lines are both's.
func mergeHookup(old, now *HookupRec) *HookupRec {
	if old == nil || now == nil {
		return cmpHookup(old, now)
	}
	out := *now
	out.CreatedFile = old.CreatedFile || now.CreatedFile
	out.NoFinalNewline = old.NoFinalNewline || now.NoFinalNewline
	if old.LinkTarget != "" {
		out.LinkTarget = old.LinkTarget
	}
	if old.Backup != "" {
		out.Backup = old.Backup
	}
	out.Edit.Wrapped = old.Edit.Wrapped || now.Edit.Wrapped
	if old.Edit.WrapLine != "" {
		out.Edit.WrapLine = old.Edit.WrapLine
	}
	out.Edit.Inserted = append(slices.Clone(old.Edit.Inserted), now.Edit.Inserted...)
	out.Edit.Commented = append(slices.Clone(old.Edit.Commented), now.Edit.Commented...)
	if old.Edit.CreatedSection != "" {
		out.Edit.CreatedSection = old.Edit.CreatedSection
	}
	return &out
}

func cmpHookup(old, now *HookupRec) *HookupRec {
	if now != nil {
		return now
	}
	return old
}

// Done records the change as made, with what was written (nil: as before).
func (l *Ledger) Done(id string, wrote json.RawMessage) {
	if l == nil || id == "" {
		return
	}
	err := l.update(func(f *file) (bool, error) {
		i := slices.IndexFunc(f.Rows, func(r Row) bool { return r.ID == id })
		if i < 0 {
			return false, nil
		}
		r := &f.Rows[i]
		if r.State == StateApplied && (wrote == nil || string(wrote) == string(r.Wrote)) {
			return false, nil
		}
		r.State = StateApplied
		if wrote != nil {
			r.Wrote = wrote
		}
		r.Updated = l.o.Now().Unix()
		return true, nil
	})
	if err != nil {
		l.log("footprint: %v", err)
		return
	}
	l.changed()
}

// Drop removes a row without undoing it (what it recorded is gone by
// other means).
func (l *Ledger) Drop(id string) {
	if l == nil || id == "" {
		return
	}
	_ = l.update(func(f *file) (bool, error) {
		n := len(f.Rows)
		f.Rows = slices.DeleteFunc(f.Rows, func(r Row) bool { return r.ID == id })
		return len(f.Rows) != n, nil
	})
	l.changed()
}

// Rows are the recorded rows, as read (no status).
func (l *Ledger) Rows() []Row {
	if l == nil {
		return nil
	}
	release, err := l.lock()
	if err == nil {
		defer release()
	}
	f, _ := l.read()
	return f.Rows
}

// List is every row with its status, in the order recorded.
func (l *Ledger) List(ctx context.Context) []RowStatus {
	rows := l.Rows()
	out := make([]RowStatus, 0, len(rows))
	for _, r := range rows {
		out = append(out, RowStatus{Row: r, Status: l.status(ctx, r)})
	}
	return out
}

func (l *Ledger) status(ctx context.Context, r Row) string {
	l.mu.Lock()
	c := l.checkers[r.Kind]
	l.mu.Unlock()
	if c == nil {
		return StatusPresent
	}
	return c(ctx, r)
}

// Select is the ids Undo all takes: every row but the system's own
// (unless IncludeSystem) and the inferred ones (unless Force).
func (l *Ledger) Select(o UndoOptions) []string {
	var ids []string
	for _, r := range l.Rows() {
		if r.System && !o.IncludeSystem || r.Inferred && !o.Force {
			continue
		}
		ids = append(ids, r.ID)
	}
	return ids
}

// SelectOwner is the ids of the rows an owner's setting caused.
func (l *Ledger) SelectOwner(owner string) []string {
	var ids []string
	for _, r := range l.Rows() {
		if r.Owner == owner {
			ids = append(ids, r.ID)
		}
	}
	return ids
}

// Backfilled says whether the backfill ran.
func (l *Ledger) Backfilled() bool {
	if l == nil {
		return true
	}
	release, err := l.lock()
	if err == nil {
		defer release()
	}
	f, _ := l.read()
	return f.Backfilled != 0
}

// Backfill adds rows found without a record of writing them (each marked
// inferred, applied) where no row with their id exists, once: it returns
// ran false when the ledger was backfilled already.
func (l *Ledger) Backfill(rows []Row) (added []string, ran bool, err error) {
	err = l.update(func(f *file) (bool, error) {
		if f.Backfilled != 0 {
			return false, nil
		}
		ran = true
		now := l.o.Now().Unix()
		for _, r := range rows {
			r.ID = ID(r.Kind, r.Target, r.Key)
			if l.own(r.Kind, r.Target) || slices.ContainsFunc(f.Rows, func(have Row) bool { return have.ID == r.ID }) {
				continue
			}
			r.Inferred, r.State, r.Created, r.Updated = true, StateApplied, now, now
			f.Rows = append(f.Rows, r)
			added = append(added, r.ID)
		}
		f.Backfilled = 1
		return true, nil
	})
	if err == nil && len(added) > 0 {
		l.changed()
	}
	return added, ran, err
}

// Undo takes the changes of the rows ids name out, settings first (the
// order of the kinds), each only when it's still as axiom wrote it. A row
// that's gone or undone is removed. An inferred row needs Force, else it's
// refused. DryRun reports and changes nothing.
func (l *Ledger) Undo(ctx context.Context, ids []string, o UndoOptions) []Result {
	results := []Result{}
	var rows []Row
	err := func() error {
		release, err := l.lock()
		if err != nil {
			return axerr.Wrap(axerr.Unavailable, err, "the footprint ledger")
		}
		defer release()
		f, readOnly := l.read()
		if readOnly && !o.DryRun {
			return axerr.New(axerr.Refused, "the footprint ledger is of another version: left as it is")
		}
		rows = l.picked(f.Rows, ids)
		var removed []string
		for _, r := range rows {
			res := l.undoOne(ctx, &r, o)
			results = append(results, res)
			switch {
			case o.DryRun:
			case res.Outcome == OutcomeDone || res.Outcome == OutcomeGone:
				removed = append(removed, r.ID)
				f.Rows = slices.DeleteFunc(f.Rows, func(have Row) bool { return have.ID == r.ID })
				if err := l.write(f); err != nil {
					return err
				}
			default:
				// A row the undoer shrank to what it left is kept so
				if i := slices.IndexFunc(f.Rows, func(have Row) bool { return have.ID == r.ID }); i >= 0 &&
					(!bytes.Equal(f.Rows[i].Prior, r.Prior) || !bytes.Equal(f.Rows[i].Wrote, r.Wrote)) {
					f.Rows[i] = r
					if err := l.write(f); err != nil {
						return err
					}
				}
			}
		}
		if len(removed) > 0 {
			l.gcPrior(f.Rows)
		}
		return nil
	}()
	if err != nil {
		results = append(results, Result{Outcome: OutcomeFailed, Detail: err.Error()})
		if ae := (*axerr.Error)(nil); errors.As(err, &ae) && ae.Kind == axerr.Refused {
			results[len(results)-1].Outcome = OutcomeRefused
		}
	}
	if !o.DryRun {
		l.changed()
	}
	return results
}

// picked are the rows ids name, in undo order.
func (l *Ledger) picked(all []Row, ids []string) []Row {
	var rows []Row
	for _, id := range ids {
		if i := slices.IndexFunc(all, func(r Row) bool { return r.ID == id }); i >= 0 && !slices.ContainsFunc(rows, func(r Row) bool { return r.ID == id }) {
			rows = append(rows, all[i])
		}
	}
	rank := func(kind string) int {
		if i := slices.Index(kindOrder, kind); i >= 0 {
			return i
		}
		return len(kindOrder)
	}
	// Latest first within a kind (a dir deepest first)
	slices.SortStableFunc(rows, func(a, b Row) int {
		if d := rank(a.Kind) - rank(b.Kind); d != 0 {
			return d
		}
		if a.Kind == KindDir {
			return len(b.Target) - len(a.Target)
		}
		return int(b.Created - a.Created)
	})
	return rows
}

func (l *Ledger) undoOne(ctx context.Context, r *Row, o UndoOptions) Result {
	res := Result{ID: r.ID}
	if r.Inferred && !o.Force {
		res.Outcome, res.Detail = OutcomeRefused, "found without a record of writing it: needs force"
		return res
	}
	l.mu.Lock()
	undo, check := l.undoers[r.Kind], l.checkers[r.Kind]
	l.mu.Unlock()
	if undo == nil {
		res.Outcome, res.Detail = OutcomeFailed, "no undo for "+r.Kind
		return res
	}
	if o.DryRun {
		status := StatusPresent
		if check != nil {
			status = check(ctx, *r)
		}
		switch status {
		case StatusGone:
			res.Outcome = OutcomeGone
		case StatusChanged:
			res.Outcome = OutcomeChanged
		default:
			res.Outcome, res.Detail = OutcomeDone, "dry run"
		}
		return res
	}
	res.Outcome, res.Detail = undo(ctx, r)
	if res.Outcome == "" {
		res.Outcome = OutcomeDone
	}
	if res.Outcome == OutcomeFailed || res.Outcome == OutcomeChanged || res.Outcome == OutcomeNeedsRunning {
		l.log("footprint: %s: %s %s", r.ID, res.Outcome, res.Detail)
	}
	return res
}

// Get is the row with id.
func (l *Ledger) Get(id string) (Row, bool) {
	for _, r := range l.Rows() {
		if r.ID == id {
			return r, true
		}
	}
	return Row{}, false
}

// Amend lets fn change the row with id (a Prior or Wrote merged with an
// earlier one's), under the lock.
func (l *Ledger) Amend(id string, fn func(*Row)) error {
	if l == nil || id == "" {
		return nil
	}
	return l.update(func(f *file) (bool, error) {
		i := slices.IndexFunc(f.Rows, func(r Row) bool { return r.ID == id })
		if i < 0 {
			return false, nil
		}
		fn(&f.Rows[i])
		return true, nil
	})
}
