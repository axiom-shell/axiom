// Package steps is the format-2 migrations: each takes a config from the
// version before it to its own, so a file of any format-2 version loads in
// the current shape. A format-1 file is converted first (to version 76,
// package convert), then runs them too. A step reshapes existing config
// only: a new setting is just its schema default. Pure: no I/O.
package steps

import (
	"fmt"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/migrate/convert"
)

// Step is one migration.
type Step struct {
	// Version is the one a config has after it: the version before it
	// plus one
	Version int
	// Run changes cfg (a whole config of the version before, not yet
	// pruned or filled) in place and says what it did (English, for the
	// log), nothing when there was nothing to do. It checks each value's
	// shape before using it, and running it twice changes nothing more.
	Run func(cfg *jsonx.Object) []string
}

// all are the steps in order, the first at convert.Version + 1. The
// schema's `version` default (config/schema/index.yaml) is the last one's.
var all = []Step{
	// v77: the clipboard history is the daemon's own, images included
	// (roadmap stage 2): cliphist is no longer a source to pick
	{Version: 77, Run: func(cfg *jsonx.Object) []string {
		clip := object(cfg, "Launcher", "providers", "clipboard")
		if clip == nil {
			return nil
		}
		if _, ok := clip.Get("source"); !ok {
			return nil
		}
		clip.Delete("source")
		return []string{"Launcher.providers.clipboard.source removed: axiom keeps the clipboard history itself, images included"}
	}},
	// v78: idle is the daemon's (roadmap stage 2): the managed autostart's
	// default hypridle entry goes, as it left the default
	{Version: 78, Run: func(cfg *jsonx.Object) []string {
		session := object(cfg, "Session")
		if session == nil {
			return nil
		}
		autostart, _ := session.Value("autostart").(*jsonx.Array)
		if autostart == nil {
			return nil
		}
		kept := autostart.Items[:0:0]
		for _, item := range autostart.Items {
			if e, _ := item.(*jsonx.Object); e != nil && e.Value("id") == "hypridle" && e.Value("command") == "hypridle" {
				continue
			}
			kept = append(kept, item)
		}
		if len(kept) == len(autostart.Items) {
			return nil
		}
		autostart.Items = kept
		return []string{"Session.autostart: the hypridle entry removed: axiom handles idle itself (Idle settings); add it back to keep running hypridle"}
	}},
	// v79: Tailscale's interval moved from each bar widget to the
	// Tailscale section (v79.go)
	{Version: 79, Run: v79},
	// v80: the Custom widgets page, a tool page every config has once
	{Version: 80, Run: func(cfg *jsonx.Object) []string {
		overlay := object(cfg, "Overlay")
		if overlay == nil {
			return nil
		}
		items, _ := overlay.Value("items").(*jsonx.Array)
		if items == nil {
			return nil
		}
		for _, item := range items.Items {
			if view, _ := item.(*jsonx.Object); view != nil && view.Value("type") == "CustomWidgets" {
				return nil
			}
		}
		items.Append(jsonx.Obj("id", "customWidgets", "type", "CustomWidgets"))
		return []string{"Overlay.items: added the Custom widgets page"}
	}},
	// v81: CommandOutput modules became custom widgets (v81.go)
	{Version: 81, Run: v81},
	// v82: niri's hot corner became an axiom one (v82.go)
	{Version: 82, Run: v82},
	// v83: Notifications.appTimeouts became followApps
	{Version: 83, Run: func(cfg *jsonx.Object) []string {
		n := object(cfg, "Notifications")
		if n == nil || !n.Has("appTimeouts") {
			return nil
		}
		v, _ := n.Get("appTimeouts")
		n.Delete("appTimeouts")
		if !n.Has("followApps") {
			n.Set("followApps", v)
		}
		return []string{"Notifications.appTimeouts became Notifications.followApps (which also lets apps withdraw their notifications from the history)"}
	}},
	// v84: Notifications' corner became an edge placement (v84.go)
	{Version: 84, Run: v84},
	// v85: the tray's icons follow the bar's font, as every other bar
	// widget's icon does: its iconSize went
	{Version: 85, Run: func(cfg *jsonx.Object) []string {
		removed := 0
		for _, w := range barWidgets(cfg, "SystemTray") {
			if p, _ := w.Value("properties").(*jsonx.Object); p != nil && p.Delete("iconSize") {
				removed++
			}
		}
		if removed == 0 {
			return nil
		}
		return []string{fmt.Sprintf("iconSize removed from %d System Tray bar widget(s): tray icons now follow the bar's font size", removed)}
	}},
	// v86: an OSD's bars became its items (v86.go)
	{Version: 86, Run: v86},
	// v87: an OSD's items split into bars, statuses and media (v87.go)
	{Version: 87, Run: v87},
	// v88: the awww wallpaper backend went: axiom draws every wallpaper,
	// with its own transitions
	{Version: 88, Run: func(cfg *jsonx.Object) []string {
		w := object(cfg, "Appearance", "wallpaper")
		if w == nil {
			return nil
		}
		backend, _ := w.Value("backend").(string)
		removed := w.Delete("backend")
		removed = w.Delete("daemon") || removed
		if !removed {
			return nil
		}
		if backend == "awww" {
			return []string{"Appearance.wallpaper.backend awww removed: axiom draws the wallpaper itself, with its own transitions (Appearance.wallpaper.transition)"}
		}
		return []string{"Appearance.wallpaper.backend and daemon removed: axiom always draws the wallpaper"}
	}},
	// v89: hot corners that ran an action a corner no longer offers went,
	// and the old default bind that logged out at once; OSDs on the old
	// default status icons got the new default's (v89.go)
	{Version: 89, Run: v89},
	// v90: Drives.announce (osd | notification | off) became Drives.notify:
	// an OSD listing Removable drives shows them, whatever the setting
	{Version: 90, Run: func(cfg *jsonx.Object) []string {
		d := object(cfg, "Drives")
		if d == nil {
			return nil
		}
		announce, ok := d.Value("announce").(string)
		if !ok {
			return nil
		}
		var notify bool
		switch announce {
		case "osd", "notification":
			notify = true
		case "off":
		default:
			return nil
		}
		d.Delete("announce")
		if !d.Has("notify") {
			d.Set("notify", notify)
		}
		return []string{"Drives.announce " + announce + " became Drives.notify: an OSD listing Removable drives shows them, else they notify unless it's off"}
	}},
	// v91: an OSD's cards got their own object (`cards`: enabled, timeout,
	// the card-only types and Now playing as `items`) (v91.go)
	{Version: 91, Run: v91},
	// v92: a notification rule's toasts and history became level
	{Version: 92, Run: v92},
	// v93: the bar rewrite: surface and floating for background, renamed
	// sizes, text scale for font size, three sections with Spacers (v93.go)
	{Version: 93, Run: v93},
	// v94: Input.keyboard's layout and variant became the input sources,
	// Input.keyboard.sources (v94.go)
	{Version: 94, Run: v94},
	// v95: the default input source binds (CTRL + space and with SHIFT)
	// joined configs where their keys and ids are free (v95.go)
	{Version: 95, Run: v95},
	// v96: the settings overhaul: clocks' use24Hour became hourFormat
	// (default follows Date & time), Apps' terminal, fileManager and
	// browser moved into Apps.commands, the old default kitty dropped
	// (v96.go)
	{Version: 96, Run: v96},
	// v97: an OSD's, a dock's and an edge menu's `gap` dropped: detached
	// surfaces are placed by `distance`, as the launcher (v97.go)
	{Version: 97, Run: v97},
	// v98: `trigger` dropped from Popouts and every bar, dock and edge
	// menu (one fixed hover strip, its surface's length), and an edge
	// menu's `padding` (v98.go)
	{Version: 98, Run: v98},
	// v99: the toasts' `gap` and a per-app rule's `timeout` store
	// Automatic as null, no longer -1 (v99.go)
	{Version: 99, Run: v99},
	// v100: one catalogue of actions: QuickActions' caffeine and dnd tiles
	// became idleInhibit and toggleDnd, a Button's appLauncher and
	// workspaceOverlay actions launcher and workspaceOverview (v100.go)
	{Version: 100, Run: v100},
	// v101: an OSD's bars, status icons and cards became one ordered list
	// of systems (`systems`), the bars' layout `barLayout`, `statuses.row`
	// `row`, the cards' switch and time `cardsEnabled` / `cardTimeout`
	// (v101.go)
	{Version: 101, Run: v101},
	// v102: every bar of an OSD's Audio got a stable id, so an App bar is
	// keyed by it and an OSD's barOrder can name it (v102.go)
	{Version: 102, Run: v102},
	// v103: an edge menu's `mode` became `placement` (floating → edge,
	// integrated → strip, submenu → free), and its `open.delay` dropped
	// (v103.go)
	{Version: 103, Run: v103},
	// v104: EdgeMenus became Menus, and the edgeMenu action (keybinds, hot
	// corners, Button widgets) menu (v104.go)
	{Version: 104, Run: v104},
}

// object is the object at path in cfg, nil when any part isn't one.
func object(cfg *jsonx.Object, path ...string) *jsonx.Object {
	o := cfg
	for _, k := range path {
		next, _ := o.Value(k).(*jsonx.Object)
		if next == nil {
			return nil
		}
		o = next
	}
	return o
}

// Current is the version this axiom writes: the last step's, else the
// conversion's.
func Current() int {
	return current(all)
}

func current(list []Step) int {
	if len(list) == 0 {
		return convert.Version
	}
	return list[len(list)-1].Version
}

// Migrate runs the steps newer than cfg's version on it, in place, and
// sets its version to Current. migrated says it was older.
func Migrate(cfg *jsonx.Object) (changes []string, migrated bool) {
	return migrate(all, cfg)
}

func migrate(list []Step, cfg *jsonx.Object) ([]string, bool) {
	from, _ := cfg.Value("version").(float64)
	var changes []string
	for _, step := range list {
		if float64(step.Version) > from {
			changes = append(changes, step.Run(cfg)...)
			cfg.Set("version", float64(step.Version))
		}
	}
	return changes, from < float64(current(list))
}
