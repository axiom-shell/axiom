pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.ui
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
// A type marked `x-elastic` in its schema is "elastic" instead: its
// implicit size capped at preferredSize, shrinking towards minimumSize
// when crowded (BarsConfig.isElastic, the one place it's stated).
//   preferredSize: main-axis size (fixed: the size; elastic: the cap)
//   minimumSize:   smallest main-axis size an elastic module accepts
// Its priority (when a section can't fit even the minimum sizes, the
// lowest-priority modules are hidden first) is its type's (`x-priority`,
// default 0: `defaultPriority`)
//
// The widget's `layout` config (`layoutOverrides`: priority, and on an
// elastic module minSize and maxSize, its cap) wins over the module's own
// values. The host's main-axis size (`mainSize`) is assigned by
// WidgetGroup; the cross axis is the bar's thickness. Modules must fit
// their content to whatever size they're given and report their natural
// size through implicitWidth/implicitHeight, independent of that size.
Item {
  id: root

  required property var barConfig
  property var panel
  property var screen

  // The widget's config ({ type, properties, layout })
  required property var widget
  readonly property var properties: root.widget.properties ?? {}
  readonly property var layoutOverrides: root.widget.layout ?? {}
  // Where it starts along its bar as laid out (never as it glides), and the
  // bar's length, which the bar's gradient spans: 0 for no gradient (set by
  // WidgetGroup). Its module reads its slice of the gradient from them.
  property real barStart: 0
  property real barLength: 0
  // The bar editor's selected widget: outlined, and its sizing reported
  property bool highlighted: false
  // The widget hovered in the bar editor: outlined as the selected one
  property bool hoverHighlighted: false
  // Outlined for the bar editor: selected or hovered there
  readonly property bool editorOutlined: root.highlighted || root.hoverHighlighted
  // The pointer is over it (its hit area), for the bar editor's chips
  readonly property bool pointerHovered: hitArea.hovered
  // A live copy of a widget in the bar editor (its chips): opens no menu
  // popout. Its host puts it under an `enabled: false` item, so it takes
  // no input either; `panel` may be null (no bar window).
  property bool preview: false

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
  // A level filling its background's shape (the module's `backgroundLevel`), -1 none
  readonly property real backgroundLevel: _item?.backgroundLevel ?? -1
  readonly property color backgroundLevelColor: _item?.backgroundLevelColor ?? "transparent"
  // A split bar's widget showing its icon part and label apart
  // (IconTextWidget.splits): along it, the middle of the gap between them
  // (`at`), and what the icon part holds (`part`), in its own coordinates;
  // null otherwise
  readonly property var split: {
    if (!(_item?.splits ?? false))
      return null;
    const part = _item.splitPart;
    return {
      "at": (isVertical ? contentLoader.y : contentLoader.x) + _item.splitAt,
      "part": Qt.rect(contentLoader.x + part.x, contentLoader.y + part.y, part.width, part.height)
    };
  }
  // A divider of its own (Separator): the group draws none beside it
  readonly property bool divides: _item?.divides ?? false
  // Room that takes the free space on its side of the bar (Spacer): it
  // keeps its preferredSize at least (BarLayout.allocate)
  readonly property bool fills: _item?.fills ?? false
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
  // How far its background reaches past its outer side as a tab
  // (widgetShape tab, set by WidgetGroup): hovered and clicked out to
  // there, its content centred in the tab
  property real tabReach: 0
  readonly property bool _outerFar: barConfig.right || barConfig.bottom
  // The module's shift across to the tab's middle
  readonly property real _tabShift: Math.round(tabReach / 2) * (_outerFar ? 1 : -1)
  // The hit area below, by a name its menu anchor (whose own `hitArea`
  // would shadow the id) can read
  readonly property Item _hitArea: hitArea
  // Rounded up: half a powerline join is fractional, and the allocation
  // floors sizes, which would leave the module under its natural size and
  // elide its label
  readonly property real _insets: naturalSize > 0 ? Math.ceil(leadInset + trailInset) : 0
  readonly property real naturalSize: _item ? Math.ceil(isVertical ? _item.implicitHeight : _item.implicitWidth) : 0
  readonly property string sizePolicy: BarsConfig.isElastic(root.widget.type ?? "") ? "elastic" : _item?.sizePolicy ?? "content"

  // The module's own sizes, then with the insets
  readonly property real _preferred: {
    if (sizePolicy === "fixed")
      return _item?.preferredSize ?? naturalSize;
    if (sizePolicy === "elastic")
      return Math.min(naturalSize, layoutOverrides?.maxSize ?? _item?.preferredSize ?? naturalSize);
    return naturalSize;
  }
  readonly property real preferredSize: _preferred + _insets
  readonly property real minimumSize: {
    const min = sizePolicy === "elastic" ? layoutOverrides?.minSize ?? _item?.minimumSize : undefined;
    return (min === undefined ? _preferred : Math.min(min, _preferred)) + _insets;
  }
  // Its type's own priority (BarsConfig.defaultPriority, the schema's
  // `x-priority`), which the widget's `layout.priority` overrides
  readonly property int defaultPriority: BarsConfig.defaultPriority(root.widget.type ?? "")
  readonly property int priority: layoutOverrides?.priority ?? defaultPriority
  // Its sizing as laid out, for the bar editor's inspector
  readonly property var measure: ({
      "policy": root.sizePolicy,
      "size": Math.round(root.shown ? root.mainSize : 0),
      "preferred": Math.round(root.preferredSize),
      "minimum": Math.round(root.minimumSize),
      "priority": root.priority,
      // Its insets, which its maxSize doesn't count
      "insets": Math.round(root._insets)
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

  implicitWidth: isVertical ? root.barConfig.thickness : preferredSize
  implicitHeight: isVertical ? preferredSize : root.barConfig.thickness
  width: isVertical ? root.barConfig.thickness : mainSize
  height: isVertical ? mainSize : root.barConfig.thickness

  // Its place and size as drawn glide to the layout's (x, y and the size
  // above, which its background and the bar's pills follow); the layout
  // itself is measured from the module, never from these, so it can't
  // chase its own animation. Off until first placed, so a new bar (or an
  // editor rebuild) doesn't fly its widgets in from the start.
  property bool _settled: false
  Component.onCompleted: {
    _load();
    // A method, not a closure: the call is dropped if the host is gone
    // by then (a bar rebuilt)
    Qt.callLater(root._settle);
  }
  function _settle() {
    root._settled = true;
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

  // The type loaded
  property string _type: ""
  // Created with its inputs already set, so the module's own bindings
  // never see them undefined; bound afterwards so later changes (e.g. edits
  // live in the bar editor) reach it. Its `properties` are handed over
  // from `widget` whole (not `properties`, which may not have caught up):
  // a new type is loaded with its own, so a module never sees another
  // type's (a bar's widgets swapped by a saved config)
  function _load() {
    root._type = root.widget.type ?? "";
    contentLoader.setSource(root._type ? Paths.widgetUrl(root._type) : "", {
      "barConfig": root.barConfig,
      "panel": root.panel,
      "screen": root.screen,
      "properties": root.widget.properties ?? {},
      "autoColors": root.widget.autoColors ?? {}
    });
  }
  onWidgetChanged: {
    if ((root.widget.type ?? "") !== root._type)
      root._load();
    else if (root._item) {
      root._item.properties = root.widget.properties ?? {};
      root._item.autoColors = root.widget.autoColors ?? {};
    }
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
    x: root.isVertical ? (root._outerFar ? 0 : -root.tabReach) : -back
    y: root.isVertical ? -back : (root._outerFar ? 0 : -root.tabReach)
    width: root.width + (root.isVertical ? root.tabReach : back)
    height: root.height + (root.isVertical ? back : root.tabReach)
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
    active: menu !== "" && !root.preview
  }

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
      x: root.isVertical ? root._tabShift : start
      y: root.isVertical ? start : root._tabShift
      width: root.isVertical ? root.width : length
      height: root.isVertical ? length : root.height
      onLoaded: {
        if (item) {
          item.barConfig = Qt.binding(() => root.barConfig);
          item.panel = Qt.binding(() => root.panel);
          item.screen = Qt.binding(() => root.screen);
          // Where it sits along the bar, for the bar's gradient: its
          // module starts past its lead inset (at rest)
          root._item.barOffset = Qt.binding(() => root.barStart + root.leadInset);
          root._item.barLength = Qt.binding(() => root.barLength);
          if ("hitArea" in item)
            item.hitArea = Qt.binding(() => root.hitShape ? hitArea : null);
        }
      }
    }
  }

  // A module's news (BaseWidget.attention) shows its bar while hidden
  // (an auto-hiding bar with revealOnActivity); a preview's goes nowhere
  Connections {
    target: root._item
    enabled: !root.preview
    ignoreUnknownSignals: true
    function onAttention() {
      BarRevealManager.attention(root.barConfig.id);
    }
  }

  // A module with a background shows it in its shape (WidgetBackground)
  Rectangle {
    anchors.fill: parent
    visible: root.editorOutlined && !root.hasBackground
    radius: root.barConfig.radius
    color: Qt.alpha(Theme.accent, 0.15)
    border.color: Theme.accent
    border.width: 2
  }
}
