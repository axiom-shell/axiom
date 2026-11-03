pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.components.reusable

// A combo's modifiers in one keycap: as glyphs (Super as an icon, ⌃ ⌥ ⇧),
// or as words with `glyphs` off
Rectangle {
  id: root

  required property var mods
  property bool glyphs: true
  property bool compact: false

  readonly property real textSize: Appearance.fontSize - (root.compact ? 2 : 1)

  visible: root.mods.length > 0
  implicitHeight: Math.round(Widget.height * (root.compact ? 0.62 : 0.75))
  implicitWidth: Math.max(implicitHeight, content.implicitWidth + Widget.padding)
  radius: Widget.radius / 2
  color: Theme.backgroundHighlight

  Row {
    id: content
    anchors.centerIn: parent
    spacing: root.glyphs ? Widget.spacing / 2 : Widget.spacing

    Repeater {
      model: root.mods

      delegate: Item {
        id: mod
        required property string modelData
        readonly property string glyph: root.glyphs ? KeyNames.modifierGlyph(mod.modelData) : ""
        readonly property bool asIcon: root.glyphs && mod.modelData === "SUPER"
        anchors.verticalCenter: parent?.verticalCenter
        implicitWidth: mod.asIcon ? icon.implicitWidth : label.implicitWidth
        implicitHeight: Math.max(icon.implicitHeight, label.implicitHeight)

        StyledIcon {
          id: icon
          visible: mod.asIcon
          anchors.centerIn: parent
          text: "keyboard_command_key"
          textSize: root.textSize
        }

        StyledText {
          id: label
          visible: !mod.asIcon
          anchors.centerIn: parent
          text: mod.glyph !== "" ? mod.glyph : KeyNames.modifierLabel(mod.modelData)
          textSize: root.textSize
        }
      }
    }
  }
}
