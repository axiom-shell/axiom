// Package steps is the format-2 migrations: each takes a config from the
// version before it to its own, so a file of any format-2 version loads in
// the current shape. A format-1 file is converted first (to version 76,
// package convert), then runs them too. A step reshapes existing config
// only: a new setting is just its schema default. Pure: no I/O.
package steps

import (
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
