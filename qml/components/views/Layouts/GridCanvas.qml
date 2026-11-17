pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.methods
import qs.components.reusable
import qs.components.forms
import qs.components.content.parts
import qs.components.views.base

// The edited page (or edge menu) as it will look: its modules on their
// grid of quarter cards, drawn at the scale that fits, with room around them
// to drop into (left of or above the grid shifts it to make room). Drag a
// module to move it, an edge or corner to resize it; a library module
// dropped into a gap shrinks to fit it, and one dropped onto modules
// pushes them aside (GridEditor's plans, shown live while dragging).
// Drag a box on the background (Shift: adding) or Shift/Ctrl+click
// modules to select several, then drag one to move them all.
// A WorkArea: the icon, title and count in its header, then at its
// right undo / redo before Save and Discard; the nudge, the grid
// offset and how it fits in its status line, which says how to use the
// canvas while nothing is selected. Keys while it has focus: Ctrl+Z,
// Ctrl+Shift+Z (Ctrl+Y); with a selection, arrows move it, Shift+arrows
// resize a single module, Delete removes it, Escape deselects it.
// Geometry is scaled by hand (not Item.scale) so text and controls stay
// crisp.
WorkArea {
  id: root

  required property var dragLayer
  // The modules being edited, or null when there's nothing to edit (then
  // `emptyText` shows under the icon)
  property var modules: null
  property string emptyText: ""
  // The sentence over an empty canvas; a page with another source of modules says its own
  property string emptyHint: I18n.tr("Empty: drag modules here from the library below, or click one to add it.")
  // An edge menu's edge ("left", …), drawn along that side; "" for a page
  property string edge: ""
  // An edge menu's screen around it ({ x, y, w, h } in grid units from
  // the grid's origin, GridPlacement.screenBox), else null: drawn as a
  // dashed outline, with what lies outside it tinted (it'd scroll)
  property var screenBox: null
  // That screen's size in px ({ width, height }), for what's drawn on it in
  // px: the band along its edge taken by the bars and border, or reserved
  // by an integrated menu (`reservedDepth` px deep, labelled
  // `reservedLabel`), and the other menus (`ghosts`: [{ name, rect, modules:
  // [{ type, rect }] }], rects { x, y, width, height } in screen px)
  property var screenSize: null
  property real reservedDepth: 0
  property string reservedLabel: ""
  property var ghosts: []
  // How the result fits, under the title (e.g. per monitor)
  property string fitText: ""
  property bool fitWarning: false
  // A link beside it (EditTarget.fitLink), or null
  property var fitLink: null
  // Arrows under the title moving it along its edge (EditTarget's nudge
  // fields): hidden while `nudgeText` is ""
  property string nudgeText: ""
  property bool nudgeVertical: false
  property bool canNudgeBack: false
  property bool canNudgeForward: false
  property bool canCentre: false
  property var nudge: step => {}
  property var centre: () => {}
  // Beside them, the px its lattice is moved (up to `gridOffsetLimit`
  // either way), set through `setGridOffset`
  property int gridOffset: 0
  property int gridOffsetLimit: 0
  property var setGridOffset: px => {}
  // A menu's lattice along its edge ({ from, to } in units from the
  // grid's origin), else null: the units past it are tinted as past the
  // screen are
  property var latticeSpan: null
  // What's drawn under the modules, dimmed and not selectable, as the
  // lattice's bounds count it ([{ place, label }]: the custom widget editor's
  // base elements while a screen is edited)
  property var underlay: []
  // What a tile draws instead of its icon and label (the custom widget
  // editor draws the element itself): a Component whose root has a
  // `module` (the tile's module, or an underlay item's `element`), loaded by
  // CanvasModule and the underlay
  property Component tileContent: null
  // The selected module's room to each side (margins). Off in the custom
  // widget editor, where the lines read as stray guides
  property bool showMargins: true

  // A right click on tile `index` (selected by it), at (x, y) in `tile`
  // (an Item): the owner opens the menu it wants
  signal tileContext(int index, var tile, real x, real y)
  // Whether that right click keeps a selected group (the owner's menu acts on
  // it); off, it selects the tile alone
  property bool contextKeepsGroup: false

  // Whether the canvas shows its own Undo/Redo (off: the host has a pair)
  property bool showUndo: true
  readonly property bool editable: root.modules !== null && root.modules !== undefined
  readonly property var list: root.editable ? root.modules : []
  readonly property var bounds: GridPlacement.bounds(root.underlay.length > 0 ? root.list.concat(root.underlay) : root.list)

  // How a growing module (`properties.grow`) grows alone: { up, down } rows
  // (GridPlacement.growthAround; a bottom menu grows towards its bottom
  // first), for its dashed outline
  function growthOf(index) {
    const grow = root.list[index]?.properties?.grow ?? 0;
    return GridPlacement.growthAround(root.list.map(module => module?.place ?? null), index, grow, root.edge === "bottom" ? 1 : -1);
  }

  // The axis the menu's edge runs along (a side menu's rows, else columns)
  readonly property bool alongRows: root.edge === "left" || root.edge === "right"
  readonly property bool hasScreen: root.screenBox !== null && root.screenBox !== undefined
  // The grid drawn: a unit of room before the modules and three after
  // (to make space left of / above them, and to grow them right / down),
  // or one unit past the screen all round (GridPlacement.canvasExtent)
  readonly property var extent: GridPlacement.canvasExtent(root.bounds, root.hasScreen ? root.screenBox : null, 1, 3)
  // Its scale to fit the area, from the default card size; geometry is
  // scaled by hand (GridPlacement.canvasFit)
  readonly property var fit: GridPlacement.canvasFit(root.extent, area.width, area.height, 0.6)
  readonly property real step: root.fit.step
  readonly property real gap: root.fit.gap
  readonly property real unitSize: root.fit.unitSize
  // The corners of the lattice's squares and of the modules on it, the
  // same so they line up
  readonly property real cellRadius: Math.min(Style.radius, root.unitSize / 4)
  // The screen, in the area's px (its sides midway in the gaps)
  readonly property var screenRect: root.hasScreen ? GridPlacement.canvasScreenRect(root.fit, root.screenBox) : root.noRect
  readonly property var noRect: ({
      "x": 0,
      "y": 0,
      "width": 0,
      "height": 0
    })

  // Screen px in the area, through the screen's outline
  readonly property real pxScale: root.hasScreen && root.screenSize && root.screenSize.width > 0 ? root.screenRect.width / root.screenSize.width : 0
  function screenPx(r) {
    return Qt.rect(root.screenRect.x + r.x * root.pxScale, root.screenRect.y + r.y * root.pxScale, r.width * root.pxScale, r.height * root.pxScale);
  }
  // The band along the menu's edge, in the area
  readonly property var reservedRect: GridPlacement.edgeBand(root.screenRect, root.edge, root.reservedDepth * root.pxScale)

  // Alignment guides. Every module's place (null without one)
  readonly property var places: root.list.map(module => module?.place ?? null)
  // The centre of their frame drawn faintly (GridEditor.guideFrame): a
  // screen layout's screen, the page's modules (what the overlay
  // centres), an edge menu's screen along its edge
  readonly property var centreLines: GridPlacement.centreGuides(root.dragLayer.editor.guideFrame(root.places, []))
  // While a module is carried or resized: wherever it lines up with the
  // others (where they'd be) or is centred among them, or on a bounded
  // grid (GridPlacement.alignments)
  readonly property var guidePlaces: root.dragLayer.previewPlaces ?? root.places
  readonly property var guides: {
    const layer = root.dragLayer;
    if (!layer.landingPlace || !layer.landingValid)
      return [];
    return GridPlacement.alignments(layer.landingPlace, root.guidePlaces, layer.landingMembers, layer.editor.guideFrame(root.guidePlaces, layer.landingMembers));
  }
  // The one selected module's room to each side of its frame, in units,
  // while nothing's carried or resized (GridPlacement.canvasMargins)
  readonly property var margins: {
    const editor = root.dragLayer.editor;
    const place = root.places[editor.selected] ?? null;
    if (!root.showMargins || !place || root.dragLayer.landingPlace)
      return [];
    return GridPlacement.canvasMargins(root.fit, place, editor.guideFrame(root.places, [editor.selected]));
  }

  function rectFor(place) {
    const r = GridPlacement.canvasRect(root.fit, place);
    return Qt.rect(r.x, r.y, r.width, r.height);
  }

  anchors.fill: parent
  count: root.editable ? root.list.length : -1
  help: I18n.tr("Drag a module to move it, an edge or corner to resize it, a box on the background to select several (Shift adds). Arrows move the selection, Shift+arrows resize a single module, Delete removes it, Escape deselects, Ctrl+Z undoes.")
  hintWhenIdle: root.editable ? I18n.tr("Drag to move · drag an edge to resize · click to edit") : ""
  idle: root.editable && root.dragLayer.editor.selected < 0 && root.dragLayer.editor.group.length === 0

  undoRedo: UndoRedoButtons {
    visible: root.editable && root.showUndo
    canUndo: root.dragLayer.editor.canUndo
    canRedo: root.dragLayer.editor.canRedo
    onUndo: root.dragLayer.editor.undo()
    onRedo: root.dragLayer.editor.redo()
  }

  // How the result moves along its edge and fits
  status: ColumnLayout {
    visible: root.editable && (root.nudgeText !== "" || root.fitText !== "")
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    RowLayout {
      visible: root.editable && root.nudgeText !== ""
      spacing: 0

      FlatIconButton {
        iconText: root.nudgeVertical ? "keyboard_arrow_up" : "chevron_left"
        tooltipText: root.nudgeVertical ? I18n.tr("Move up") : I18n.tr("Move left")
        enabled: root.canNudgeBack
        onClicked: root.nudge(-1)
      }
      FlatIconButton {
        iconText: root.nudgeVertical ? "keyboard_arrow_down" : "chevron_right"
        tooltipText: root.nudgeVertical ? I18n.tr("Move down") : I18n.tr("Move right")
        enabled: root.canNudgeForward
        onClicked: root.nudge(1)
      }
      StyledLabel {
        Layout.leftMargin: Widget.spacing / 2
        text: root.nudgeText
        role: "caption"
        tone: "muted"
      }
      FlatIconButton {
        visible: root.canCentre
        iconText: root.nudgeVertical ? "align_vertical_center" : "align_horizontal_center"
        tooltipText: I18n.tr("Centre")
        onClicked: root.centre()
      }
      SchemaNumberField {
        Layout.fillWidth: false
        Layout.leftMargin: Widget.spacing
        label: I18n.tr("Grid")
        mode: "stepper"
        unit: "px"
        minimum: -root.gridOffsetLimit
        maximum: root.gridOffsetLimit
        currentConfigValue: root.gridOffset
        // It outlives the menu it edits when another is selected
        debounced: false
        onCommitted: value => root.setGridOffset(value)
      }
    }

    RowLayout {
      visible: root.editable && root.fitText !== ""
      Layout.fillWidth: true
      spacing: Widget.spacing

      StyledLabel {
        Layout.fillWidth: fitLinks.visible ? false : true
        Layout.maximumWidth: fitLinks.visible ? implicitWidth : -1
        Layout.minimumWidth: 0
        text: root.fitText
        role: "caption"
        tone: root.fitWarning ? "warning" : "muted"
        overflow: "line"
      }

      FieldLinks {
        id: fitLinks
        Layout.fillWidth: true
        links: root.fitLink ?? undefined
      }
    }
  }

  Item {
    id: area
    anchors.fill: parent
    clip: true

    // Keys while the canvas has focus (taken on a click or a selection)
    focus: true
    Keys.onPressed: event => {
      const editor = root.dragLayer.editor;
      const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
      const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
      if (!root.editable)
        return;
      if (ctrl && event.key === Qt.Key_Z) {
        if (shift)
          editor.redo();
        else
          editor.undo();
        event.accepted = true;
        return;
      }
      if (ctrl && event.key === Qt.Key_Y) {
        editor.redo();
        event.accepted = true;
        return;
      }
      if (editor.selection().length === 0 || ctrl)
        return;
      const arrows = {
        [Qt.Key_Left]: [-1, 0],
        [Qt.Key_Right]: [1, 0],
        [Qt.Key_Up]: [0, -1],
        [Qt.Key_Down]: [0, 1]
      };
      const step = arrows[event.key];
      if (step) {
        if (!shift)
          editor.nudge(step[0], step[1]);
        else if (editor.selected >= 0)
          editor.grow(step[0], step[1]);
      } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
        editor.removeSelection();
      } else if (event.key === Qt.Key_Escape) {
        editor.clearSelection();
      } else {
        return;
      }
      event.accepted = true;
    }

    Connections {
      target: root.dragLayer.editor
      function onSelectedChanged() {
        if (root.dragLayer.editor.selected >= 0)
          area.forceActiveFocus();
      }
      function onGroupChanged() {
        if (root.dragLayer.editor.group.length > 0)
          area.forceActiveFocus();
      }
    }

    // Clicking the background drops the selection; dragging on it draws
    // a box selecting every module it touches (with Shift, added to
    // what's selected)
    MouseArea {
      id: marquee
      anchors.fill: parent
      enabled: root.editable
      preventStealing: true
      // The box being dragged (area px), else null
      property var box: null
      property point from: Qt.point(0, 0)
      property var base: []

      function touched(box) {
        const out = [];
        root.list.forEach((module, i) => {
          if (!module?.place)
            return;
          const r = root.rectFor(module.place);
          if (r.x < box.x + box.width && box.x < r.x + r.width && r.y < box.y + box.height && box.y < r.y + r.height)
            out.push(i);
        });
        return out;
      }

      onPressed: mouse => {
        area.forceActiveFocus();
        marquee.from = Qt.point(mouse.x, mouse.y);
        marquee.base = (mouse.modifiers & Qt.ShiftModifier) ? root.dragLayer.editor.selection() : [];
        marquee.box = null;
      }
      onPositionChanged: mouse => {
        if (!marquee.pressed)
          return;
        if (!marquee.box && Math.hypot(mouse.x - marquee.from.x, mouse.y - marquee.from.y) < 6)
          return;
        marquee.box = Qt.rect(Math.min(mouse.x, marquee.from.x), Math.min(mouse.y, marquee.from.y), Math.abs(mouse.x - marquee.from.x), Math.abs(mouse.y - marquee.from.y));
        root.dragLayer.editor.selectGroup(marquee.base.concat(marquee.touched(marquee.box)));
      }
      onReleased: {
        if (!marquee.box && marquee.base.length === 0)
          root.dragLayer.editor.clearSelection();
        marquee.box = null;
      }
      onCanceled: marquee.box = null
    }

    // Nothing to edit: a tool page, or none at all
    EmptyState {
      anchors.centerIn: parent
      width: Math.min(parent.width, Widget.textPx(240))
      visible: !root.editable
      icon: root.icon
      text: root.emptyText
    }

    // The drop target: the whole area, snapped to the grid
    Item {
      id: gridTarget
      anchors.fill: parent
      visible: root.editable

      readonly property string targetKind: "grid"

      // Where `drag` would go with the pointer at `point` (in the drag
      // layer): a moved module keeps the unit it was grabbed by
      // under the pointer, a new one is centred on it
      function placeAt(point, drag, grab) {
        const p = root.dragLayer.mapToItem(gridTarget, point.x, point.y);
        if (drag.kind !== "module-move")
          return GridPlacement.canvasDropPlace(root.fit, p.x, p.y, drag.w ?? 2, drag.h ?? 2, null);
        const module = root.list[drag.index];
        return module ? GridPlacement.canvasDropPlace(root.fit, p.x, p.y, module.place.w, module.place.h, grab) : null;
      }

      Component.onCompleted: root.dragLayer.registerTarget(gridTarget)
      Component.onDestruction: root.dragLayer.unregisterTarget(gridTarget)
    }

    // The unit lattice, one square per grid unit: stronger inside the
    // modules' bounds. One Canvas, as there can be hundreds of squares.
    Canvas {
      id: lattice
      anchors.fill: parent
      visible: root.editable
      readonly property string paintKey: [root.extent.cols, root.extent.rows, root.step, root.fit.originX, root.fit.originY, root.bounds.cols, root.bounds.rows, root.screenRect.x, root.screenRect.y, root.screenRect.width, root.screenRect.height, root.cellRadius, JSON.stringify(root.latticeSpan), width, height, Style.revision].join(",")
      onPaintKeyChanged: lattice.requestPaint()
      onPaint: {
        const ctx = lattice.getContext("2d");
        ctx.reset();
        ctx.strokeStyle = Style.divider;
        ctx.lineWidth = 1;
        ctx.fillStyle = Style.warning;
        const radius = root.cellRadius;
        const extent = root.extent;
        for (let row = -extent.leadRows; row < extent.rows - extent.leadRows; row++) {
          for (let col = -extent.leadCols; col < extent.cols - extent.leadCols; col++) {
            const inside = col >= 0 && row >= 0 && col < root.bounds.cols && row < root.bounds.rows;
            const box = root.screenBox;
            const along = root.alongRows ? row : col;
            const span = root.latticeSpan;
            const past = root.hasScreen && (col + 0.5 < box.x || col + 0.5 > box.x + box.w || row + 0.5 < box.y || row + 0.5 > box.y + box.h) || (span !== null && (along < span.from || along > span.to));
            const x = Math.round(root.fit.originX + col * root.step) + 0.5;
            const y = Math.round(root.fit.originY + row * root.step) + 0.5;
            ctx.beginPath();
            ctx.roundedRect(x, y, root.unitSize - 1, root.unitSize - 1, radius, radius);
            if (past) {
              ctx.globalAlpha = 0.08;
              ctx.fill();
            }
            ctx.globalAlpha = inside ? 0.45 : 0.18;
            ctx.stroke();
          }
        }
        // The screen's outline, past which the menu scrolls
        if (root.hasScreen) {
          const r = root.screenRect;
          ctx.globalAlpha = 0.9;
          ctx.strokeStyle = Style.warning;
          ctx.lineWidth = 2;
          ctx.setLineDash([6, 4]);
          ctx.beginPath();
          ctx.rect(Math.round(r.x) + 0.5, Math.round(r.y) + 0.5, Math.round(r.width), Math.round(r.height));
          ctx.stroke();
        }
      }
    }

    // The band the bars and border take along the menu's edge, or that an
    // integrated menu reserves while open
    Rectangle {
      visible: root.editable && root.hasScreen && root.reservedDepth > 0
      x: root.reservedRect.x
      y: root.reservedRect.y
      width: root.reservedRect.width
      height: root.reservedRect.height
      color: Style.accentWash

      // Its inner side, where the windows start
      Rectangle {
        color: Style.accent
        width: root.alongRows ? 1 : parent.width
        height: root.alongRows ? parent.height : 1
        x: root.edge === "left" ? parent.width - 1 : 0
        y: root.edge === "top" ? parent.height - 1 : 0
      }

      StyledLabel {
        visible: root.reservedLabel !== "" && parent.width > width && parent.height > height
        anchors.centerIn: parent
        rotation: root.alongRows && parent.width < width + Widget.padding ? -90 : 0
        text: root.reservedLabel
        textColor: Style.textAccent
        role: "micro"
      }
    }

    // The other menus on the screen, dimmed (OverlayManager.menus.showingOthers)
    Repeater {
      model: root.editable && root.pxScale > 0 ? root.ghosts.length : 0

      Item {
        id: ghost
        required property int index
        readonly property var info: root.ghosts[ghost.index] ?? null
        readonly property rect r: ghost.info ? root.screenPx(ghost.info.rect) : Qt.rect(0, 0, 0, 0)
        x: ghost.r.x
        y: ghost.r.y
        width: ghost.r.width
        height: ghost.r.height
        opacity: Style.opacityDisabled

        Rectangle {
          anchors.fill: parent
          radius: root.cellRadius
          color: "transparent"
          border.color: Style.borderStrong
          border.width: Style.hairline
        }

        Repeater {
          model: ghost.info ? ghost.info.modules.length : 0

          Rectangle {
            id: ghostModule
            required property int index
            readonly property var module: ghost.info.modules[ghostModule.index] ?? null
            readonly property rect r: ghostModule.module ? root.screenPx(ghostModule.module.rect) : Qt.rect(0, 0, 0, 0)
            x: ghostModule.r.x - ghost.r.x
            y: ghostModule.r.y - ghost.r.y
            width: ghostModule.r.width
            height: ghostModule.r.height
            radius: root.cellRadius
            color: Style.surfaceRaised
            border.color: Style.borderStrong
            border.width: Style.hairline

            StyledIcon {
              anchors.centerIn: parent
              visible: parent.width > Appearance.fontSize * 1.5 && parent.height > Appearance.fontSize * 1.5
              text: root.dragLayer.moduleIcon(ghostModule.module?.type ?? "")
              tone: "muted"
            }
          }
        }

        StyledText {
          anchors.top: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.topMargin: 2
          text: ghost.info?.name ?? ""
          role: "micro"
        }
      }
    }

    // The menu's screen edge: all of it faintly, and the part the menu
    // covers solid
    Repeater {
      model: root.editable && root.edge !== "" && root.hasScreen ? 2 : 0

      Rectangle {
        id: edgeLine
        required property int index
        // 0: the menu's part, 1: the whole edge
        readonly property bool whole: edgeLine.index === 1
        readonly property rect box: root.rectFor({
          "x": 0,
          "y": 0,
          "w": Math.max(1, root.bounds.cols),
          "h": Math.max(1, root.bounds.rows)
        })
        readonly property real thick: Math.max(3, root.gap / 2)
        readonly property var bar: GridPlacement.edgeBar(root.screenRect, root.edge, edgeLine.whole ? root.screenRect : edgeLine.box, edgeLine.thick)
        visible: edgeLine.whole || root.list.length > 0
        z: edgeLine.whole ? 0 : 1
        x: edgeLine.bar.x
        y: edgeLine.bar.y
        width: edgeLine.bar.width
        height: edgeLine.bar.height
        radius: edgeLine.thick / 2
        color: edgeLine.whole ? Style.rail : Style.accent
      }
    }

    // The screen's name, under its outline's far corner
    StyledText {
      visible: root.editable && root.hasScreen
      x: Math.max(0, Math.min(area.width - width, root.screenRect.x + root.screenRect.width - width))
      y: Math.max(0, Math.min(area.height - height, root.screenRect.y + root.screenRect.height + 2))
      text: I18n.tr("Screen edge")
      textColor: Style.warningText
      role: "micro"
    }

    StyledText {
      visible: root.editable && root.list.length === 0 && root.dragLayer.dragging === null
      anchors.centerIn: parent
      width: Math.min(parent.width, Widget.textPx(260))
      horizontalAlignment: Text.AlignHCenter
      overflow: "wrap"
      text: root.emptyHint
      tone: "muted"
    }

    // The underlay: places drawn dimmed under the tiles, by count
    Repeater {
      model: root.editable ? root.underlay.length : 0

      Rectangle {
        id: under
        required property int index
        readonly property var item: root.underlay[under.index] ?? null
        readonly property rect r: under.item ? root.rectFor(under.item.place) : Qt.rect(0, 0, 0, 0)
        x: under.r.x
        y: under.r.y
        width: under.r.width
        height: under.r.height
        radius: root.cellRadius
        color: Style.surfaceRaised
        border.width: 1
        border.color: Style.rail
        opacity: Style.opacityDisabled

        StyledText {
          visible: root.tileContent === null
          anchors.fill: parent
          anchors.margins: Widget.px(4)
          text: under.item?.label ?? ""
          role: "micro"
          tone: "muted"
          overflow: "line"
        }

        Loader {
          id: underContent
          anchors.fill: parent
          active: root.tileContent !== null && under.item?.element !== undefined
          sourceComponent: root.tileContent
        }
        Binding {
          when: underContent.item !== null
          target: underContent.item
          property: "module"
          value: under.item?.element ?? null
        }
      }
    }

    // Keyed by count: edits update the modules in place. Each tile is
    // streamed in (StreamedLoader) as the page opens, in its place
    Repeater {
      model: root.list.length

      StreamedLoader {
        id: tile
        required property int index
        readonly property var module: root.list[tile.index] ?? null
        // Where a drop or resize being dragged would put it, else its
        // place
        readonly property rect r: root.rectFor(root.dragLayer.previewPlaces?.[tile.index] ?? tile.module?.place ?? {
          "x": 0,
          "y": 0,
          "w": 1,
          "h": 1
        })
        // Carried (faded, its landing drawn over it): it jumps with the
        // landing instead of gliding after it
        readonly property bool carried: root.dragLayer.draggingKind === "module-move" && (root.dragLayer.dragging.index === tile.index || (root.dragLayer.dragging.group ?? []).includes(tile.index))
        x: tile.r.x
        y: tile.r.y
        width: tile.r.width
        height: tile.r.height
        label: "layouts canvas tile"

        Glide on x {
          enabled: !tile.carried
        }
        Glide on y {
          enabled: !tile.carried
        }
        Glide on width {
          enabled: !tile.carried
        }
        Glide on height {
          enabled: !tile.carried
        }

        sourceComponent: CanvasModule {
          dragLayer: root.dragLayer
          index: tile.index
          radius: root.cellRadius
          module: tile.module
          step: root.step
          gap: root.gap
          growth: root.growthOf(tile.index)
          tileContent: root.tileContent
          contextKeepsGroup: root.contextKeepsGroup
          onContextRequested: (x, y) => root.tileContext(tile.index, tile, x, y)
        }
      }
    }

    // The centre cross (faint, dashed, over the tiles so a full page
    // doesn't hide it), and where the module carried or resized lines
    // up: a line along each edge or centre it shares with another
    // module, stronger where it's centred (GridPlacement.alignments).
    // One Canvas: they change with every unit the pointer crosses
    Canvas {
      id: guideLines
      anchors.fill: parent
      visible: root.editable
      z: 4
      readonly property string paintKey: [JSON.stringify([root.guides, root.centreLines, root.fit]), width, height, Style.revision].join(",")
      onPaintKeyChanged: guideLines.requestPaint()
      onPaint: {
        const ctx = guideLines.getContext("2d");
        ctx.reset();
        ctx.strokeStyle = Style.accent;
        // Pixel-aligned, so a 1 px line stays sharp
        const stroke = guide => {
          const l = GridPlacement.canvasGuide(root.fit, guide);
          ctx.beginPath();
          ctx.moveTo(Math.round(l.x1) + 0.5, Math.round(l.y1) + 0.5);
          ctx.lineTo(Math.round(l.x2) + 0.5, Math.round(l.y2) + 0.5);
          ctx.stroke();
        };
        // The centre, faintly dashed over everything
        ctx.globalAlpha = 0.4;
        ctx.lineWidth = 1;
        ctx.setLineDash([4, 4]);
        root.centreLines.forEach(stroke);
        ctx.setLineDash([]);
        root.guides.forEach(guide => {
          ctx.globalAlpha = guide.frame ? 1 : 0.7;
          ctx.lineWidth = guide.frame ? 2 : 1;
          stroke(guide);
        });
      }
    }

    // The selected module's room to each side (of the screen, or of the
    // other modules): a line and its length in cards, accent where
    // both sides match
    Repeater {
      model: 4

      Item {
        id: margin
        required property int index
        readonly property var info: root.margins.find(m => m.side === ["left", "right", "top", "bottom"][margin.index]) ?? null
        readonly property color tint: margin.info?.even ? Style.accent : Style.textFaint
        visible: root.editable && margin.info !== null
        z: 4
        x: margin.info ? Math.min(margin.info.x1, margin.info.x2) : 0
        y: margin.info ? Math.min(margin.info.y1, margin.info.y2) : 0
        width: margin.info ? Math.max(1, Math.abs(margin.info.x2 - margin.info.x1)) : 0
        height: margin.info ? Math.max(1, Math.abs(margin.info.y2 - margin.info.y1)) : 0

        Rectangle {
          anchors.fill: parent
          color: margin.tint
        }

        Surface {
          anchors.centerIn: parent
          width: marginLabel.implicitWidth + Widget.spacing
          height: marginLabel.implicitHeight
          tone: "raised"
          solid: true
          radius: height / 2
          border.color: margin.tint

          StyledLabel {
            id: marginLabel
            anchors.centerIn: parent
            text: margin.info ? (margin.info.exact ? "" : "≈") + GridPlacement.cards(margin.info.units) : ""
            role: "micro"
            tone: margin.info?.even ? "accent" : "muted"
          }
        }
      }
    }

    // Drop a module here to remove it
    TrashTarget {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Widget.padding
      dragLayer: root.dragLayer
      active: root.dragLayer.carryingRemovable
    }

    // The box being dragged to select modules
    Rectangle {
      visible: marquee.box !== null
      z: 6
      x: marquee.box?.x ?? 0
      y: marquee.box?.y ?? 0
      width: marquee.box?.width ?? 0
      height: marquee.box?.height ?? 0
      color: Style.accentWash
      border.color: Style.accent
      border.width: Style.hairline
    }

    // Where the carried (or resized) module would land
    Rectangle {
      readonly property var place: root.dragLayer.landingPlace
      readonly property rect r: place ? root.rectFor(place) : Qt.rect(0, 0, 0, 0)
      // A resize shows on the tile itself, unless it can't be made
      visible: place !== null && (root.dragLayer.dragging !== null || !root.dragLayer.landingValid)
      z: 5
      x: r.x
      y: r.y
      width: r.width
      height: r.height
      radius: root.cellRadius
      color: root.dragLayer.landingValid ? Style.accentWash : Style.errorWash
      border.color: root.dragLayer.landingValid ? Style.accent : Style.error
      border.width: Style.focusWidth
    }
  }
}
