package daemon

import (
	"context"
	"fmt"
	"log/slog"
	"maps"
	"path/filepath"
	"slices"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/compositor/edit"
	"github.com/axiom-shell/axiom/backend/internal/cursortheme"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/footprint"
	"github.com/axiom-shell/axiom/backend/internal/hookup"
	"github.com/axiom-shell/axiom/backend/internal/inputmethod"
	"github.com/axiom-shell/axiom/backend/internal/mimeapps"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/theme"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// footprintPart: the ledger of what axiom changed outside its own folders
// (docs/dev/backend/footprint.md): listing it, undoing it, and the backfill
// of what an earlier axiom left. The recording points (themes, hookups,
// cursor, input method, default apps) get the ledger from d.footprint.
func (d *Daemon) footprintPart() part {
	return part{name: "footprint", methods: d.footprintMethods}
}

// NewLedger is the footprint ledger of the user's state folder, with every
// kind's undo registered: the daemon's, and the command line's (which works
// on the file directly, so it runs without a daemon). onChange is called
// after a row changes.
func NewLedger(getenv func(string) string, log *slog.Logger, onChange func()) *footprint.Ledger {
	return newLedger(getenv, log, onChange, gsettings)
}

func newLedger(getenv func(string) string, log *slog.Logger, onChange func(), gs func(context.Context, ...string) (string, error)) *footprint.Ledger {
	if log == nil {
		log = slog.New(slog.DiscardHandler)
	}
	l := footprint.New(footprint.Options{
		Dirs:      xdg.Resolve(getenv),
		GSettings: gs,
		Getenv:    getenv,
		Log:       func(format string, args ...any) { log.Info(fmt.Sprintf(format, args...), "part", "footprint") },
		OnChange:  onChange,
	})
	edit.RegisterUndo(l)
	theme.RegisterUndo(l)
	mimeapps.RegisterUndo(l)
	inputmethod.RegisterUndo(l, func(ctx context.Context) (*dbus.Conn, error) {
		addr, err := dbus.SessionAddress(getenv)
		if err != nil {
			return nil, err
		}
		return dbus.Dial(ctx, addr, dbus.Options{})
	})
	return l
}

// newFootprint makes the daemon's ledger; its changes are pushed. Before
// anything is served, the backfill that needs nothing of the shell runs
// (once per ledger): the files an earlier axiom's integrations left and the
// cursor's folders and setting. Run later, a write could take such a file
// for one that wasn't there, and an undo would put the old output back.
func (d *Daemon) newFootprint() {
	d.footprint = newLedger(d.opts.Getenv, d.opts.Log, func() {
		if d.server != nil {
			pushFootprintChanged.Send(d.server, struct{}{}, subscribedTo(topicFootprint))
		}
	}, d.gsettings())
	if d.footprint.BackfilledFiles() {
		return
	}
	in := theme.NewIntegrator(theme.IntegrateOptions{Getenv: d.opts.Getenv,
		Profiles: func(key string) []string { e, _ := d.integrationEntry(key); return e.Profiles }})
	rows := in.Existing()
	rows = append(rows, cursortheme.New(cursortheme.Options{Getenv: d.opts.Getenv, GSettings: d.gsettings()}).Existing(context.Background(), cursorOwner)...)
	if _, _, err := d.footprint.BackfillFiles(rows); err != nil {
		d.opts.Log.Warn("footprint: the backfill of files failed", "err", err)
	}
}

// FootprintListResult is the ledger's rows with their status.
type FootprintListResult struct {
	Rows []footprint.RowStatus `json:"rows"`
}

// FootprintUndoRequest names the rows to undo.
type FootprintUndoRequest struct {
	IDs []string `json:"ids"`
	footprint.UndoOptions
}

// FootprintUndoResult is how each undo went.
type FootprintUndoResult struct {
	Results []footprint.Result `json:"results"`
}

// FootprintBackfillRequest is, per ThemeIntegrations key (and the
// compositor's), the owner and the hookup targets to look for evidence of.
type FootprintBackfillRequest struct {
	Targets map[string]FootprintBackfillTargets `json:"targets"`
}

// FootprintBackfillTargets are one key's owner and hookup targets.
type FootprintBackfillTargets struct {
	Owner   string          `json:"owner"`
	Targets []hookup.Target `json:"targets"`
	// Profiles are the profiles.ini files of a PerProfile target
	Profiles []string `json:"profiles,omitempty"`
}

// FootprintBackfillResult says whether the backfill ran (once per ledger)
// and the rows it added.
type FootprintBackfillResult struct {
	Ran   bool     `json:"ran"`
	Added []string `json:"added"`
}

// cursorOwner is the setting asking for the cursor theme.
const cursorOwner = "Input.cursor.enabled"

func (d *Daemon) footprintMethods(reg *rpc.Registry) {
	rpc.Handle(reg, "footprint.list", func(ctx context.Context, c *rpc.Conn, _ struct{}) (FootprintListResult, error) {
		return FootprintListResult{Rows: d.footprint.List(ctx)}, nil
	})
	rpc.Handle(reg, "footprint.undo", func(ctx context.Context, c *rpc.Conn, p FootprintUndoRequest) (FootprintUndoResult, error) {
		if !fromShell(c) {
			return FootprintUndoResult{}, axerr.New(axerr.Refused, "only the shell undoes what axiom changed")
		}
		return FootprintUndoResult{Results: d.footprint.Undo(ctx, p.IDs, p.UndoOptions)}, nil
	})
	// The command line works on the ledger itself, and tells the daemon
	// after (the card refreshes)
	rpc.Handle(reg, "footprint.notify", func(ctx context.Context, c *rpc.Conn, _ struct{}) (struct{}, error) {
		pushFootprintChanged.Send(d.server, struct{}{}, subscribedTo(topicFootprint))
		return struct{}{}, nil
	})
	rpc.Handle(reg, "footprint.backfill", func(ctx context.Context, c *rpc.Conn, p FootprintBackfillRequest) (FootprintBackfillResult, error) {
		if !fromShell(c) {
			return FootprintBackfillResult{}, axerr.New(axerr.Refused, "only the shell asks for the backfill")
		}
		if d.footprint.Backfilled() {
			return FootprintBackfillResult{Added: []string{}}, nil
		}
		added, ran, err := d.footprint.Backfill(d.inferredRows(p))
		if added == nil {
			added = []string{}
		}
		return FootprintBackfillResult{Ran: ran, Added: added}, err
	})
}

// inferredRows are the hookup lines an earlier axiom left (with a comment of
// ours or a backup beside them) that the ledger has no row of: the targets
// come from the shell. The integrations' files and the cursor's folders and
// setting are found when the daemon starts (newFootprint). Not backfilled,
// as nothing tells them apart from the user's own: kdeglobals, fcitx5, ibus,
// default apps and color-scheme.
func (d *Daemon) inferredRows(p FootprintBackfillRequest) []footprint.Row {
	return inferredHookups(d.opts.Getenv, d.opts.Tree, p)
}

// inferredHookups is that, for the environment getenv names and the tree
// whose data/ the hookups copy from (the uninstall's too, without a daemon).
func inferredHookups(getenv func(string) string, treeDir string, p FootprintBackfillRequest) []footprint.Row {
	h := edit.NewHookups(edit.HookupOptions{Getenv: getenv, DataDir: filepath.Join(treeDir, "data")})
	var rows []footprint.Row
	for _, key := range slices.Sorted(maps.Keys(p.Targets)) {
		e := p.Targets[key]
		for _, row := range h.Inferred(e.Targets, e.Profiles, e.Owner) {
			// A file two keys have lines in is one row
			if i := slices.IndexFunc(rows, func(have footprint.Row) bool { return have.Kind == row.Kind && have.Target == row.Target }); i >= 0 {
				rows[i] = edit.MergeInferred(rows[i], row)
				continue
			}
			rows = append(rows, row)
		}
	}
	return rows
}

// gsettings is the gsettings runner: Options.GSettings, else the installed one.
func (d *Daemon) gsettings() func(ctx context.Context, args ...string) (string, error) {
	if d.opts.GSettings != nil {
		return d.opts.GSettings
	}
	return gsettings
}
