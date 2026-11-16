pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.components.reusable
import qs.config

// The foot of a modal's card (the prompt, the polkit prompt, the
// screen-share picker): the key hints on the left, the buttons (the default
// slot) on the right. `hints` is [{ key, label }, ...], labels already
// translated.
RowLayout {
  id: root

  property var hints: []
  default property alias buttons: buttonRow.data

  spacing: Widget.spacing

  Flow {
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignVCenter
    spacing: Widget.padding

    Repeater {
      model: root.hints

      KeyHint {
        required property var modelData
        key: modelData.key
        label: modelData.label
      }
    }
  }

  RowLayout {
    id: buttonRow
    spacing: Widget.spacing
  }
}
