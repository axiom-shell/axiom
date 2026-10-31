pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.reusable

// i18n: keys from the schema (module and view labels)
// The layouts editor's whole area: a DragLayer whose ghost is drawn above
// every panel, so a module can be carried from the library onto the
// canvas, a page or menu up or down its list.
//
// Payloads: { kind, icon, label, ... }, kind one of
//   "module-add" { type, w, h }   from the library
//   "module-move" { index, group } a module on the canvas, with the
//                                 group selected with it (indices), if any
//   "page-move" { index }         a page row
//   "tool-move" { index }         a tool page row
//   "menu-move" { index }         an edge menu row
// Targets: items with `targetKind` "grid" (placeAt(point, drag, grab)
// → { x, y, w, h }), "list" (EntryListTarget: takes(drag), indexAt,
// dropRequested(drag, index)) or "trash" (TrashTarget: a module, or the
// group carried with it, dropped there is removed). Module edits go to `editor` (a GridEditor),
// planned while carried (hoverPlan) so the canvas shows them first; a
// list handles its own drops.
DragLayer {
  id: root

  required property GridEditor editor
  // For a grid of something other than overlay modules (a custom widget's
  // elements): type => { icon, label } (label translated), else null
  property var describe: null
  // A tile's size while it's resized, from its w × h grid units
  property var sizeLabel: (w, h) => I18n.tr("{0} × {1} cards", GridPlacement.cards(w), GridPlacement.cards(h))
  // How many there are, named (the canvas's count, a carried group)
  property var countLabel: n => I18n.tr("{0} modules", n)

  readonly property string draggingKind: root.dragging?.kind ?? ""
  readonly property bool carryingModule: root.draggingKind === "module-add" || root.draggingKind === "module-move"
  // Whether what's carried can go in the trash: a module on the canvas
  // (and the group carried with it) with a removable one among them
  readonly property bool carryingRemovable: root.draggingKind === "module-move" && root._removable(root.dragging)

  // Where in the carried item it was picked up (in its own pixels), so a
  // moved module keeps its place under the pointer
  property point grab: Qt.point(0, 0)
  // The pointer, in this item
  property point pointer: Qt.point(0, 0)
  // Where a module dropped now would go ({ x, y, w, h }), else null. Set
  // (_updatePlace) only when the snapped place changes: the pointer moves
  // within a unit far more often than it crosses into another, and
  // everything below (the plan, every tile's rect, the guides) follows it
  property var hoverPlace: null
  // What dropping it there would do (a GridEditor plan), else null
  readonly property var hoverPlan: root._planFor(root.dragging, root.hoverPlace)
  // The plan the canvas shows while a module is carried, and the one its
  // drop makes: the hover plan, or while that can't be made (no room
  // there: pushes only go down, so a bounded grid often runs out of rows),
  // the last one this drag could make, so the tiles hold still instead of
  // gliding back and forth. Null off the grid
  property var shownPlan: null
  // Whether dropping on the target under the pointer would do anything
  readonly property bool hoverValid: root.hoverTarget !== null && root.dragging !== null && (root.hoverTarget.targetKind !== "grid" || (root.shownPlan?.valid ?? false))
  // A module's resize being dragged (CanvasModule sets it), else null
  property var resizePlan: null
  // The plan shown: a carried module's, else a resize's
  readonly property var _plan: root.dragging !== null ? root.shownPlan : root.resizePlan
  // Every module's place while a drop or resize is shown before it's made
  // (others pushed out of the way), else null
  readonly property var previewPlaces: root._plan?.valid && !root._plan.noop ? root._plan.places : null
  // Where the module carried or resized would land, else null
  readonly property var landingPlace: root._plan?.place ?? null
  readonly property bool landingValid: root._plan?.valid ?? false
  // Which of previewPlaces is the module landing (a group: each of
  // them; a new one: the last), else []
  readonly property var landingMembers: {
    const plan = root._plan;
    if (!plan?.valid)
      return [];
    if (plan.kind === "group")
      return plan.members ?? [];
    return [plan.kind === "add" ? plan.places.length - 1 : plan.index];
  }

  function _updatePlace() {
    const place = root.carryingModule && root.hoverTarget?.targetKind === "grid" ? root.hoverTarget.placeAt(root.pointer, root.dragging, root.grab) : null;
    if (!GridPlacement.samePlace(place, root.hoverPlace))
      root.hoverPlace = place;
  }

  // A valid plan (a no-op too: back over its own place) or leaving the
  // grid replaces the one shown; one that can't be made only shows when
  // nothing valid came before it. Kept once the drag ends, for its drop
  onHoverPlanChanged: {
    if (root.dragging === null)
      return;
    const plan = root.hoverPlan;
    if (!plan || plan.valid || !(root.shownPlan?.valid ?? false))
      root.shownPlan = plan;
  }
  onHoverTargetChanged: root._updatePlace()
  onDraggingChanged: root._updatePlace()

  function _planFor(drag, place) {
    if (!drag || !place)
      return null;
    const held = root.editor.module(drag.index)?.place;
    if (drag.kind === "module-add")
      return root.editor.planAdd(drag.type, place);
    if ((drag.group?.length ?? 0) > 0 && held)
      return root.editor.planMoveGroup(drag.group, place.x - held.x, place.y - held.y);
    return root.editor.planMove(drag.index, place.x, place.y);
  }

  function moduleIcon(type) {
    if (root.describe)
      return root.describe(type)?.icon ?? "extension";
    return OverlayConfig.moduleInfo(type)?.icon ?? "extension";
  }

  function moduleLabel(type) {
    if (root.describe)
      return root.describe(type)?.label ?? type;
    const info = OverlayConfig.moduleInfo(type);
    return info ? I18n.tr(info.label) : (type || I18n.tr("Unknown"));
  }

  accepts: (target, drag) => {
    switch (target.targetKind) {
    case "grid":
      return drag.kind === "module-add" || drag.kind === "module-move";
    case "list":
      return target.takes(drag);
    case "trash":
      return drag.kind === "module-move" && root._removable(drag);
    }
    return false;
  }

  function _members(drag) {
    return (drag.group?.length ?? 0) > 0 ? drag.group : [drag.index];
  }

  function _removable(drag) {
    return root._members(drag).some(i => root.editor.canRemove(i));
  }

  onStarted: (payload, item, x, y) => {
    root.grab = Qt.point(x, y);
    root.shownPlan = null;
  }

  onMoved: point => {
    root.pointer = point;
    root._updatePlace();
    ghost.x = point.x - ghost.height / 2;
    ghost.y = point.y - ghost.height / 2;
  }

  // Does whatever the target takes
  onDropped: (drag, target, index) => {
    if (target.targetKind === "list") {
      target.dropRequested(drag, index);
      return;
    }
    if (target.targetKind === "trash") {
      root.editor.selectGroup(root._members(drag));
      root.editor.removeSelection();
      return;
    }
    // What the canvas showed (a plan that can't be made does nothing)
    root.editor.applyPlan(root.shownPlan);
    root.shownPlan = null;
  }

  // What's being carried, as a pill under the pointer (the canvas draws
  // where it would land)
  Rectangle {
    id: ghost
    visible: root.dragging !== null
    z: 10
    width: ghostRow.implicitWidth + Widget.padding * 2
    height: Widget.height + Widget.padding / 2
    radius: Widget.radius
    color: root.hoverTarget && (!root.hoverValid || root.hoverTarget.targetKind === "trash") ? Theme.error : Theme.accent
    opacity: 0.92

    RowLayout {
      id: ghostRow
      anchors.centerIn: parent
      spacing: Widget.spacing

      StyledIcon {
        text: root.dragging?.icon ?? ""
        textColor: Theme.background
        textSize: Appearance.fontSizeBy(2)
      }
      StyledText {
        text: root.hoverTarget?.targetKind === "trash" ? I18n.tr("Remove") : root.hoverTarget && !root.hoverValid ? I18n.tr("Doesn't fit here") : (root.dragging?.label ?? "")
        textColor: Theme.background
        font.bold: true
      }
    }
  }
}
