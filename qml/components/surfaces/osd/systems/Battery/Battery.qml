pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// The battery and charger on the OSD, each a tile its `tiles` picks: the
// charger (unusual on battery; plugging in is its card: the level,
// Charging / Fully charged / Plugged in, the time to full; it folds back
// as it's unplugged) and the battery dropping to low, then critical (its
// card, critical on the warning colour, only through
// BatteryManager.levelEvent, never the level alone). BatteryWatch reads
// BatteryManager; nothing is judged with no battery
OSDSystem {
  // The charger plugged in: its card; unplugged: its icon (the battery's
  // events: their card)
  onAdd: "card"
  retractsCardWhenOff: true

  // I18n.tr("Charger") I18n.tr("Low battery")
  readonly property var _keys: ({
      "charger": {
        "icon": "power",
        "label": "Charger"
      },
      "battery": {
        "icon": "battery_alert",
        "label": "Low battery",
        "model": "event"
      }
    })
  exposes: (options.tiles ?? ["charger", "battery"]).filter(key => _keys[key]).map(key => Object.assign({
      "key": key,
      "part": "tile"
    }, _keys[key]))

  // charger: { available, value (plugged), percent, charging, full,
  // untilFull (as shown) }; battery: { available, level ("none" | "low" |
  // "critical"), percent, timeLeft (as shown), event (levelEvent), seq }
  function tile(key, state) {
    const s = state ?? {};
    if (key === "charger") {
      const plugged = s.value === true;
      return {
        "name": plugged && s.percent !== undefined ? `${s.percent}%` : "",
        "on": plugged,
        "notable": s.available === true && !plugged,
        "hidden": s.available !== true
      };
    }
    // Lit and unusual while low or critical
    const level = s.level ?? "none";
    return {
      "icon": level === "critical" ? "battery_alert" : level === "low" ? "battery_low" : "battery_full",
      "name": `${s.percent ?? 0}%`,
      "on": level !== "none",
      "notable": level !== "none",
      "hidden": s.available !== true
    };
  }

  // I18n.tr("Fully charged") I18n.tr("Charging") I18n.tr("Plugged in")
  // I18n.tr("Battery low") I18n.tr("Battery critically low")
  function card(change, state) {
    const s = state[change.key] ?? {};
    if (change.key === "charger")
      return {
        "icon": "battery_charging_full",
        "title": `${s.percent ?? 0}%`,
        "role": s.full === true ? "Fully charged" : s.charging === true ? "Charging" : "Plugged in",
        "detail": s.full === true ? "" : (s.untilFull ?? "")
      };
    // The drop it says (the event's), not the level now, which turns
    // "none" as the charger goes in under a card shown: its icon too (not
    // the tile's, OSDEngine.cardOf's default)
    const critical = s.event?.level === "critical";
    return {
      "icon": critical ? "battery_alert" : "battery_low",
      "title": `${s.percent ?? 0}%`,
      "role": critical ? "Battery critically low" : "Battery low",
      "detail": s.timeLeft ?? "",
      "tone": critical ? "warning" : ""
    };
  }
}
