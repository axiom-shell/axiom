package cli

import (
	"context"
	"flag"
	"strings"
)

// named is a command that calls one IPC target: `axiom <name> <verb>
// [args]` runs `<target>.<function>`. The test checks every entry against
// the shell's targets (docs/dev/generated/ipc.md).
type named struct {
	name    string
	summary string
	target  string
	verbs   []verb
}

type verb struct {
	name     string // the command line's word
	function string // the target's function
	args     string // synopsis of its arguments ("" for none)
	nargs    int
	summary  string
}

var namedCommands = []named{
	{"launcher", "Open, close or search the launcher", "appLauncher", []verb{
		{"toggle", "toggle", "", 0, "Open it, or close it when open"},
		{"open", "open", "", 0, "Open it"},
		{"close", "close", "", 0, "Close it"},
		{"search", "search", "TEXT", 1, "Open it searching for TEXT"},
	}},
	{"overlay", "Open, close or switch the overlay", "overlay", []verb{
		{"toggle", "toggle", "", 0, "Open it, or close it when open"},
		{"open", "open", "", 0, "Open it"},
		{"close", "close", "", 0, "Close it"},
		{"page", "page", "TYPE", 1, "Open it on a page of TYPE"},
	}},
	{"menu", "Open, close or pin a menu", "menu", menuVerbs},
	// The command's old name (edge menus became menus, v104), hidden
	{"edge-menu", "Open, close or pin a menu (old name of menu)", "menu", menuVerbs},
	{"dock", "Show or hide a dock", "dock", []verb{
		{"toggle", "toggle", "ID", 1, "Show it, or hide it when shown"},
		{"open", "open", "ID", 1, "Show it"},
		{"close", "close", "ID", 1, "Hide it"},
	}},
	{"power-menu", "Open or close the power menu", "powermenu", []verb{
		{"toggle", "toggle", "", 0, "Open it, or close it when open"},
		{"open", "open", "", 0, "Open it"},
		{"close", "close", "", 0, "Close it"},
	}},
	{"workspace", "Switch workspaces, or move the window to one", "workspaces", []verb{
		{"go", "go", "ID", 1, "Go to a workspace"},
		{"move", "move", "ID", 1, "Move the window there, and follow it"},
		{"move-silent", "moveSilent", "ID", 1, "Move the window there"},
		{"nth", "nth", "N MODE", 2, "Go to (or move to: MODE) the Nth workspace"},
		{"step", "step", "DIR MODE", 2, "Go to (or move to) the next or previous one"},
		{"scroll", "scroll", "DIR", 1, "Scroll the workspaces"},
	}},
	{"overview", "Open or close the workspace overview", "workspaceOverlay", []verb{
		{"toggle", "toggle", "", 0, "Open it, or close it when open"},
		{"open", "open", "", 0, "Open it"},
		{"close", "hide", "", 0, "Close it"},
	}},
	{"window-switcher", "Drive the window switcher", "windowSwitcher", []verb{
		{"next", "next", "", 0, "Open it, or move to the next window"},
		{"previous", "previous", "", 0, "Move to the previous window"},
		{"commit", "commit", "", 0, "Switch to the chosen window"},
		{"cancel", "cancel", "", 0, "Close it"},
	}},
	{"screenshot", "Take a screenshot", "screenshot", []verb{
		{"take", "take", "KIND", 1, "Take one (region, window, screen, …)"},
		{"cancel", "cancel", "", 0, "Stop choosing"},
	}},
	{"record", "Record the screen", "screenRecord", []verb{
		{"toggle", "toggle", "", 0, "Start, or stop when recording"},
		{"start", "enable", "", 0, "Start recording"},
		{"stop", "disable", "", 0, "Stop recording"},
		{"status", "status", "", 0, "Say whether it's recording"},
	}},
	{"volume", "Change the volume or the output", "audio", []verb{
		{"up", "volumeUp", "", 0, "Louder"},
		{"down", "volumeDown", "", 0, "Quieter"},
		{"toggle-mute", "toggleMute", "", 0, "Mute, or unmute when muted"},
		{"next-output", "nextOutput", "", 0, "Switch to the next output"},
	}},
	{"mic", "Turn the microphone on or off", "microphone", []verb{
		{"toggle", "toggle", "", 0, "Mute it, or unmute it when muted"},
		{"on", "enable", "", 0, "Unmute it"},
		{"off", "disable", "", 0, "Mute it"},
		{"status", "status", "", 0, "Say whether it's on (unmuted)"},
	}},
	{"brightness", "Change the screen brightness", "brightness", []verb{
		{"up", "up", "", 0, "Brighter"},
		{"down", "down", "", 0, "Dimmer"},
		{"set", "set", "PERCENT", 1, "Set it"},
		{"dim", "dim", "PERCENT", 1, "Dim to PERCENT (undim restores it)"},
		{"undim", "undim", "", 0, "Restore it after a dim"},
	}},
	{"media", "Control the playing media", "media", []verb{
		{"play-pause", "playPause", "", 0, "Play, or pause"},
		{"next", "next", "", 0, "Next track"},
		{"previous", "previous", "", 0, "Previous track"},
		{"stop", "stop", "", 0, "Stop"},
	}},
	{"notifications", "Clear the notifications, or fold their Quiet section", "notifications", []verb{
		{"clear", "clear", "", 0, "Clear them all (no undo)"},
		{"clear-quiet", "clearQuiet", "", 0, "Clear the Quiet section's (no undo)"},
		{"toggle-quiet", "toggleQuiet", "", 0, "Fold the Quiet section open, or shut"},
	}},
	{"dnd", "Turn do not disturb on or off", "dnd", []verb{
		{"toggle", "toggle", "", 0, "On, or off"},
		{"on", "enable", "", 0, "On"},
		{"off", "disable", "", 0, "Off"},
		{"status", "status", "", 0, "Say whether it's on"},
	}},
	{"night-light", "Switch the night light", "nightLight", []verb{
		{"toggle", "toggle", "", 0, "On, or off"},
		{"on", "enable", "", 0, "On"},
		{"off", "disable", "", 0, "Off"},
		{"status", "status", "", 0, "Say whether it's on"},
	}},
	{"idle-inhibit", "Keep the screen awake", "idleInhibit", []verb{
		{"toggle", "toggle", "", 0, "On, or off"},
		{"on", "enable", "", 0, "Keep it awake"},
		{"off", "disable", "", 0, "Let it sleep again"},
		{"status", "status", "", 0, "Say whether it's kept awake"},
	}},
	{"wallpaper", "Change the wallpaper", "wallpaper", []verb{
		{"next", "next", "", 0, "The next one"},
		{"random", "random", "", 0, "A random one, on the focused monitor"},
	}},
	{"dark-mode", "Switch between the theme's dark and light variants", "darkMode", []verb{
		{"toggle", "toggle", "", 0, "Dark, or light"},
		{"on", "enable", "", 0, "Dark"},
		{"off", "disable", "", 0, "Light"},
	}},
	{"wifi", "Turn Wi-Fi on or off", "wifi", []verb{
		{"toggle", "toggle", "", 0, "On, or off"},
		{"on", "enable", "", 0, "On"},
		{"off", "disable", "", 0, "Off"},
	}},
	{"bluetooth", "Turn Bluetooth on or off", "bluetooth", []verb{
		{"toggle", "toggle", "", 0, "On, or off"},
		{"on", "enable", "", 0, "On"},
		{"off", "disable", "", 0, "Off"},
	}},
	{"vpn", "Connect or disconnect the VPN", "vpn", []verb{
		{"toggle", "toggle", "", 0, "Bring the last one used up, or the active one down"},
	}},
}

var menuVerbs = []verb{
	{"toggle", "toggle", "ID", 1, "Open it, or close it when open"},
	{"open", "open", "ID", 1, "Open it"},
	{"close", "close", "ID", 1, "Close it"},
	{"pin", "pin", "ID", 1, "Keep it open"},
	{"unpin", "unpin", "ID", 1, "Let it close again"},
	{"list", "list", "", 0, "List the menus"},
}

// The commands kept under an old name: they work, but help and
// completions leave them out
var hiddenNamed = map[string]bool{"edge-menu": true}

// namedCommandList builds the commands of the table.
func namedCommandList() []*Command {
	var out []*Command
	for _, n := range namedCommands {
		cmd := &Command{Name: n.name, Summary: n.summary, Hidden: hiddenNamed[n.name]}
		for _, v := range n.verbs {
			v, target := v, n.target
			cmd.Subs = append(cmd.Subs, &Command{
				Name:    v.name,
				Summary: v.summary,
				Args:    v.args,
				Setup: func(fs *flag.FlagSet) Runner {
					return func(ctx context.Context, e *Env, args []string) error {
						if len(args) != v.nargs {
							return usageError([]string{"axiom", n.name, v.name}, "takes "+strings.TrimSpace(v.args+" "))
						}
						return ipcCall(ctx, e, target, v.function, args)
					}
				},
			})
		}
		out = append(out, cmd)
	}
	return out
}
