pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// One device or network in a radio menu (DeviceList): its icon, name and
// status, a forget button on hover (for a known one; a second click within
// a few seconds forgets it) after any other `hoverActions`, and connect /
// disconnect. Clicking the row
// `activated`s it. Children go under the row, shown while `expanded` (e.g.
// a password field).
Rectangle {
  id: root

  // DeviceList.rowHeight
  required property real rowHeight
  property string icon: ""
  property string title: ""
  property string status: ""
  // The status in the error colour (e.g. a failed connection)
  property bool failed: false
  property bool connected: false
  // Saved or paired: it can be forgotten
  property bool known: false
  property bool busy: false
  // Highlighted without being connected (e.g. asking for a password)
  property bool selected: false
  property bool expanded: false
  property string connectTip: I18n.tr("Connect")
  property string disconnectTip: I18n.tr("Disconnect")
  // Beside the title (e.g. a lock)
  property alias titleExtras: titleExtrasRow.data
  // Buttons before forget, shown as it is (e.g. autoconnect); read
  // `hovered` for their opacity
  property alias hoverActions: hoverActionsRow.data
  readonly property bool hovered: rowHover.hovered
  default property alias below: belowItem.data

  property bool _confirmForget: false

  signal activated
  signal connectClicked
  signal forgetConfirmed

  // A different device in this row (the list changed under it)
  function reset() {
    root._confirmForget = false;
  }

  // A DeviceList's delegate: as wide as the list
  width: ListView.view?.width ?? implicitWidth
  implicitHeight: root.rowHeight + (root.expanded ? belowItem.childrenRect.height + Widget.spacing : 0)
  radius: Widget.radius
  color: root.connected || root.selected ? Theme.backgroundHighlight : rowHover.hovered ? Qt.alpha(Theme.backgroundHighlight, 0.5) : Qt.alpha(Theme.backgroundHighlight, 0)
  clip: true

  ColorGlide on color {}
  Glide on implicitHeight {}

  HoverHandler {
    id: rowHover
    onHoveredChanged: {
      if (!hovered)
        root._confirmForget = false;
    }
  }

  Timer {
    running: root._confirmForget
    interval: 3000
    onTriggered: root._confirmForget = false
  }

  MouseArea {
    width: parent.width
    height: root.rowHeight
    cursorShape: root.busy ? Qt.BusyCursor : Qt.PointingHandCursor
    onClicked: root.activated()
  }

  RowLayout {
    height: root.rowHeight
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Widget.padding
    anchors.rightMargin: Widget.spacing
    spacing: Widget.padding

    StyledIcon {
      Layout.preferredWidth: Widget.iconButton
      horizontalAlignment: Text.AlignHCenter
      text: root.icon
      textSize: Appearance.fontSize * 1.4
      textColor: root.connected ? Theme.accent : Theme.foregroundAlt
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0

      RowLayout {
        id: titleRow
        Layout.fillWidth: true
        spacing: Widget.spacing / 2

        StyledText {
          Layout.fillWidth: true
          text: root.title
          elide: Text.ElideRight
          textSize: Appearance.fontSizeBy(-1)
          textColor: root.connected ? Theme.foreground : Theme.foregroundAlt
        }

        RowLayout {
          id: titleExtrasRow
          spacing: Widget.spacing / 2
        }
      }
      StyledText {
        Layout.fillWidth: true
        text: root._confirmForget ? I18n.tr("Click again to forget") : root.status
        elide: Text.ElideRight
        textSize: Appearance.fontSizeBy(-3)
        textColor: root._confirmForget || root.failed ? Theme.error : root.busy || root.connected ? Theme.accent : Theme.foregroundAlt
      }
    }

    RowLayout {
      id: hoverActionsRow
      spacing: Widget.spacing / 2
    }

    // Only on hover, but always laid out so showing it moves nothing
    StyledRectButton {
      size: Widget.iconButton
      visible: root.known
      enabled: rowHover.hovered && !root.busy
      opacity: rowHover.hovered || root._confirmForget ? 1 : 0
      iconText: "delete"
      iconColor: Theme.error
      backgroundColor: Qt.alpha(Theme.error, root._confirmForget ? 0.2 : 0)
      borderHoverColor: Theme.error
      tooltipText: I18n.tr("Forget")
      onClicked: {
        if (root._confirmForget)
          root.forgetConfirmed();
        root._confirmForget = !root._confirmForget;
      }

      Glide on opacity {}
    }

    StyledRectButton {
      size: Widget.iconButton
      enabled: !root.busy
      opacity: enabled ? 1 : 0.5
      iconText: root.connected ? "link_off" : "link"
      iconColor: root.connected ? Theme.accent : Theme.foreground
      backgroundColor: "transparent"
      borderHoverColor: Theme.accent
      tooltipText: root.connected ? root.disconnectTip : root.connectTip
      onClicked: root.connectClicked()
    }
  }

  Item {
    id: belowItem
    visible: root.expanded
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: root.rowHeight
    anchors.leftMargin: Widget.padding
    anchors.rightMargin: Widget.spacing
    height: childrenRect.height
  }
}
