package mimeapps

import (
	"context"
	"errors"
	"io/fs"
	"os"
	"slices"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/footprint"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
)

// terminalKey is the Key of an xdg-terminals.list row (the whole list is
// its value; the others are one type's line, "<group>/<mime>").
const terminalKey = "terminal"

// listPrior is what a list held before axiom set a default.
type listPrior struct {
	Absent      bool     `json:"absent,omitempty"` // the type had no line (the terminal list: no file)
	Value       string   `json:"value,omitempty"`
	GroupAbsent bool     `json:"groupAbsent,omitempty"` // the group wasn't there
	FileAbsent  bool     `json:"fileAbsent,omitempty"`  // the file wasn't there
	Lines       []string `json:"lines,omitempty"`       // the terminal list's lines
}

// listWrote is what axiom set: a type's value, the terminal list's lines.
type listWrote struct {
	Value string   `json:"value,omitempty"`
	Lines []string `json:"lines,omitempty"`
}

// RegisterUndo makes l undo default apps: a type's line is set back to what
// it held (or removed, with the group and file axiom made once nothing is
// in them) only while it's still what axiom wrote; the terminal list the
// same as a whole.
func RegisterUndo(l *footprint.Ledger) {
	l.Register(footprint.KindMimeapps, undo, check)
}

func linesOf(text string) []string {
	text = strings.TrimRight(text, "\n")
	if text == "" {
		return nil
	}
	return strings.Split(text, "\n")
}

func check(_ context.Context, r footprint.Row) string {
	data, err := os.ReadFile(r.Target)
	if err != nil {
		return footprint.StatusGone
	}
	if r.Key == terminalKey {
		var w listWrote
		var p listPrior
		_ = jsonUnmarshal(r.Wrote, &w)
		_ = jsonUnmarshal(r.Prior, &p)
		switch {
		case r.Wrote == nil && slices.Equal(linesOf(string(data)), p.Lines):
			return footprint.StatusGone
		case r.Wrote == nil, !slices.Equal(linesOf(string(data)), w.Lines):
			return footprint.StatusChanged
		}
		return footprint.StatusPresent
	}
	group, mime, _ := strings.Cut(r.Key, "/")
	var w listWrote
	_ = jsonUnmarshal(r.Wrote, &w)
	var p listPrior
	_ = jsonUnmarshal(r.Prior, &p)
	v, ok := listValue(string(data), group, mime)
	switch {
	case !ok:
		return footprint.StatusGone
	case r.Wrote == nil && !p.Absent && v == p.Value:
		return footprint.StatusGone
	case r.Wrote == nil, v != w.Value:
		return footprint.StatusChanged
	}
	return footprint.StatusPresent
}

func undo(_ context.Context, r *footprint.Row) (string, string) {
	data, err := os.ReadFile(r.Target)
	if errors.Is(err, fs.ErrNotExist) {
		return footprint.OutcomeGone, ""
	}
	if err != nil {
		return footprint.OutcomeFailed, err.Error()
	}
	var prior listPrior
	var wrote listWrote
	_ = jsonUnmarshal(r.Prior, &prior)
	_ = jsonUnmarshal(r.Wrote, &wrote)
	text := string(data)
	var out string
	if r.Key == terminalKey {
		// A row with nothing written yet is compared with what was there
		if r.Wrote == nil {
			if slices.Equal(linesOf(text), prior.Lines) {
				return footprint.OutcomeGone, ""
			}
			return footprint.OutcomeChanged, "the list differs from what was there: left as it is"
		}
		if !slices.Equal(linesOf(text), wrote.Lines) {
			return footprint.OutcomeChanged, "the list was changed since: left as it is"
		}
		if prior.Absent {
			if err := os.Remove(r.Target); err != nil {
				return footprint.OutcomeFailed, err.Error()
			}
			return footprint.OutcomeDone, ""
		}
		if len(prior.Lines) > 0 {
			out = strings.Join(prior.Lines, "\n") + "\n"
		}
	} else {
		group, mime, _ := strings.Cut(r.Key, "/")
		v, ok := listValue(text, group, mime)
		if !ok {
			return footprint.OutcomeGone, ""
		}
		if r.Wrote == nil {
			if !prior.Absent && v == prior.Value {
				return footprint.OutcomeGone, ""
			}
			return footprint.OutcomeChanged, "the line differs from what was there: left as it is"
		}
		if v != wrote.Value {
			return footprint.OutcomeChanged, "the line was changed since: left as it is"
		}
		var back *string
		if !prior.Absent {
			back = &prior.Value
		}
		out = setListValue(text, group, mime, back, prior.GroupAbsent)
		if prior.FileAbsent && strings.TrimSpace(out) == "" {
			if err := os.Remove(r.Target); err != nil {
				return footprint.OutcomeFailed, err.Error()
			}
			return footprint.OutcomeDone, ""
		}
	}
	mode := fs.FileMode(0o644)
	if info, err := os.Stat(r.Target); err == nil {
		mode = info.Mode().Perm()
	}
	if err := fsx.WriteFile(r.Target, []byte(out), mode); err != nil {
		return footprint.OutcomeFailed, err.Error()
	}
	return footprint.OutcomeDone, ""
}
