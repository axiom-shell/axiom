package theme

import (
	"context"
	"encoding/json"
	"errors"
	"io/fs"
	"os"

	"github.com/axiom-shell/axiom/backend/internal/footprint"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/theme/integrations"
)

// RegisterUndo makes l take ini-groups rows out (kdeglobals): per key, each
// key axiom wrote goes back to what it held while it's still as axiom
// wrote it, and a key the user changed since is left (the outcome is then
// "changed", though every other key was put back). A group axiom created
// goes once it holds no key.
func RegisterUndo(l *footprint.Ledger) {
	l.Register(footprint.KindINIGroups, undoINIGroups, checkINIGroups)
}

func keysOf(r footprint.Row) (prior, wrote integrations.Keys) {
	_ = json.Unmarshal(r.Prior, &prior)
	_ = json.Unmarshal(r.Wrote, &wrote)
	return prior, wrote
}

func undoINIGroups(_ context.Context, r *footprint.Row) (string, string) {
	data, err := os.ReadFile(r.Target)
	if errors.Is(err, fs.ErrNotExist) {
		return footprint.OutcomeGone, ""
	}
	if err != nil {
		return footprint.OutcomeFailed, err.Error()
	}
	prior, wrote := keysOf(*r)
	out, changed := integrations.RestoreKeys(data, prior, wrote)
	mode := fs.FileMode(0o644)
	if info, err := os.Stat(r.Target); err == nil {
		mode = info.Mode().Perm()
	}
	if string(out) != string(data) {
		if err := fsx.WriteFile(r.Target, out, mode); err != nil {
			return footprint.OutcomeFailed, err.Error()
		}
	}
	if len(changed) > 0 {
		// What's left to undo is the keys that changed
		r.Prior, r.Wrote = footprint.Raw(integrations.OnlyKeys(prior, changed)), footprint.Raw(integrations.OnlyKeys(wrote, changed))
		return footprint.OutcomeChanged, "changed since, left: " + joinKeys(changed)
	}
	return footprint.OutcomeDone, ""
}

func joinKeys(keys []string) string {
	out := ""
	for i, k := range keys {
		if i > 0 {
			out += ", "
		}
		out += k
	}
	return out
}

func checkINIGroups(_ context.Context, r footprint.Row) string {
	data, err := os.ReadFile(r.Target)
	if err != nil {
		return footprint.StatusGone
	}
	_, wrote := keysOf(r)
	if len(integrations.KeysAre(data, wrote)) > 0 {
		return footprint.StatusChanged
	}
	return footprint.StatusPresent
}
