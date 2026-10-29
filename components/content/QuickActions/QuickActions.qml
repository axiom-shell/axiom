pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.core
import qs.services.session
import qs.services.system
import qs.services.ui
import qs.components.content.parts
import qs.components.reusable
import qs.components.content.base

// A grid of action tiles: toggles, session actions and pin, in any mix.
// Tiles that can't work here are hidden: night light (no color transform,
// gamma control or wlsunset) and power saver (power-profiles-daemon)
// without their tool, pin outside an edge menu. Log out, reboot and power
// off ask for a second click.
// Names show on every tile or none ("auto": only when all fit whole),
// always ("show", elided) or never ("hide").
// "pills" draws wide tiles with a status line, as Android's quick settings
// do. Wi-Fi, Bluetooth and Do not disturb have a detail (their networks,
// devices, notifications) that grows over the grid, as does Brightness
// (every monitor's sliders), which has nothing to switch: a tap opens it: a pill opens it from
// beside its icon, a tile on a right click or long press.
// properties: { actions: ["wifi", "bluetooth", "caffeine", "dnd", "darkMode", "nightLight", "powerSaver",
//                         "brightness", "lock", "suspend", "hibernate", "logout", "reboot", "poweroff", "pin"],
//               labels: "auto" | "show" | "hide", style: "tiles" | "pills" }
Card {
  id: root

  property string armed: ""

  readonly property bool inMenu: EdgeMenuManager.canPin(root.host)
  readonly property bool pinned: root.inMenu && EdgeMenuManager.isPinned(root.host.id)

  readonly property var sessionActions: ["lock", "suspend", "hibernate", "logout", "reboot", "poweroff"]

  readonly property var defs: ({
      "wifi": {
        "icon": NetworkingManager.wifiEnabled ? "wifi" : "wifi_off",
        "label": I18n.tr("Wi-Fi"),
        "active": NetworkingManager.wifiEnabled,
        "status": !NetworkingManager.wifiEnabled ? I18n.tr("Off") : NetworkingManager.netInfo.kind === "wifi" ? NetworkingManager.netInfo.name : I18n.tr("Not connected"),
        "detail": "WifiNetworks"
      },
      "bluetooth": {
        "icon": BluetoothManager.enabled ? "bluetooth" : "bluetooth_disabled",
        "label": I18n.tr("Bluetooth"),
        "active": BluetoothManager.enabled,
        "status": root.bluetoothStatus,
        "detail": "BluetoothDevices"
      },
      "caffeine": {
        "icon": "coffee",
        "label": I18n.tr("Caffeine"),
        "active": IdleManager.caffeine,
        "status": IdleManager.caffeineTimed ? IdleManager.caffeineText : root.onOff(IdleManager.caffeine)
      },
      "dnd": {
        "icon": NotificationManager.dnd ? "notifications_off" : "notifications",
        "label": I18n.tr("Do not disturb"),
        "active": NotificationManager.dnd,
        "status": root.onOff(NotificationManager.dnd),
        "detail": "Notifications"
      },
      "darkMode": {
        "icon": "clear_night",
        "label": I18n.tr("Dark mode"),
        "active": Appearance.darkMode,
        "status": root.onOff(Appearance.darkMode)
      },
      "nightLight": {
        "icon": "nightlight",
        "label": I18n.tr("Night light"),
        "active": NightLightManager.active,
        "status": root.onOff(NightLightManager.active)
      },
      "powerSaver": {
        "icon": "eco",
        "label": I18n.tr("Power saver"),
        "active": BatteryManager.powerSaver,
        "status": root.onOff(BatteryManager.powerSaver)
      },
      "brightness": {
        "icon": root.brightnessLevel < 0.34 ? "brightness_low" : root.brightnessLevel < 0.67 ? "brightness_medium" : "brightness_high",
        "label": I18n.tr("Brightness"),
        "active": false,
        "status": I18n.tr("{0}%", Math.round(root.brightnessLevel * 100)),
        "detail": "Brightness",
        "detailProperties": {
          "monitor": "*"
        },
        // Nothing to switch: a tap opens the sliders
        "opensOnly": true
      },
      "pin": {
        "icon": "push_pin",
        "label": root.pinned ? I18n.tr("Pinned") : I18n.tr("Pin open"),
        "active": root.pinned
      }
    })

  readonly property bool pills: root.properties.style === "pills"

  function onOff(on) {
    return on ? I18n.tr("On") : I18n.tr("Off");
  }
  readonly property string bluetoothStatus: {
    if (!BluetoothManager.enabled)
      return I18n.tr("Off");
    const connected = BluetoothManager.connectedDevices;
    if (connected.length === 1)
      return BluetoothManager.deviceLabel(connected[0]);
    return connected.length > 1 ? I18n.tr("{0} connected", connected.length) : I18n.tr("On");
  }
  // The detail an action opens here ("" for none)
  // Every monitor's, for the brightness tile
  readonly property real brightnessLevel: BrightnessManager.average(BrightnessManager.names)
  // Opens the action's detail from `from`, or runs it (a toggle)
  function tap(name, from) {
    const d = root.def(name);
    if (d.opensOnly && root.detailOf(d) !== "")
      root.expand(d.detail, d.detailProperties ?? {}, from);
    else
      root.run(name);
  }
  function detailOf(def) {
    return def.detail && root.canExpand(def.detail) ? def.detail : "";
  }

  function def(name) {
    if (!root.sessionActions.includes(name))
      return root.defs[name];
    const info = SessionManager.sessionActionInfo(name);
    const destructive = SessionManager.destructiveActions.includes(name);
    return {
      "icon": info.icon,
      "label": root.armed === name ? I18n.tr("Confirm?") : info.label,
      "active": root.armed === name,
      "destructive": destructive,
      "tone": destructive ? Theme.error : Theme.accent
    };
  }

  // Config, tool availability and host only (never toggle state), so the
  // tiles aren't rebuilt whenever something is switched: a literal list,
  // not defs' keys (defs follows the toggles)
  readonly property var known: ["wifi", "bluetooth", "caffeine", "dnd", "darkMode", "nightLight", "powerSaver", "brightness", "pin"].concat(root.sessionActions)
  readonly property var actions: root.properties.actions.filter(a => root.known.includes(a))
  readonly property var shown: root.actions.filter(a => {
    switch (a) {
    case "wifi":
      return NetworkingManager.available;
    case "bluetooth":
      return BluetoothManager.available;
    case "nightLight":
      return NightLightManager.available;
    case "powerSaver":
      return BatteryManager.hasPowerProfiles;
    case "brightness":
      return BrightnessManager.names.length > 0;
    case "pin":
      return root.inMenu;
    default:
      return !root.sessionActions.includes(a) || SessionManager.sessionActionInfo(a) !== null;
    }
  })

  // Every tile is the same size, so the names all fit when the widest does
  // (ActionTile.labelFits, measured in its label font)
  readonly property string labels: root.properties.labels
  // "Confirm?" counts for the actions that ask, so arming one doesn't hide
  // every name
  readonly property var _fitLabels: root.shown.map(a => root.def(a).label).concat(root.shown.some(a => SessionManager.destructiveActions.includes(a)) ? [I18n.tr("Confirm?")] : [])
  readonly property real widestLabel: Math.max(0, ...root._fitLabels.map(label => labelFont.advanceWidth(label)))
  readonly property bool labelsFit: root.widestLabel <= grid.tileWidth - Widget.spacing * 2 && grid.tileHeight >= Appearance.fontSize * 4.5

  FontMetrics {
    id: labelFont
    font.family: Appearance.fontFamily
    font.pixelSize: Appearance.fontSizeBy(-1)
  }

  function run(name) {
    if (root.sessionActions.includes(name)) {
      if (SessionManager.destructiveActions.includes(name) && root.armed !== name) {
        root.armed = name;
        disarm.restart();
        return;
      }
      root.armed = "";
      SessionManager.sessionAction(name);
      return;
    }
    switch (name) {
    case "wifi":
      NetworkingManager.toggleWifi();
      break;
    case "bluetooth":
      BluetoothManager.toggleEnabled();
      break;
    case "caffeine":
      IdleManager.toggle();
      break;
    case "dnd":
      NotificationManager.toggleDnd();
      break;
    case "darkMode":
      ThemeManager.toggleDarkMode();
      break;
    case "nightLight":
      NightLightManager.toggle();
      break;
    case "powerSaver":
      BatteryManager.setPowerSaver(!BatteryManager.powerSaver);
      break;
    case "pin":
      EdgeMenuManager.togglePinned(root.host.id);
      break;
    }
  }

  // Caffeine's time left, while it's on for a set time
  Component.onCompleted: IdleManager.acquire(root, 1000)
  Component.onDestruction: IdleManager.release(root)

  Timer {
    id: disarm
    interval: 3000
    onTriggered: root.armed = ""
  }

  TileGrid {
    id: grid
    anchors.fill: parent
    anchors.margins: root.pad
    count: root.shown.length
    maxAspect: root.pills ? 4 : 1.6
    minAspect: root.pills ? 2.2 : 0

    Repeater {
      model: root.pills ? 0 : root.shown.length

      ActionTile {
        id: tile
        required property int index
        readonly property string action: root.shown[index] ?? ""
        readonly property var def: root.def(action)
        readonly property string detail: root.detailOf(def)
        x: grid.tileX(index)
        y: grid.tileY(index)
        width: grid.tileWidth
        height: grid.tileHeight
        icon: def.icon
        label: def.label
        active: def.active
        showLabel: root.labels === "show" || (root.labels === "auto" && root.labelsFit)
        forceLabel: root.labels === "show"
        activeColor: def.destructive ? Theme.error : Theme.accent
        tone: def.tone ?? activeColor
        countdown: def.destructive ? disarm.interval : 0
        opens: detail !== ""
        onClicked: root.tap(action, tile)
        onOpened: root.expand(tile.detail, tile.def.detailProperties ?? {}, tile)
      }
    }

    Repeater {
      model: root.pills ? root.shown.length : 0

      ActionPill {
        id: pill
        required property int index
        readonly property string action: root.shown[index] ?? ""
        readonly property var def: root.def(action)
        readonly property string detail: root.detailOf(def)
        x: grid.tileX(index)
        y: grid.tileY(index)
        width: grid.tileWidth
        height: grid.tileHeight
        icon: def.icon
        label: def.label
        status: def.status ?? ""
        active: def.active
        activeColor: def.destructive ? Theme.error : Theme.accent
        tone: def.tone ?? activeColor
        countdown: def.destructive ? disarm.interval : 0
        opens: detail !== ""
        onClicked: root.tap(action, pill)
        onOpened: root.expand(pill.detail, pill.def.detailProperties ?? {}, pill)
      }
    }
  }
}
