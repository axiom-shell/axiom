pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.components.reusable

// An OSD's status: one line, its icon and what changed ("Caps Lock on",
// a layout's or device's name, a message), as tall as a horizontal level
// bar. A new line cross-fades over the old.
Item {
  id: root

  // { type, icon, text } (OSDStatusSource.fired, or a message)
  property var line: ({
      "type": "",
      "icon": "",
      "text": ""
    })

  implicitWidth: Math.max(Widget.px(160), row.implicitWidth + Widget.spacing * 4)
  implicitHeight: Widget.px(48)

  RowLayout {
    id: row
    anchors.centerIn: parent
    spacing: Widget.spacing * 2

    CrossFade {
      Layout.alignment: Qt.AlignVCenter
      value: root.line.icon
      visible: root.line.icon !== ""
      delegate: StyledIcon {
        required property var value
        text: value
        textSize: Appearance.fontSizeBy(10)
      }
    }

    StyledText {
      Layout.alignment: Qt.AlignVCenter
      Layout.maximumWidth: Widget.px(320)
      text: root.line.text
      textSize: Appearance.fontSizeLarge
      elide: Text.ElideRight
      maximumLineCount: 1
    }
  }
}
