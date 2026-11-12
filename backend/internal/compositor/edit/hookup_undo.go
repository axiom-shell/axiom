package edit

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io/fs"
	"os"
	"slices"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/footprint"
	"github.com/axiom-shell/axiom/backend/internal/hookup"
)

// RegisterUndo makes l take hookup rows out: only the lines an Edit
// recorded, a created file deleted when nothing else is left in it, a
// wrapped link made a link again, a copied file deleted when it's still the
// copy. The .axiom-bak backups are listed in the row and never touched,
// and never put back.
func RegisterUndo(l *footprint.Ledger) {
	l.Register(footprint.KindHookup, undoHookup, checkHookup)
}

func sha(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

// editedLines is the file's lines (nil, false when it isn't a file).
func editedLines(path string) ([]string, os.FileMode, bool, error) {
	info, err := os.Stat(path)
	if errors.Is(err, fs.ErrNotExist) || err == nil && !info.Mode().IsRegular() {
		return nil, 0, false, nil
	}
	if err != nil {
		return nil, 0, false, err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, 0, false, err
	}
	return hookup.Lines(string(data)), info.Mode().Perm(), true, nil
}

func undoHookup(_ context.Context, row *footprint.Row) (string, string) {
	rec := row.Hookup
	if rec == nil {
		return footprint.OutcomeFailed, "no record of the edit"
	}
	path := row.Target
	if rec.CopiedSHA256 != "" {
		data, err := os.ReadFile(path)
		switch {
		case errors.Is(err, fs.ErrNotExist):
			return footprint.OutcomeGone, ""
		case err != nil:
			return footprint.OutcomeFailed, err.Error()
		case sha(data) != rec.CopiedSHA256:
			return footprint.OutcomeChanged, "the copy was changed: left as it is"
		}
		if err := os.Remove(path); err != nil {
			return footprint.OutcomeFailed, err.Error()
		}
		return footprint.OutcomeDone, ""
	}
	if info, err := os.Lstat(path); rec.Edit.Wrapped && err == nil && info.Mode()&fs.ModeSymlink != 0 {
		return footprint.OutcomeGone, "it's a link again"
	}
	lines, mode, ok, err := editedLines(path)
	if err != nil {
		return footprint.OutcomeFailed, err.Error()
	}
	if !ok {
		return footprint.OutcomeGone, ""
	}
	out, _ := hookup.Undo(lines, rec.Edit)
	switch {
	case rec.Edit.Wrapped:
		// Back to the link when only the wrap is left of it
		if len(out) != 1 || out[0] != rec.Edit.WrapLine {
			return footprint.OutcomeChanged, "the file was changed: left as it is"
		}
		return restoreLink(path, rec.LinkTarget)
	case rec.CreatedFile && strings.TrimSpace(strings.Join(out, "")) == "":
		if err := os.Remove(path); err != nil {
			return footprint.OutcomeFailed, err.Error()
		}
		return footprint.OutcomeDone, ""
	case slices.Equal(out, lines):
		return footprint.OutcomeGone, ""
	}
	text := ""
	if len(out) > 0 {
		text = hookup.Text(out)
		if rec.NoFinalNewline {
			text = strings.TrimSuffix(text, "\n")
		}
	}
	if err := WriteMode(path, []byte(text), mode); err != nil {
		return footprint.OutcomeFailed, err.Error()
	}
	return footprint.OutcomeDone, ""
}

// restoreLink replaces the file at path with a link to target.
func restoreLink(path, target string) (string, string) {
	tmp := path + ".axiom-undo"
	_ = os.Remove(tmp)
	if err := os.Symlink(target, tmp); err != nil {
		return footprint.OutcomeFailed, err.Error()
	}
	if err := os.Rename(tmp, path); err != nil {
		_ = os.Remove(tmp)
		return footprint.OutcomeFailed, err.Error()
	}
	return footprint.OutcomeDone, ""
}

func checkHookup(_ context.Context, row footprint.Row) string {
	rec := row.Hookup
	if rec == nil {
		return footprint.StatusPresent
	}
	if rec.CopiedSHA256 != "" {
		data, err := os.ReadFile(row.Target)
		switch {
		case err != nil:
			return footprint.StatusGone
		case sha(data) != rec.CopiedSHA256:
			return footprint.StatusChanged
		}
		return footprint.StatusPresent
	}
	lines, _, ok, err := editedLines(row.Target)
	if err != nil || !ok {
		return footprint.StatusGone
	}
	for _, in := range rec.Edit.Inserted {
		if in.Text != "" && slices.Contains(lines, in.Text) {
			return footprint.StatusPresent
		}
	}
	for _, orig := range rec.Edit.Commented {
		if slices.Contains(lines, rec.Edit.Comment+" axiom: "+orig) {
			return footprint.StatusPresent
		}
	}
	return footprint.StatusGone
}
