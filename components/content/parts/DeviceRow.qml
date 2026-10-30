pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// One device or network in a radio menu (DeviceList): its icon (with an
// optional badge on its corner, e.g. a lock), name and status, and connect
// / disconnect. On hover, any `hoverActions` and a forget button (for a
// known one; a second click within a few seconds forgets it) show over the
// end of the name, so every row lays out alike. Clicking the row
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
  // A small icon on the icon's bottom-right corner (e.g. "lock")
  property string iconBadge: ""
  // Buttons before forget, shown with it on hover (e.g. autoconnect)
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
      id: mainIcon
      Layout.preferredWidth: Widget.iconButton
      horizontalAlignment: Text.AlignHCenter
      text: root.icon
      textSize: Appearance.fontSize * 1.4
      textColor: root.connected ? Theme.accent : Theme.foregroundAlt

      // On the glyph's bottom-right corner
      StyledIcon {
        visible: root.iconBadge !== ""
        x: Math.round((mainIcon.width + mainIcon.contentWidth) / 2 - width * 0.7)
        y: Math.round((mainIcon.height + mainIcon.contentHeight) / 2 - height * 0.85)
        text: root.iconBadge
        fill: 1
        textSize: Appearance.fontSizeBy(-4)
        textColor: mainIcon.textColor
      }
    }

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      ColumnLayout {
        anchors.left: parent.left
        anchors.right: actions.shown ? actions.left : parent.right
        anchors.rightMargin: actions.shown ? Widget.spacing : 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        StyledText {
          Layout.fillWidth: true
          text: root.title
          elide: Text.ElideRight
          textSize: Appearance.fontSizeBy(-1)
          textColor: root.connected ? Theme.foreground : Theme.foregroundAlt
        }
        StyledText {
          Layout.fillWidth: true
          text: root._confirmForget ? I18n.tr("Click again to forget") : root.status
          elide: Text.ElideRight
          textSize: Appearance.fontSizeBy(-3)
          textColor: root._confirmForget || root.failed ? Theme.error : root.busy || root.connected ? Theme.accent : Theme.foregroundAlt
        }
      }

      // Over the end of the name while hovered: laid out by no row, so
      // every row's icons and buttons line up
      RowLayout {
        id: actions
        readonly property bool shown: (rowHover.hovered || root._confirmForget) && (root.known || hoverActionsRow.implicitWidth > 0)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Widget.spacing / 2
        opacity: actions.shown ? 1 : 0

        Glide on opacity {}

        RowLayout {
          id: hoverActionsRow
          spacing: Widget.spacing / 2
        }

        StyledRectButton {
          size: Widget.iconButton
          visible: root.known
          enabled: rowHover.hovered && !root.busy
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
        }
      }
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
