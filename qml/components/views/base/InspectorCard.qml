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
// `scrolls: false` builds no CardScroll: the children sit in a plain column
// filling the rest, for a host whose body scrolls inside itself (two panes
// side by side). The one default slot is the same either way.
Surface {
  id: root

  // The top: an InspectorHeader or a titled header
  property alias header: headerSlot.data
  // Where the body was scrolled to is kept under this key; none keeps nothing
  property string scrollKey: ""
  property bool scrolls: true
  default property alias content: slot.data
  // The body's CardScroll (null while `scrolls` is off)
  readonly property CardScroll scroll: scrollLoader.item as CardScroll

  tone: "surface"

  ColumnLayout {
    id: outer
    anchors.fill: parent
    anchors.margins: Widget.padding
    spacing: Widget.spacing

    ColumnLayout {
      id: headerSlot
      visible: children.length > 0
      Layout.fillWidth: true
      spacing: 0
    }

    Loader {
      id: scrollLoader
      active: root.scrolls
      visible: root.scrolls
      Layout.fillWidth: true
      Layout.fillHeight: true

      sourceComponent: CardScroll {
        id: scroll

        property ScrollMemory memory: ScrollMemory {
          flickable: scroll.flickable as Flickable
          key: root.scrollKey
        }
      }
    }

    // The body: inside the CardScroll while it scrolls, else here
    ColumnLayout {
      id: slot
      Layout.fillWidth: true
      Layout.fillHeight: !root.scrolls
      spacing: Style.cardGap
    }

    Binding {
      target: slot
      property: "parent"
      value: root.scrolls && root.scroll ? root.scroll.body : outer
    }
  }
}
