package render

import (
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// --- KeyNames: keys as Hyprland writes them ("SUPER + SHIFT + space") ---

// Other spellings Hyprland accepts, by axiom's name
var modAliases = map[string]string{"WIN": "SUPER", "LOGO": "SUPER", "MOD4": "SUPER", "META": "SUPER", "CONTROL": "CTRL", "MOD1": "ALT"}

// Modifier keys a bind can be on by themselves (a tap), by keysym
var tapKeys = map[string]string{"super_l": "SUPER", "super_r": "SUPER", "control_l": "CTRL", "control_r": "CTRL",
	"alt_l": "ALT", "alt_r": "ALT", "shift_l": "SHIFT", "shift_r": "SHIFT"}

// Combo is a key combo split: its modifiers (axiom's names) and key.
type Combo struct {
	Mods []string
	Key  string
}

// SplitKey is KeyNames.split: "SUPER + SHIFT + space" as its modifiers and
// key.
func SplitKey(combo any) Combo {
	var parts []string
	for _, p := range strings.Split(str(or(combo, "")), "+") {
		if p = trim(p); p != "" {
			parts = append(parts, p)
		}
	}
	if len(parts) == 0 {
		return Combo{Mods: []string{}}
	}
	mods := make([]string, 0, len(parts)-1)
	for _, m := range parts[:len(parts)-1] {
		up := strings.ToUpper(m)
		if alias, ok := modAliases[up]; ok {
			up = alias
		}
		mods = append(mods, up)
	}
	return Combo{Mods: mods, Key: parts[len(parts)-1]}
}

func (c Combo) json() *jsonx.Object {
	return jsonx.Obj("mods", strs(c.Mods), "key", c.Key)
}

// JoinKey is KeyNames.join.
func JoinKey(mods []string, key string) string {
	return strings.Join(append(append([]string(nil), mods...), key), " + ")
}

// TapModifier is KeyNames.tapModifier: the modifier a combo taps ("Super_L"
// → "SUPER"), or "" when it isn't a tap. Its own modifier may be written too.
func TapModifier(combo any) string {
	c := SplitKey(combo)
	mod := tapKeys[strings.ToLower(c.Key)]
	for _, held := range c.Mods {
		if held != mod {
			return ""
		}
	}
	return mod
}

// --- BindKeys: binds against what the compositor reports ---

var modBits = map[string]int{"SHIFT": 1, "CAPS": 2, "LOCK": 2, "CTRL": 4, "CONTROL": 4, "ALT": 8, "MOD1": 8, "MOD2": 16,
	"MOD3": 32, "SUPER": 64, "WIN": 64, "LOGO": 64, "MOD4": 64, "META": 64, "MOD5": 128}

// KeyID is BindKeys.keyId: "SUPER + SHIFT + SPACE" as hyprctl binds lists it
// ("65:space"), or "".
func KeyID(key any) string {
	var parts []string
	for _, p := range strings.Split(str(or(key, "")), "+") {
		if p = trim(p); p != "" {
			parts = append(parts, p)
		}
	}
	if len(parts) == 0 {
		return ""
	}
	mask := 0
	for _, m := range parts[:len(parts)-1] {
		bit, ok := modBits[strings.ToUpper(m)]
		if !ok {
			return ""
		}
		mask |= bit
	}
	return keyIDOf(float64(mask), parts[len(parts)-1])
}

// EntryID is BindKeys.entryId: a binds entry's id in KeyID's form.
func EntryID(entry any) string {
	key := get(entry, "key")
	if !truthy(key) {
		key = ""
		if kc := get(entry, "keycode"); truthy(kc) {
			key = "code:" + str(kc)
		}
	}
	return keyIDOf(get(entry, "modmask"), str(key))
}

// A modifier key on its own (a tap) leaves its own modifier out: Hyprland
// lists SUPER + Super_L, sway Super_L
func keyIDOf(mask any, key string) string {
	if tap := TapModifier(key); tap != "" {
		return fmtNum(float64(int32(num(mask))&^int32(modBits[tap]))) + ":" + strings.ToLower(key)
	}
	if mask == nil {
		return "undefined:" + strings.ToLower(key)
	}
	return str(mask) + ":" + strings.ToLower(key)
}

// RuntimeBinds is BindKeys.runtimeBinds: what a runtime layer does with
// axiom's binds given the compositor's entries: { apply, skipped,
// unreadable }.
func RuntimeBinds(binds, entries any) *jsonx.Object {
	taken := map[string]bool{}
	for _, e := range items(entries) {
		if !truthy(get(e, "submap")) {
			taken[EntryID(e)] = true
		}
	}
	apply, skipped, unreadable := jsonx.Arr(), jsonx.Arr(), jsonx.Arr()
	for _, b := range items(binds) {
		id := KeyID(get(b, "key"))
		switch {
		case id == "":
			unreadable.Append(str(or(get(b, "key"), "")))
		case taken[id]:
			skipped.Append(trim(str(get(b, "key"))))
		default:
			apply.Append(b)
		}
	}
	return jsonx.Obj("apply", apply, "skipped", skipped, "unreadable", unreadable)
}

// MergeBinds is BindKeys.mergeBinds: binds with incoming merged in, one bind
// per key, an incoming bind replacing the one on its key where it stands.
func MergeBinds(binds, incoming any) *jsonx.Array {
	result := jsonx.Arr(items(binds)...)
	at := map[string]int{}
	for i, b := range result.Items {
		id := ""
		if !isTrue(get(b, "paused")) {
			id = KeyID(get(b, "key"))
		}
		if _, seen := at[id]; id != "" && !seen {
			at[id] = i
		}
	}
	for _, b := range items(incoming) {
		id := KeyID(get(b, "key"))
		if i, ok := at[id]; id != "" && ok {
			result.Items[i] = b
			continue
		}
		if id != "" {
			at[id] = len(result.Items)
		}
		result.Append(b)
	}
	return result
}
