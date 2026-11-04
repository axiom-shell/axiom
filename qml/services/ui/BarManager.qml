pragma Singleton
import QtQuick
import qs.config
import qs.components.methods
import qs.services.core
import qs.services.compositor

/* BarManager holds the bar editor's working copy of the Bars section (its
 * `style`, every bar's look unless a bar sets its own, and the bars,
 * `items`). Edits
 * show live on the running bars (through ConfigManager.previews) as
 * they're made; saveChanges() writes them to config.json, resetChanges()
 * drops them. The preview is never part of ConfigManager.config, so other
 * saves (a theme, the settings page) don't persist unsaved bar edits.
 *
 * Also keeps the page's own state (selected bar and widget), since the
 * page is unloaded whenever the overlay closes, and, while the page is on
 * screen, what the running bars report back about the selected bar.
 * The running bars themselves are ScreenEdgeManager's.
 *
 * Every edit can be undone (`history`: the bars and the selection, taken
 * before each edit; edits to one field in a row are one step). The widget
 * hovered on the page's board is outlined on the running bars
 * (`hoveredWidget`), and the one hovered on a running bar is reported
 * back (`barHover`). */
QtObject {
  id: root

  property ConfigDraft _draft: ConfigDraft {
    id: draft
    path: ["Bars"]
    onRefused: root.applyChanges()
  }
  // The bars (Bars.items) in the draft, and as saved
  readonly property var localConfig: draft.local?.items ?? null
  readonly property var savedConfig: draft.saved?.items ?? null
  // The style every bar inherits (Bars.style) in the draft
  readonly property var localStyle: draft.local?.style ?? null
  readonly property alias isDirty: draft.isDirty
  property int selectedBarIndex: 0
  // The widget open in the inspector: { zone, index }, zone "" for none
  property var selectedWidget: ({
      "zone": "",
      "index": -1
    })
  // The section last selected or added to, where the library adds
  property string lastZone: "center"

  // The selected bar as the board's live chips draw its widgets: the
  // draft bar enriched at a fixed thickness, along a top edge (chips are
  // rows) whatever its own, standing alone (no ends meet it)
  readonly property var previewConfig: {
    const bar = root.selectedBar();
    if (!bar)
      return null;
    const config = BarsConfig.enrichBarConfig(Object.assign({}, bar, {
      "thickness": Math.round(Widget.px(BarsConfig.referenceThickness)),
      "location": "top"
    }), CompositorManager.gapsOut, ScreenEdgeManager.floatGaps);
    const end = {
      "kind": "bare",
      "reach": 0,
      "joinable": false
    };
    return Object.assign(config, {
      "ends": {
        "start": end,
        "end": end
      },
      "outerReach": 0,
      "stripCover": 0
    });
  }

  // Undo and redo of the draft's bars, with the selection
  readonly property EditHistory history: EditHistory {
    snapshot: () => ({
          "items": root.localConfig ?? [],
          "bar": root.selectedBarIndex,
          "widget": root.selectedWidget
        })
    restore: snap => root._restore(snap)
  }

  // The widget hovered on the editor's board, in the selected bar:
  // { zone, index }, zone "" for none. The running bars outline it
  readonly property var hoveredWidget: root._hoveredWidget
  property var _hoveredWidget: ({
      "zone": "",
      "index": -1
    })
  // The widget under the pointer on a running bar, while editing:
  // { source (its bar's config id), zone, index }, or null
  readonly property var barHover: root._barHover
  property var _barHover: null

  // A bar's look: its `style`, and its fields in the look groups
  // (`x-group`), not its identity, placement, behaviour or widgets
  readonly property var styleGroups: ["Size", "Surface"]
  readonly property var styleKeys: ["style"].concat(...BarsConfig.fieldGroups.filter(group => root.styleGroups.includes(group.title)).map(group => group.keys))
  // The style copied with copyStyle(): { index, values }, or null. By
  // index, since ids may be empty or shared: kept pointing at its bar as
  // bars are added, moved and removed. Never saved.
  property var copiedStyle: null

  // The bar editor pages on screen (`watch`/`unwatch`). While there are
  // any, the running bars outline the selected widget and report to `live`
  property ConsumerRegistry _watchers: ConsumerRegistry {}
  readonly property bool editing: root._watchers.active
  // What each running bar reports while editing, by its id (a bar on every
  // monitor has one per screen): { source (its config entry's id), screen,
  // hidden: { zone: [widget indices hidden for want of room] }, selected:
  // how it sizes the selected widget ({ policy, size, preferred, minimum,
  // priority }), or null }
  readonly property var live: root._live
  property var _live: ({})

  function watch(owner) {
    root._watchers.acquire(owner, true);
  }

  function unwatch(owner) {
    root._watchers.release(owner);
    if (!root.editing) {
      root._barHover = null;
      root.setHoveredWidget("", -1);
    }
  }

  function setLive(id, report) {
    if (id && JSON.stringify(root._live[id]) !== JSON.stringify(report))
      root._live = Utils.withEntry(root._live, id, report ?? undefined);
  }

  // Clears a bar's report, unless another bar (on another screen) has
  // taken its id since
  function clearLive(id, screenName) {
    if (root._live[id]?.screen === screenName)
      root._live = Utils.withEntry(root._live, id, undefined);
  }

  // The selected bar's reports, one per screen it's on, by screen name
  function liveReports() {
    const id = selectedBar()?.id;
    return Object.values(root.live).filter(report => report.source === id).sort((a, b) => a.screen.localeCompare(b.screen));
  }

  // Whether a running bar (by its config entry's id) shows the selected
  // widget, while editing
  function isSelectedWidget(source, zone, index) {
    const sel = root.selectedWidget;
    return root.editing && sel.zone === zone && sel.index === index && selectedBar()?.id === source;
  }

  // Whether a running bar shows the widget hovered on the board
  function isHoveredWidget(source, zone, index) {
    const hover = root.hoveredWidget;
    return root.editing && hover.zone === zone && hover.index === index && selectedBar()?.id === source;
  }

  // The board's hovered widget (zone "" for none)
  function setHoveredWidget(zone, index) {
    if (root._hoveredWidget.zone !== zone || root._hoveredWidget.index !== index)
      root._hoveredWidget = {
        "zone": zone,
        "index": index
      };
  }

  // A running bar's widget the pointer entered (`hovered`) or left
  function setBarHover(source, zone, index, hovered) {
    const hover = root._barHover;
    const same = hover !== null && hover.source === source && hover.zone === zone && hover.index === index;
    if (hovered && !same)
      root._barHover = {
        "source": source,
        "zone": zone,
        "index": index
      };
    else if (!hovered && same)
      root._barHover = null;
  }

  // Whether the selected bar's widget is under the pointer on a running bar
  function isBarHovered(zone, index) {
    const hover = root.barHover;
    return root.editing && hover !== null && hover.zone === zone && hover.index === index && hover.source === selectedBar()?.id;
  }

  onSelectedBarIndexChanged: {
    clearSelection();
    setHoveredWidget("", -1);
  }

  function selectBar(index) {
    root.selectedBarIndex = index;
  }

  // Records an undo step before an edit; edits with the same `fieldKey`
  // in a row (typing, a stepper) join one step, "" is a step of its own
  function _record(fieldKey) {
    root.history.record(fieldKey ?? "");
  }

  // Puts a snapshot (history) back: the bars, then the bar and widget
  // selected then
  function _restore(snap) {
    const items = root.localConfig;
    if (!items)
      return;
    items.splice(0, items.length, ...Utils.clone(snap.items));
    root.selectedBarIndex = Math.max(0, Math.min(snap.bar, items.length - 1));
    root.selectedWidget = snap.widget;
    if (!selectedWidgetConfig())
      clearSelection();
    applyChanges();
  }

  function undo() {
    root.history.undo();
  }

  function redo() {
    root.history.redo();
  }

  // Keeps the selected bar and widget where they still exist
  function loadConfig() {
    draft.load();
    root.history.clear();
    ConfigManager.clearPreview("Bars");
    selectedBarIndex = Math.max(0, Math.min(selectedBarIndex, (root.localConfig?.length ?? 1) - 1));
    if (root.copiedStyle && root.copiedStyle.index >= (root.localConfig?.length ?? 0))
      root.copiedStyle = null;
    if (!selectedWidgetConfig())
      clearSelection();
  }

  // Loads the draft unless it holds unsaved edits (the page is rebuilt
  // whenever the overlay reopens)
  function ensureLoaded() {
    if (!draft.isDirty)
      loadConfig();
  }

  // Call after mutating localConfig in place: shows the edit on the
  // running bars while the draft differs from the saved config
  function applyChanges() {
    draft.changed();
    if (draft.isDirty)
      ConfigManager.setPreview("Bars", draft.local);
    else
      ConfigManager.clearPreview("Bars");
  }

  // Whether a bar differs from its saved version (matched by id)
  function barChanged(index) {
    const bar = root.localConfig?.[index];
    const saved = (root.savedConfig ?? []).find(b => b.id === bar?.id);
    return JSON.stringify(bar) !== JSON.stringify(saved);
  }

  function selectedBar() {
    return root.localConfig?.[root.selectedBarIndex] || null;
  }

  function _zone(zone) {
    const bar = selectedBar();
    if (!bar)
      return null;
    if (!bar.widgets)
      bar.widgets = {};
    if (!bar.widgets[zone])
      bar.widgets[zone] = [];
    return bar.widgets[zone];
  }

  // --- Bars ---

  function addBar() {
    // Every other field comes from the Bar schema's defaults
    const bar = ConfigManager.withDefaults({
      "id": _uniqueId("bar-" + (root.localConfig.length + 1))
    }, "Bar");
    _record();
    root.localConfig.push(bar);
    root.selectedBarIndex = root.localConfig.length - 1;
    applyChanges();
  }

  // An id no bar in the draft has: `base`, else `base-2`, `base-3`, ...
  function _uniqueId(base) {
    return Utils.freeId(base, root.localConfig.map(b => b.id), "-");
  }

  // Inserts a copy after the bar and selects it. A copy of a bar on one
  // monitor moves to the first screen with no bar on that edge yet, so it
  // doesn't sit on the original. Its widgets start unselected, whichever
  // bar was selected before.
  function duplicateBar(index) {
    const bar = root.localConfig?.[index];
    if (!bar)
      return;
    _record();
    const copy = Utils.clone(bar);
    copy.id = _uniqueId(`${bar.id}-copy`);
    if (bar.screen.mode !== "all") {
      const onEdge = root.localConfig.filter(b => b.location === bar.location);
      const taken = name => onEdge.some(b => b.screen.mode === "all" || General.screensFor(b.screen).some(s => s.name === name));
      const free = General.outputs.find(s => !taken(s.name));
      if (free)
        copy.screen = {
          "mode": "named",
          "names": [free.name]
        };
    }
    root.localConfig.splice(index + 1, 0, copy);
    _moveCopied(i => i > index ? i + 1 : i);
    root.selectedBarIndex = index + 1;
    // Already index + 1 (a copy of the bar before the selected one), the
    // change handler didn't clear the old bar's widget
    clearSelection();
    applyChanges();
  }

  // The name a bar is listed by: its id, else its place
  function barLabel(index) {
    return root.localConfig?.[index]?.id || I18n.tr("Bar {0}", index + 1);
  }

  // Follows the copied style's bar to its new index (-1: it's gone)
  function _moveCopied(map) {
    if (!root.copiedStyle)
      return;
    const index = map(root.copiedStyle.index);
    root.copiedStyle = index < 0 ? null : {
      "index": index,
      "values": root.copiedStyle.values
    };
  }

  function copyStyle(index) {
    const bar = root.localConfig?.[index];
    if (!bar)
      return;
    root.copiedStyle = {
      "index": index,
      "values": Utils.clone(root.styleKeys.reduce((out, key) => {
        if (key in bar)
          out[key] = bar[key];
        return out;
      }, {}))
    };
  }

  function _pasteStyleOnto(bar) {
    Object.assign(bar, Utils.clone(root.copiedStyle.values));
  }

  function pasteStyle(index) {
    const bar = root.localConfig?.[index];
    if (!bar || !root.copiedStyle)
      return;
    _record();
    _pasteStyleOnto(bar);
    applyChanges();
  }

  function pasteStyleToAll() {
    if (!root.copiedStyle)
      return;
    _record();
    root.localConfig.forEach(bar => _pasteStyleOnto(bar));
    applyChanges();
  }

  // The selection stays on its bar (and widget), unless that's the bar
  // removed: then the one in its place is selected
  function removeBar(index) {
    if (root.localConfig.length <= 1 || !root.localConfig[index])
      return; // never remove the last bar
    _record();
    const selected = root.selectedBarIndex;
    const widget = root.selectedWidget;
    root.localConfig.splice(index, 1);
    _moveCopied(i => i === index ? -1 : i > index ? i - 1 : i);
    if (index === selected) {
      root.selectedBarIndex = Math.min(selected, root.localConfig.length - 1);
      clearSelection();
    } else if (index < selected) {
      root.selectedBarIndex = selected - 1;
      root.selectedWidget = widget;
    }
    applyChanges();
  }

  function updateBarField(key, value) {
    const bar = selectedBar();
    if (!bar || JSON.stringify(bar[key]) === JSON.stringify(value))
      return;
    _record(`bar:${root.selectedBarIndex}:${key}`);
    bar[key] = value;
    applyChanges();
  }

  // --- A bar's own style ---
  // A bar's `style` holds a BarStyle whose keys it leaves null take the
  // shared one's (Bars.style). The editor switches whole groups
  // (BarsConfig.styleGroups' keys): owned, each key holds a value of the bar's
  // own; not, all are null.

  // Whether the bar at `index` sets any of `keys` itself
  function ownsStyle(index, keys) {
    const style = root.localConfig?.[index]?.style ?? {};
    return keys.some(key => key === "shadow" ? Object.values(style.shadow ?? {}).some(value => value !== null) : (style[key] ?? null) !== null);
  }

  // Gives the selected bar its own `keys`, starting from what it inherits,
  // or (`owned` false) hands them back to the shared style
  function setStyleOwned(keys, owned) {
    const bar = selectedBar();
    if (!bar)
      return;
    _record();
    const style = bar.style;
    for (const key of keys) {
      if (key === "shadow") {
        const shared = root.localStyle.shadow;
        style.shadow = Object.keys(style.shadow).reduce((out, part) => {
          out[part] = owned ? shared[part] : null;
          return out;
        }, {});
      } else {
        style[key] = owned ? root._inherited(key) : null;
      }
    }
    applyChanges();
  }

  // One key of the selected bar's own style (`part` of its shadow)
  function updateStyleField(key, value, part) {
    const bar = selectedBar();
    if (!bar)
      return;
    const current = part ? bar.style[key]?.[part] : bar.style[key];
    if (JSON.stringify(current) === JSON.stringify(value))
      return;
    _record(`style:${root.selectedBarIndex}:${key}:${part ?? ""}`);
    if (part)
      bar.style[key][part] = value;
    else
      bar.style[key] = value;
    applyChanges();
  }

  // What a bar's style key is while it's null: the shared style's, or
  // (null there too) the setting it follows (SettingsManager.inheritedValue)
  function _inherited(key) {
    const shared = root.localStyle[key] ?? null;
    return shared !== null ? shared : SettingsManager.inheritedValue(ConfigManager.configSchema.definitions.BarStyle.properties[key]);
  }

  // --- Widgets ---

  function selectWidget(zone, index) {
    root.selectedWidget = {
      "zone": zone,
      "index": index
    };
    if (zone !== "")
      root.lastZone = zone;
  }

  function clearSelection() {
    selectWidget("", -1);
  }

  function selectedWidgetConfig() {
    const sel = root.selectedWidget;
    return sel.zone === "" ? null : (selectedBar()?.widgets?.[sel.zone]?.[sel.index] ?? null);
  }

  // Inserts a new widget at `index` (the end by default) and selects it;
  // `widgetType` may be a library key (CustomWidgetsConfig.splitKey)
  function addWidget(zone, widgetType, index = -1) {
    const arr = _zone(zone);
    if (!arr)
      return;
    const at = index < 0 || index > arr.length ? arr.length : index;
    const key = CustomWidgetsConfig.splitKey(widgetType);
    // Properties start at the widget schema's defaults
    const widget = ConfigManager.withDefaults({
      "id": root._widgetId(key.type, selectedBar()),
      "type": key.type
    }, "BarWidget");
    if (key.properties)
      widget.properties = Object.assign({}, widget.properties, key.properties);
    _record();
    arr.splice(at, 0, widget);
    selectWidget(zone, at);
    applyChanges();
  }

  // Appends `widget` ({ type, properties }, the rest from the schema's
  // defaults) to bar `barIndex`'s `zone` and selects that bar and widget;
  // for other editors (an edge menu's "Add to a bar")
  function addWidgetTo(barIndex, zone, widget) {
    ensureLoaded();
    const bar = root.localConfig?.[barIndex];
    if (!bar)
      return;
    _record();
    if (!bar.widgets)
      bar.widgets = {};
    if (!bar.widgets[zone])
      bar.widgets[zone] = [];
    bar.widgets[zone].push(ConfigManager.withDefaults(Object.assign({
      "id": root._widgetId(widget.type, bar)
    }, widget), "BarWidget"));
    selectBar(barIndex);
    selectWidget(zone, bar.widgets[zone].length - 1);
    applyChanges();
  }

  function removeWidget(zone, index) {
    const arr = selectedBar()?.widgets?.[zone];
    if (!arr || index < 0 || index >= arr.length)
      return;
    _record();
    arr.splice(index, 1);
    const sel = root.selectedWidget;
    if (sel.zone === zone) {
      if (sel.index === index)
        clearSelection();
      else if (sel.index > index)
        selectWidget(zone, sel.index - 1);
    }
    applyChanges();
  }

  function duplicateWidget(zone, index) {
    const arr = selectedBar()?.widgets?.[zone];
    if (!arr?.[index])
      return;
    _record();
    const copy = Utils.clone(arr[index]);
    copy.id = root._widgetId(copy.type, selectedBar());
    arr.splice(index + 1, 0, copy);
    selectWidget(zone, index + 1);
    applyChanges();
  }

  // Moves a widget to `toIndex` in `toZone`, counted as if it were still in
  // place (so dropping it just after itself leaves it where it is). The
  // selection follows whatever moved.
  function moveWidget(fromZone, fromIndex, toZone, toIndex) {
    const from = selectedBar()?.widgets?.[fromZone];
    const to = _zone(toZone);
    if (!from || !to || fromIndex < 0 || fromIndex >= from.length)
      return;
    let at = Math.max(0, Math.min(toIndex, to.length));
    if (fromZone === toZone && at > fromIndex)
      at--;
    if (fromZone === toZone && at === fromIndex)
      return;
    _record();

    const sel = root.selectedWidget;
    const [item] = from.splice(fromIndex, 1);
    to.splice(at, 0, item);

    if (sel.zone === fromZone && sel.index === fromIndex) {
      selectWidget(toZone, at);
    } else if (sel.zone !== "") {
      // Shift a selection the move went past
      let index = sel.index;
      if (sel.zone === fromZone && index > fromIndex)
        index--;
      if (sel.zone === toZone && index >= at)
        index++;
      if (index !== sel.index)
        selectWidget(sel.zone, index);
    }
    applyChanges();
  }

  // A new widget's id: unique among every widget of the bar (they move
  // between its sections)
  function _widgetId(type, bar) {
    const all = [].concat(...BarsConfig.sectionNames.map(section => bar?.widgets?.[section] ?? []));
    return Utils.newId(type, all);
  }

  function _widget(zone, index) {
    return selectedBar()?.widgets?.[zone]?.[index] ?? null;
  }

  function updateWidgetProperty(zone, index, key, value) {
    const widget = _widget(zone, index);
    if (!widget || JSON.stringify(widget.properties?.[key]) === JSON.stringify(value))
      return;
    _record(`widget:${root.selectedBarIndex}:${zone}:${index}:${key}`);
    if (!widget.properties)
      widget.properties = {};
    widget.properties[key] = value;
    applyChanges();
  }

  function setWidgetVisible(zone, index, visible) {
    const widget = _widget(zone, index);
    if (!widget || (widget.visible !== false) === visible)
      return;
    _record();
    if (visible)
      delete widget.visible;
    else
      widget.visible = false;
    applyChanges();
  }

  // Layout overrides are optional: an empty value removes the override
  function updateWidgetLayout(zone, index, key, value) {
    const widget = _widget(zone, index);
    if (!widget)
      return;
    const layout = Object.assign({}, widget.layout ?? {});
    if (value === undefined || value === null || value === "")
      delete layout[key];
    else
      layout[key] = value;
    if (JSON.stringify(layout) === JSON.stringify(widget.layout ?? {}))
      return;
    _record(`layout:${root.selectedBarIndex}:${zone}:${index}:${key}`);
    if (Object.keys(layout).length > 0)
      widget.layout = layout;
    else
      delete widget.layout;
    applyChanges();
  }

  // A widget's priority (layout.priority; null drops the override)
  function setWidgetPriority(zone, index, value) {
    updateWidgetLayout(zone, index, "priority", value);
  }

  // The most length a widget takes (layout.maxSize; null drops it)
  function setWidgetMax(zone, index, value) {
    updateWidgetLayout(zone, index, "maxSize", value);
  }

  // Moves the selected widget to the start or end (`atEnd`) of `zone`
  function moveWidgetTo(zone, atEnd) {
    const sel = root.selectedWidget;
    if (!selectedWidgetConfig())
      return;
    moveWidget(sel.zone, sel.index, zone, atEnd ? (_zone(zone)?.length ?? 0) : 0);
  }

  // Moves the selected widget one place back (`step` -1) or on (1) along
  // the bar: from a section's end into the next section's near end
  function stepWidget(step) {
    const sel = root.selectedWidget;
    const arr = selectedBar()?.widgets?.[sel.zone];
    if (!arr?.[sel.index])
      return;
    const to = sel.index + step;
    if (to >= 0 && to < arr.length) {
      // Counted as if still in place: one past the next is just after it
      moveWidget(sel.zone, sel.index, sel.zone, step > 0 ? to + 1 : to);
      return;
    }
    const zones = BarsConfig.sectionNames;
    const next = zones[zones.indexOf(sel.zone) + step];
    if (next)
      moveWidget(sel.zone, sel.index, next, step > 0 ? 0 : (_zone(next)?.length ?? 0));
  }

  // Inserts a Spacer at `index` in `zone` and selects it
  function addSpacer(zone, index) {
    addWidget(zone, "Spacer", index);
  }

  // Appends a copy of the selected widget to the same section of bar
  // `barIndex` (with an id free there); the selection stays
  function copyWidgetToBar(barIndex) {
    const widget = selectedWidgetConfig();
    const bar = root.localConfig?.[barIndex];
    if (!widget || !bar || barIndex === root.selectedBarIndex)
      return;
    _record();
    const zone = root.selectedWidget.zone;
    const copy = Utils.clone(widget);
    copy.id = root._widgetId(copy.type, bar);
    if (!bar.widgets)
      bar.widgets = {};
    if (!bar.widgets[zone])
      bar.widgets[zone] = [];
    bar.widgets[zone].push(copy);
    applyChanges();
  }

  // Merged onto the latest real config; stays dirty if rejected
  function saveChanges() {
    if (!draft.save())
      return false;
    ConfigManager.clearPreview("Bars");
    return true;
  }

  // Discard edits: reload from the current config, and the bars with it
  function resetChanges() {
    loadConfig();
  }
}
