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
  // Where a module dropped now would go ({ x, y, w, h }), else null
  readonly property var hoverPlace: root.carryingModule && root.hoverTarget?.targetKind === "grid" ? root.hoverTarget.placeAt(root.pointer, root.dragging, root.grab) : null
  // What dropping it there would do (a GridEditor plan), else null
  readonly property var hoverPlan: root._planFor(root.dragging, root.hoverPlace)
  // Whether dropping on the target under the pointer would do anything
  readonly property bool hoverValid: root.hoverTarget !== null && root.dragging !== null && (root.hoverTarget.targetKind !== "grid" || (root.hoverPlan?.valid ?? false))
  // A module's resize being dragged (CanvasModule sets it), else null
  property var resizePlan: null
  // Every module's place while a drop or resize is shown before it's made
  // (others pushed out of the way), else null
  readonly property var previewPlaces: {
    const plan = root.dragging !== null ? root.hoverPlan : root.resizePlan;
    return plan?.valid && !plan.noop ? plan.places : null;
  }
  // Where the module carried or resized would land, else null
  readonly property var landingPlace: root.dragging !== null ? (root.hoverPlan?.place ?? null) : (root.resizePlan?.place ?? null)
  readonly property bool landingValid: (root.dragging !== null ? root.hoverPlan : root.resizePlan)?.valid ?? false
  // Which of previewPlaces is the module landing (a group: each of
  // them; a new one: the last), else []
  readonly property var landingMembers: {
    const plan = root.dragging !== null ? root.hoverPlan : root.resizePlan;
    if (!plan?.valid)
      return [];
    if (plan.kind === "group")
      return plan.members ?? [];
    return [plan.kind === "add" ? plan.places.length - 1 : plan.index];
  }

  // The last plan made: the pointer moves within a unit far more often
  // than it crosses into another. Mutated, not notified
  readonly property var _memo: ({
      "key": "",
      "plan": null
    })

  function _planFor(drag, place) {
    if (!drag || !place)
      return null;
    const key = JSON.stringify([root.editor.scopeKey, drag.kind, drag.index ?? -1, drag.type ?? "", drag.group ?? [], place]);
    if (root._memo.key !== key) {
      root._memo.key = key;
      const held = root.editor.module(drag.index)?.place;
      if (drag.kind === "module-add")
        root._memo.plan = root.editor.planAdd(drag.type, place);
      else if ((drag.group?.length ?? 0) > 0 && held)
        root._memo.plan = root.editor.planMoveGroup(drag.group, place.x - held.x, place.y - held.y);
      else
        root._memo.plan = root.editor.planMove(drag.index, place.x, place.y);
    }
    return root._memo.plan;
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
    root._memo.key = "";
  }

  onMoved: point => {
    root.pointer = point;
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
    root.editor.applyPlan(root._planFor(drag, target.placeAt(root.pointer, drag, root.grab)));
    root._memo.key = "";
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
