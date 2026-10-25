pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.components.methods
import qs.components.reusable

// The keybinds reference as a keyboard: under the modifiers picked
// (`mods`), each key
// shows what it does (KeyMap.labels), coloured by whose bind it is. A click
// on one of axiom's opens it in the editor.
ColumnLayout {
  id: root

  // KeybindManager.keybindings, or some of them
  required property var sections
  // The modifiers held, and chips to change them (the page's, shared with
  // the editor's key map); a Cheatsheet passes its own without chips
  property var mods: KeybindManager.keyMapMods
  property bool showMods: true

  readonly property var labels: KeyMap.labels(root.sections, root.mods)

  spacing: Widget.spacing * 1.5

  signal editRequested(int bindIndex)

  function fill(source) {
    switch (source) {
    case "axiom":
      return Theme.accent;
    case "both":
      return Qt.alpha(Theme.accent, 0.6);
    case "user":
      return Qt.alpha(Theme.warning, 0.7);
    }
    return Theme.backgroundAlt;
  }

  function _ink(key) {
    const source = root.labels[key]?.source;
    return source === "axiom" || source === "both" ? Theme.background : Theme.foreground;
  }

  Flow {
    visible: root.showMods
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    Repeater {
      model: KeyNames.modifiers

      delegate: SegmentButton {
        required property string modelData
        text: KeyNames.modifierLabel(modelData)
        active: root.mods.includes(modelData)
        onClicked: KeybindManager.toggleKeyMapMod(modelData)
      }
    }
  }

  KeyboardMap {
    Layout.fillWidth: true
    tall: true
    fillOf: key => root.fill(root.labels[key]?.source)
    inkOf: key => root._ink(key)
    labelOf: key => root.labels[key]?.label ?? ""
    iconOf: key => root.labels[key]?.action ? KeybindManager.actionIcon(root.labels[key].action) : ""
    clickableOf: key => KeybindManager.bindIndexFor(root.labels[key]?.ids ?? []) >= 0
    onClicked: key => root.editRequested(KeybindManager.bindIndexFor(root.labels[key].ids))
  }

  // What the colours mean
  Row {
    Layout.alignment: Qt.AlignHCenter
    spacing: Widget.spacing * 2

    Repeater {
      model: [["free", I18n.tr("Free")], ["axiom", I18n.tr("Axiom")], ["user", I18n.tr("Your compositor config")], ["both", I18n.tr("Both")]]

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
