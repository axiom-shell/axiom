// Package uninstall takes axiom's footprint out of the user's home and
// session (docs/dev/backend/uninstall.md): the compositor configs given
// back, the ledger's changes undone, the lines install.sh added taken out,
// what a crash left, the installed files, the portal restarted, the
// keyring and the folders, each as the user answered. Build says what that
// would do and changes nothing; Run does it, step by step, each step going
// on when an item fails, and lists what it left. It never deletes a file
// that is the user's (a compositor config, a backup), and never runs
// anything as root.
package uninstall

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/compositor/takeover"
	"github.com/axiom-shell/axiom/backend/internal/footprint"
	"github.com/axiom-shell/axiom/backend/internal/session"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// SecretsSeam is the keyring, which the uninstall only counts and clears.
// Nil funcs: there is none.
type SecretsSeam struct {
	Count    func(ctx context.Context) (int, error)
	ClearAll func(ctx context.Context) error
}

// Options are what an uninstall works on, each replaced in tests.
type Options struct {
	Dirs   xdg.Dirs
	Getenv func(string) string
	// Root is "/" (tests: a fixture root for /usr/share/axiom-greeter and
	// /etc/greetd)
	Root string
	// Bin is this binary: the autostart line's binary may be any path
	// matching the start pattern
	Bin    string
	Ledger *footprint.Ledger
	// Inferred is what the ledger's backfill would add (nothing is written
	// by asking): the hookups, and the files and cursor folders, an earlier
	// axiom made without recording them (the ledger backfills them apart)
	Inferred func(ctx context.Context) (hookups, files []footprint.Row)
	Session  session.Seams
	// DialBus connects to the session bus (nil: none, so no units and no
	// portal restart)
	DialBus func(ctx context.Context) (session.Bus, func())
	Secrets SecretsSeam
	// Shutdown asks the daemon at socket to quit (Stop)
	Shutdown func(ctx context.Context, socket string) error
	// ExcludeDisplay is the display of the daemon that makes the plan: it
	// isn't counted as running
	ExcludeDisplay string
	Log            *slog.Logger
	Now            func() time.Time
}

func (o Options) withDefaults() Options {
	if o.Getenv == nil {
		o.Getenv = os.Getenv
	}
	if o.Root == "" {
		o.Root = "/"
	}
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	if o.Now == nil {
		o.Now = time.Now
	}
	if o.Dirs.State == "" {
		o.Dirs = xdg.Resolve(o.Getenv)
	}
	o.Session = o.Session.WithDefaults()
	return o
}

// Action is one thing the uninstall does: its Step, what it does to Path,
// and Asks, the Answers field deciding it ("" for one that always goes).
type Action struct {
	Step   string `json:"step"`
	What   string `json:"what"`
	Path   string `json:"path,omitempty"`
	Detail string `json:"detail,omitempty"`
	Asks   string `json:"asks,omitempty"`
}

// GreeterNote says the login screen is installed for the whole system and
// stays: removing it takes an administrator.
type GreeterNote struct {
	Text  string   `json:"text"`
	Paths []string `json:"paths"`
}

const greeterText = "axiom's login screen is installed for the whole system and stays after this. " +
	"Remove it first in Settings → Login screen → Uninstall (one admin prompt), or with " +
	"`axiom greeter-install uninstall` as root (docs/installation.md › Uninstall)."

// Plan is what an uninstall would do (Build changes nothing).
type Plan struct {
	Actions []Action `json:"actions"`
	// Manual are lines of axiom's the uninstall isn't sure are its own
	Manual  []Manual     `json:"manual"`
	Backups []string     `json:"backups"`
	Greeter *GreeterNote `json:"greeter,omitempty"`
	// Running are the displays a daemon runs on
	Running []string `json:"running"`
	Counts  Counts   `json:"counts"`
}

// Item is one thing done, or left.
type Item struct {
	Step   string `json:"step"`
	What   string `json:"what"`
	Path   string `json:"path,omitempty"`
	Detail string `json:"detail,omitempty"`
}

// Report is how a Run went: what it did, what it left (changed since,
// kept as asked, failed), the lines to remove by hand, the backups kept.
type Report struct {
	Done    []Item       `json:"done"`
	Left    []Item       `json:"left"`
	Manual  []Manual     `json:"manual"`
	Backups []string     `json:"backups"`
	Greeter *GreeterNote `json:"greeter,omitempty"`
	// Notes are what's left to do (restart the session)
	Notes []string `json:"notes"`
}

// greeter is the note when the login screen is installed.
func (o Options) greeter() *GreeterNote {
	var paths []string
	dir := filepath.Join(o.Root, "usr/share/axiom-greeter")
	if _, err := os.Stat(dir); err == nil {
		paths = append(paths, dir)
	}
	cfg := filepath.Join(o.Root, "etc/greetd/config.toml")
	if data, err := os.ReadFile(cfg); err == nil && strings.Contains(string(data), "axiom-greeter") {
		paths = append(paths, cfg)
	}
	if len(paths) == 0 {
		return nil
	}
	return &GreeterNote{Text: greeterText, Paths: paths}
}

var rowWhat = map[string]string{
	footprint.KindFile:        "Delete the file axiom made",
	footprint.KindDir:         "Remove the folder axiom made",
	footprint.KindHookup:      "Take axiom's lines out of",
	footprint.KindGSetting:    "Put back the setting",
	footprint.KindINIGroups:   "Put back the keys in",
	footprint.KindMarkedBlock: "Remove axiom's block from",
	footprint.KindFcitxConfig: "Put back the fcitx5 option",
	footprint.KindFcitxGroup:  "Put back the fcitx5 input methods",
	footprint.KindMimeapps:    "Put back the default app",
	footprint.KindRebuild:     "Rebuild once the files are out",
}

// rowAction describes a ledger row (status: present, changed or gone, ""
// for one a backfill would add).
func rowAction(r footprint.Row, status string) Action {
	a := Action{Step: "ledger", What: rowWhat[r.Kind], Path: r.Target}
	if r.Key != "" {
		a.Path += " [" + r.Key + "]"
	}
	var detail []string
	if status != "" {
		detail = append(detail, status)
	}
	if r.Owner != "" {
		detail = append(detail, r.Owner)
	}
	a.Detail = strings.Join(detail, ", ")
	switch {
	case r.System:
		a.Asks = FieldRestoreSystem
	case r.Inferred:
		a.Asks = FieldUndoInferred
	}
	return a
}

// ledgerRows are the rows the plan is about: the recorded ones with their
// status, and the ones the backfill would add. Nothing is created to read
// them: without a ledger file there are none recorded.
func (o Options) ledgerRows(ctx context.Context) (rows []footprint.RowStatus, candidates []footprint.Row) {
	if o.Ledger == nil {
		return nil, nil
	}
	recorded := false
	if _, err := os.Stat(filepath.Join(o.Dirs.State, "footprint.json")); err == nil {
		recorded = true
		rows = o.Ledger.List(ctx)
	}
	hooksDone, filesDone := recorded && o.Ledger.Backfilled(), recorded && o.Ledger.BackfilledFiles()
	if o.Inferred != nil && (!hooksDone || !filesDone) {
		have := map[string]bool{}
		for _, r := range rows {
			have[r.ID] = true
		}
		hooks, files := o.Inferred(ctx)
		var all []footprint.Row
		if !hooksDone {
			all = append(all, hooks...)
		}
		if !filesDone {
			all = append(all, files...)
		}
		for _, r := range all {
			r.ID = footprint.ID(r.Kind, r.Target, r.Key)
			if !have[r.ID] {
				r.Inferred = true
				candidates = append(candidates, r)
			}
		}
	}
	return rows, candidates
}

// Build says what an uninstall would do. It reads, and changes nothing.
func Build(ctx context.Context, o Options) (Plan, error) {
	o = o.withDefaults()
	p := Plan{Actions: []Action{}, Manual: []Manual{}, Backups: []string{}, Running: []string{}}
	p.Running = append(p.Running, o.running()...)
	p.Greeter = o.greeter()

	// 2. the managed configs
	for _, kind := range kinds {
		w := o.offline(kind)
		opts := w.Takeover()
		opts.Elsewhere = ""
		switch result, err := takeover.Check(ctx, opts); {
		case err != nil:
			o.Log.Warn("uninstall: checking the "+kind+" config", "err", err)
		case result == "ours":
			p.Actions = append(p.Actions, Action{Step: "managed", What: "Give back the config axiom manages", Path: w.ManagedPath()})
		case strings.HasPrefix(result, "blocked") && isOurs(w.ManagedPath(), opts.Header):
			p.Manual = append(p.Manual, Manual{File: w.ManagedPath(), Text: opts.Header,
				Reason: "axiom's managed config, which is a symlink or in a git repository, so axiom can't give it back: replace it with your own"})
		}
	}

	// 3. the ledger
	rows, candidates := o.ledgerRows(ctx)
	var all []footprint.Row
	covered := map[string]bool{}
	for _, r := range rows {
		p.Actions = append(p.Actions, rowAction(r.Row, r.Status))
		all = append(all, r.Row)
		p.count(r.Row)
		coverLines(covered, r.Row)
	}
	for _, r := range candidates {
		p.Actions = append(p.Actions, rowAction(r, ""))
		all = append(all, r)
		p.count(r)
		coverLines(covered, r)
	}

	// 4. the lines left
	files := o.lineFiles()
	for _, f := range files {
		data, err := os.ReadFile(f.Path)
		if err != nil {
			continue
		}
		s := scanFile(f.Kind, f.Path, data)
		lines := splitKeep(string(data))
		for _, i := range s.Remove {
			text := strings.TrimSpace(lines[i])
			if !covered[f.Path+"\x00"+text] {
				p.Actions = append(p.Actions, Action{Step: "lines", What: "Remove axiom's line from", Path: f.Path, Detail: text})
			}
		}
		p.Manual = append(p.Manual, s.Manual...)
	}

	// 5. what an unclean stop left
	p.Actions = append(p.Actions, o.sessionLeftovers()...)

	// 6. installed files
	for _, f := range o.installedFiles() {
		p.Actions = append(p.Actions, Action{Step: "files", What: "Delete", Path: f.Path})
	}

	// 7. the portal
	for _, a := range p.Actions {
		if isPortalPath(strings.SplitN(a.Path, " [", 2)[0]) {
			p.Counts.Portal = true
		}
	}
	if p.Counts.Portal {
		p.Actions = append(p.Actions, Action{Step: "portal", What: "Restart the screen-share portal (a share running ends)", Asks: FieldRestartPortal})
	}

	// 8. the keyring
	if o.Secrets.Count != nil {
		n, err := o.Secrets.Count(ctx)
		if err != nil {
			o.Log.Warn("uninstall: counting the keyring's items", "err", err)
		}
		p.Counts.Secrets = n
	}
	if p.Counts.Secrets > 0 {
		p.Actions = append(p.Actions, Action{Step: "secrets", What: "Remove axiom's items from the keyring", Detail: fmt.Sprint(p.Counts.Secrets), Asks: FieldKeepSecrets})
	}
	if isFile(filepath.Join(o.Dirs.State, "secrets.json")) {
		p.Actions = append(p.Actions, Action{Step: "secrets", What: "Delete the saved passwords file", Path: filepath.Join(o.Dirs.State, "secrets.json"), Asks: FieldKeepSecrets})
	}

	// 9. the folders
	for _, f := range o.folders() {
		if exists(f.Path) {
			p.Actions = append(p.Actions, Action{Step: "folders", What: f.What, Path: f.Path, Asks: f.Asks})
		}
	}

	// 10. the backups
	p.Backups = o.backups(all, files)
	return p, nil
}

func (p *Plan) count(r footprint.Row) {
	if r.System {
		p.Counts.System++
	} else if r.Inferred {
		p.Counts.Inferred++
	}
}

// coverLines notes the lines a hookup row took in, as file + text: the
// ledger takes them out, so the plan says them once.
func coverLines(covered map[string]bool, r footprint.Row) {
	if r.Kind != footprint.KindHookup || r.Hookup == nil {
		return
	}
	for _, in := range r.Hookup.Edit.Inserted {
		covered[r.Target+"\x00"+strings.TrimSpace(in.Text)] = true
	}
}

func isOurs(path, header string) bool {
	data, err := os.ReadFile(path)
	return err == nil && strings.HasPrefix(string(data), header)
}

func exists(path string) bool {
	_, err := os.Lstat(path)
	return err == nil
}

// run is one Run's state.
type run struct {
	Options
	a      Answers
	report Report
	// portal: a portal file or line changed
	portal bool
	// kept: rows the ledger still has after its undo
	kept int
}

func (r *run) done(step, what, path, detail string) {
	r.report.Done = append(r.report.Done, Item{Step: step, What: what, Path: path, Detail: detail})
}

func (r *run) left(step, what, path, detail string) {
	r.report.Left = append(r.report.Left, Item{Step: step, What: what, Path: path, Detail: detail})
}

// Run does the uninstall, in the order of the steps in the docs, as a has
// answered. It refuses while axiom runs (Stop quits it first). A step goes
// on when an item fails: the item is in Report.Left.
func Run(ctx context.Context, o Options, p Plan, a Answers) (Report, error) {
	o = o.withDefaults()
	// 0. nothing may run
	if running := o.running(); len(running) > 0 {
		return Report{}, runningError(running)
	}
	r := &run{Options: o, a: a}
	r.report = Report{Done: []Item{}, Left: []Item{}, Manual: []Manual{}, Backups: []string{}, Notes: []string{}, Greeter: p.Greeter}
	if r.report.Greeter == nil {
		r.report.Greeter = o.greeter()
	}
	// What the ledger holds now, before its undo takes the rows away
	rows, candidates := o.ledgerRows(ctx)
	var before []footprint.Row
	for _, x := range rows {
		before = append(before, x.Row)
	}
	before = append(before, candidates...)

	r.managed(ctx)
	r.ledger(ctx)
	r.lines()
	r.sessionLeft(ctx)
	r.files()
	r.restartPortal(ctx)
	r.secrets(ctx)
	r.folders()

	// 10. the backups, as the first look found them and as they are now
	files := o.lineFiles()
	r.report.Backups = o.backups(before, files)
	for _, f := range files {
		if data, err := os.ReadFile(f.Path); err == nil {
			r.report.Manual = append(r.report.Manual, scanFile(f.Kind, f.Path, data).Manual...)
		}
	}
	r.report.Manual = append(r.report.Manual, p.managedManual()...)
	return r.report, nil
}

// managedManual are the plan's notes about a managed config that couldn't
// be given back.
func (p Plan) managedManual() []Manual {
	var out []Manual
	for _, m := range p.Manual {
		if m.Line == 0 {
			out = append(out, m)
		}
	}
	return out
}

// 2. the managed configs
func (r *run) managed(ctx context.Context) {
	for _, kind := range kinds {
		w := r.offline(kind)
		opts := w.Takeover()
		opts.Logf = func(format string, args ...any) { r.Log.Info(fmt.Sprintf(format, args...), "part", "uninstall") }
		if result, err := takeover.Check(ctx, withoutElsewhere(opts)); err != nil || result != "ours" {
			continue
		}
		result, err := takeover.Release(ctx, opts)
		word, rest, _ := strings.Cut(result, ":")
		switch {
		case err != nil:
			r.left("managed", "Give back the config axiom manages", w.ManagedPath(), err.Error())
		case word == "blocked":
			r.left("managed", "Give back the config axiom manages", w.ManagedPath(), "it is a symlink or in a git repository: replace it with your own")
		default:
			r.done("managed", "Gave back the config axiom managed", w.ManagedPath(), strings.TrimPrefix(word+":"+rest, ":"))
		}
	}
}

func withoutElsewhere(o takeover.Options) takeover.Options {
	o.Elsewhere = ""
	return o
}

// 3. the ledger: the backfill of what an earlier axiom left, then the undo
func (r *run) ledger(ctx context.Context) {
	l := r.Ledger
	if l == nil {
		return
	}
	if r.Inferred != nil && (!l.Backfilled() || !l.BackfilledFiles()) {
		hooks, files := r.Inferred(ctx)
		if !l.BackfilledFiles() {
			if _, _, err := l.BackfillFiles(files); err != nil {
				r.left("ledger", "Look for files axiom made without a record", "", err.Error())
			}
		}
		if !l.Backfilled() {
			if _, _, err := l.Backfill(hooks); err != nil {
				r.left("ledger", "Look for changes axiom made without a record", "", err.Error())
			}
		}
	}
	ids := l.Select(footprint.UndoOptions{Force: r.a.UndoInferred, IncludeSystem: r.a.RestoreSystem})
	byID := map[string]footprint.Row{}
	for _, row := range l.Rows() {
		byID[row.ID] = row
	}
	asked := map[string]bool{}
	for _, res := range l.Undo(ctx, ids, footprint.UndoOptions{Force: r.a.UndoInferred, IncludeSystem: r.a.RestoreSystem}) {
		asked[res.ID] = true
		row := byID[res.ID]
		what := rowWhat[row.Kind]
		switch res.Outcome {
		case footprint.OutcomeDone, footprint.OutcomeGone:
			r.done("ledger", what, row.Target, res.Outcome)
			if isPortalPath(row.Target) {
				r.portal = true
			}
		default:
			r.left("ledger", what, row.Target, strings.TrimSpace(res.Outcome+" "+res.Detail))
		}
	}
	for _, row := range l.Rows() {
		r.kept++
		if !asked[row.ID] {
			r.left("ledger", rowWhat[row.Kind], row.Target, "kept, as you chose")
		}
	}
}

// 4. the lines install.sh and the cards added, and any from before the
// ledger
func (r *run) lines() {
	for _, f := range r.lineFiles() {
		removed, _, err := removeLines(f.Kind, f.Path)
		if err != nil {
			r.left("lines", "Remove axiom's lines from", f.Path, err.Error())
			continue
		}
		for _, text := range removed {
			r.done("lines", "Removed axiom's line from", f.Path, text)
		}
		if len(removed) > 0 && isPortalPath(f.Path) {
			r.portal = true
		}
	}
}

// 6. install.sh's files
func (r *run) files() {
	var dirs []string
	for _, f := range r.installedFiles() {
		if err := os.Remove(f.Path); err != nil {
			r.left("files", "Delete", f.Path, err.Error())
			continue
		}
		r.done("files", "Deleted", f.Path, "")
		if isPortalPath(f.Path) {
			r.portal = true
		}
		dirs = append(dirs, f.Dirs...)
	}
	// Those folders that are empty now (deepest first)
	slices.SortFunc(dirs, func(a, b string) int { return len(b) - len(a) })
	for _, d := range slices.Compact(dirs) {
		if os.Remove(d) == nil {
			r.done("files", "Removed the empty folder", d, "")
		}
	}
}

// 7. the portal
func (r *run) restartPortal(ctx context.Context) {
	if !r.portal {
		return
	}
	note := "Restart your session (or the screen-share portal) to finish: it still has the old screen-share setup."
	if !r.a.RestartPortal || r.DialBus == nil {
		r.report.Notes = append(r.report.Notes, note)
		return
	}
	bus, closeBus := r.DialBus(ctx)
	if closeBus != nil {
		defer closeBus()
	}
	if bus == nil {
		r.report.Notes = append(r.report.Notes, note)
		return
	}
	logf := func(format string, args ...any) { r.Log.Info(fmt.Sprintf(format, args...), "part", "uninstall") }
	if err := session.RestartPortal(ctx, bus, session.ScopeFrom(r.Getenv), r.Session.Systemctl, r.Session.Signal, nil, logf); err != nil {
		r.left("portal", "Restart the screen-share portal", "", err.Error())
		r.report.Notes = append(r.report.Notes, note)
		return
	}
	r.done("portal", "Restarted the screen-share portal", "", "")
}

// 8. the keyring
func (r *run) secrets(ctx context.Context) {
	if r.a.KeepSecrets || r.Secrets.ClearAll == nil {
		return
	}
	if err := r.Secrets.ClearAll(ctx); err != nil {
		r.left("secrets", "Remove axiom's items from the keyring", "", err.Error())
		return
	}
	r.done("secrets", "Removed axiom's items from the keyring", "", "")
}
