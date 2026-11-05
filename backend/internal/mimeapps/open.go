package mimeapps

import (
	"bufio"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
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
// URL or file, xdg-open gets it, when installed.
func (a *Apps) Command(target string, args []string, ov Overrides) ([]string, error) {
	if r, ok := RoleOf(target); ok {
		return a.roleCommand(r, args, ov)
	}
	mime, role := a.typeOf(target)
	if role != "" {
		r, _ := RoleOf(role)
		// A web or mail link follows its role's app (https as http), as
		// does a file of the role's main type
		if ov[role] != "" || mime == r.Types[0] || strings.HasPrefix(mime, "x-scheme-handler/") {
			return a.roleCommand(r, append([]string{target}, args...), ov)
		}
	}
	if id := a.Default(mime); id != "" && mime != "" {
		return a.entryCommand(a.entries[id], append([]string{target}, args...), ov)
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

// typeOf is what a URL or path is: its MIME type, and the role that type
// is the main one of ("" for none).
func (a *Apps) typeOf(target string) (mime, role string) {
	if m := schemePattern.FindStringSubmatch(target); m != nil && !strings.HasPrefix(target, "/") {
		scheme := strings.ToLower(m[1])
		if scheme != "file" {
			mime = "x-scheme-handler/" + scheme
			switch scheme {
			case "http", "https":
				return mime, "browser"
			case "mailto":
				return mime, "mail"
			}
			return mime, ""
		}
		target = strings.TrimPrefix(strings.TrimPrefix(target, "file://"), "file:")
	}
	st, err := os.Stat(target)
	if err == nil && st.IsDir() {
		return "inode/directory", "fileManager"
	}
	mime = a.mimeOfName(filepath.Base(target))
	for _, r := range Roles {
		if len(r.Types) > 0 && contains(r.Types, mime) {
			return mime, r.ID
		}
	}
	return mime, ""
}

// glob is one of shared-mime-info's globs2 lines
type glob struct {
	weight  int
	mime    string
	pattern string
	cased   bool // matched as written ("cs")
}

// mimeOfName is the type a file's name says it is (shared-mime-info's
// globs2, the heaviest then longest pattern matching), "" when none does.
func (a *Apps) mimeOfName(name string) string {
	best, bestWeight, bestLen := "", -1, -1
	for _, g := range a.globs() {
		subject, pattern := name, g.pattern
		if !g.cased {
			subject, pattern = strings.ToLower(name), strings.ToLower(pattern)
		}
		if ok, _ := filepath.Match(pattern, subject); !ok {
			continue
		}
		if g.weight > bestWeight || g.weight == bestWeight && len(g.pattern) > bestLen {
			best, bestWeight, bestLen = g.mime, g.weight, len(g.pattern)
		}
	}
	return best
}

// globs reads the first globs2 each data folder's mime/ has, once.
func (a *Apps) globs() []glob {
	if a.globList != nil {
		return a.globList
	}
	a.globList = []glob{}
	for _, d := range append([]string{a.o.DataHome}, a.o.DataDirs...) {
		f, err := os.Open(filepath.Join(d, "mime", "globs2"))
		if err != nil {
			continue
		}
		sc := bufio.NewScanner(f)
		for sc.Scan() {
			line := sc.Text()
			if line == "" || line[0] == '#' {
				continue
			}
			parts := strings.SplitN(line, ":", 4)
			if len(parts) < 3 {
				continue
			}
			w, err := strconv.Atoi(parts[0])
			if err != nil {
				continue
			}
			a.globList = append(a.globList, glob{weight: w, mime: parts[1], pattern: parts[2], cased: len(parts) == 4 && strings.Contains(parts[3], "cs")})
		}
		f.Close()
	}
	return a.globList
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
