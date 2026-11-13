package windowrules

import (
	"regexp"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// builtin is one built-in switch as a rule: key is its WindowRules.switches
// key, rule its windows, window and icon in config form (what a user would
// save), so Builtins and Copy as rule read one source.
type builtin struct {
	key, name string
	on        func(Switches) bool
	rule      func(Switches) *jsonx.Object
}

// builtins is the table; its order is the priority, below every rule of the
// user's. The ids start with "_", outside the pattern of a rule id the page
// makes.
var builtins = []builtin{
	{
		key: "steamFloat", name: "Float Steam's small windows",
		on: func(s Switches) bool { return s.SteamFloat },
		// Every Steam window but the main one and Big Picture. The positive
		// "matches ." keeps a window with no title yet tiled.
		rule: func(Switches) *jsonx.Object {
			return jsonx.Obj(
				"icon", "picture_in_picture",
				"windows", jsonx.Arr(jsonx.Obj("conditions", jsonx.Arr(
					condObj("appId", "is", "steam"),
					condObj("title", "matches", "."),
					condObj("title", "isNot", "Steam"),
					condObj("title", "isNot", "Steam Big Picture Mode"),
				))),
				"window", jsonx.Obj("float", true),
			)
		},
	},
	{
		key: "gamesSpecial", name: "Send games to a special workspace",
		on: func(s Switches) bool { return s.GamesSpecial.Enabled },
		// Kind 0 is written (Steam games), kind 1 is live: the other
		// launchers' games are moved just after they open.
		rule: func(s Switches) *jsonx.Object {
			return jsonx.Obj(
				"icon", "sports_esports",
				"windows", jsonx.Arr(
					jsonx.Obj("conditions", jsonx.Arr(condObj("appId", "matches", `^steam_app_\d+$`))),
					jsonx.Obj("conditions", jsonx.Arr(condObj("game", "is", ""))),
				),
				"window", jsonx.Obj("special", jsonx.Obj("id", s.GamesSpecial.Special.ID, "silent", s.GamesSpecial.Special.Silent)),
			)
		},
	},
	{
		key: "pictureInPicture", name: "Float picture-in-picture videos",
		on: func(s Switches) bool { return s.PictureInPicture },
		// Title only: Firefox and Chromium name the window, no other signal
		// tells it from the browser's. English titles; translated browsers miss.
		rule: func(Switches) *jsonx.Object {
			return jsonx.Obj(
				"icon", "picture_in_picture_alt",
				"windows", jsonx.Arr(jsonx.Obj("conditions", jsonx.Arr(
					condObj("title", "matches", `^(Picture-in-Picture|Picture in picture)$`),
				))),
				"window", jsonx.Obj("float", true, "pin", true),
			)
		},
	},
	{
		key: "utilityFloat", name: "Float utility windows",
		on: func(s Switches) bool { return s.UtilityFloat },
		rule: func(Switches) *jsonx.Object {
			quoted := make([]string, len(utilityAppIDs))
			for i, id := range utilityAppIDs {
				quoted[i] = regexp.QuoteMeta(id)
			}
			return jsonx.Obj(
				"icon", "tune",
				"windows", jsonx.Arr(jsonx.Obj("conditions", jsonx.Arr(
					condObj("appId", "matches", "^("+strings.Join(quoted, "|")+")$"),
				))),
				"window", jsonx.Obj("float", true),
			)
		},
	},
	{
		key: "fullscreenAwake", name: "Keep the screen awake while fullscreen",
		on: func(s Switches) bool { return s.FullscreenAwake },
		// "appId matches .*" is how a rule says any window (a kind with no
		// condition is refused). A shell-only rule is never written.
		rule: func(Switches) *jsonx.Object {
			return jsonx.Obj(
				"icon", "coffee",
				"windows", jsonx.Arr(jsonx.Obj("conditions", jsonx.Arr(condObj("appId", "matches", ".*")))),
				"shell", jsonx.Obj("keepAwake", jsonx.Obj("enabled", true, "when", "fullscreen")),
			)
		},
	},
}

// utilityAppIDs are the Wayland app ids Float utility windows matches: file
// picker portals, polkit agents, volume, network and Bluetooth apps.
var utilityAppIDs = []string{
	"xdg-desktop-portal-gtk", "xdg-desktop-portal-gnome",
	"org.freedesktop.impl.portal.desktop.kde",
	"org.kde.polkit-kde-authentication-agent-1", "polkit-gnome-authentication-agent-1",
	"org.pulseaudio.pavucontrol", "pavucontrol", "com.saivert.pwvucontrol",
	"nm-connection-editor", "blueman-manager",
}

func condObj(field, op, value string) *jsonx.Object {
	return jsonx.Obj("field", field, "op", op, "value", value)
}

// Builtins are the switched-on built-in rules (WindowRules.switches) with no
// issue, in table order: they rank below every rule of the user's.
func Builtins(s Switches, issues []Issue) []Rule {
	var out []Rule
	for _, b := range builtins {
		if !b.on(s) || switchIssue(b.key, issues) {
			continue
		}
		r := parseRule(b.rule(s))
		r.ID, r.Name, r.Enabled = "_"+b.key, b.name, true
		out = append(out, r)
	}
	return out
}

// switchIssue: an issue of the switch (Rule "") at its path or under it.
func switchIssue(key string, issues []Issue) bool {
	p := "switches." + key
	for _, i := range issues {
		if i.Rule == "" && (i.Path == p || strings.HasPrefix(i.Path, p+".")) {
			return true
		}
	}
	return false
}

// BuiltinRule is the built-in switch key's rule in config form ({icon,
// windows, window}) for s's values: what Copy as rule adds. false: no such key.
func BuiltinRule(key string, s Switches) (*jsonx.Object, bool) {
	for _, b := range builtins {
		if b.key == key {
			return b.rule(s), true
		}
	}
	return nil, false
}

// BuiltinIDs are the built-in rules' ids, which no rule of the user's can take.
func BuiltinIDs() []string {
	ids := make([]string, len(builtins))
	for i, b := range builtins {
		ids[i] = "_" + b.key
	}
	return ids
}

// Effective are the rules to write and match: Usable, then Builtins.
func Effective(c Config, issues []Issue) []Rule {
	return append(Usable(c, issues), Builtins(c.Switches, issues)...)
}
