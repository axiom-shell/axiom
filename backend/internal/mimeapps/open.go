package mimeapps

import (
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// Overrides are the commands the config sets in place of a role's
// default app (Apps.commands.<role id>), by role id; "" or missing: the
// default app.
type Overrides map[string]string

// A URL's scheme ("https:", "mailto:"), not a Windows-style path
var schemePattern = regexp.MustCompile(`^([a-zA-Z][a-zA-Z0-9+.-]+):`)

// Command is the argv that opens target with args:
//   - a role id ("browser", "terminal", "fileManager", …): its app, given
//     args (the URLs, paths, or for the terminal the command to run in it)
//   - a URL: its scheme's app (http and https the browser's)
//   - a path: its type's app (a folder the file manager's)
//
// An override for the role (Overrides) runs instead of its app, args
// after its words (the terminal's command after -e). With no app for a
// URL or file of its own, its parent types' are tried, nearest first
// (Globs.Lineage: a script no app claims opens as text/plain, so in the
// text editor role's app); with none, xdg-open gets it, when installed.
func (a *Apps) Command(target string, args []string, ov Overrides) ([]string, error) {
	if r, ok := RoleOf(target); ok {
		return a.roleCommand(r, args, ov)
	}
	withTarget := append([]string{target}, args...)
	mime := a.typeOf(target)
	for _, names := range a.lineage(mime) {
		for _, t := range names {
			if r, ok := roleOfType(t); ok {
				// A web or mail link follows its role's app (https as
				// http), as does a file of the role's main type, and any
				// of the role's types when the role has a command set
				if ov[r.ID] != "" || t == r.Types[0] || strings.HasPrefix(t, "x-scheme-handler/") {
					return a.roleCommand(r, withTarget, ov)
				}
			}
		}
		if id := a.ownDefault(names); id != "" {
			return a.entryCommand(a.entries[id], withTarget, ov)
		}
	}
	if _, err := exec.LookPath("xdg-open"); err == nil {
		return []string{"xdg-open", target}, nil
	}
	return nil, axerr.New(axerr.NotFound, "nothing opens %s", target)
}

func (a *Apps) roleCommand(r Role, args []string, ov Overrides) ([]string, error) {
	if words := splitExec(ov[r.ID]); len(words) > 0 {
		if r.ID == "terminal" && len(args) > 0 {
			return append(append(words, "-e"), args...), nil
		}
		return append(words, args...), nil
	}
	if r.ID == "terminal" {
		return a.terminalCommand(args, ov)
	}
	id := a.Default(r.Types[0])
	if id == "" {
		return nil, axerr.New(axerr.NotFound, "no app is set or installed for %s", r.ID)
	}
	return a.entryCommand(a.entries[id], args, ov)
}

// entryCommand is an entry's command, in a terminal when it says
// Terminal=true.
func (a *Apps) entryCommand(e Entry, args []string, ov Overrides) ([]string, error) {
	argv := e.Argv(args)
	if len(argv) == 0 {
		return nil, axerr.New(axerr.BadRequest, "%s has no command", e.ID)
	}
	if e.Terminal {
		return a.terminalCommand(argv, ov)
	}
	return argv, nil
}

// terminalCommand starts the terminal, running argv in it when given:
// the override, else the default terminal's entry (argv after its
// X-TerminalArgExec, else -e), else xdg-terminal-exec.
func (a *Apps) terminalCommand(argv []string, ov Overrides) ([]string, error) {
	if words := splitExec(ov["terminal"]); len(words) > 0 {
		if len(argv) == 0 {
			return words, nil
		}
		return append(append(words, "-e"), argv...), nil
	}
	if id := a.Terminal(); id != "" {
		e := a.entries[id]
		out := e.Argv(nil)
		if len(argv) > 0 {
			arg := e.TerminalArg
			if arg == "" {
				arg = "-e"
			}
			out = append(append(out, arg), argv...)
		}
		return out, nil
	}
	if _, err := exec.LookPath("xdg-terminal-exec"); err == nil {
		return append([]string{"xdg-terminal-exec"}, argv...), nil
	}
	return nil, axerr.New(axerr.NotFound, "no terminal is installed")
}

// typeOf is the MIME type of a URL (its scheme's handler type) or a path
// (a folder's, else the type its name says), "" for none.
func (a *Apps) typeOf(target string) string {
	if m := schemePattern.FindStringSubmatch(target); m != nil && !strings.HasPrefix(target, "/") {
		scheme := strings.ToLower(m[1])
		if scheme != "file" {
			return "x-scheme-handler/" + scheme
		}
		target = strings.TrimPrefix(strings.TrimPrefix(target, "file://"), "file:")
	}
	if st, err := os.Stat(target); err == nil && st.IsDir() {
		return "inode/directory"
	}
	return a.mimeDB().TypeOfName(filepath.Base(target))
}

// roleOfType is the role a type is one of, ok false for none.
func roleOfType(mime string) (Role, bool) {
	for _, r := range Roles {
		if contains(r.Types, mime) {
			return r, true
		}
	}
	return Role{}, false
}

// mimeDB is shared-mime-info's database, read when first asked.
func (a *Apps) mimeDB() *Globs {
	if a.globs == nil {
		a.globs = LoadGlobs(append([]string{a.o.DataHome}, a.o.DataDirs...))
	}
	return a.globs
}

// OverridesFrom reads the config's Apps.commands, a command per role
// (nil cfg: none).
func OverridesFrom(cfg *jsonx.Object) Overrides {
	ov := Overrides{}
	if cfg == nil {
		return ov
	}
	for _, r := range Roles {
		if v, ok := config.Lookup(cfg, config.Keys("Apps", "commands", r.ID)); ok {
			if s, _ := v.(string); strings.TrimSpace(s) != "" {
				ov[r.ID] = strings.TrimSpace(s)
			}
		}
	}
	return ov
}
