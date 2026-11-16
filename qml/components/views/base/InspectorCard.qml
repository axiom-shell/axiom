pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// An editor's inspector box (the bar editor's widget, the layouts editor's
// module, a custom widget's element): a `surface` card padded
// `Widget.padding`, a `header` slot at the top (an InspectorHeader) and under
// it the body in a CardScroll (children: the cards). With a `scrollKey` the
// body keeps where it was scrolled across the overlay closing (ScrollMemory).
Surface {
  id: root

  // The top: an InspectorHeader or a titled header
  property alias header: headerSlot.data
  // Where the body was scrolled to is kept under this key; none keeps nothing
  property string scrollKey: ""
  default property alias content: scroll.content
  readonly property alias scroll: scroll

  tone: "surface"

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Widget.padding
    spacing: Widget.spacing

    ColumnLayout {
      id: headerSlot
      visible: children.length > 0
      Layout.fillWidth: true
      spacing: 0
    }

    CardScroll {
      id: scroll
      Layout.fillWidth: true
      Layout.fillHeight: true

      property ScrollMemory memory: ScrollMemory {
        flickable: scroll.flickable as Flickable
        key: root.scrollKey
      }
    }
  }
}
