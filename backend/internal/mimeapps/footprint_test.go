package mimeapps

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/footprint"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

func TestSetDefaultRecordsPriorAndUndoesExactKeys(t *testing.T) {
	t.Parallel()
	tr := newTree(t)
	tr.standard()
	user := filepath.Join(tr.config, "mimeapps.list")
	before := "# mine\n[Default Applications]\nx-scheme-handler/http=chromium.desktop;other.desktop;\ntext/plain=nvim.desktop;\n"
	tr.write(user, before)
	state := filepath.Join(filepath.Dir(tr.config), "state")
	l := footprint.New(footprint.Options{Dirs: xdg.Resolve(func(k string) string {
		return map[string]string{"HOME": tr.config, "XDG_STATE_HOME": state, "XDG_CONFIG_HOME": filepath.Join(state, "c"), "XDG_CACHE_HOME": filepath.Join(state, "ca")}[k]
	})})
	RegisterUndo(l)
	a := Load(Options{ConfigHome: tr.config, ConfigDirs: []string{tr.sysConfig}, DataHome: tr.data, DataDirs: []string{tr.sysData}, Ledger: l})
	if err := a.SetDefault("browser", "firefox.desktop"); err != nil {
		t.Fatal(err)
	}
	rows := map[string]footprint.Row{}
	for _, r := range l.Rows() {
		rows[r.Key] = r
		if !r.System || r.Kind != footprint.KindMimeapps || r.Target != user || r.State != footprint.StateApplied {
			t.Errorf("%+v", r)
		}
	}
	if len(rows) != 3 || string(rows["Default Applications/x-scheme-handler/http"].Prior) != `{"value":"chromium.desktop;other.desktop;"}` ||
		string(rows["Default Applications/text/html"].Prior) != `{"absent":true}` {
		t.Fatalf("%v", rows)
	}
	// The user changes one line since: it stays, the others go back
	after, _ := os.ReadFile(user)
	os.WriteFile(user, []byte(strings.Replace(string(after), "x-scheme-handler/https=firefox.desktop;", "x-scheme-handler/https=mine.desktop;", 1)), 0o644)
	res := l.Undo(context.Background(), l.Select(footprint.UndoOptions{IncludeSystem: true}), footprint.UndoOptions{})
	outcomes := map[string]string{}
	for _, r := range res {
		outcomes[strings.TrimPrefix(r.ID, "mimeapps:"+user+":Default Applications/")] = r.Outcome
	}
	if outcomes["x-scheme-handler/https"] != footprint.OutcomeChanged || outcomes["text/html"] != footprint.OutcomeDone || outcomes["x-scheme-handler/http"] != footprint.OutcomeDone {
		t.Errorf("%v", outcomes)
	}
	if got, _ := os.ReadFile(user); string(got) != before+"x-scheme-handler/https=mine.desktop;\n" {
		t.Errorf("after undo:\n%s", got)
	}
	if len(l.Rows()) != 1 {
		t.Errorf("rows left: %+v", l.Rows())
	}
}

func TestSetDefaultUndoIsExact(t *testing.T) {
	t.Parallel()
	tr := newTree(t)
	tr.standard()
	user := filepath.Join(tr.config, "mimeapps.list")
	before := "# mine\n[Added Associations]\ntext/plain=nvim.desktop;\n\n[Default Applications]\nx-scheme-handler/http=chromium.desktop;other.desktop;\ntext/plain=nvim.desktop;\n"
	tr.write(user, before)
	state := filepath.Join(filepath.Dir(tr.config), "state")
	l := footprint.New(footprint.Options{Dirs: xdg.Resolve(func(k string) string {
		return map[string]string{"HOME": tr.config, "XDG_STATE_HOME": state, "XDG_CONFIG_HOME": filepath.Join(state, "c"), "XDG_CACHE_HOME": filepath.Join(state, "ca")}[k]
	})})
	RegisterUndo(l)
	a := Load(Options{ConfigHome: tr.config, ConfigDirs: []string{tr.sysConfig}, DataHome: tr.data, DataDirs: []string{tr.sysData}, Ledger: l})
	if err := a.SetDefault("browser", "firefox.desktop"); err != nil {
		t.Fatal(err)
	}
	if err := a.SetDefault("terminal", "kitty.desktop"); err != nil {
		t.Fatal(err)
	}
	res := l.Undo(context.Background(), l.Select(footprint.UndoOptions{IncludeSystem: true}), footprint.UndoOptions{})
	for _, r := range res {
		if r.Outcome != footprint.OutcomeDone {
			t.Errorf("%+v", r)
		}
	}
	if got, _ := os.ReadFile(user); string(got) != before {
		t.Errorf("after undo:\n%s\nwant:\n%s", got, before)
	}
	if _, err := os.Stat(filepath.Join(tr.config, "xdg-terminals.list")); err == nil {
		t.Error("the terminal list axiom made stayed")
	}
}
