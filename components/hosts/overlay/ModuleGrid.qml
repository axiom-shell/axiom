pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.core
import qs.components.methods
import qs.components.reusable

// A Custom page's, an edge menu's or the lock screen's modules, each in its
// own place on a grid of quarter cards (GridPlacement). The grid is as big
// as its modules reach (or its `extent`), at the card size of `grid`;
// `stretch` grows it into room. Modules with `properties.grow` take more
// rows while their content wants them, pushing those under them down.
Item {
  id: root

  // [{ type, properties, place: { x, y, w, h } }]
  required property var modules
  required property OverlayGrid grid
  // Room to grow into ({ width, height }, either optional), null for none
  property var stretch: null
  // Where the modules are shown, handed to each as `host` (see OverlaySlot)
  property var host: ({
      "kind": "overlay"
    })

  // What each module is drawn at: laid out at its slot's size over this,
  // then scaled to fill it (an edge menu's, EdgeMenusConfig.zoomOf). The
  // grid itself is laid out at `grid`'s card size, drawn
  property real zoom: 1

  // The least the grid spans ({ cols, rows }) whatever its modules reach
  // (a lock screen's grid), null for just the modules
  property var extent: null

  // Growing: a module with `properties.grow` takes up to that many rows
  // more under its place while its content wants them (its
  // `wantedHeight`), pushing what's under it down (GridPlacement.grown).
  // Not on a bounded grid (the lock screen's, the greeter's). `growth` is
  // the rows each has now, set a tick after what they want changes, so a
  // module's size never feeds back into itself in one pass
  readonly property bool growable: root.extent === null && (root.host?.kind === "overlay" || root.host?.kind === "edgeMenu")
  property var growth: []
  // Where the grid's edge is (GridPlacement.grown): -1 at its top (a page,
  // a top or side menu), 1 at its bottom (a bottom menu). Growing takes the
  // free rows that way first, then grows away from it
  property int growTowards: -1
  // Where each module is shown: its place, grown
  readonly property var places: {
    const placed = (root.modules ?? []).map(module => module?.place ?? null);
    return root.growth.some(n => n > 0) ? GridPlacement.grown(placed, root.growth, root.growTowards) : placed;
  }

  function _boundsOf(places) {
    const reach = GridPlacement.bounds(places.map(place => ({
          "place": place
        })));
    return root.extent ? {
      "cols": Math.max(reach.cols, root.extent.cols),
      "rows": Math.max(reach.rows, root.extent.rows)
    } : reach;
  }
  readonly property var bounds: root._boundsOf(root.places)
  readonly property var sizes: root.grid.sizes(root.bounds, root.stretch)
  // As placed, ungrown: its unit is what growth counts rows in
  readonly property var _placedSizes: root.grid.sizes(GridPlacement.bounds(root.modules), root.stretch)

  // The rows `px` takes, at least one
  function rowsFor(px) {
    const unit = root._placedSizes.unitH;
    const gap = root._placedSizes.gap;
    return Math.max(1, Math.ceil((px + gap) / (unit + gap)));
  }

  property var _pendingGrowth: ({})
  function _setGrowth(index, rows) {
    root._pendingGrowth[index] = rows;
    Qt.callLater(root._applyGrowth);
  }
  function _applyGrowth() {
    const count = root.modules?.length ?? 0;
    const next = [];
    for (let i = 0; i < count; i++)
      next.push(root._pendingGrowth[i] ?? root.growth[i] ?? 0);
    root._pendingGrowth = {};
    if (JSON.stringify(next) !== JSON.stringify(root.growth))
      root.growth = next;
  }

  // Slots glide to new places once first laid out
  property bool _settled: false

  // Streaming: the modules are built over the frames after the grid is,
  // a job each in BuildQueueManager's queue, top left to bottom right
  // (GridPlacement.revealOrder), each fading in, so showing a page doesn't
  // wait on all of its modules. Without it (the lock screen, the greeter,
  // the desktop, a screen layout) all are built with the grid
  property bool stream: false
  readonly property var _order: GridPlacement.revealOrder(root.modules)
  // How many modules (in reveal order) are built, and queued
  property int revealed: 0
  property int _queued: 0
  // All of them streamed in once: modules added later build at once (a
  // later one ranked earlier would otherwise unload the last one)
  property bool _streamed: false
  readonly property int _count: root.modules?.length ?? 0
  property real _streamStart: Date.now()
  on_CountChanged: root._queueModules()
  function _queueModules() {
    if (!root.stream || root._streamed)
      return;
    for (; root._queued < root._count; root._queued++) {
      const type = root.modules[root._order.indexOf(root._queued)]?.type ?? "";
      BuildQueueManager.request(root, () => {
        root.revealed++;
        if (root._streamed || root.revealed < root._count)
          return;
        root._streamed = true;
        console.log(`Overlay modules streamed in ${Date.now() - root._streamStart} ms (${root._count} modules)`);
      }, `overlay module ${type}`);
    }
  }
  Component.onDestruction: BuildQueueManager.cancel(root)

  // A module's detail grown over the others (ExpandedModule): { type,
  // properties, from: [x, y, w, h] px in the grid }, null for none. Only on
  // overlay pages and edge menus, and only types allowed on the host
  // (`x-hosts`)
  property var expanded: null
  readonly property bool expandable: root.host?.kind === "overlay" || root.host?.kind === "edgeMenu"
  function canExpand(type) {
    return root.expandable && OverlayConfig.moduleInfo(type) !== null && OverlayConfig.allowedIn(type, root.host.kind);
  }
  function expand(type, properties, from) {
    if (!root.canExpand(type))
      return;
    const at = from ? from.mapToItem(root, 0, 0) : Qt.point(0, 0);
    root.expanded = {
      "type": type,
      "properties": properties ?? {},
      "from": [at.x, at.y, from?.width ?? root.width, from?.height ?? root.height]
    };
  }
  // Shrinks the detail back into where it came from, then drops it
  function collapse() {
    expandedLayer.collapse();
  }

  implicitWidth: root.sizes.width
  implicitHeight: root.sizes.height

  // Logs modules that overlap another, a tick after they change: a
  // screen layout's modules can pass through places not yet arranged
  // (ScreenLayoutView's `placedModules` read before its `arrangement`)
  readonly property string _checkKey: JSON.stringify((root.modules ?? []).map(module => [module?.type, module?.place]))
  on_CheckKeyChanged: Qt.callLater(root._check)
  Component.onCompleted: {
    root._queueModules();
    Qt.callLater(root._check);
    Qt.callLater(() => root._settled = true);
  }
  function _check() {
    const modules = root.modules ?? [];
    modules.forEach((module, i) => {
      if (!GridPlacement.canPlace(modules.slice(0, i), module?.place, -1))
        console.warn(`[ModuleGrid] Overlay module ${module?.type} overlaps another`);
    });
  }

  // The modules, dimmed and out of reach under an expanded detail
  Item {
    anchors.fill: parent
    enabled: root.expanded === null
    opacity: expandedLayer.shown ? 0.35 : 1
    Glide on opacity {
      duration: Appearance.animNormal
    }

    // Keyed by count: edits update the modules in place
    Repeater {
      model: root.modules?.length ?? 0

      Item {
        id: slot
        required property int index
        readonly property var module: root.modules[slot.index]
        // As shown: grown, or pushed down by one that is
        readonly property var place: root.places[slot.index] ?? slot.module?.place ?? {
          "x": 0,
          "y": 0,
          "w": 4,
          "h": 4
        }
        readonly property var r: GridPlacement.rectPx(slot.place, root.sizes)

        // The rows more its content wants, up to its `grow`
        readonly property int wantRows: {
          const grow = root.growable ? (slot.module?.properties?.grow ?? 0) : 0;
          const wanted = moduleSlot.growHeight;
          const placed = slot.module?.place;
          if (grow <= 0 || !(wanted > 0) || !placed)
            return 0;
          // Two units wide or less, two rows or less is compact
          // (SlotContext): three at the least
          const rows = Math.max(root.rowsFor(wanted), placed.w <= 2 ? 3 : 1);
          return Math.max(0, Math.min(grow, rows - placed.h));
        }
        onWantRowsChanged: root._setGrowth(slot.index, slot.wantRows)
        Component.onCompleted: root._setGrowth(slot.index, slot.wantRows)

        x: slot.r.x
        y: slot.r.y
        width: slot.r.width
        height: slot.r.height
        clip: true
        opacity: moduleSlot.ready || !root.stream ? 1 : 0

        Glide on opacity {
          enabled: root.stream
          duration: Appearance.animFast
        }

        Glide on y {
          enabled: root._settled
          duration: Appearance.animNormal
        }
        Glide on height {
          enabled: root._settled
          duration: Appearance.animNormal
        }

        // At its place's size from the start, revealed as the slot grows
        OverlaySlot {
          id: moduleSlot
          anchors.fill: undefined
          width: slot.r.width
          height: slot.r.height
          config: slot.module
          rect: GridPlacement.rectOf(slot.place)
          host: root.host
          expander: root.expandable ? root : null
          zoom: root.zoom
          active: !root.stream || root._streamed || (root._order[slot.index] ?? 0) < root.revealed
        }
      }
    }
  }

  ExpandedModule {
    id: expandedLayer
    anchors.fill: parent
    request: root.expanded
    host: root.host
    slotRect: [0, 0, root.bounds.cols, root.bounds.rows]
    inset: root.grid.gap
    zoom: root.zoom
    onClosed: root.expanded = null
  }
}
