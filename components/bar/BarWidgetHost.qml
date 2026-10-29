pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.components.reusable
// Imported (though widgets load by URL) so qs scans what they import and
// the folders whose files see each other (scripts/check_structure.py)
import qs.components.bar.widgets.base // qmllint disable unused-imports
import qs.components.bar.widgets.Workspaces // qmllint disable unused-imports
import qs.components.hosts.popout

// Hosts one bar module and turns its sizing contract into the numbers the
// bar layout works with. A module may declare any of these on its root item:
//
//   sizePolicy:    "content" (default) - exactly its implicit size
//                  "fixed"             - exactly preferredSize, whatever it shows
//                  "elastic"           - its implicit size capped at preferredSize,
//                                        shrinks towards minimumSize when crowded
//   preferredSize: main-axis size (fixed: the size; elastic: the cap)
//   minimumSize:   smallest main-axis size an elastic module accepts
//   priority:      when a section can't fit even the minimum sizes, the
//                  lowest-priority modules are hidden first (default 0)
//
// The widget's `layout` config (`layoutOverrides`) wins over the module's
// own values. The host's main-axis size (`mainSize`) is assigned by
// WidgetGroup; the cross axis is the bar's widgetSize. Modules must fit
// their content to whatever size they're given and report their natural
// size through implicitWidth/implicitHeight, independent of that size.
Item {
  id: root

  required property var barConfig
  property var panel
  property var screen

  required property var properties
  required property string componentPath
  property var layoutOverrides: ({})
  // The bar editor's selected widget: outlined, and its sizing reported
  property bool highlighted: false

  readonly property bool isVertical: barConfig.vertical

  readonly property var _item: contentLoader.item
  // What WidgetGroup draws under the module: its colors on this bar
  // (BarsConfig.widgetColors), or null when it has no background
  readonly property bool hasBackground: _item?.hasBackground ?? false
  readonly property var background: hasBackground ? _item.colors : null
  // The module's own fade, which its background follows: its `dim` when
  // it has one (a press fades only its content; the background shows it
  // by `pressed`, as a fade would let a powerline neighbour's square start
  // show through), else its opacity
  readonly property real contentOpacity: _item ? ("dim" in _item ? _item.dim : _item.opacity) : 1
  readonly property bool pressed: _item?.pressed ?? false
  // A level filling its background's shape (the module's `fillShare`), -1 none
  readonly property real fillShare: _item?.fillShare ?? -1
  readonly property color fillShareColor: _item?.fillShareColor ?? "transparent"
  // A divider of its own (Separator): the group draws none beside it
  readonly property bool divides: _item?.divides ?? false
  // Hovered, on a module that shows an outline then (its hoverOutline)
  readonly property bool outlined: (_item?.hoverOutline ?? false) && (_item?.hovered ?? false)
  // Room along the bar kept clear of its background's caps, at its start
  // and end (set by WidgetGroup): added to its sizes, the module inside
  property real leadInset: 0
  property real trailInset: 0
  // Its background's shape as drawn (BarShapes.segment, set by WidgetGroup),
  // which it's hovered and clicked in: past its caps' insets, back under a
  // powerline neighbour, and not in a slant's or arrow's cut-off corners.
  // Null (no background) leaves the module's own bounds.
  property var hitShape: null
  // The hit area below, by a name its menu anchor (whose own `hitArea`
  // would shadow the id) can read
  readonly property Item _hitArea: hitArea
  // Rounded up: half a powerline join is fractional, and the allocation
  // floors sizes, which would leave the module under its natural size and
  // elide its label
  readonly property real _insets: naturalSize > 0 ? Math.ceil(leadInset + trailInset) : 0
  readonly property real naturalSize: _item ? Math.ceil(isVertical ? _item.implicitHeight : _item.implicitWidth) : 0
  readonly property string sizePolicy: _item?.sizePolicy ?? "content"

  // The module's own sizes, then with the insets
  readonly property real _preferred: {
    const override = layoutOverrides?.size;
    if (sizePolicy === "fixed")
      return override ?? _item?.preferredSize ?? naturalSize;
    if (sizePolicy === "elastic")
      return Math.min(naturalSize, override ?? _item?.preferredSize ?? naturalSize);
    return override ?? naturalSize;
  }
  readonly property real preferredSize: _preferred + _insets
  readonly property real minimumSize: {
    const min = layoutOverrides?.minSize ?? (sizePolicy === "elastic" ? _item?.minimumSize : undefined);
    return (min === undefined ? _preferred : Math.min(min, _preferred)) + _insets;
  }
  readonly property int priority: layoutOverrides?.priority ?? _item?.priority ?? 0
  // Its sizing as laid out, for the bar editor's inspector
  readonly property var measure: ({
      "policy": root.sizePolicy,
      "size": Math.round(root.shown ? root.mainSize : 0),
      "preferred": Math.round(root.preferredSize),
      "minimum": Math.round(root.minimumSize),
      "priority": root.priority
    })

  // Assigned by WidgetGroup; standalone hosts just
  // get their preferred size
  property real mainSize: preferredSize

  // Set by WidgetGroup when the bar is too crowded for this module. It must
  // not become `visible: false`: positioners inside modules (Row/Column)
  // skip invisible children, which would change the size being measured
  // and flip the module between hidden and shown forever.
  property bool shown: true
  opacity: shown ? 1 : 0
  enabled: shown

  implicitWidth: isVertical ? root.barConfig.widgetSize : preferredSize
  implicitHeight: isVertical ? preferredSize : root.barConfig.widgetSize
  width: isVertical ? root.barConfig.widgetSize : mainSize
  height: isVertical ? mainSize : root.barConfig.widgetSize

  // Its place and size as drawn glide to the layout's (x, y and the size
  // above, which its background and the bar's pills follow); the layout
  // itself is measured from the module, never from these, so it can't
  // chase its own animation. Off until first placed, so a new bar (or an
  // editor rebuild) doesn't fly its widgets in from the start.
  property bool _settled: false
  Component.onCompleted: {
    _load();
    Qt.callLater(() => root._settled = true);
  }
  readonly property real _drawnMain: isVertical ? height : width
  readonly property bool _resizing: Math.abs(_drawnMain - mainSize) > 0.5

  Glide on opacity {}
  Glide on x {
    enabled: root._settled
  }
  Glide on y {
    enabled: root._settled
  }
  Glide on width {
    enabled: root._settled
  }
  Glide on height {
    enabled: root._settled
  }

  // Created with its inputs already set, so the module's own bindings
  // never see them undefined; bound afterwards so later changes (e.g. edits
  // live in the bar editor) reach it
  function _load() {
    contentLoader.setSource(root.componentPath, {
      "barConfig": root.barConfig,
      "panel": root.panel,
      "screen": root.screen,
      "properties": root.properties
    });
  }

  // Where the module's pointer areas go (BarWidget.hitArea), over the
  // module so nothing in it takes the hover first. It tracks hover itself
  // (a PopoutAnchor given it reads `hovered`): a HoverHandler moved into
  // it after it's made isn't reliably hovered. Nothing under it is hovered,
  // so a module with several anchors (the tray's icons) asks `hovers(item)`.
  Item {
    id: hitArea

    readonly property real back: root.hitShape?.back ?? 0
    readonly property bool hovered: hoverHandler.hovered
    // Whether the pointer over it is over `item`, an item of the module
    function hovers(item: Item): bool {
      return hoverHandler.hovered && item.contains(item.mapFromItem(hitArea, hoverHandler.point.position));
    }
    readonly property QtObject mask: QtObject {
      function contains(point: point): bool {
        // A containmentMask replaces the bounds check: without a shape (a
        // hidden module), its own bounds, or a zero-sized hit area would
        // claim the whole window and take the hover from the modules
        // under it
        const shape = root.hitShape;
        if (!shape)
          return point.x >= 0 && point.y >= 0 && point.x < hitArea.width && point.y < hitArea.height;
        const v = root.isVertical;
        return BarShapes.contains(v ? point.y : point.x, v ? point.x : point.y, v ? hitArea.height : hitArea.width, v ? hitArea.width : hitArea.height, shape.shownStart, shape.endCap);
      }
    }

    z: 1
    x: root.isVertical ? 0 : -back
    y: root.isVertical ? -back : 0
    width: root.width + (root.isVertical ? 0 : back)
    height: root.height + (root.isVertical ? back : 0)
    containmentMask: mask

    HoverHandler {
      id: hoverHandler
    }
  }

  // Its menu popout: the edge menu it opens when hovered, as its popout
  // or in place of its own (whose anchor stands down meanwhile). Hovered
  // in the hit area, but over the module itself, not the hit area's reach
  // back under the one before: a menu opened at its widget
  // (PopoutAnchor.screenRect) centres on the module
  PopoutAnchor {
    hitArea: root._hitArea
    menu: EdgeMenusConfig.popoutMenuOf(root.properties)
    active: menu !== ""
  }
  onComponentPathChanged: _load()

  // The module at its laid-out size, centred in the size drawn (or at its
  // start, with `pinStart`): it never re-fits (eliding its label)
  // mid-animation, and shows through the drawn size, clipped, while that
  // catches up
  Item {
    anchors.fill: parent
    clip: root._resizing

    Loader {
      id: contentLoader
      readonly property real length: Math.max(0, root.mainSize - root.leadInset - root.trailInset)
      readonly property real start: (root._item?.pinStart ? 0 : Math.round((root._drawnMain - root.mainSize) / 2)) + root.leadInset
      x: root.isVertical ? 0 : start
      y: root.isVertical ? start : 0
      width: root.isVertical ? root.width : length
      height: root.isVertical ? length : root.height
      onLoaded: {
        if (item) {
          item.barConfig = Qt.binding(() => root.barConfig);
          item.panel = Qt.binding(() => root.panel);
          item.screen = Qt.binding(() => root.screen);
          item.properties = Qt.binding(() => root.properties);
          if ("hitArea" in item)
            item.hitArea = Qt.binding(() => root.hitShape ? hitArea : null);
        }
      }
    }
  }

  // A module with a background shows it in its shape (WidgetBackground)
  Rectangle {
    anchors.fill: parent
    visible: root.highlighted && !root.hasBackground
    radius: root.barConfig.radius
    color: Qt.alpha(Theme.accent, 0.15)
    border.color: Theme.accent
    border.width: 2
  }
}
