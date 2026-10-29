pragma ComponentBehavior: Bound
import QtQuick
import qs.config
// Imported (though modules load by URL) so qs scans what they import
// (scripts/check_structure.py)
import qs.components.content.parts.calendar // qmllint disable unused-imports
import qs.components.content.parts.chat // qmllint disable unused-imports
import qs.components.content.parts.custom // qmllint disable unused-imports
import qs.components.content.parts.notes // qmllint disable unused-imports

// Hosts one overlay module in its slot on a grid: loads content/<type>.qml and
// hands it the entry's `properties` (defaults filled from the schema, as
// for bar widgets). An empty slot renders nothing.
Item {
  id: root

  // A slot entry: { type, properties }, or undefined for an empty slot
  property var config
  // The slot's [x, y, w, h] in grid units (its place); passed on
  // as the module's `slotRect`, from which Card derives its shape
  property var rect: [0, 0, 4, 4]
  // Where the module is shown: { kind: "overlay" } or { kind: "edgeMenu",
  // id }, passed on as its `host`
  property var host: ({
      "kind": "overlay"
    })

  // The ModuleGrid hosting it, passed on as the module's `expander`
  property var expander: null
  // What the module is drawn at: laid out at the slot's size over this,
  // then scaled to it (an edge menu's modules, see ModuleGrid.zoom)
  property real zoom: 1
  // The height the module grows to, drawn (its growHeight; 0: as placed)
  readonly property real growHeight: (loader.item?.growHeight ?? 0) * root.zoom
  // Whether the module is built yet: a streaming grid (ModuleGrid.stream)
  // builds it once `active`, and shows it once `ready`
  property bool active: true
  readonly property bool ready: loader.item !== null

  anchors.fill: parent

  readonly property string componentPath: root.config?.type ? Paths.contentUrl(root.config.type) : ""

  // Created with its properties already set, then bound so later config
  // edits reach it (as BarWidgetHost does)
  onActiveChanged: _load()
  function _load() {
    if (!root.active || !root.componentPath) {
      loader.source = "";
      return;
    }
    loader.setSource(root.componentPath, {
      "properties": root.config.properties || {},
      "slotRect": root.rect,
      "embedded": true,
      "host": root.host,
      "expander": root.expander
    });
  }
  onComponentPathChanged: _load()
  Component.onCompleted: _load()

  // `contentZoom`: see StyledIcon
  Loader {
    id: loader
    width: root.width / root.zoom
    height: root.height / root.zoom
    scale: root.zoom
    transformOrigin: Item.TopLeft
    readonly property real contentZoom: root.zoom
    onLoaded: {
      item.properties = Qt.binding(() => root.config?.properties || {});
      item.slotRect = Qt.binding(() => root.rect);
      item.host = Qt.binding(() => root.host);
      item.expander = Qt.binding(() => root.expander);
    }
  }
}
