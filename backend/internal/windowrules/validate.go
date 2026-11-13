package windowrules

import (
	"regexp"
	"slices"
	"strconv"
	"strings"
	"unicode"

	"github.com/axiom-shell/axiom/backend/internal/specialid"
)

// Issue is one problem of a rule (Rule: its id) or of the switches (Rule ""),
// at Path, dotted keys and list indices from the rule (or the section for
// the switches): "windows.0.conditions.1.value". Message is an English
// template with {0}… placeholders that Args fill.
type Issue struct {
	Rule    string   `json:"rule"`
	Path    string   `json:"path"`
	Code    string   `json:"code"`
	Message string   `json:"message"`
	Args    []string `json:"args"` // never nil: [] when none
}

// Context is what validation needs from outside the section: the Keybinds
// bind ids (nil: unknown, the check is skipped).
type Context struct{ BindIDs []string }

var steamID = regexp.MustCompile(`^[0-9]+$`)

// Validate lists every rule's issues (enabled or not), then the switches',
// in config order and, within a rule, in the order of the checks.
func Validate(c Config, ctx Context) []Issue {
	issues := []Issue{}
	seen := map[string]bool{}
	for _, r := range c.Rules {
		add := func(path, code, message string, args ...string) {
			if args == nil {
				args = []string{}
			}
			issues = append(issues, Issue{Rule: r.ID, Path: path, Code: code, Message: message, Args: args})
		}
		if r.ID == "" {
			add("id", "missingId", "This rule has no id.")
		}
		if seen[r.ID] {
			add("id", "duplicateId", "Another rule above has the same id.")
		}
		seen[r.ID] = true
		checkKinds(r, add)
		checkWindow(r.Window, add)
		checkShell(r.Shell, ctx, add)
	}
	checkSwitches(c.Switches, &issues)
	return issues
}

type adder func(path, code, message string, args ...string)

func allowed(f Field, op Op) bool {
	switch f {
	case FieldAppID, FieldTitle, FieldProcess, FieldStartedFrom:
		return slices.Contains([]Op{OpIs, OpContains, OpMatches, OpIsNot}, op)
	case FieldSteamGame, FieldApp, FieldXwayland, FieldGame:
		return op == OpIs || op == OpIsNot
	}
	return false
}

func checkKinds(r Rule, add adder) {
	if len(r.Kinds) == 0 {
		add("windows", "noKinds", "Add at least one kind of window.")
	}
	for ki, k := range r.Kinds {
		kp := "windows." + strconv.Itoa(ki)
		if len(k.Conditions) == 0 {
			add(kp, "emptyKind", "This kind has no conditions, so it would match every window.")
		}
		positive := map[Field]bool{}
		for ci, c := range k.Conditions {
			cp := kp + ".conditions." + strconv.Itoa(ci)
			if !allowed(c.Field, c.Op) {
				add(cp+".op", "opNotAllowed", "{0} can't be tested this way.", string(c.Field))
				continue
			}
			checkValue(c, cp+".value", add)
			if c.Op == OpIsNot || k.Live() {
				continue
			}
			target := c.Field
			if target == FieldSteamGame || target == FieldApp {
				target = FieldAppID
			}
			if target != FieldAppID && target != FieldTitle {
				continue
			}
			if positive[target] {
				add(cp, "twoTests", "A kind can test {0} only once with is, contains or matches: join them into one pattern.", string(target))
			}
			positive[target] = true
		}
	}
}

func checkValue(c Condition, path string, add adder) {
	switch c.Field {
	case FieldSteamGame:
		if !steamID.MatchString(c.Value) {
			add(path, "steamGameId", "A Steam game id is a number.")
		}
	case FieldXwayland, FieldGame:
	default:
		if c.Value == "" {
			add(path, "emptyValue", "Enter a value.")
		} else if c.Op == OpMatches {
			if _, err := Normalise(c.Value); err != nil {
				pe := err.(*PatternError)
				if pe.Code == "patternRefused" {
					add(path, "patternRefused", "Patterns can't use {0} here.", pe.Arg)
				} else {
					add(path, "patternInvalid", "This pattern doesn't work: {0}", pe.Arg)
				}
			}
		}
	}
}

func checkWindow(w WindowEffects, add adder) {
	if (w.Width == 0) != (w.Height == 0) {
		add("window.size", "sizePair", "Give both a width and a height.")
	}
	if w.Workspace != "" && w.Special.ID != "" {
		add("window.special.id", "workspaceAndSpecial", "Pick a workspace or a special workspace, not both.")
	}
	if w.Workspace != "" && !workspaceOK(w.Workspace) {
		add("window.workspace", "workspaceName", "A workspace is a number from 1 up, or a name.")
	}
	if w.Special.ID != "" && !specialid.Valid(w.Special.ID) {
		add("window.special.id", "specialId", "A special workspace id is up to 32 letters, digits, dots, dashes or underscores.")
	}
}

func workspaceOK(name string) bool {
	if strings.Trim(name, "0123456789") == "" {
		n, err := strconv.Atoi(name)
		return err == nil && n >= 1
	}
	if name != strings.TrimSpace(name) || strings.HasPrefix(name, "special") {
		return false
	}
	return !strings.ContainsFunc(name, unicode.IsControl)
}

func checkShell(s ShellEffects, ctx Context, add adder) {
	whenOK := func(path string, t Trigger) {
		if !slices.Contains([]When{WhenOpen, WhenFocused, WhenFullscreen}, t.When) {
			add(path, "unknownWhen", "Pick when it applies.")
		}
	}
	if p := s.PowerProfile; p.Enabled && p.Profile != "performance" && p.Profile != "powerSaver" {
		add("shell.powerProfile.profile", "powerProfile", "Pick performance or power saver.")
	}
	if h := s.HideFrom; h.Enabled && !h.Dock && !h.Switcher && !h.Workspaces && !h.Launcher {
		add("shell.hideFrom", "hideFromNothing", "Pick at least one place to hide it from.")
	}
	if p := s.PauseBinds; p.Enabled {
		switch {
		case p.Mode == "these" && len(p.Binds) == 0:
			add("shell.pauseBinds.binds", "pauseBindsNone", "Pick at least one shortcut to pause.")
		case p.Mode == "allExcept" && len(p.Binds) == 0:
			add("shell.pauseBinds.binds", "pauseBindsNoWayOut", "Keep at least one shortcut, your way out.")
		}
		if p.Mode == "allExcept" && p.When == WhenOpen {
			add("shell.pauseBinds.when", "pauseBindsWhen", "All except works only while the window is focused or fullscreen.")
		}
		if ctx.BindIDs != nil {
			for i, id := range p.Binds {
				if !slices.Contains(ctx.BindIDs, id) {
					add("shell.pauseBinds.binds."+strconv.Itoa(i), "unknownBind", "Shortcut {0} no longer exists.", id)
				}
			}
		}
	}
	for _, e := range []struct {
		name string
		t    Trigger
	}{
		{"dnd", s.DND}, {"keepAwake", s.KeepAwake}, {"powerProfile", s.PowerProfile.Trigger},
		{"hideFrom", s.HideFrom.Trigger}, {"pauseBinds", s.PauseBinds.Trigger},
		{"pauseOsd", s.PauseOSD}, {"hideBar", s.HideBar},
	} {
		if e.t.Enabled {
			whenOK("shell."+e.name+".when", e.t)
		}
	}
}

func checkSwitches(s Switches, issues *[]Issue) {
	g := s.GamesSpecial
	if !g.Enabled {
		return
	}
	add := func(code, message string) {
		*issues = append(*issues, Issue{Path: "switches.gamesSpecial.special.id", Code: code, Message: message, Args: []string{}})
	}
	switch {
	case g.Special.ID == "":
		add("specialMissing", "Pick a special workspace.")
	case !specialid.Valid(g.Special.ID):
		add("specialId", "A special workspace id is up to 32 letters, digits, dots, dashes or underscores.")
	}
}

// Usable are the enabled rules with no issue, in priority order: the ones to
// write and match. A duplicated id drops every rule that has it.
func Usable(c Config, issues []Issue) []Rule {
	bad := map[string]bool{}
	count := map[string]int{}
	for _, r := range c.Rules {
		count[r.ID]++
	}
	for _, i := range issues {
		if i.Rule != "" {
			bad[i.Rule] = true
		}
	}
	var out []Rule
	for _, r := range c.Rules {
		if r.Enabled && r.ID != "" && !bad[r.ID] && count[r.ID] == 1 {
			out = append(out, r)
		}
	}
	return out
}
