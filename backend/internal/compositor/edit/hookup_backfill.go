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
	var rows []footprint.Row
	for _, r := range h.resolve(targets, profiles) {
		p, lines, err := h.plan(r)
		if err != nil || r.Path == "" || p.CopyOnly || !p.Done {
			continue
		}
		if row, ok := h.inferred(r, p, lines, owner); ok {
			rows = append(rows, row)
		}
	}
	return rows
}

func (h *Hookups) inferred(r hookup.Resolved, p hookup.Plan, lines []string, owner string) (footprint.Row, bool) {
	row := footprint.Row{Kind: footprint.KindHookup, Target: p.Resolved, Owner: owner}
	if r.Place == hookup.Copy {
		want, err := os.ReadFile(filepath.Join(h.opts.DataDir, r.From))
		have, err2 := os.ReadFile(p.Resolved)
		if err != nil || err2 != nil || string(want) != string(have) {
			return row, false
		}
		row.Hookup = &footprint.HookupRec{CopiedSHA256: sha(have)}
		return row, true
	}
	comment := cmp.Or(r.Comment, "#")
	mark := comment + " axiom: "
	rec := footprint.HookupRec{Edit: hookup.EditRecord{Comment: comment, Inserted: []hookup.Inserted{}, Commented: []string{}}}
	for _, line := range lines {
		if strings.HasPrefix(line, mark) {
			rec.Edit.Commented = append(rec.Edit.Commented, strings.TrimPrefix(line, mark))
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
	if backup != "" && !rec.Edit.Wrapped {
		blankInserted(&rec.Edit, lines, backupLines, r)
	}
	if len(rec.Edit.Commented) == 0 && backup == "" && len(rec.Edit.Inserted) == 0 {
		return row, false
	}
	if backup != "" {
		rec.Backup = backup
	}
	row.Hookup = &rec
	return row, true
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
