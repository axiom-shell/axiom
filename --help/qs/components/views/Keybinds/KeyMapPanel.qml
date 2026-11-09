pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.components.methods
import qs.components.reusable
import qs.components.content.parts

// The Keybinds editor's key map, shown while no bind is selected: a
// keyboard (KeyMap) under the modifiers picked, each key coloured by who
// holds it (KeyMap.occupancy). A free key starts a bind on it, an axiom
// key selects its bind.
ColumnLayout {
  id: root

  readonly property var occupancy: KeyMap.occupancy(KeybindManager.editor.keyMapBinds, KeybindManager.userKeyCounts, KeybindManager.page.keyMapMods)

  spacing: Widget.spacing * 1.5

  function held(key) {
    return root.occupancy[key] ?? {
      "source": "free",
      "index": -1
    };
  }

  function pick(key) {
    const held = root.held(key);
    if (held.index >= 0)
      KeybindManager.editor.editBind(held.index);
    else if (held.source === "free")
      KeybindManager.editor.addBind({
        "key": KeyNames.join(KeybindManager.page.keyMapMods, key)
      });
  }

  function fill(source) {
    switch (source) {
    case "axiom":
      return Theme.accent;
    case "both":
      return Theme.error;
    case "paused":
      return Qt.alpha(Theme.accent, 0.3);
    case "user":
      return Qt.alpha(Theme.warning, 0.7);
    }
    return Theme.backgroundAlt;
  }

  SectionHeading {
    title: I18n.tr("Free keys")
    description: I18n.tr("Pick the modifiers to look under. Click a free key to bind it, or one of axiom's to edit its bind.")
  }

  KeyboardMap {
    Layout.fillWidth: true
    showMods: true
    mods: KeybindManager.page.keyMapMods
    sourceOf: key => root.held(key).source
    fillFor: source => root.fill(source)
    legend: [["free", I18n.tr("Free")], ["axiom", I18n.tr("Axiom")], ["paused", I18n.tr("Paused or not bound now")], ["user", I18n.tr("Your compositor config")], ["both", I18n.tr("Both")]]
    clickableOf: key => root.held(key).source !== "user"
    onClicked: key => root.pick(key)
  }
}
