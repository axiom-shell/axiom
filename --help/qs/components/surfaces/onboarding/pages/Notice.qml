pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.components.reusable

// A highlighted note: an icon and wrapped text, tinted by `tone`
// ("info" | "warning" | "error" | "success")
Rectangle {
  id: root

  property string tone: "info"
  property string icon: ({
      "warning": "warning",
      "error": "error",
      "success": "check_circle"
    })[root.tone] ?? "info"
  property string text
  readonly property color toneColor: ({
      "warning": Theme.warning,
      "error": Theme.error,
      "success": Theme.success
    })[root.tone] ?? Theme.info

  Layout.fillWidth: true
  implicitHeight: row.implicitHeight + Widget.padding * 1.5
  radius: Widget.radius
  color: Qt.alpha(root.toneColor, 0.12)
  border.color: root.toneColor
  border.width: Appearance.borderWidth

  RowLayout {
    id: row
    anchors.fill: parent
    anchors.margins: Widget.padding * 0.75
    spacing: Widget.spacing * 1.5

    StyledIcon {
      Layout.alignment: Qt.AlignTop
      text: root.icon
      textColor: root.toneColor
      textSize: Appearance.fontSize * 1.3
    }

    StyledText {
      Layout.fillWidth: true
      text: root.text
      wrapMode: Text.WordWrap
    }
  }
}
