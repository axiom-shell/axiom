package uninstall

import (
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// TestAnswerTable is the whole decision table: flags, a tty or none, and
// what's asked. If the System answer changes, only this table changes.
func TestAnswerTable(t *testing.T) {
	t.Parallel()
	all := Counts{Inferred: 2, System: 3, Secrets: 4, Portal: true}
	none := Counts{}
	defaults := Answers{KeepConfig: true, KeepUserContent: true, KeepSecrets: true, UndoInferred: true, RestoreSystem: false, RestartPortal: true}
	with := func(f func(a *Answers)) Answers { a := defaults; f(&a); return a }
	for _, c := range []struct {
		name  string
		flags Flags
		c     Counts
		tty   bool
		say   map[string]bool // the user's answers, by field (others: the default)
		want  Answers
		asked []string
		err   bool
	}{
		{name: "no tty, no --yes", flags: Flags{}, c: all, err: true},
		{name: "no tty, --purge-all alone", flags: Flags{PurgeAll: true}, c: all, err: true},
		{name: "--yes takes the defaults", flags: Flags{Yes: true}, c: all, want: defaults},
		{name: "--yes with a tty asks nothing", flags: Flags{Yes: true}, c: all, tty: true, want: defaults},
		{name: "--yes --restore-system", flags: Flags{Yes: true, RestoreSystem: true}, c: all, want: with(func(a *Answers) { a.RestoreSystem = true })},
		{name: "--yes --purge-all keeps the system", flags: Flags{Yes: true, PurgeAll: true}, c: all,
			want: Answers{UndoInferred: true, RestartPortal: true}},
		{name: "--yes --purge-all --restore-system", flags: Flags{Yes: true, PurgeAll: true, RestoreSystem: true}, c: all,
			want: Answers{UndoInferred: true, RestoreSystem: true, RestartPortal: true}},
		{name: "--yes --no-portal-restart", flags: Flags{Yes: true, NoPortalRestart: true}, c: all, want: with(func(a *Answers) { a.RestartPortal = false })},
		{name: "a tty asks each, in order", flags: Flags{}, c: all, tty: true, want: defaults,
			asked: []string{FieldKeepConfig, FieldKeepUserContent, FieldKeepSecrets, FieldUndoInferred, FieldRestoreSystem, FieldRestartPortal}},
		{name: "a tty, nothing to decide", flags: Flags{}, c: none, tty: true, want: with(func(a *Answers) {}),
			asked: []string{FieldKeepConfig, FieldKeepUserContent}},
		{name: "the user changes some", flags: Flags{}, c: all, tty: true,
			say:   map[string]bool{FieldKeepConfig: false, FieldRestoreSystem: true, FieldRestartPortal: false},
			want:  Answers{KeepUserContent: true, KeepSecrets: true, UndoInferred: true, RestoreSystem: true},
			asked: []string{FieldKeepConfig, FieldKeepUserContent, FieldKeepSecrets, FieldUndoInferred, FieldRestoreSystem, FieldRestartPortal}},
		{name: "--purge-all still asks about the system", flags: Flags{PurgeAll: true}, c: all, tty: true,
			say:   map[string]bool{FieldRestoreSystem: true},
			want:  Answers{UndoInferred: true, RestoreSystem: true, RestartPortal: true},
			asked: []string{FieldRestoreSystem, FieldRestartPortal}},
		{name: "--restore-system isn't asked", flags: Flags{RestoreSystem: true, NoPortalRestart: true}, c: all, tty: true, want: with(func(a *Answers) { a.RestoreSystem = true; a.RestartPortal = false }),
			asked: []string{FieldKeepConfig, FieldKeepUserContent, FieldKeepSecrets, FieldUndoInferred}},
	} {
		t.Run(c.name, func(t *testing.T) {
			var asked []string
			got, err := Answer(c.flags, c.c, c.tty, func(q Question, def bool) bool {
				asked = append(asked, q.Field)
				if v, ok := c.say[q.Field]; ok {
					return v
				}
				return def
			})
			if c.err {
				if axerr.KindOf(err) != axerr.BadRequest {
					t.Fatalf("%v", err)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if got != c.want {
				t.Errorf("got  %+v\nwant %+v", got, c.want)
			}
			if len(asked) != len(c.asked) {
				t.Fatalf("asked %v, want %v", asked, c.asked)
			}
			for i := range asked {
				if asked[i] != c.asked[i] {
					t.Fatalf("asked %v, want %v", asked, c.asked)
				}
			}
		})
	}
}
