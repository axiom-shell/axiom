pragma Singleton
import QtQuick
import qs.config
import qs.components.methods
import qs.services.core

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
 * The running bars themselves are ScreenEdgeManager's. */
QtObject {
  id: root

  property ConfigDraft _draft: ConfigDraft {
    id: draft
    path: ["Bars"]
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

  // A bar's look: its `style`, and its fields in the look groups
  // (`x-group`), not its identity, placement, behaviour or widgets
  readonly property var styleGroups: ["Size", "Style"]
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

  onSelectedBarIndexChanged: clearSelection()

  function selectBar(index) {
    root.selectedBarIndex = index;
  }

  // Keeps the selected bar and widget where they still exist
  function loadConfig() {
    draft.load();
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
  // doesn't sit on the original.
  function duplicateBar(index) {
    const bar = root.localConfig?.[index];
    if (!bar)
      return;
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
    _pasteStyleOnto(bar);
    applyChanges();
  }

  function pasteStyleToAll() {
    if (!root.copiedStyle)
      return;
    root.localConfig.forEach(bar => _pasteStyleOnto(bar));
    applyChanges();
  }

  function removeBar(index) {
    if (root.localConfig.length <= 1)
      return; // never remove the last bar
    root.localConfig.splice(index, 1);
    _moveCopied(i => i === index ? -1 : i > index ? i - 1 : i);
    root.selectedBarIndex = Math.max(0, Math.min(root.selectedBarIndex, root.localConfig.length - 1));
    clearSelection();
    applyChanges();
  }

  function updateBarField(key, value) {
    const bar = selectedBar();
    if (!bar)
      return;
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
    if (!widget)
      return;
    if (!widget.properties)
      widget.properties = {};
    widget.properties[key] = value;
    applyChanges();
  }

  function setWidgetVisible(zone, index, visible) {
    const widget = _widget(zone, index);
    if (!widget)
      return;
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
    if (Object.keys(layout).length > 0)
      widget.layout = layout;
    else
      delete widget.layout;
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
