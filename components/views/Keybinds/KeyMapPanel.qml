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

  readonly property var occupancy: KeyMap.occupancy(KeybindManager.binds, KeybindManager.userKeyCounts, KeybindManager.keyMapMods)

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
      KeybindManager.selectBind(held.index);
    else if (held.source === "free")
      KeybindManager.addBind({
        "key": KeyNames.join(KeybindManager.keyMapMods, key)
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

  Flow {
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    Repeater {
      model: KeyNames.modifiers

      delegate: SegmentButton {
        required property string modelData
        text: KeyNames.modifierLabel(modelData)
        active: KeybindManager.keyMapMods.includes(modelData)
        onClicked: KeybindManager.toggleKeyMapMod(modelData)
      }
    }
  }

  KeyboardMap {
    Layout.fillWidth: true
    fillOf: key => root.fill(root.held(key).source)
    inkOf: key => root.held(key).source === "axiom" || root.held(key).source === "both" ? Theme.background : Theme.foreground
    clickableOf: key => root.held(key).source !== "user"
    onClicked: key => root.pick(key)
  }

  // What the colours mean
  Flow {
    Layout.fillWidth: true
    spacing: Widget.spacing * 2

    Repeater {
      model: [["free", I18n.tr("Free")], ["axiom", I18n.tr("Axiom")], ["paused", I18n.tr("Paused")], ["user", I18n.tr("Your compositor config")], ["both", I18n.tr("Both")]]

      delegate: Row {
        id: legend
        required property var modelData
        spacing: Widget.spacing / 2

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Appearance.fontSize
          height: Appearance.fontSize
          radius: Widget.px(3)
          color: root.fill(legend.modelData[0])
          border.width: 1
          border.color: Theme.border
        }

        StyledText {
          text: legend.modelData[1]
          opacity: 0.7
          textSize: Appearance.fontSizeBy(-2)
        }
      }
    }
  }
}
