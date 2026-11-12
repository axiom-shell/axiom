package edit

import (
	"cmp"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/footprint"
	"github.com/axiom-shell/axiom/backend/internal/hookup"
)

// Inferred are hookup rows for the edits an earlier axiom made, found
// where there's evidence: each target that's done, whose file has a line
// "<comment> axiom: …", a sibling .axiom-bak-<stamp>, or a line equal to
// the target's text. Its EditRecord is made from what's found: the target's
// lines in the file are the inserted ones (sharpened to those the newest
// backup lacks), the prefixed lines the commented ones. The ledger's
// backfill marks them inferred. A copy target that's the file it would copy
// is recorded with its checksum.
func (h *Hookups) Inferred(targets []hookup.Target, profiles []string, owner string) []footprint.Row {
	// What a row was found from, to finish it once its file's targets are in
	type found struct {
		r             hookup.Resolved
		lines, backup []string
	}
	var rows []footprint.Row
	var from []found
	for _, r := range h.resolve(targets, profiles) {
		p, lines, err := h.plan(r)
		if err != nil || r.Path == "" || p.CopyOnly || !p.Done {
			continue
		}
		row, backupLines, ok := h.inferred(r, p, lines, owner)
		if !ok {
			continue
		}
		// Targets on one file (the compositor's include and autostart lines)
		// are one row: their lines together
		if i := slices.IndexFunc(rows, func(have footprint.Row) bool { return have.Kind == row.Kind && have.Target == row.Target }); i >= 0 {
			rows[i] = MergeInferred(rows[i], row)
			if backupLines != nil {
				from[i] = found{r, lines, backupLines}
			}
			continue
		}
		rows = append(rows, row)
		from = append(from, found{r, lines, backupLines})
	}
	// The blank lines an edit sets before its text, once every target's
	// lines are known (the other targets' are not the backup's)
	for i, f := range from {
		if f.backup != nil && rows[i].Hookup.CopiedSHA256 == "" {
			blankInserted(&rows[i].Hookup.Edit, f.lines, f.backup, f.r)
		}
	}
	return rows
}

// MergeInferred is two rows of one file as one: the union of their
// inserted and commented lines, each once.
func MergeInferred(a, b footprint.Row) footprint.Row {
	if a.Hookup == nil || b.Hookup == nil {
		if a.Hookup == nil {
			return b
		}
		return a
	}
	out := a
	rec := *a.Hookup
	for _, in := range b.Hookup.Edit.Inserted {
		if !slices.Contains(rec.Edit.Inserted, in) {
			rec.Edit.Inserted = append(slices.Clone(rec.Edit.Inserted), in)
		}
	}
	for _, c := range b.Hookup.Edit.Commented {
		if !slices.Contains(rec.Edit.Commented, c) {
			rec.Edit.Commented = append(slices.Clone(rec.Edit.Commented), c)
		}
	}
	slices.SortFunc(rec.Edit.Inserted, func(x, y hookup.Inserted) int { return x.Index - y.Index })
	if rec.Edit.CreatedSection == "" {
		rec.Edit.CreatedSection = b.Hookup.Edit.CreatedSection
	}
	if rec.Backup == "" {
		rec.Backup = b.Hookup.Backup
	}
	if rec.CopiedSHA256 == "" {
		rec.CopiedSHA256 = b.Hookup.CopiedSHA256
	}
	out.Hookup = &rec
	return out
}

func (h *Hookups) inferred(r hookup.Resolved, p hookup.Plan, lines []string, owner string) (footprint.Row, []string, bool) {
	row := footprint.Row{Kind: footprint.KindHookup, Target: p.Resolved, Owner: owner}
	if r.Place == hookup.Copy {
		want, err := os.ReadFile(filepath.Join(h.opts.DataDir, r.From))
		have, err2 := os.ReadFile(p.Resolved)
		if err != nil || err2 != nil || string(want) != string(have) {
			return row, nil, false
		}
		row.Hookup = &footprint.HookupRec{CopiedSHA256: sha(have)}
		return row, nil, true
	}
	comment := cmp.Or(r.Comment, "#")
	rec := footprint.HookupRec{Edit: hookup.EditRecord{Comment: comment, Inserted: []hookup.Inserted{}, Commented: []string{}}}
	for _, line := range lines {
		// Only a line commenting out what this target's text sets is axiom's
		if orig, ok := hookup.Commented(r, line); ok {
			rec.Edit.Commented = append(rec.Edit.Commented, orig)
		}
	}
	var text []string
	for _, t := range strings.Split(r.Text, "\n") {
		if t = strings.TrimSpace(t); t != "" {
			text = append(text, t)
		}
	}
	backups, _ := filepath.Glob(p.Path + ".axiom-bak-*")
	if len(backups) == 0 && p.Resolved != p.Path {
		backups, _ = filepath.Glob(p.Resolved + ".axiom-bak-*")
	}
	slices.Sort(backups)
	var backup string
	var backupLines []string
	if len(backups) > 0 {
		backup = backups[len(backups)-1]
		if info, err := os.Lstat(backup); err == nil && info.Mode()&fs.ModeSymlink != 0 {
			// A wrapped link: the backup is the link it replaced
			if to, err := os.Readlink(backup); err == nil && len(lines) > 0 {
				rec.LinkTarget, rec.Edit.Wrapped, rec.Edit.WrapLine = to, true, lines[0]
				row.Target = p.Path
			}
		} else if data, err := os.ReadFile(backup); err == nil {
			backupLines = hookup.Lines(string(data))
		}
	}
	for i, line := range lines {
		if rec.Edit.Wrapped && i == 0 || !slices.Contains(text, strings.TrimSpace(line)) {
			continue
		}
		// With the backup, only what it lacks is the edit's
		if backup != "" && !rec.Edit.Wrapped && slices.ContainsFunc(backupLines, func(b string) bool { return strings.TrimSpace(b) == strings.TrimSpace(line) }) {
			continue
		}
		rec.Edit.Inserted = append(rec.Edit.Inserted, hookup.Inserted{Text: line, Index: i})
	}
	if len(rec.Edit.Commented) == 0 && backup == "" && len(rec.Edit.Inserted) == 0 {
		return row, nil, false
	}
	if backup != "" {
		rec.Backup = backup
	}
	row.Hookup = &rec
	if backup == "" || rec.Edit.Wrapped {
		backupLines = nil
	}
	return row, backupLines, true
}

// blankInserted adds the blank lines an edit set before its text (and a new
// section's header) when the file is the backup, with only those and the
// text added: the lines left once the inserted ones go are the backup's
// lines, then blank ones (and a header).
func blankInserted(rec *hookup.EditRecord, lines, backup []string, r hookup.Resolved) {
	skip := map[int]bool{}
	for _, in := range rec.Inserted {
		skip[in.Index] = true
	}
	var rest []int
	for i := range lines {
		if !skip[i] {
			rest = append(rest, i)
		}
	}
	// The commented lines are the backup's own, as they were
	orig := func(i int) string {
		return strings.TrimPrefix(lines[i], rec.Comment+" axiom: ")
	}
	if len(rest) < len(backup) {
		return
	}
	for k, b := range backup {
		if lines[rest[k]] != b && orig(rest[k]) != b {
			return
		}
	}
	extra := rest[len(backup):]
	header := "[" + r.Section + "]"
	for n, i := range extra {
		switch {
		case strings.TrimSpace(lines[i]) == "":
		case r.Place == hookup.Section && lines[i] == header && n == len(extra)-1:
			rec.CreatedSection = r.Section
		default:
			return
		}
	}
	for _, i := range extra {
		if strings.TrimSpace(lines[i]) == "" {
			rec.Inserted = append(rec.Inserted, hookup.Inserted{Text: "", Index: i})
		}
	}
	slices.SortFunc(rec.Inserted, func(a, b hookup.Inserted) int { return a.Index - b.Index })
}
