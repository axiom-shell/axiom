pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.services.system
import qs.services.ui
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
  // (WorkspaceCells.pick), text, plain (text drawn as words, not an
  // icon), lead (a label's icon before its text, or ""), leadPlain (that
  // icon drawn in the text font), icons (icon paths), number, length
  // (along the bar, at rest), occupied, urgent }
  function of(wsId, glyph, withIcons) {
    const ws = CompositorManager.workspaces.find(w => w.id === wsId);
    const number = root.numberOf(wsId);
    // An entry names the number shown; where the compositor makes the
    // workspaces itself, the workspace's place on its monitor
    const labelNumber = CompositorManager.dynamicWorkspaces ? wsId - root.base + 1 : number;
    const icons = withIcons && root.properties.showAppIcons && (ws?.windowCount ?? 0) > 0 ? root._icons(wsId) : [];
    const name = root.properties.useNames ? WorkspaceCells.nameShown(ws?.name, wsId, number) : "";
    // A label's text where it has one (its icon then leading it), else
    // its icon
    const label = WorkspaceCells.labelFor(root.properties.workspaceLabels, labelNumber);
    const shown = WorkspaceCells.pick(glyph, label.text !== "" ? label.text : label.icon, icons, name);
    shown.written = shown.kind === "text" && label.text !== "";
    shown.lead = shown.written ? label.icon : "";
    return {
      "kind": shown.kind,
      "text": shown.text,
      "plain": root._plain(shown),
      "lead": shown.lead,
      "leadPlain": !root._drawsIcon(shown.lead),
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
    return root._iconsFrom(bySize, root._onScreen(wsId, bySize));
  }

  // The icons of windows `bySize` (the biggest first), `onScreen` being
  // the same windows in the order they sit on screen
  function _iconsFrom(bySize, onScreen) {
    const windows = root.iconLayout === "largest" ? bySize.slice(0, 1) : WorkspaceCells.chosen(bySize, root.iconSlots, root.properties.appIconsCount === "windows", onScreen);
    return windows.map(w => AppIconManager.resolveWindowIcon(w.appId, w.title));
  }

  // What the cell of scratchpad `special` (CompositorManager.specials) shows,
  // `entry` being its Workspaces.scratchpads entry or null: the fields of
  // of(), with app icons only in icon mode (`scratchpadLabel`) or, with
  // `scratchpadSplit`, after the label and a divider (`tail`: their paths,
  // `tailLength` how much longer they make the cell)
  function ofScratchpad(special, entry) {
    const mode = root.properties.scratchpadLabel;
    const split = root.properties.scratchpadSplit === true;
    const icons = (mode === "icon" || split) && root.properties.showAppIcons && special.windows.length > 0 ? root._iconsFrom(WorkspaceCells.bySize(special.windows), WorkspaceCells.byPosition(special.windows)) : [];
    const shown = Scratchpads.content(entry, special.name, mode, icons.length > 0, split);
    shown.written = mode !== "icon" && shown.kind === "text";
    const tail = shown.tail ? icons : [];
    const sep = root.barConfig.look.separators;
    const along = WorkspaceCells.dividerAlong(root.thickness, sep.style, sep.thickness);
    return {
      "kind": shown.kind,
      "text": shown.text,
      "plain": root._plain(shown),
      "lead": shown.lead,
      "leadPlain": !root._drawsIcon(shown.lead),
      "icons": shown.kind === "icons" ? icons : [],
      "tail": tail,
      "tailLength": WorkspaceCells.splitTail(tail.length, root.thickness, along),
      "tailEdge": WorkspaceCells.splitPad(root.thickness),
      "tailShift": WorkspaceCells.splitShift(tail.length, root.thickness, along),
      "dividerAlong": along,
      "number": "",
      "length": tail.length > 0 ? WorkspaceCells.splitLength(root._labelLength(shown), tail.length, root.thickness, along) : root._length(shown, icons),
      "occupied": special.windowCount > 0,
      "urgent": special.urgent === true
    };
  }

  // A workspace's windows (`windows`) in the order they sit on screen: on
  // a strip monitor (its output's) strip order, else by position
  function _onScreen(wsId, windows) {
    const output = CompositorManager.workspaces.find(w => w.id === wsId)?.output ?? "";
    const direction = output !== "" ? CompositorManager.stripDirection(output) : "";
    return direction !== "" ? CompositorManager.stripWindows(wsId, direction === "vertical") : WorkspaceCells.byPosition(windows);
  }

  // Whether a label's icon draws as one: a name the icon font has (as the
  // icon picker tells: a word like "dev" reads as a name but has no icon,
  // and drawn in the icon font it's unreadable)
  function _drawsIcon(icon) {
    return Utils.isSymbolName(icon) && IconManager.isKnown(icon);
  }

  // Whether `shown`'s text is words: a name always, a label's text
  // (`written`), or its icon unless it draws as one
  function _plain(shown) {
    return shown.kind === "name" || shown.kind === "text" && (shown.written || !root._drawsIcon(shown.text));
  }

  // Along the bar: the rest length, longer for text that needs it (with
  // half a cell's thickness of room around it, and its leading icon and a
  // gap before it) or a row of icons
  function _length(shown, icons) {
    if (shown.kind === "icons" && root.iconLayout === "row")
      return WorkspaceCells.rowLength(icons.length, root.thickness, root.restLength);
    if (!root._plain(shown))
      return root.restLength;
    // The size read, so a binding calling this measures again when it changes
    if (root._metrics.font.pixelSize <= 0)
      return root.restLength;
    const lead = shown.lead === "" ? 0 : root._leadLength(shown.lead) + WorkspaceCells.iconGap(root.thickness);
    return Math.max(root.restLength, Math.ceil(root._metrics.advanceWidth(shown.text) + lead) + Math.round(root.thickness * 0.5));
  }

  // A label's own length along the bar, no room around it (a split cell's
  // label): an icon at the size a cell draws it, or words measured; with its
  // leading icon and a gap. A label that doesn't turn on a vertical bar is
  // as tall as it is.
  function _labelLength(shown) {
    const size = Math.round(root.barConfig.fontSize * 1.2);
    const lead = shown.lead === "" ? 0 : root._leadLength(shown.lead) + WorkspaceCells.iconGap(root.thickness);
    if (!root._plain(shown))
      return size + lead;
    if (root._metrics.font.pixelSize <= 0)
      return size + lead;
    const words = Math.ceil(root._metrics.advanceWidth(shown.text) + lead);
    return root.barConfig.vertical && words <= root.thickness * 0.8 ? Math.ceil(root._metrics.height) : words;
  }

  // A label's leading icon along the bar: an icon at the size a cell
  // draws it (WorkspaceCell), else its text measured
  function _leadLength(icon) {
    // (The metrics are at the bar's font size less 1; an icon at 1.2 times it)
    return root._drawsIcon(icon) ? Math.round((root._metrics.font.pixelSize + 1) * 1.2) : root._metrics.advanceWidth(icon);
  }
}
