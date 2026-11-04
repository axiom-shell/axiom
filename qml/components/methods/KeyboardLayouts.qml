pragma Singleton
import QtQuick

// A keyboard's layouts as the shell shows them ({ layouts, index, keymap },
// CompositorManager.withKeyboard), from the full names a compositor reports
// ("English (US)"): the same for every backend that only has those. Their
// codes come from the xkb registry when it's handed in.
QtObject {
  id: root

  // `names` (full), the active one's `index`, and `codes` (the configured
  // xkb layouts, "us,de"), which give their short names when there are as
  // many, else each short name comes from its full one (code, through
  // `registry`)
  function shape(names, index, codes, registry) {
    const configured = String(codes ?? "").split(",").map(code => code.trim()).filter(code => code !== "");
    const active = Number(index) || 0;
    return {
      "layouts": configured.length === names.length ? configured : names.map(name => root.code(name, registry)),
      "index": active,
      "keymap": names[active] ?? ""
    };
  }

  // A short name for an xkb layout's full one: the layout the xkb registry
  // (the daemon's input.layouts, { layouts: [{ name, description,
  // variants: [{ description }] }] }, or null) gives that name, a variant's
  // name its layout ("German (Neo 2)" → "de"); without one listed, what its
  // parentheses hold when short ("English (US)" → "us"), else its first
  // two letters
  function code(name, registry) {
    for (const layout of registry?.layouts ?? [])
      if (layout?.description === name || (layout?.variants ?? []).some(v => v?.description === name))
        return layout.name;
    const inner = /\(([^)]{1,4})\)/.exec(name ?? "");
    return (inner ? inner[1] : String(name ?? "").slice(0, 2)).toLowerCase();
  }
}
