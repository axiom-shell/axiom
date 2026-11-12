.pragma library
// Battery's timelines: the charger (unusual on battery; plugging in is its
// card: the level, Charging / Fully charged / Plugged in, the time to full;
// its card folds back as it's unplugged) and the battery dropping to low,
// then to critical (its card; critical's on the warning colour).
//
// State by key (BatteryWatch, BatteryManager):
//   charger  { available (isAvailable), value (plugged: !onBattery), percent,
//            charging (isCharging), full (isFull), untilFull (timeToFull, as
//            shown) }
//   battery  { available, level ("none" | "low" | "critical", now),
//            percent, timeLeft (timeRemaining, as shown), event
//            (BatteryManager.levelEvent: { level, serial }, set only as the
//            level drops, once settled; or null), seq }
//
// decided: `battery` is an "event" model key (its card comes only with
//   levelEvent, never from `level` alone), its tile reading `level` from
//   the same state; `charger` is a scalar on `value` (plugged).

var opts = { "shows": ["charger", "battery"] };

function ch(plugged, extra) {
  return Object.assign({ "available": true, "value": plugged, "percent": 64, "charging": false, "full": false, "untilFull": "" }, extra || {});
}
function bat(level, percent, timeLeft, event, seq) {
  return { "available": true, "level": level, "percent": percent, "timeLeft": timeLeft || "", "event": event || null, "seq": seq || 0 };
}

var rows = [
  {
    "name": "no battery: both tiles hidden",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "charger": ch(false, { "available": false }), "battery": Object.assign(bat("none", 0), { "available": false }) },
        "tiles": { "charger": { "hidden": true }, "battery": { "hidden": true } } }
    ]
  },
  {
    "name": "the battery at no level: its tile unlit, ordinary",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "charger": ch(false), "battery": bat("none", 64) },
        "tiles": { "battery": { "icon": "battery_full", "on": false, "notable": false, "hidden": false } } }
    ]
  },
  {
    "name": "the first reading shows nothing",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "charger": ch(true), "battery": bat("low", 18, "", { "level": "low", "serial": 1 }, 1) } }
    ]
  },
  // ---- The charger ----
  {
    "name": "plugged in, charging: its card, the level, Charging and the time to full",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "charger": ch(false), "battery": bat("none", 64) } },
      { "at": 3000, "state": { "charger": ch(true, { "charging": true, "untilFull": "1h 20m" }) },
        "expect": { "key": "charger", "show": "card", "kind": "add",
          "tile": { "icon": "power", "on": true, "notable": false, "hidden": false, "slash": false, "name": "64%" },
          "card": { "icon": "battery_charging_full", "title": "64%", "role": "Charging", "detail": "1h 20m", "clickable": false },
          "host": "open", "action": null } }
    ]
  },
  {
    "name": "plugged in, full: Fully charged, nothing left to full",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "charger": ch(false, { "percent": 100 }), "battery": bat("none", 100) } },
      { "at": 3000, "state": { "charger": ch(true, { "percent": 100, "full": true, "untilFull": "0m" }) },
        "expect": { "key": "charger", "show": "card", "card": { "title": "100%", "role": "Fully charged", "detail": "" } } }
    ]
  },
  {
    "name": "plugged in, not charging yet: Plugged in",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "charger": ch(false, { "percent": 80 }), "battery": bat("none", 80) } },
      { "at": 3000, "state": { "charger": ch(true, { "percent": 80 }) },
        "expect": { "key": "charger", "show": "card", "card": { "title": "80%", "role": "Plugged in" } } }
    ]
  },
  {
    "name": "unplugged: the icon, unlit and unusual",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "charger": ch(true), "battery": bat("none", 64) } },
      { "at": 3000, "state": { "charger": ch(false) },
        "expect": { "key": "charger", "show": "tile", "kind": "remove", "tile": { "icon": "power", "on": false, "notable": true, "name": "" }, "host": "ring" } }
    ]
  },
  {
    "name": "unplugged just after plugging in: the card folds back",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "charger": ch(false), "battery": bat("none", 64) } },
      { "at": 3000, "state": { "charger": ch(true) },
        "expect": { "key": "charger", "show": "card", "host": "open" } },
      { "at": 3300, "state": { "charger": ch(false) },
        "expect": { "key": "charger", "show": "tile", "host": "retract" } }
    ]
  },
  {
    "name": "the level, charging or the time changing: nothing",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "charger": ch(true, { "charging": true }), "battery": bat("none", 64) } },
      { "at": 3000, "state": { "charger": ch(true, { "percent": 65, "charging": true, "untilFull": "1h" }) } },
      { "at": 6000, "state": { "charger": ch(true, { "percent": 100, "full": true }) } }
    ]
  },
  {
    "name": "no battery: nothing, nor as UPower answers",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "charger": { "available": false, "value": true, "percent": 0, "charging": false, "full": false, "untilFull": "" } } },
      { "at": 3000, "state": { "charger": ch(false) } }
    ]
  },
  {
    "name": "the charger's tile not listed: nothing",
    "options": { "shows": ["battery"] },
    "steps": [
      { "at": 0, "state": { "charger": ch(false), "battery": bat("none", 64) } },
      { "at": 3000, "state": { "charger": ch(true) } }
    ]
  },
  // ---- The battery ----
  {
    "name": "dropped to low: its card, the level, Battery low and the time left",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "charger": ch(false, { "percent": 21 }), "battery": bat("none", 21, "1h 15m") } },
      { "at": 3000, "state": { "battery": bat("low", 18, "1h 5m", { "level": "low", "serial": 1 }, 1) },
        "expect": { "key": "battery", "show": "card", "kind": "event",
          "tile": { "icon": "battery_low", "on": true, "notable": true, "hidden": false, "slash": false },
          "card": { "icon": "battery_low", "title": "18%", "role": "Battery low", "detail": "1h 5m", "tone": "", "clickable": false },
          "host": "open" } }
    ]
  },
  {
    "name": "dropped to critical: on the warning colour",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "charger": ch(false), "battery": bat("low", 8, "", { "level": "low", "serial": 1 }, 1) } },
      { "at": 3000, "state": { "battery": bat("critical", 6, "", { "level": "critical", "serial": 2 }, 2) },
        "expect": { "key": "battery", "show": "card",
          "tile": { "icon": "battery_alert", "on": true, "notable": true },
          "card": { "icon": "battery_alert", "title": "6%", "role": "Battery critically low", "detail": "", "tone": "warning" } } }
    ]
  },
  {
    "name": "a critical drop's card says critical though the level reads none (plugged in under it)",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "charger": ch(false), "battery": bat("low", 8, "", { "level": "low", "serial": 1 }, 1) } },
      { "at": 3000, "state": { "battery": bat("none", 6, "", { "level": "critical", "serial": 2 }, 2) },
        "expect": { "key": "battery", "show": "card",
          "card": { "icon": "battery_alert", "title": "6%", "role": "Battery critically low", "tone": "warning" } } }
    ]
  },
  {
    "name": "the level changing without an event (never at the start, nor rising): nothing",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "charger": ch(false), "battery": bat("none", 30) } },
      { "at": 3000, "state": { "battery": bat("low", 18, "1h") } },
      { "at": 6000, "state": { "battery": bat("none", 40, "3h") } }
    ]
  },
  {
    "name": "the event cleared: nothing",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "charger": ch(false), "battery": bat("low", 18, "", { "level": "low", "serial": 1 }, 1) } },
      { "at": 3000, "state": { "battery": bat("low", 18, "", null, 1) } }
    ]
  },
  {
    "name": "the battery's tile not listed: nothing",
    "options": { "shows": ["charger"] },
    "steps": [
      { "at": 0, "state": { "charger": ch(false), "battery": bat("none", 21) } },
      { "at": 3000, "state": { "battery": bat("low", 18, "", { "level": "low", "serial": 1 }, 1) } }
    ]
  },
  {
    "name": "plugged in just after the low card: the charger's card replaces it",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "charger": ch(false, { "percent": 19 }), "battery": bat("none", 19) } },
      { "at": 3000, "state": { "battery": bat("low", 18, "", { "level": "low", "serial": 1 }, 1) },
        "expect": { "key": "battery", "show": "card", "host": "open" } },
      { "at": 3500, "state": { "charger": ch(true, { "percent": 18, "charging": true }) },
        "expect": { "key": "charger", "show": "card", "host": "replace" } }
    ]
  }
];
