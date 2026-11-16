pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// One entry in a module's list (clipboard clips, calculator answers,
// recordings): an icon or a rounded thumbnail, a title and a muted
// subtitle, a faint `detail` on the right (a value), and buttons after it
// (children), faint until the row is hovered or one has focus so showing them moves
// nothing. Clicking the row `activated`s it, unless it isn't `clickable`.
// The name shows whole in a tooltip while it is cut.
Item {
  id: root

  property string icon: ""
  // An image url: a thumbnail in place of the icon
  property string image: ""
  property string title: ""
  property string subtitle: ""
  // Title lines before it elides
  property int titleLines: 1
  // Marked (e.g. pinned): the icon in the accent
  property bool marked: false
  // A done task, not a disabled one: title, subtitle and icon go faint
  property bool dimmed: false
  property color iconColor: root.dimmed ? Style.textFaint : root.marked ? Style.accent : Style.textMuted
  property string detail: ""
  property bool clickable: true
  readonly property bool hovered: rowHover.hovered
  // Whether the actions show: hovered, or one of them focused
  readonly property bool revealed: root.hovered || root._actionFocused
  default property alias actions: actionRow.data

  readonly property bool _actionFocused: Array.prototype.some.call(actionRow.children, child => child.activeFocus)

  signal activated

  Layout.fillWidth: true
  implicitHeight: Math.max(content.implicitHeight, Appearance.fontSize * 2) + Widget.spacing * 2

  StateLayer {
    anchors.fill: parent
    radius: Style.radius
    hovered: rowHover.hovered && (root.clickable || actionRow.children.length > 0)
  }

  HoverHandler {
    id: rowHover
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.clickable
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }

  RowLayout {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Widget.spacing
    anchors.rightMargin: Widget.spacing / 2
    spacing: Widget.spacing

    StyledIcon {
      visible: root.image === "" && root.icon !== ""
      Layout.preferredWidth: Appearance.fontSize * 1.5
      horizontalAlignment: Text.AlignHCenter
      text: root.icon
      size: "md"
      textColor: root.iconColor
    }

    Thumbnail {
      visible: root.image !== ""
      Layout.preferredWidth: Appearance.fontSize * 3
      Layout.preferredHeight: Appearance.fontSize * 2
      source: root.image
      decodeSize: Qt.size(Appearance.fontSize * 6, 0)
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0

      StyledLabel {
        id: titleText
        Layout.fillWidth: true
        role: "label"
        tone: root.dimmed ? "faint" : ""
        overflow: root.titleLines > 1 ? "wrap" : "line"
        maxLines: root.titleLines
        text: root.title

        HoverHandler {
          id: titleHover
        }
      }
      StyledLabel {
        visible: root.subtitle !== ""
        Layout.fillWidth: true
        role: "caption"
        tone: root.dimmed ? "faint" : ""
        overflow: "line"
        text: root.subtitle
      }
    }

    StyledLabel {
      visible: root.detail !== ""
      role: "micro"
      tone: "faint"
      text: root.detail
    }

    RowLayout {
      id: actionRow
      spacing: 0
      // Never disabled: a hidden action must be able to take the focus that reveals it
      opacity: root.revealed ? 1 : 0

      Glide on opacity {}
    }
  }

  TruncationTip {
    target: titleText
    text: root.title
    hovered: titleHover.hovered
    maxWidth: Widget.textPx(320)
  }
}
