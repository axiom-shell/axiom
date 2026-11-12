package uninstall

import "github.com/axiom-shell/axiom/backend/internal/axerr"

// Answers are what the user decides: what to keep, what to undo that
// axiom can't be sure of, and whether to restart the portal. The defaults
// keep everything the user could want back.
type Answers struct {
	// KeepConfig: config.json and the saved setups ($XDG_CONFIG_HOME/axiom)
	KeepConfig bool `json:"keepConfig"`
	// KeepUserContent: wallpapers, calendars ($XDG_DATA_HOME/axiom)
	KeepUserContent bool `json:"keepUserContent"`
	// KeepSecrets: the keyring's items (and secrets.json)
	KeepSecrets bool `json:"keepSecrets"`
	// UndoInferred: undo changes found without a record of making them
	UndoInferred bool `json:"undoInferred"`
	// RestoreSystem: put back the default apps and input method engines
	RestoreSystem bool `json:"restoreSystem"`
	// RestartPortal: restart the screen-share portal after changing it
	RestartPortal bool `json:"restartPortal"`
}

// Counts are what the plan has of each kind a question is about.
type Counts struct {
	Inferred int `json:"inferred"`
	System   int `json:"system"`
	Secrets  int `json:"secrets"`
	// Portal: a portal file or line is among the changes
	Portal bool `json:"portal"`
}

// Flags are what the command line says before any question.
type Flags struct {
	// Yes takes the defaults without asking
	Yes bool
	// PurgeAll gets rid of everything: config, content, secrets, and the
	// changes found without a record (it still asks about the System rows)
	PurgeAll bool
	// RestoreSystem puts the system's own choices back without asking
	RestoreSystem bool
	// NoPortalRestart: never restart the portal
	NoPortalRestart bool
}

// The fields a Question can be about (Answers' names).
const (
	FieldKeepConfig      = "KeepConfig"
	FieldKeepUserContent = "KeepUserContent"
	FieldKeepSecrets     = "KeepSecrets"
	FieldUndoInferred    = "UndoInferred"
	FieldRestoreSystem   = "RestoreSystem"
	FieldRestartPortal   = "RestartPortal"
)

// Question is one thing asked: the Answers field it decides, and how many
// things it's about (the N of its text).
type Question struct {
	Field string
	N     int
}

// Answer is the whole decision table: the answers from the flags, a tty
// and the answers to ask for. Without a tty only --yes goes on (an unasked
// question has its default). With --yes every default is taken, and the
// flags still say what they say. ask is called, in this order, for each
// question that remains: KeepConfig, KeepUserContent, KeepSecrets (only
// with secrets saved), UndoInferred (only with some found), RestoreSystem
// (only with some recorded, and not already by --restore-system) and
// RestartPortal (only when a portal file changed, and not --no-portal-restart).
func Answer(f Flags, c Counts, tty bool, ask func(q Question, def bool) bool) (Answers, error) {
	if !tty && !f.Yes {
		return Answers{}, axerr.New(axerr.BadRequest, "run with --yes to take the defaults, or --dry-run to see the plan")
	}
	interactive := tty && !f.Yes
	// ask only where there's something to decide and the flags left it open
	choose := func(q Question, def bool) bool {
		if !interactive || ask == nil {
			return def
		}
		return ask(q, def)
	}
	a := Answers{KeepConfig: true, KeepUserContent: true, KeepSecrets: true, UndoInferred: true, RestartPortal: true}
	if f.PurgeAll {
		a.KeepConfig, a.KeepUserContent, a.KeepSecrets, a.UndoInferred = false, false, false, true
	} else {
		a.KeepConfig = choose(Question{Field: FieldKeepConfig}, true)
		a.KeepUserContent = choose(Question{Field: FieldKeepUserContent}, true)
		if c.Secrets > 0 {
			a.KeepSecrets = choose(Question{Field: FieldKeepSecrets, N: c.Secrets}, true)
		}
		if c.Inferred > 0 {
			a.UndoInferred = choose(Question{Field: FieldUndoInferred, N: c.Inferred}, true)
		}
	}
	switch {
	case f.RestoreSystem:
		a.RestoreSystem = true
	case c.System > 0:
		a.RestoreSystem = choose(Question{Field: FieldRestoreSystem, N: c.System}, false)
	}
	switch {
	case f.NoPortalRestart:
		a.RestartPortal = false
	case c.Portal:
		a.RestartPortal = choose(Question{Field: FieldRestartPortal}, true)
	}
	return a, nil
}
