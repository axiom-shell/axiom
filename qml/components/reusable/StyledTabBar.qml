pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.methods

// A row of equal-width tabs (StyledTabButtons), one per label in `tabs`.
// The owner keeps the current index: set `currentIndex`, and update it
// from tabClicked. The current tab's highlight is the bar's own, sliding
// from tab to tab: a 2 px accent underline under the current tab's label,
// on a full-width baseline. `scrollable` keeps every label whole instead:
// the tabs take their own widths, packed at the start, in a row that
// scrolls sideways, the current tab kept in view.
Item {
  id: root

  property var tabs: []
  property int currentIndex: 0
  property alias spacing: row.spacing
  property bool scrollable: false

  signal tabClicked(int index)

  Layout.fillWidth: true
  Layout.fillHeight: false
  Layout.preferredHeight: Widget.height
  implicitWidth: root.scrollable ? Widget.textPx(160) : row.implicitWidth
  implicitHeight: Widget.height

  // The tab under the underline: its label's width plus a gap each side,
  // centred in its cell (null until the Repeater has built it)
  readonly property var _host: InkHost.find(root.parent)
  readonly property var _current: root.currentIndex >= 0 && root.currentIndex < tabRepeater.count ? tabRepeater.itemAt(root.currentIndex) : null
  readonly property real _markWidth: root._current ? Math.min(root._current.width, root._current.contentItem.implicitWidth + Style.space2 * 2) : 0

  // Off until laid out, so it doesn't grow in from nothing
  property bool _settled: false
  Component.onCompleted: Qt.callLater(() => {
    root._settled = true;
    root._reveal();
  })

  // Scrolls the strip so the current tab is whole in view
  function _reveal() {
    const tab = root._current;
    if (!root.scrollable || !tab)
      return;
    const max = Math.max(0, flick.contentWidth - flick.width);
    if (tab.x < flick.contentX)
      flick.contentX = Math.min(max, tab.x);
    else if (tab.x + tab.width > flick.contentX + flick.width)
      flick.contentX = Math.min(max, tab.x + tab.width - flick.width);
  }
  onCurrentIndexChanged: Qt.callLater(root._reveal)
  onScrollableChanged: Qt.callLater(root._reveal)

  // The baseline under every tab
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Style.dividerWidth
    color: root._host ? root._host.inkScope.divider : Style.divider
  }

  Flickable {
    id: flick
    anchors.fill: parent
    contentWidth: row.width
    contentHeight: height
    interactive: root.scrollable && flick.contentWidth > flick.width
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    clip: root.scrollable

    // The current tab's underline, in the content: it scrolls with its tab
    Rectangle {
      id: indicator
      visible: root._current !== null
      x: root._current ? root._current.x + (root._current.width - width) / 2 : 0
      y: flick.height - height
      width: root._markWidth
      height: Widget.px(2)
      radius: height / 2
      color: Style.accent

      Glide on x {
        enabled: root._settled
        duration: Appearance.animNormal
      }
      Glide on width {
        enabled: root._settled
        duration: Appearance.animNormal
      }
    }

    RowLayout {
      id: row
      width: root.scrollable ? row.implicitWidth : flick.width
      height: flick.height
      spacing: Widget.spacing
      uniformCellSizes: !root.scrollable

      Repeater {
        id: tabRepeater
        model: root.tabs

        StyledTabButton {
          required property int index
          required property string modelData
          leftPadding: root.scrollable ? Style.space3 : undefined
          rightPadding: root.scrollable ? Style.space3 : undefined
          Layout.fillWidth: !root.scrollable
          text: modelData
          checked: root.currentIndex === index
          onClicked: root.tabClicked(index)
        }
      }
    }
  }
}
