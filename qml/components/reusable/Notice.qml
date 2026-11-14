pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A status callout: an icon, a title, wrapped text and an optional small
// button, on the status's container fill. `enabled: false` disables the button.
Surface {
  id: root

  signal triggered

  // -- Public API --
  // info | success | warning | error | accent
  property string status: "info"
  // A Material Symbols name (by default the status's)
  property string icon: ({
      "warning": "warning",
      "error": "error",
      "success": "check_circle"
    })[root.status] ?? "info"
  property string title: ""
  property string text: ""
  // The button's label; no button while empty
  property string actionText: ""

  Layout.fillWidth: true
  tone: root.status + "Container"
  outlined: true
  implicitHeight: row.implicitHeight + Widget.padding

  RowLayout {
    id: row
    anchors.fill: parent
    anchors.leftMargin: Widget.padding
    anchors.rightMargin: root.actionText !== "" ? Widget.padding / 2 : Widget.padding
    spacing: Widget.padding

    StyledIcon {
      Layout.alignment: Qt.AlignTop
      Layout.topMargin: Widget.padding / 2
      text: root.icon
      size: "md"
      textColor: root.ink.icon
    }
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0
      StyledLabel {
        Layout.fillWidth: true
        visible: root.title !== ""
        text: root.title
        role: "caption"
        font.weight: Style.weightStrong
        overflow: "wrap"
        textColor: root.ink.text
      }
      StyledLabel {
        Layout.fillWidth: true
        visible: root.text !== ""
        text: root.text
        role: root.title !== "" ? "micro" : "caption"
        overflow: "wrap"
        textColor: root.title !== "" ? root.ink.muted : root.ink.text
      }
    }
    StyledTextButton {
      visible: root.actionText !== ""
      text: root.actionText
      kind: "text"
      textSize: Style.typeCaption
      textPadding: Widget.smallPadding
      onClicked: root.triggered()
    }
  }
}
