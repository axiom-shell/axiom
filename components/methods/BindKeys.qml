pragma Singleton
import QtQuick

// Binds against what the compositor reports (CompositorManager.withBinds
// entries: { modmask, key, keycode, description, submap }, the modifiers as
// X11 mask bits, as Hyprland's `hyprctl binds -j` lists them and the daemon
// reads a sway config's): a key's id, which of axiom's binds a runtime
// layer applies and which it skips because the user's config already binds
// that key, and how many binds on each key are the user's own.
QtObject {
  id: root

  readonly property var _modBits: ({
      "SHIFT": 1,
      "CAPS": 2,
      "LOCK": 2,
      "CTRL": 4,
      "CONTROL": 4,
      "ALT": 8,
      "MOD1": 8,
      "MOD2": 16,
      "MOD3": 32,
      "SUPER": 64,
      "WIN": 64,
      "LOGO": 64,
      "MOD4": 64,
      "META": 64,
      "MOD5": 128
    })

  // "SUPER + SHIFT + SPACE" as hyprctl binds lists it ("64:space"), or ""
  function keyId(key) {
    const parts = String(key ?? "").split("+").map(part => part.trim()).filter(part => part !== "");
    if (parts.length === 0)
      return "";
    let mask = 0;
    for (const mod of parts.slice(0, -1)) {
      const bit = _modBits[mod.toUpperCase()];
      if (bit === undefined)
        return "";
      mask |= bit;
    }
    return _id(mask, parts[parts.length - 1]);
  }

  // A binds entry's id, in keyId's form (a keycode bind as code:N)
  function entryId(entry) {
    const key = entry.key || (entry.keycode ? "code:" + entry.keycode : "");
    return _id(entry.modmask, String(key));
  }

  // A modifier key on its own (a tap) leaves its own modifier out: Hyprland
  // lists SUPER + Super_L, sway Super_L
  function _id(mask, key) {
    const tap = KeyNames.tapModifier(key);
    return (tap !== "" ? mask & ~_modBits[tap] : mask) + ":" + key.toLowerCase();
  }

  /**
   * How many binds on each key id are the user's: every entry outside a
   * submap, less one for each of axiom's `applied` binds (its own binds
   * show up among the entries too).
   */
  function userKeyCounts(entries, applied) {
    const counts = {};
    for (const entry of entries ?? []) {
      if (entry.submap)
        continue;
      const id = entryId(entry);
      counts[id] = (counts[id] ?? 0) + 1;
    }
    for (const bind of applied ?? []) {
      const id = keyId(bind.key);
      if (id !== "" && counts[id])
        counts[id]--;
    }
    return counts;
  }

  /**
   * `binds` with `incoming` merged in, one bind per key: an incoming bind on
   * a key already bound replaces that bind where it stands (the user's
   * config loads after axiom's layer, so it's the one that was in effect),
   * the rest are added at the end, a later one on the same key winning.
   * Binds whose key has no id (none yet, or a bad modifier) and paused
   * ones (they hold no key) are kept as they are.
   */
  function mergeBinds(binds, incoming) {
    const result = (binds ?? []).slice();
    const at = {};
    result.forEach((bind, index) => {
      const id = bind.paused === true ? "" : keyId(bind.key);
      if (id !== "" && at[id] === undefined)
        at[id] = index;
    });
    for (const bind of incoming ?? []) {
      const id = keyId(bind.key);
      if (id !== "" && at[id] !== undefined) {
        result[at[id]] = bind;
      } else {
        if (id !== "")
          at[id] = result.length;
        result.push(bind);
      }
    }
    return result;
  }

  /**
   * `binds` with every bind given an id (the schema's ItemId: required,
   * unique in the list): a valid one not taken by an earlier bind is kept,
   * the rest get one made from the key, as the config conversion names
   * them ("SUPER + Y" → "super-y", then "super-y-2"; "bind" with no key).
   * New, duplicated, merged and preset binds come without one, or with a
   * copy of another's. Returns a new list; binds keeping theirs are the
   * same objects.
   */
  function withIds(binds) {
    const taken = {};
    const fresh = base => {
      let id = base;
      for (let n = 2; taken[id]; n++)
        id = `${base}-${n}`;
      return id;
    };
    return (binds ?? []).map(bind => {
      const own = bind?.id;
      if (typeof own === "string" && /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(own) && !taken[own]) {
        taken[own] = true;
        return bind;
      }
      const slug = String(bind?.key ?? "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 40).replace(/-+$/, "");
      const id = fresh(slug || "bind");
      taken[id] = true;
      return Object.assign({
        "id": id
      }, bind, {
        "id": id
      });
    });
  }
}
