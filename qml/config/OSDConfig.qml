pragma Singleton
import QtQuick
import qs.components.methods
import qs.services.core

// Reader for the OSD section (the on-screen displays of levels, lock keys,
// the keyboard layout, toggles and the track). Named OSDConfig because
// `OSD` is the module type.
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.OSD

  // Level change per wheel notch (0-1); 0 when scrolling is off
  readonly property real scrollStep: _c.scrollToChange ? _c.scrollStep / 100 : 0
  // A change the pointer made in axiom's own bar and panels
  // (ShellManager.onScreen's mark, OSDEngine.byUser) opens an OSD too
  readonly property bool onScreenChanges: _c.onScreenChanges
  // [OSDEntry] (see the schema): each with its id, screen (a ScreenTarget),
  // place, `barLayout`, `row`, `cardsEnabled` / `cardTimeout` and
  // `systems` (what it shows, in order: [{ type, tile, card, quiet, …its
  // own settings }], an OSDSystem each). Goes through a string so a
  // reload that leaves the list unchanged doesn't rebuild the OSDs.
  readonly property string _osdsJson: JSON.stringify(_c.items)
  readonly property var osds: JSON.parse(_osdsJson)
  // The enabled ones, by id: what the shell builds
  readonly property var shownIds: osds.filter(osd => osd.enabled).map(osd => osd.id)
  // The streams the App bars of every OSD's Audio match, which the Other
  // apps bars skip
  readonly property var excludedApps: [].concat(...osds.map(osd => [].concat(...osd.systems.filter(item => item.type === "Audio").map(item => [].concat(...item.bars.filter(bar => bar.type === "app").map(bar => bar.apps))))))

  // An event card shown on an OSD (a drive, the battery, a monitor, a
  // screenshot, a message) is also filed in the notification history,
  // without a popup (NotificationManager.announce)
  readonly property bool cardsToHistory: _c.cardsToHistory

  // Where an event of the OSD system `system` and its key `key` (the
  // caller's: Drives' drive, Battery's battery, …) goes
  // (OSDEngine.cardRoute): "osd" (an OSD opens its card:
  // OSDEngine.opensCard; the low battery's only where Battery's `tiles`
  // pick `battery`), else "notification" with `notify` (its section's
  // switch: Battery.notify, Drives.notify, Monitors.notify,
  // Screenshots.notify), else "" (nowhere)
  function routeOf(system, key, notify) {
    return OSDEngine.cardRoute(root.osds, system, notify, key);
  }

  function osdById(id) {
    return osds.find(osd => osd.id === id) ?? null;
  }

  // The OSD a message goes to (`axiom message`) as its card: the one of
  // that id, else (`id` "") the first, of those that show Messages
  // (OSDEngine.opensCard); "" with none: it's a notification
  function messageOsd(id) {
    const showing = osds.filter(osd => OSDEngine.opensCard(osd, "Message"));
    const pick = id !== "" ? showing.find(osd => osd.id === id) : showing[0];
    return pick ? pick.id : "";
  }

  // The OSD systems' definitions in the schema (the OSDSystem kind's
  // oneOf), by type
  readonly property var _systemDefs: {
    const schema = ConfigManager.configSchema;
    const out = {};
    for (const option of schema.definitions.OSDSystem.oneOf) {
      const def = schema.definitions[option.$ref.replace("#/definitions/", "")];
      out[def.properties.type.const] = def;
    }
    return out;
  }
  // Every system an OSD can show, for the settings editor's list and its
  // picker: { type, label (English), icon, group (`x-libraryGroup`),
  // schema (its item's definition) }, in the kind's oneOf order
  readonly property var systemTypes: Object.keys(root._systemDefs).map(type => {
    const def = root._systemDefs[type];
    return {
      "type": type,
      "label": def.properties.type.description || type,
      "icon": def["x-icon"] ?? "extension",
      "group": def["x-libraryGroup"],
      "schema": def
    };
  })
  // A system's name, translated: its label in the schema (its type's
  // description); "" for one there isn't
  function nameOf(type) {
    const english = root._systemDefs[type]?.properties.type.description;
    return english ? I18n.tr(english) : "";
  }

  // The names of an item's bars, by its schema's `x-barNames`: "label",
  // its own name (Brightness); { from, by, named }, each entry of its
  // setting `from` by its `named` list joined, else its `by` field's
  // x-enumLabels (Audio's bars: an App bar by its apps, the others by
  // their kind); none without it
  function _barNames(item) {
    const def = root._systemDefs[item.type];
    const spec = def?.["x-barNames"];
    if (!spec)
      return [];
    if (spec === "label")
      return [root.nameOf(item.type)];
    const labels = def.properties[spec.from]?.items?.properties?.[spec.by]?.["x-enumLabels"] ?? {};
    return item[spec.from].map(entry => {
      const named = spec.named ? entry[spec.named] : [];
      return named.length > 0 ? named.join(" / ") : I18n.tr(labels[entry[spec.by]] ?? "");
    }).filter(name => name !== "");
  }

  // The name on its tab: its own, else its bars', else what it shows as
  // icons (so the default isn't named by all of them), else with its
  // cards on the systems it shows only as cards (Now playing, or a
  // system with a card switch and its tiles off)
  function labelOf(osd) {
    if (osd.name)
      return osd.name;
    const shown = osd.systems.filter(item => item.tile !== false);
    const bars = [].concat(...shown.map(item => root._barNames(item)));
    // (a system with no tile switch is only ever a card)
    const tiled = item => root._systemDefs[item.type]?.properties.tile !== undefined;
    const parts = bars.length > 0 ? bars : shown.filter(tiled).map(item => root.nameOf(item.type)).filter(name => name !== "");
    if (parts.length > 0)
      return parts.join(", ");
    const carded = item => !tiled(item) || (item.tile === false && root._systemDefs[item.type]?.properties.card !== undefined);
    const cards = osd.cardsEnabled ? osd.systems.filter(item => carded(item) && item.card !== false).map(item => root.nameOf(item.type)).filter(name => name !== "") : [];
    return cards.length > 0 ? cards.join(", ") : I18n.tr("Empty OSD");
  }
}
