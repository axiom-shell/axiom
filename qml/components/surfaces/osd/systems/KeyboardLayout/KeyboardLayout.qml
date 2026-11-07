pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Keyboard layout on the OSD: the input source in use, by its own short
// label (a layout's code, an input method's あ) and its kind's icon;
// hidden with one source, unusual past the first. A switch is its icon;
// a changed list is a config reload, and a change just after the focused
// window changed is that window's own input method coming back (fcitx5,
// shareState off) unless axiom switched then (KeyboardLayoutWatch reads
// InputSourceManager and the focused window)
OSDSystem {
  // Only a switch from one source to another shows: none current (or the
  // list appearing) is nothing, and the label read again for the same
  // source isn't a change of its look
  onAdd: "none"
  onRemove: "none"
  updateFields: []
  resetBy: ["ids"]
  ignoreWithin: ({
      "after": "focusedAt",
      "ms": 1000,
      "unlessAfter": "switchedAt"
    })

  // I18n.tr("Keyboard layout")
  exposes: [
    {
      "key": "keyboardLayout",
      "part": "tile",
      "icon": "keyboard",
      "label": "Keyboard layout",
      "action": "inputSourceNext"
    }
  ]

  // state: { ids, value (the source in use, "" for none), label, icon,
  // focusedAt, switchedAt }; lit always (the label tells it)
  function tile(key, state) {
    const ids = state?.ids ?? [];
    const value = state?.value ?? "";
    const out = {
      "label": String(state?.label ?? ""),
      "on": true,
      "notable": ids.length > 0 && value !== "" && value !== ids[0],
      "hidden": ids.length < 2
    };
    if (state?.icon)
      out.icon = state.icon;
    return out;
  }
}
