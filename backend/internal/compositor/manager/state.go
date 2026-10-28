package manager

import (
	"encoding/json"
	"os"
	"path/filepath"

	"github.com/axiom-shell/axiom/backend/internal/fsx"
)

// runtimeState is what the layer applied to the running compositor, kept
// across re-execs of the daemon (dev builds) in its runtime folder, as the
// shell kept it across its reloads (PersistentProperties): for the
// compositor instance it was written for only (a new session starts over).
type runtimeState struct {
	path string

	Instance string `json:"instance"`
	// AppliedMode: the mode apply() last set up, "" before the first, so a
	// load never gives anything back
	AppliedMode string `json:"appliedMode"`
	// LiveApplied: the live parts evaluated since the last reload
	// ("borders,gaps,input:keyboard"); LiveCursor the cursor last set
	LiveApplied string `json:"liveApplied"`
	LiveCursor  string `json:"liveCursor"`
	// SwayUnbind: the commands taking out what sway's runtime layer bound
	SwayUnbind []string `json:"swayUnbind"`
	// NiriWrapper: whether niri runs the detached wrapper
	NiriWrapper bool `json:"niriWrapper"`
}

func loadState(path, instance string) *runtimeState {
	s := &runtimeState{path: path, Instance: instance}
	data, err := os.ReadFile(path)
	if err != nil {
		return s
	}
	var saved runtimeState
	if json.Unmarshal(data, &saved) == nil && saved.Instance == instance {
		saved.path = path
		return &saved
	}
	return s
}

func (s *runtimeState) save() {
	if s.path == "" {
		return
	}
	data, err := json.Marshal(s)
	if err != nil {
		return
	}
	os.MkdirAll(filepath.Dir(s.path), 0o700)
	fsx.WriteFile(s.path, data, 0o600)
}

// approvals are the compositors whose config the user let axiom take over
// ($XDG_STATE_HOME/axiom/ui/takeover.json: { approved: [kind] }): state,
// not config, so an imported mode never counts as one
type approvals struct{ path string }

func (a approvals) list() []string {
	var v struct {
		Approved []string `json:"approved"`
	}
	data, err := os.ReadFile(a.path)
	if err == nil {
		json.Unmarshal(data, &v)
	}
	return v.Approved
}

func (a approvals) has(kind string) bool {
	for _, k := range a.list() {
		if k == kind {
			return true
		}
	}
	return false
}

func (a approvals) add(kind string) error {
	if a.has(kind) {
		return nil
	}
	return a.save(append(a.list(), kind))
}

// remove forgets kind's approval (its config was given back)
func (a approvals) remove(kind string) error {
	if !a.has(kind) {
		return nil
	}
	var kept []string
	for _, k := range a.list() {
		if k != kind {
			kept = append(kept, k)
		}
	}
	return a.save(kept)
}

func (a approvals) save(kinds []string) error {
	if kinds == nil {
		kinds = []string{}
	}
	data, _ := json.MarshalIndent(map[string][]string{"approved": kinds}, "", "  ")
	if err := os.MkdirAll(filepath.Dir(a.path), 0o755); err != nil {
		return err
	}
	return fsx.WriteFile(a.path, data, 0o644)
}
