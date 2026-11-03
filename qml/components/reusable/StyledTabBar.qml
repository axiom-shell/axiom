pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A row of equal-width tabs (StyledTabButtons), one per label in `tabs`.
// The owner keeps the current index: set `currentIndex`, and update it
// from tabClicked. The current tab's highlight is the bar's own, sliding
// from tab to tab.
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

  // From the tabs' (uniform) cells rather than their items, which the
  // Repeater rebuilds whenever a label changes
  readonly property int _count: root.tabs.length
  readonly property real _tabWidth: root._count > 0 ? (row.width - row.spacing * (root._count - 1)) / root._count : 0

  // Off until laid out, so it doesn't grow in from nothing
  property bool _settled: false
  Component.onCompleted: Qt.callLater(() => root._settled = true)

  Rectangle {
    id: indicator
    visible: root.currentIndex >= 0 && root.currentIndex < root._count
    x: root.currentIndex * (root._tabWidth + row.spacing)
    width: root._tabWidth
    height: row.height
    radius: Widget.radius
    color: Theme.backgroundHighlight

    Rectangle {
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width * 0.8
      height: 2
      radius: 1
      color: Theme.accent
    }

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
