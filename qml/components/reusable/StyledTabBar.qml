pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.methods

// A row of equal-width tabs (StyledTabButtons), one per label in `tabs`.
// The owner keeps the current index: set `currentIndex`, and update it
// from tabClicked. The current tab's highlight is the bar's own, sliding
// from tab to tab: a 2 px accent underline under the current tab's label,
// on a full-width baseline.
Item {
  id: root

  property var tabs: []
  property int currentIndex: 0
  property alias spacing: row.spacing

  signal tabClicked(int index)

  Layout.fillWidth: true
  Layout.fillHeight: false
  Layout.preferredHeight: Widget.height
  implicitWidth: row.implicitWidth
  implicitHeight: Widget.height

  // The tab under the underline: its label's width plus a gap each side,
  // centred in its cell (null until the Repeater has built it)
  readonly property var _host: InkHost.find(root.parent)
  readonly property var _current: root.currentIndex >= 0 && root.currentIndex < tabRepeater.count ? tabRepeater.itemAt(root.currentIndex) : null
  readonly property real _markWidth: root._current ? Math.min(root._current.width, root._current.contentItem.implicitWidth + Style.space2 * 2) : 0

  // Off until laid out, so it doesn't grow in from nothing
  property bool _settled: false
  Component.onCompleted: Qt.callLater(() => root._settled = true)

  // The baseline under every tab
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Style.dividerWidth
    color: root._host ? root._host.inkScope.divider : Style.divider
  }

  // x centres on the target width (_markWidth), never the gliding width, so the two glides never chase each other
  Rectangle {
    id: indicator
    visible: root._current !== null
    x: root._current ? root._current.x + (root._current.width - root._markWidth) / 2 : 0
    y: parent.height - height
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
    anchors.fill: parent
    spacing: Widget.spacing
    uniformCellSizes: true

    Repeater {
      id: tabRepeater
      model: root.tabs

      StyledTabButton {
        required property int index
        required property string modelData
        text: modelData
        checked: root.currentIndex === index
        onClicked: root.tabClicked(index)
      }
    }
  }
}
