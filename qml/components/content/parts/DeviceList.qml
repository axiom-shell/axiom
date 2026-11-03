pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A radio menu's list of devices or networks (Wi-Fi, Bluetooth). In a
// popout it's as high as its rows (off, its message; empty, one row) up to
// `visibleRows`, then it scrolls: the popout grows away from
// its controls (Panel.growth), and its content declares `growRoom` in its
// maxImplicitHeight. In a card it fills the height. Off, a message takes
// the list's place. Rows are `delegate`s (DeviceRows, with `required
// property int index`), modelled by `count` so they survive the list being
// re-evaluated.
Item {
  id: root

  property bool embedded: false
  // Off: the message shows instead of the list
  property bool on: true
  property string offIcon: ""
  property string offMessage: ""
  property string emptyText: ""
  property int count: 0
  property Component delegate
  property int visibleRows: 5
  // What the list is short of (or, negative, has to spare) to show every
  // row; off, all of it is spare. For a card that grows (wantedHeight)
  readonly property real overflow: scroll.height <= 0 ? 0 : root.on ? list.implicitHeight - scroll.height : -scroll.height

  // One row's height (DeviceRow.rowHeight): its two lines, or a button
  readonly property real rowHeight: Math.max(titleMetrics.height + statusMetrics.height, Widget.iconButton) + Widget.spacing * 2
  function rowsHeight(rows) {
    return root.rowHeight * rows + list.spacing * (rows - 1);
  }
  readonly property real listHeight: root.rowsHeight(root.visibleRows)
  // In a popout: its rows, up to visibleRows; off, its message; empty, a row
  readonly property real shownHeight: !root.on ? offState.implicitHeight : Math.max(root.rowHeight, Math.min(list.implicitHeight, root.listHeight))
  // How much taller it can grow in a popout (for Panel.maxImplicitHeight)
  readonly property real growRoom: root.embedded ? 0 : root.listHeight - root.shownHeight

  // Fades the rows in, e.g. on a tab switch
  function fadeIn() {
    fade.restart();
  }

  Layout.fillWidth: true
  Layout.preferredHeight: root.embedded ? -1 : root.shownHeight
  Layout.fillHeight: root.embedded

  FontMetrics {
    id: titleMetrics
    font.family: Appearance.fontFamily
    font.pixelSize: Appearance.fontSizeBy(-1)
  }
  FontMetrics {
    id: statusMetrics
    font.family: Appearance.fontFamily
    font.pixelSize: Appearance.fontSizeBy(-3)
  }

  EmptyState {
    id: offState
    visible: !root.on
    anchors.centerIn: parent
    maxWidth: parent.width
    icon: root.offIcon
    text: root.offMessage
  }

  StyledScrollView {
    id: scroll
    visible: root.on
    anchors.fill: parent
    contentPadding: 0
    showScrollBar: list.implicitHeight > scroll.height

    // A ListView, so only the rows in view are built: Wi-Fi can see
    // dozens of networks, and a row is a few dozen items
    ListView {
      id: list
      implicitHeight: list.contentHeight
      spacing: 2
      boundsBehavior: Flickable.StopAtBounds
      model: root.count
      delegate: root.delegate

      NumberAnimation on opacity {
        id: fade
        from: 0
        to: 1
        duration: Appearance.animNormal
      }
    }
  }

  StyledText {
    anchors.fill: parent
    visible: root.on && root.count === 0
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    wrapMode: Text.WordWrap
    text: root.emptyText
    textColor: Theme.foregroundAlt
  }
}
