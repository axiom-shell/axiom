pragma Singleton
import QtQuick

// What an OSD item is and what it shows (the OSD's surfaces/osd): each
// type's shape (a level bar, a one-line status or the media card), which
// lock key or layout change is the user's, the status line of each type
// from its state, and which status may replace the one shown.
QtObject {
  id: root

  readonly property var _levels: ["master", "other", "app", "microphone", "brightness"]
  readonly property var _statuses: ["lockKeys", "keyboardLayout", "micMute", "outputDevice", "powerProfile", "caffeine", "dnd", "nightLight", "wifi", "bluetooth", "airplane", "charger", "message"]

  // "level" | "status" | "media" for an item's type, "" for none
  function shapeOf(type) {
    if (root._levels.includes(type))
      return "level";
    if (root._statuses.includes(type))
      return "status";
    return type === "media" ? "media" : "";
  }

  // The items of one shape, in order, each as { item, index } (its place
  // in the OSD's items)
  function ofShape(items, shape) {
    return items.map((item, index) => ({
          "item": item,
          "index": index
        })).filter(entry => root.shapeOf(entry.item.type) === shape);
  }

  // The lock key a lockKeys item shows that changed between two states
  // ({ available, caps, num, scroll }) as { key, on }, the first of caps,
  // num, scroll; null when none did, or when either state is unavailable
  // (the first reading, or the LEDs gone: not the user)
  function lockKeyChange(before, after, item) {
    if (!before || !after || !before.available || !after.available)
      return null;
    const key = ["caps", "num", "scroll"].find(k => item[k] === true && before[k] !== after[k]);
    return key ? {
      "key": key,
      "on": after[key] === true
    } : null;
  }

  // Whether the layout switched between two keyboard states ({ layouts,
  // index }): the same list of more than one layout, another index. A
  // changed list is a config reload, not a switch
  function layoutSwitched(before, after) {
    if (!before || !after || after.layouts.length < 2)
      return false;
    return JSON.stringify(before.layouts) === JSON.stringify(after.layouts) && before.index !== after.index;
  }

  // A status type's line from its state: { icon, text } with text English,
  // for the caller to translate, or { icon, value } with value shown as it
  // is (a name). States:
  //   lockKeys { key, on }, keyboardLayout { name }, micMute { muted },
  //   outputDevice { name }, powerProfile { profile: "powerSaver" |
  //   "balanced" | "performance" }, charger { plugged }, message { icon,
  //   text }, every other type { on }
  function status(type, state) {
    switch (type) {
    case "lockKeys":
      {
        const keys = {
          "caps": ["keyboard_capslock", "Caps Lock on", "Caps Lock off"],
          "num": ["dialpad", "Num Lock on", "Num Lock off"],
          "scroll": ["swap_vert", "Scroll Lock on", "Scroll Lock off"]
        };
        const k = keys[state.key];
        return {
          "icon": k[0],
          "text": state.on ? k[1] : k[2]
        };
      }
    case "keyboardLayout":
      return {
        "icon": "keyboard",
        "value": state.name
      };
    case "micMute":
      return {
        "icon": state.muted ? "mic_off" : "mic",
        "text": state.muted ? "Microphone off" : "Microphone on"
      };
    case "outputDevice":
      return {
        "icon": "speaker",
        "value": state.name
      };
    case "powerProfile":
      {
        const profiles = {
          "powerSaver": ["energy_savings_leaf", "Power saver"],
          "balanced": ["balance", "Balanced"],
          "performance": ["speed", "Performance"]
        };
        const p = profiles[state.profile] ?? profiles.balanced;
        return {
          "icon": p[0],
          "text": p[1]
        };
      }
    case "charger":
      return {
        "icon": state.plugged ? "power" : "power_off",
        "text": state.plugged ? "Charger plugged in" : "On battery"
      };
    case "message":
      return {
        "icon": state.icon,
        "value": state.text
      };
    }
    const toggles = {
      "caffeine": ["coffee", "coffee", "Caffeine on", "Caffeine off"],
      "dnd": ["notifications_off", "notifications", "Do not disturb on", "Do not disturb off"],
      "nightLight": ["nightlight", "light_mode", "Night light on", "Night light off"],
      "wifi": ["wifi", "wifi_off", "Wi-Fi on", "Wi-Fi off"],
      "bluetooth": ["bluetooth", "bluetooth_disabled", "Bluetooth on", "Bluetooth off"],
      "airplane": ["airplanemode_active", "airplanemode_inactive", "Airplane mode on", "Airplane mode off"]
    };
    const t = toggles[type];
    if (!t)
      return {
        "icon": "",
        "text": ""
      };
    return {
      "icon": state.on ? t[0] : t[1],
      "text": state.on ? t[2] : t[3]
    };
  }

  // How long after an airplane mode status the radios' own switching
  // (which airplane mode causes) doesn't replace it, in ms
  readonly property int radioQuiet: 2000

  // Whether a status of type `incoming` replaces `shown` (the type of the
  // status showing, "" for none) `elapsed` ms after it showed: always,
  // except Wi-Fi or Bluetooth just after airplane mode switched them
  function replaces(shown, incoming, elapsed) {
    return !(shown === "airplane" && (incoming === "wifi" || incoming === "bluetooth") && elapsed < root.radioQuiet);
  }
}
