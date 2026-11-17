pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A status callout: an icon, a title, wrapped text and optional small
// buttons, on the status's container fill: `actionText` is one (`triggered`),
// `actions` (the default slot) holds any more. `enabled: false` disables the
// buttons. `clickable` makes the whole callout press (`clicked`), under its
// buttons, and draws a trailing chevron saying it opens something. `spinning`
// turns the icon (a build, a scan). The buttons sit beside the text, or under
// it, left-aligned with it, once they need more than a third of the width
// (decided from their width and the callout's, never from heights).
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
  // The icon turns (a busy mark)
  property bool spinning: false
  // More buttons, after the text
  default property alias actions: actionRow.data

  signal clicked

  Layout.fillWidth: true
  tone: root.status + "Container"
  outlined: true
  // Whether there are buttons at all, and whether they need more than a
  // third of the width (their implicit width and `width` only)
  readonly property bool hasActions: root.actionText !== "" || actionRow.children.length > 0
  readonly property bool actionsBelow: root.hasActions && actionBox.implicitWidth > root.width / 3
  implicitHeight: row.implicitHeight + Widget.padding

  Pressable {
    enabled: root.clickable
    tabStop: root.clickable
    onClicked: root.clicked()
  }

  RowLayout {
    id: row
    anchors.fill: parent
    anchors.leftMargin: Widget.padding
    anchors.rightMargin: root.hasActions && !root.actionsBelow ? Widget.padding / 2 : Widget.padding
    spacing: Widget.padding

    SpinningIcon {
      Layout.alignment: Qt.AlignTop
      Layout.topMargin: Widget.padding / 2
      text: root.icon
      size: "md"
      spinning: root.spinning
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
      // The buttons, when they need room of their own
      Item {
        id: belowSlot
        Layout.fillWidth: true
        visible: root.actionsBelow
        implicitHeight: actionBox.implicitHeight
      }
    }
    // The buttons, when there is room beside the text
    Item {
      id: besideSlot
      visible: root.hasActions && !root.actionsBelow
      Layout.alignment: Qt.AlignVCenter
      implicitWidth: actionBox.implicitWidth
      implicitHeight: actionBox.implicitHeight
    }
    StyledIcon {
      visible: root.clickable
      Layout.alignment: Qt.AlignVCenter
      text: "chevron_right"
      size: "md"
      textColor: root.ink.muted
    }
  }

  // One row of buttons, moved between the two slots
  RowLayout {
    id: actionBox
    parent: root.actionsBelow ? belowSlot : besideSlot
    width: implicitWidth
    height: implicitHeight
    spacing: Widget.spacing

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
