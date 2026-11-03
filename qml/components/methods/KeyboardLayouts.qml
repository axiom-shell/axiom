pragma Singleton
import QtQuick

// A keyboard's layouts as the shell shows them ({ layouts, index, keymap },
// CompositorManager.withKeyboard), from the full names a compositor reports
// ("English (US)"): the same for every backend that only has those.
QtObject {
  id: root

  // `names` (full), the active one's `index`, and `codes` (the configured
  // xkb layouts, "us,de"), which give their short names when there are as
  // many, else each short name comes from its full one
  function shape(names, index, codes) {
    const configured = String(codes ?? "").split(",").map(code => code.trim()).filter(code => code !== "");
    const active = Number(index) || 0;
    return {
      "layouts": configured.length === names.length ? configured : names.map(name => root.code(name)),
      "index": active,
      "keymap": names[active] ?? ""
    };
  }

  // A short name for an xkb layout's full one: what its parentheses hold
  // when short ("English (US)" → "us"), else its first two letters
  function code(name) {
    const inner = /\(([^)]{1,4})\)/.exec(name ?? "");
    return (inner ? inner[1] : String(name ?? "").slice(0, 2)).toLowerCase();
  }
}
