pragma ComponentBehavior: Bound
import QtQuick

// The sizing wrapper for bar modules (WidgetGroup draws their
// backgrounds). Its size is set by the bar (BarWidgetHost); subclasses
// report their natural size through implicitWidth/implicitHeight and fit
// their content inside whatever size they're actually given. Content
// never draws outside it.
Item {
  id: root

  property alias content: contentLoader.sourceComponent
  // Set from the bar's barConfig: its padding, and the thickness across
  // the bar (its widgetSize)
  property int padding: 0
  property bool isVertical: false
  property int crossSize: 0

  implicitWidth: isVertical ? root.crossSize : (contentLoader.item ? contentLoader.item.implicitWidth + padding * 2 : 0)
  implicitHeight: isVertical ? (contentLoader.item ? contentLoader.item.implicitHeight + padding * 2 : 0) : root.crossSize

  clip: true

  Loader {
    id: contentLoader
    anchors.centerIn: parent
  }
}
