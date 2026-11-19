pragma ComponentBehavior: Bound
import QtQuick
import qs.components.methods

// A Loader whose item is laid out at the Loader's size and drawn `zoom`
// times that from its top left: a zoom host and relay for the texts inside
// (`contentZoom`, `drawnZoom`, `inkHostAbove`: style.md › Crisp text).
// OverlaySlot's module, a bar popout's and a submenu's content.
Loader {
  id: root

  // -- Public API --
  property real zoom: 1

  // -- Implementation --
  scale: root.zoom
  transformOrigin: Item.TopLeft
  readonly property real contentZoom: root.zoom
  readonly property real drawnZoom: root.contentZoom * TextRender.zoomAt(root.parent)
  readonly property var inkHostAbove: InkHost.find(root.parent)
}
