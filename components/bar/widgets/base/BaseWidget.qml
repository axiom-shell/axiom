pragma ComponentBehavior: Bound
import QtQuick

import qs.config

// Rounded background box for bar modules. Its size is set by the bar
// (BarWidgetHost); subclasses report their natural size through
// implicitWidth/implicitHeight and fit their content inside whatever size
// they're actually given. Content never draws outside the box.
Item {
  id: root

  property color backgroundColor: Theme.background
  // Off: no box, the content draws straight onto what's behind
  property bool showBackground: true
  property alias content: contentLoader.sourceComponent
  property alias contentItem: contentLoader.item
  property int padding: Widget.padding
  property int radius: Widget.radius
  property bool isVertical: false
  // Thickness across the bar: bar modules set it to their bar's widgetSize
  property int crossSize: Widget.height

  implicitWidth: isVertical ? root.crossSize : (contentLoader.item ? contentLoader.item.implicitWidth + padding * 2 : 0)
  implicitHeight: isVertical ? (contentLoader.item ? contentLoader.item.implicitHeight + padding * 2 : 0) : root.crossSize

  clip: true

  Rectangle {
    anchors.fill: parent
    visible: root.showBackground
    color: root.backgroundColor
    radius: root.radius
  }

  Loader {
    id: contentLoader
    anchors.centerIn: parent
  }
}
