pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.services.system
import qs.config
import qs.components.methods

// What a Workspaces switcher's cells show and how long each is along the
// bar, for the row on the bar (WorkspaceCellRow) and the popouts alike:
// the grid's arrow, a label of one's own (`workspaceLabels`), app icons,
// the compositor's name (`useNames`), else the number, dot or nothing
// (WorkspaceCells.pick). Text longer than a number lengthens its cell.
QtObject {
  id: root

  required property var barConfig
  // The widget's options (a popout's are empty until it has loaded)
  required property var properties
  // The monitor's first workspace id (relative numbers count from it)
  required property int base
  // A cell's thickness across the bar, and its length at rest
  required property real thickness
  required property real restLength

  // Text as a cell draws it (StyledText at the bar's size less 1), bold
  // as an active one on the bar may be, so it never outgrows its room
  readonly property FontMetrics _metrics: FontMetrics {
    font.family: Appearance.fontFamily
    font.pixelSize: root.barConfig ? root.barConfig.fontSize - 1 : Appearance.fontSize
    font.bold: true
  }

  // The number a workspace's cell shows: its id, or counted from the
  // monitor's first with `relativeNumbers` (its place in the grid)
  function numberOf(wsId) {
    return root.properties.relativeNumbers ? wsId - root.base + 1 : wsId;
  }

  // What workspace `wsId`'s cell shows, `glyph` taking its place (the
  // grid's arrow, or ""), app icons only with `withIcons`: { kind
  // (WorkspaceCells.pick), text, icons (icon paths), number, length
  // (along the bar, at rest), occupied, urgent }
  function of(wsId, glyph, withIcons) {
    const ws = CompositorManager.workspaces.find(w => w.id === wsId);
    const number = root.numberOf(wsId);
    // An entry names the number shown; where the compositor makes the
    // workspaces itself, the workspace's place on its monitor
    const labelNumber = CompositorManager.dynamicWorkspaces ? wsId - root.base + 1 : number;
    const icons = withIcons && root.properties.showAppIcons && (ws?.windowCount ?? 0) > 0 ? root._icons(wsId) : [];
    const name = root.properties.useNames ? WorkspaceCells.nameShown(ws?.name, wsId, number) : "";
    const shown = WorkspaceCells.pick(glyph, WorkspaceCells.labelFor(root.properties.workspaceLabels, labelNumber), icons, name);
    return {
      "kind": shown.kind,
      "text": shown.text,
      "icons": shown.kind === "icons" ? icons : [],
      "number": number,
      "length": root._length(shown, icons),
      "occupied": (ws?.windowCount ?? 0) > 0,
      "urgent": ws?.urgent === true
    };
  }

  // "largest", "row" or "square" (`appIconsLayout`)
  readonly property string iconLayout: root.properties.appIconsLayout ?? "largest"
  // How many app icons a cell can show in that layout
  readonly property int iconSlots: root.iconLayout === "row" ? (root.properties.appIconsMax ?? 3) : root.iconLayout === "square" ? 4 : 1

  // The app icons a workspace with windows shows: its largest window's, or
  // in a row or square its apps' (each once, by its biggest window) or
  // with `appIconsCount: windows` its windows', the
  // biggest up to the slots, in the order they sit on screen
  // (WorkspaceCells.chosen): on a strip monitor strip order, else left to
  // right, then top to bottom
  function _icons(wsId) {
    const bySize = CompositorManager.windowsBySize(wsId);
    const windows = root.iconLayout === "largest" ? bySize.slice(0, 1) : WorkspaceCells.chosen(bySize, root.iconSlots, root.properties.appIconsCount === "windows", root._onScreen(wsId, bySize));
    return windows.map(w => AppIconManager.resolveWindowIcon(w.appId, w.title));
  }

  // A workspace's windows (`windows`) in the order they sit on screen: on
  // a strip monitor (its output's) strip order, else by position
  function _onScreen(wsId, windows) {
    const output = CompositorManager.workspaces.find(w => w.id === wsId)?.output ?? "";
    const direction = output !== "" ? CompositorManager.stripDirection(output) : "";
    return direction !== "" ? CompositorManager.stripWindows(wsId, direction === "vertical") : WorkspaceCells.byPosition(windows);
  }

  // Along the bar: the rest length, longer for text that needs it (with
  // half a cell's thickness of room around it) or a row of icons
  function _length(shown, icons) {
    if (shown.kind === "icons" && root.iconLayout === "row")
      return WorkspaceCells.rowLength(icons.length, root.thickness, root.restLength);
    if (shown.kind !== "name" && (shown.kind !== "text" || Utils.isSymbolName(shown.text)))
      return root.restLength;
    // The size read, so a binding calling this measures again when it changes
    if (root._metrics.font.pixelSize <= 0)
      return root.restLength;
    return Math.max(root.restLength, Math.ceil(root._metrics.advanceWidth(shown.text)) + Math.round(root.thickness * 0.5));
  }
}
