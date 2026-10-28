// Package actions is what every compositor's bind merge shares: axiom's
// bind actions (table.json, which the daemon also sends the shell:
// binds.actions), and the commands that are one of them (axiom's own IPC
// calls; volume, brightness and media commands). Pure: no I/O.
package actions

import (
	_ "embed"
	"fmt"
	"regexp"
	"strings"
	"sync"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// JSON is what each keybind action (the schema's Keybinds.binds[].action)
// is, independent of the compositor; how each compositor binds one is
// render's (DispatcherLua, SwayActionCommand, NiriActionNode). Labels
// aren't translated: they go to the compositor, like the user's own bind
// descriptions. Its tables, by key:
//   - ipcActions: the actions that call axiom over IPC, [IPC call, default
//     label, section]; {call} is the bind's call (calls), {0} its argument
//   - compositorActions: the ones the compositor carries out itself,
//     [default label, section]
//   - calls: the IPC function behind each call, for actions that open and
//     close something ({open, close}); a toggle is always `toggle`
//   - needs: the compositor capabilities (supports) an action needs, any
//     one of them; actions not listed work everywhere
//   - actionFlags: the flags an action starts with when it's picked
//   - flagNames: the flags a bind can set (bind[flag] === true)
//   - switcherSteps: the window switcher's actions, by the step each takes
//     through the windows
//   - argumentKinds: what an action's argument is (the Keybinds page picks
//     its editor by it); every action with a {0} in its IPC call or label
//     has one
//   - argumentDefaults: the argument an action starts with when picked
//
//go:embed table.json
var JSON []byte

// Table is the tables the merge needs.
type Table struct {
	ipc []ipcPattern
	// Repeating: the actions axiom repeats while held by default
	// (actionFlags)
	Repeating map[string]bool
}

type ipcPattern struct {
	action string
	re     *regexp.Regexp
}

// Tables is JSON parsed, by table name.
func Tables() (*jsonx.Object, error) {
	v, err := jsonx.Unmarshal(JSON)
	if err != nil {
		return nil, fmt.Errorf("the bind actions: %w", err)
	}
	o, ok := v.(*jsonx.Object)
	if !ok {
		return nil, fmt.Errorf("the bind actions aren't an object")
	}
	return o, nil
}

// Default is the merge's Table, made once from JSON (whose tests check it
// parses).
var Default = sync.OnceValue(func() *Table {
	t, err := parse()
	if err != nil {
		panic(err)
	}
	return t
})

// parse makes the Table: each IPC call of ipcActions (its {call} and {0}
// as what they match), and actionFlags' repeating actions.
func parse() (*Table, error) {
	tables, err := Tables()
	if err != nil {
		return nil, err
	}
	t := &Table{Repeating: map[string]bool{}}
	ipc, _ := tables.Value("ipcActions").(*jsonx.Object)
	for _, action := range ipc.Keys() {
		entry, _ := ipc.Value(action).(*jsonx.Array)
		if entry == nil || len(entry.Items) == 0 {
			return nil, fmt.Errorf("the bind actions: %s has no IPC call", action)
		}
		call, _ := entry.Items[0].(string)
		pattern := regexp.QuoteMeta(call)
		pattern = strings.ReplaceAll(pattern, regexp.QuoteMeta("{call}"), `(?P<call>\w+)`)
		pattern = strings.ReplaceAll(pattern, regexp.QuoteMeta("{0}"), `(?P<arg>\S+)`)
		re, err := regexp.Compile("^" + pattern + "$")
		if err != nil {
			return nil, fmt.Errorf("the bind actions: %s: %w", action, err)
		}
		t.ipc = append(t.ipc, ipcPattern{action, re})
	}
	flags, _ := tables.Value("actionFlags").(*jsonx.Object)
	for _, action := range flags.Keys() {
		list, _ := flags.Value(action).(*jsonx.Array)
		for _, f := range list.Items {
			if f == "repeating" {
				t.Repeating[action] = true
			}
		}
	}
	return t, nil
}

// What a call names, for actions that open and close (BindActions.calls)
var calls = map[string]string{"toggle": "toggle", "open": "open", "show": "open", "enable": "open",
	"close": "close", "hide": "close", "disable": "close"}

// The axiom binary, by name or path, maybe quoted (Paths.shellCommand)
const axiom = `['"]?(?:\S*/)?axiom['"]?`

var (
	axiomRestart = regexp.MustCompile(`^` + axiom + ` +restart$`)
	axiomLock    = regexp.MustCompile(`^` + axiom + ` +lock$`)
	axiomIPC     = regexp.MustCompile(`^` + axiom + ` +ipc +(.+)$`)
)

// IPCAction is the axiom bind a command calling axiom's IPC is ({ action,
// call, argument }, the last two when its call has them), or nil.
func (t *Table) IPCAction(command string) *jsonx.Object {
	if axiomRestart.MatchString(command) {
		return jsonx.Obj("action", "restartShell")
	}
	var call string
	if axiomLock.MatchString(command) {
		call = "lockscreen lock"
	} else if m := axiomIPC.FindStringSubmatch(command); m != nil {
		call = strings.TrimSpace(m[1])
	} else {
		return nil
	}
	for _, p := range t.ipc {
		m := p.re.FindStringSubmatch(call)
		if m == nil {
			continue
		}
		entry := jsonx.Obj("action", p.action)
		if i := p.re.SubexpIndex("call"); i > 0 && m[i] != "" {
			name, ok := calls[m[i]]
			if !ok {
				name = "toggle"
			}
			entry.Set("call", name)
		}
		if i := p.re.SubexpIndex("arg"); i > 0 && m[i] != "" {
			entry.Set("argument", unquote(m[i]))
		}
		return entry
	}
	return nil
}

func unquote(text string) string {
	text = strings.TrimSpace(text)
	if len(text) >= 2 && text[0] == text[len(text)-1] && (text[0] == '"' || text[0] == '\'') {
		return text[1 : len(text)-1]
	}
	return text
}

const limit = `( -l [0-9.]+)?`

var (
	wpctlUp     = regexp.MustCompile(`^set-volume` + limit + ` @DEFAULT_AUDIO_SINK@ [0-9.]+%?\+` + limit + `$`)
	wpctlDown   = regexp.MustCompile(`^set-volume` + limit + ` @DEFAULT_AUDIO_SINK@ [0-9.]+%?-` + limit + `$`)
	pactlUp     = regexp.MustCompile(`^set-sink-volume @DEFAULT_SINK@ \+[0-9]+%$`)
	pactlDown   = regexp.MustCompile(`^set-sink-volume @DEFAULT_SINK@ -[0-9]+%$`)
	brightUp    = regexp.MustCompile(`^(-\S+ )*set (\+[0-9]+%|[0-9]+%\+)$`)
	brightDown  = regexp.MustCompile(`^(-\S+ )*set [0-9]+%-$`)
	playerctlTo = map[string]string{"play-pause": "mediaPlayPause", "next": "mediaNext", "previous": "mediaPrevious", "stop": "mediaStop"}
)

// MediaAction is the axiom action a volume, brightness or media command is
// (the commands the compositors' example configs bind media keys to), or
// "".
func MediaAction(command string) string {
	words := strings.Fields(command)
	if len(words) == 0 {
		return ""
	}
	tool, rest := words[0], strings.Join(words[1:], " ")
	switch tool {
	case "wpctl":
		switch {
		case wpctlUp.MatchString(rest):
			return "volumeUp"
		case wpctlDown.MatchString(rest):
			return "volumeDown"
		case rest == "set-mute @DEFAULT_AUDIO_SINK@ toggle":
			return "toggleMute"
		case rest == "set-mute @DEFAULT_AUDIO_SOURCE@ toggle":
			return "toggleMicMute"
		}
	case "pactl":
		switch {
		case pactlUp.MatchString(rest):
			return "volumeUp"
		case pactlDown.MatchString(rest):
			return "volumeDown"
		case rest == "set-sink-mute @DEFAULT_SINK@ toggle":
			return "toggleMute"
		case rest == "set-source-mute @DEFAULT_SOURCE@ toggle":
			return "toggleMicMute"
		}
	case "brightnessctl":
		switch {
		case brightUp.MatchString(rest):
			return "brightnessUp"
		case brightDown.MatchString(rest):
			return "brightnessDown"
		}
	case "playerctl":
		return playerctlTo[rest]
	}
	return ""
}
