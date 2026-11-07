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
  // (ShellManager.fromScreen) opens an OSD too
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

  // The system an event type (NotificationManager.announce's) belongs to
  readonly property var _eventSystems: ({
      "drive": "Drives",
      "battery": "Battery",
      "monitor": "Monitors",
      "screenshot": "Screenshot",
      "bluetooth": "Bluetooth"
    })

  // Where an event of `type` (drive, battery, monitor, screenshot,
  // bluetooth) goes (OSDEngine.cardRoute, by its system): "osd" (an OSD
  // opens its card: OSDEngine.opensCard; the low battery's only where
  // Battery shows its battery icon), else "notification" with `notify`
  // (its section's switch: Battery.notify, Drives.notify,
  // Monitors.notify, Screenshots.notify), else "" (nowhere)
  function routeOf(type, notify) {
    const system = root._eventSystems[type];
    const osds = type !== "battery" ? root.osds : root.osds.filter(osd => {
      const item = OSDEngine.itemOf(osd, system);
      return item !== null && item.tiles.includes("battery");
    });
    return OSDEngine.cardRoute(osds, system, notify);
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
  // An Audio bar's kind's English name (its schema's x-enumLabels)
  readonly property var _audioBarLabels: root._systemDefs.Audio.properties.bars.items.properties.type["x-enumLabels"]

  // A system's name, translated: its label in the schema (its type's
  // description); "" for one there isn't
  function nameOf(type) {
    const english = root._systemDefs[type]?.properties.type.description;
    return english ? I18n.tr(english) : "";
  }

  // The name on its tab: its own, else its bars', else what it shows as
  // icons (so the default isn't named by all of them), else Now playing
  function labelOf(osd) {
    if (osd.name)
      return osd.name;
    const shown = osd.systems.filter(item => item.tile !== false);
    const bars = [].concat(...shown.map(item => item.type === "Brightness" ? [root.nameOf("Brightness")] : item.type === "Audio" ? item.bars.map(bar => bar.type === "app" ? (bar.apps.join(" / ") || I18n.tr("An app")) : I18n.tr(root._audioBarLabels[bar.type])) : []));
    // (a system with no tile switch is only ever a card)
    const parts = bars.length > 0 ? bars : shown.filter(item => root._systemDefs[item.type]?.properties.tile !== undefined).map(item => root.nameOf(item.type)).filter(name => name !== "");
    if (parts.length > 0)
      return parts.join(", ");
    return osd.cardsEnabled && OSDEngine.itemOf(osd, "Media") !== null ? I18n.tr("Now playing") : I18n.tr("Empty OSD");
  }
}
