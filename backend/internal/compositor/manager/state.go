package manager

import (
	"encoding/json"

	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
)

// runtimeState is what the layer applied to the running compositor, kept
// across re-execs of the daemon (dev builds) in its runtime folder, as the
// shell kept it across its reloads (PersistentProperties): for the
// compositor instance it was written for only (a new session starts over).
type runtimeState struct {
	path string
	logf func(string, ...any)

	Instance string `json:"instance"`
	// AppliedMode: the mode apply() last set up, "" before the first, so a
	// load never gives anything back
	AppliedMode string `json:"appliedMode"`
	// LiveApplied: the live parts evaluated since the last reload
	// ("borders,gaps,input:keyboard"); LiveCursor the cursor last set
	LiveApplied string `json:"liveApplied"`
	LiveCursor  string `json:"liveCursor"`
	// SwayUnbinds: the commands taking out what sway's runtime layer bound,
	// each with the key it frees. An old file's list (key "swayUnbind", plain
	// commands) is untrusted and not read: the binds an older image made stay
	// until sway reloads (bindsym overwrites anyway).
	SwayUnbinds []render.SwayUnbind `json:"swayUnbinds"`
	// SwayRules: the runtime for_window/no_focus lines sent since sway last
	// reloaded (sway can't take one back: removing one reloads)
	SwayRules []string `json:"swayRules"`
	// SwayPaused: what sway's pause did (swayWriter.pause), to give it back
	SwayPaused swayPaused `json:"swayPaused"`
	// NiriWrapper: whether niri runs the detached wrapper. A fresh daemon
	// (Options.Carried false) re-checks it: it loads the wrapper once
	NiriWrapper bool `json:"niriWrapper"`
	// RuntimeOn: the runtime layer is applied (Manager.runtimeOn), so a
	// carried image knows what a teardown takes out
	RuntimeOn bool `json:"runtimeOn"`
}

// swayPaused is a sway pause: the binds' lines unbound by it (bound again to
// restore) or the mode entered (left to restore), never both
type swayPaused struct {
	Restore []string `json:"restore"`
	Mode    string   `json:"mode"`
}

// loadState is the saved state when it is for instance, else a fresh one
// (a file that isn't JSON is logged through logf, when there is one).
func loadState(path, instance string, logf func(string, ...any)) *runtimeState {
	s := &runtimeState{path: path, Instance: instance}
	saved, r, err := fsx.ReadJSON[runtimeState](path, fsx.ReadOptions{})
	if r.Status == fsx.Corrupt && logf != nil {
		logf("%s isn't readable (%v): starting fresh", path, err)
	}
	if r.Status == fsx.OK && saved.Instance == instance {
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
	if err := fsx.WriteFileIn(s.path, data, 0o600); err != nil && s.logf != nil {
		s.logf("could not save %s: %v", s.path, err)
	}
}

// approvals are the compositors whose config the user let axiom take over
// ($XDG_STATE_HOME/axiom/ui/takeover.json: { approved: [kind] }): state,
// not config, so an imported mode never counts as one
type approvals struct {
	path string
	logf func(string, ...any)
}

func (a approvals) list() []string {
	type file struct {
		Approved []string `json:"approved"`
	}
	v, r, err := fsx.ReadJSON[file](a.path, fsx.ReadOptions{})
	if r.Status == fsx.Corrupt && a.logf != nil {
		a.logf("%s isn't readable (%v): no takeover is approved", a.path, err)
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
	return fsx.WriteFileIn(a.path, data, 0o600)
}
