package steps

import (
	"fmt"
	"slices"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// The OSD's old parts as v101 saw them, frozen here as a step's view of
// the schema: the defaults an entry without one of its parts had, and
// each old type's system.
var (
	// v100's OSDEntry defaults for `bars.items`, `statuses.items` and
	// `cards.items`
	osdV100Bars = func() *jsonx.Array {
		return jsonx.Arr(jsonx.Obj("type", "other", "icon", "music_note", "showOsd", true), jsonx.Obj("type", "master", "icon", "", "showOsd", true))
	}
	osdV100Statuses = []string{"capsLock", "numLock", "keyboardLayout", "microphone", "audio", "dnd", "caffeine", "nightLight", "recording", "drive"}
	osdV100Cards    = []string{"message"}
	// A status type's system, and the list of the item it joins (""
	// for a system that is the type alone). The lists are written in
	// this order whatever the old one: the canonical order of each
	// subset.
	osdStatusSystems = map[string][2]string{
		"capsLock": {"LockKeys", "keys"}, "numLock": {"LockKeys", "keys"}, "scrollLock": {"LockKeys", "keys"},
		"audio": {"Audio", "tiles"}, "microphone": {"Audio", "tiles"},
		"camera": {"Privacy", "kinds"}, "micUse": {"Privacy", "kinds"}, "screenShare": {"Privacy", "kinds"},
		"charger": {"Battery", "tiles"}, "battery": {"Battery", "tiles"},
		"keyboardLayout": {"KeyboardLayout"}, "powerProfile": {"PowerProfile"}, "caffeine": {"Caffeine"},
		"dnd": {"Dnd"}, "nightLight": {"NightLight"}, "airplane": {"Airplane"}, "wifi": {"Wifi"},
		"bluetooth": {"Bluetooth"}, "vpn": {"Vpn"}, "drive": {"Drives"}, "recording": {"Recording"},
	}
	osdSubsetOrder = map[string][]string{
		"LockKeys": {"capsLock", "numLock", "scrollLock"},
		"Audio":    {"audio", "microphone"},
		"Privacy":  {"camera", "micUse", "screenShare"},
		"Battery":  {"charger", "battery"},
	}
	osdCardSystems = map[string]string{"monitor": "Monitors", "screenshot": "Screenshot", "message": "Message", "media": "Media"}
	osdAudioBars   = map[string]bool{"master": true, "other": true, "app": true, "microphone": true}
)

// v101: an OSD's bars, status icons and cards became one ordered list of
// systems, `systems` ([{type, tile, card, quiet, …its own settings}]),
// each type from its folder's schema.yaml. Per entry:
//   - the bars' layout (`bars.orientation` / `alongEdge` / `showPercent`)
//     moved to `barLayout`, `statuses.row` to `row`, `cards.enabled` /
//     `timeout` to `cardsEnabled` / `cardTimeout`;
//   - the items come in order, each system once, where its first type
//     was: the bars' first (Audio's master / other / app / microphone
//     bars, keeping their apps, icon and showOsd; Brightness's
//     allMonitors, icon and showOsd, the first brightness bar's), then
//     the status icons' (lock keys one LockKeys with its `keys`; audio
//     and microphone Audio's `tiles`; camera, micUse and screenShare
//     Privacy's `kinds`; charger and battery Battery's `tiles`; the rest
//     a system each), then the cards' (Monitors, Screenshot, Message,
//     Media with the cards' onTrackChange / onPlayPause);
//   - Audio from bars alone gets `tiles: []`, from tiles alone `bars:
//     []`;
//   - an item is `quiet` when every key it took was: a status type in
//     `statuses.quiet`, a bar with showOsd off; one with a key that
//     opened the OSD isn't (a quiet audio icon beside an opening volume
//     bar opens it, as the bar did);
//   - a part the entry didn't have was its old default (an entry with
//     none of the three is left to the new default, the same list);
//   - a type no system takes is dropped, and said.
//
// An entry with `systems` is left alone.
func v101(cfg *jsonx.Object) []string {
	osd := object(cfg, "OSD")
	if osd == nil {
		return nil
	}
	list, _ := osd.Value("items").(*jsonx.Array)
	if list == nil {
		return nil
	}
	count := 0
	var notes []string
	for _, item := range list.Items {
		entry, _ := item.(*jsonx.Object)
		if entry == nil || entry.Has("systems") || !(entry.Has("bars") || entry.Has("statuses") || entry.Has("cards")) {
			continue
		}
		if dropped := osdToSystems(entry); len(dropped) > 0 {
			notes = append(notes, fmt.Sprintf("OSD %s: dropped %s", jsonx.ToString(entry.Value("id")), strings.Join(dropped, ", ")))
		}
		count++
	}
	if count == 0 {
		return nil
	}
	return append([]string{fmt.Sprintf("The bars, status icons and cards of %d OSD(s) became one list of what each shows (systems), the bars' layout under barLayout", count)}, notes...)
}

// osdSystem is an item being built: its object, and whether each key it
// took was quiet
type osdSystem struct {
	item        *jsonx.Object
	keys, quiet int
}

// osdToSystems reshapes one entry in place; the old types it dropped.
func osdToSystems(entry *jsonx.Object) []string {
	bars, _ := entry.Value("bars").(*jsonx.Object)
	statuses, _ := entry.Value("statuses").(*jsonx.Object)
	cards, _ := entry.Value("cards").(*jsonx.Object)

	var order []*osdSystem
	byType := map[string]*osdSystem{}
	var dropped []string
	system := func(name string) *osdSystem {
		if s, ok := byType[name]; ok {
			return s
		}
		s := &osdSystem{item: jsonx.Obj("type", name)}
		byType[name] = s
		order = append(order, s)
		return s
	}
	drop := func(what string) {
		if !slices.Contains(dropped, what) {
			dropped = append(dropped, what)
		}
	}
	unknown := func(v any) { drop(fmt.Sprintf("%q (no OSD system shows it)", jsonx.ToString(v))) }

	// The bars
	layout := jsonx.NewObject()
	barItems := osdV100Bars()
	if bars != nil {
		for _, k := range osdBarKeys {
			if v, ok := bars.Get(k); ok {
				layout.Set(k, v)
			}
		}
		if items, ok := bars.Value("items").(*jsonx.Array); ok {
			barItems = items
		}
	}
	for _, v := range barItems.Items {
		bar, _ := v.(*jsonx.Object)
		if bar == nil {
			continue
		}
		kind := jsonx.ToString(bar.Value("type"))
		var s *osdSystem
		switch {
		case osdAudioBars[kind]:
			s = system("Audio")
			list, _ := s.item.Value("bars").(*jsonx.Array)
			if list == nil {
				list = jsonx.Arr()
				s.item.Set("bars", list)
			}
			kept := jsonx.Obj("type", kind)
			for _, k := range []string{"apps", "icon", "showOsd"} {
				if v, ok := bar.Get(k); ok {
					kept.Set(k, v)
				}
			}
			list.Append(kept)
		case kind == "brightness":
			if _, ok := byType["Brightness"]; ok {
				drop("a second brightness bar (Brightness is one item)")
				continue
			}
			s = system("Brightness")
			for _, k := range []string{"allMonitors", "icon", "showOsd"} {
				if v, ok := bar.Get(k); ok {
					s.item.Set(k, v)
				}
			}
		default:
			unknown(bar.Value("type"))
			continue
		}
		s.keys++
		if bar.Value("showOsd") == false {
			s.quiet++
		}
	}

	// The status icons
	shown := osdV100Statuses
	var quiet []any
	if statuses != nil {
		if items, ok := statuses.Value("items").(*jsonx.Array); ok {
			shown = nil
			for _, v := range items.Items {
				shown = append(shown, jsonx.ToString(v))
			}
		}
		if q, _ := statuses.Value("quiet").(*jsonx.Array); q != nil {
			quiet = q.Items
		}
	}
	picked := map[string][]string{}
	seen := map[string]bool{}
	for _, kind := range shown {
		to, ok := osdStatusSystems[kind]
		if !ok {
			unknown(kind)
			continue
		}
		if seen[kind] {
			continue
		}
		seen[kind] = true
		s := system(to[0])
		if to[1] != "" {
			picked[to[0]] = append(picked[to[0]], kind)
		}
		s.keys++
		if slices.Contains(quiet, any(kind)) {
			s.quiet++
		}
	}
	for name, kinds := range picked {
		list := jsonx.Arr()
		for _, kind := range osdSubsetOrder[name] {
			if slices.Contains(kinds, kind) {
				list.Append(kind)
			}
		}
		byType[name].item.Set(osdStatusSystems[kinds[0]][1], list)
	}
	if audio, ok := byType["Audio"]; ok {
		if !audio.item.Has("bars") {
			audio.item.Set("bars", jsonx.Arr())
		}
		if !audio.item.Has("tiles") {
			audio.item.Set("tiles", jsonx.Arr())
		}
	}

	// The cards
	cardTypes := osdV100Cards
	if cards != nil {
		if items, ok := cards.Value("items").(*jsonx.Array); ok {
			cardTypes = nil
			for _, v := range items.Items {
				cardTypes = append(cardTypes, jsonx.ToString(v))
			}
		}
	}
	for _, kind := range cardTypes {
		name, ok := osdCardSystems[kind]
		if !ok {
			unknown(kind)
			continue
		}
		s := system(name)
		if name == "Media" && cards != nil {
			for _, k := range []string{"onTrackChange", "onPlayPause"} {
				if v, ok := cards.Get(k); ok {
					s.item.Set(k, v)
				}
			}
		}
	}

	systems := jsonx.Arr()
	for _, s := range order {
		if s.keys > 0 && s.quiet == s.keys {
			s.item.Set("quiet", true)
		}
		systems.Append(s.item)
	}

	// The entry's own keys, the old parts' places taken by the new ones
	if layout.Len() > 0 {
		entry.Set("barLayout", layout)
	}
	if statuses != nil {
		if v, ok := statuses.Get("row"); ok {
			entry.Set("row", v)
		}
	}
	if cards != nil {
		if v, ok := cards.Get("enabled"); ok {
			entry.Set("cardsEnabled", v)
		}
		if v, ok := cards.Get("timeout"); ok {
			entry.Set("cardTimeout", v)
		}
	}
	entry.Set("systems", systems)
	entry.Delete("bars")
	entry.Delete("statuses")
	entry.Delete("cards")
	return dropped
}
