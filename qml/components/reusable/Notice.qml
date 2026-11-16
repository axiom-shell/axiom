pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A status callout: an icon, a title, wrapped text and optional small
// buttons, on the status's container fill: `actionText` is one (`triggered`),
// `actions` (the default slot) holds any more. `enabled: false` disables the
// buttons. `clickable` makes the whole callout press (`clicked`), under its
// buttons.
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
  // The whole callout is a button (a banner opening what it says)
  property bool clickable: false
  // More buttons, after the text
  default property alias actions: actionRow.data

  signal clicked

  Layout.fillWidth: true
  tone: root.status + "Container"
  outlined: true
  implicitHeight: row.implicitHeight + Widget.padding

  // Until Pressable lands (wave 3) the callout's own press and tint
  StateLayer {
    visible: root.clickable
    hovered: press.containsMouse
    pressed: press.pressed
  }

  MouseArea {
    id: press
    anchors.fill: parent
    enabled: root.clickable
    hoverEnabled: true
    cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }

  RowLayout {
    id: row
    anchors.fill: parent
    anchors.leftMargin: Widget.padding
    anchors.rightMargin: root.actionText !== "" || actionRow.children.length > 0 ? Widget.padding / 2 : Widget.padding
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
    RowLayout {
      id: actionRow
      visible: children.length > 0
      spacing: Widget.spacing
    }
  }
}
