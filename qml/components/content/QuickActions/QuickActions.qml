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

// A grid of action tiles: any action of the shell's catalogue that takes
// no argument (ActionsManager: toggles, session actions, opening
// something), and a few tiles of its own that open a module (Brightness's
// sliders, Volume's mixer, the Theme and Wallpaper pickers) or pin its
// edge menu, in any mix. Tiles that can't work here are hidden
// (ActionsManager.available: night light without a way to tint the
// screen, power saver without power-profiles-daemon, …; pin outside an
// edge menu). Log out, restart and shut down ask for a second click.
// Names show on every tile or none ("auto": only when all fit whole),
// always ("show", elided) or never ("hide").
// "pills" draws wide tiles with a status line, as Android's quick settings
// do. Some tiles have a detail that grows over the grid (Wi-Fi's networks,
// Bluetooth's devices, Do not disturb's notifications, the VPNs, the audio
// mixer for the mutes, the recorder's options): a pill opens it from
// beside its icon, a tile on a right click or long press. The tiles of
// its own have nothing to switch: a tap opens theirs.
// properties: { actions: [ActionsManager ids, or "brightness", "volume", "themePicker", "wallpaperPicker", "pin"],
//               labels: "auto" | "show" | "hide", style: "tiles" | "pills" }
Card {
  id: root

  readonly property bool inMenu: EdgeMenuManager.canPin(root.host)
  readonly property bool pinned: root.inMenu && EdgeMenuManager.isPinned(root.host.id)

  // The tiles of its own (not catalogue actions)
  readonly property var ownTiles: ["brightness", "volume", "themePicker", "wallpaperPicker", "pin"]

  // The module a catalogue action's tile opens as its detail
  readonly property var details: ({
      "wifi": {
        "type": "WifiNetworks"
      },
      "bluetooth": {
        "type": "BluetoothDevices"
      },
      "toggleDnd": {
        "type": "Notifications"
      },
      "vpn": {
        "type": "VpnConnections"
      },
      "toggleMute": {
        "type": "AudioMixer",
        "properties": {
          "mode": "output"
        }
      },
      "toggleMicMute": {
        "type": "AudioMixer",
        "properties": {
          "mode": "input"
        }
      },
      "screenRecord": {
        "type": "ScreenRecord"
      }
    })

  // A tile of its own: { icon, label, active, status, detail,
  // detailProperties, opensOnly } (opensOnly: nothing to switch, a tap
  // opens its detail)
  function ownDef(name) {
    switch (name) {
    case "brightness":
      return {
        "icon": BrightnessManager.icon(root.brightnessLevel),
        "label": I18n.tr("Brightness"),
        "active": false,
        "status": I18n.tr("{0}%", Math.round(root.brightnessLevel * 100)),
        "detail": "Brightness",
        "detailProperties": {
          "monitor": "*"
        },
        "opensOnly": true
      };
    case "volume":
      return {
        "icon": AudioManager.outputIcon(AudioManager.deviceKind(AudioManager.defaultSink), AudioManager.muted, AudioManager.volume),
        "label": I18n.tr("Volume"),
        "active": false,
        "status": AudioManager.muted ? I18n.tr("Muted") : I18n.tr("{0}%", Math.round(AudioManager.volume * 100)),
        "detail": "AudioMixer",
        "detailProperties": {
          "mode": "output"
        },
        "opensOnly": true
      };
    case "themePicker":
      return {
        "icon": "palette",
        "label": I18n.tr("Theme"),
        "active": false,
        "status": ThemeManager.currentFamily?.label ?? ThemeManager.activeTheme,
        "detail": "ThemePicker",
        "opensOnly": true
      };
    case "wallpaperPicker":
      return {
        "icon": "wallpaper",
        "label": I18n.tr("Wallpaper"),
        "active": false,
        "status": String(ThemeManager.wallpaper ?? "").split("/").pop(),
        "detail": "WallpaperPicker",
        "opensOnly": true
      };
    case "pin":
      return {
        "icon": "push_pin",
        "label": root.pinned ? I18n.tr("Pinned") : I18n.tr("Pin open"),
        "active": root.pinned
      };
    }
    return null;
  }

  // A tile's look: its own, or its action's (ActionsManager.info), armed
  // for a second click when it asks for one
  function def(name) {
    const own = root.ownDef(name);
    if (own)
      return own;
    const info = ActionsManager.info(name);
    const destructive = ActionsManager.destructive(name);
    const armed = gate.armed === name;
    return {
      "icon": info.icon,
      "label": armed ? I18n.tr("Confirm?") : ActionsManager.label(name),
      "active": info.active || armed,
      "status": info.status,
      "detail": root.details[name]?.type,
      "detailProperties": root.details[name]?.properties,
      "destructive": destructive,
      "tone": destructive ? Theme.error : Theme.accent
    };
  }

  readonly property bool pills: root.properties.style === "pills"

  // Every monitor's, for the brightness tile
  readonly property real brightnessLevel: BrightnessManager.average(BrightnessManager.names)
  // Opens the action's detail from `from`, or runs it
  function tap(name, from) {
    const d = root.def(name);
    if (d.opensOnly && root.detailOf(d) !== "")
      root.expand(d.detail, d.detailProperties ?? {}, from);
    else
      root.run(name);
  }
  // The detail an action opens here ("" for none)
  function detailOf(def) {
    return def.detail && root.canExpand(def.detail) ? def.detail : "";
  }

  // Config, tool availability and host only (never toggle state:
  // ActionsManager.available reads none), so the tiles aren't rebuilt
  // whenever something is switched
  readonly property var actions: root.properties.actions
  readonly property var shown: root.actions.filter(a => {
    switch (a) {
    case "brightness":
      return BrightnessManager.names.length > 0;
    case "volume":
      return AudioManager.defaultSink !== null;
    case "themePicker":
    case "wallpaperPicker":
      return true;
    case "pin":
      return root.inMenu;
    }
    return ActionsManager.available(a);
  })

  // The VPNs' rows (Tailscale's among them) are listed while a VPN tile is
  readonly property bool showsVpn: root.actions.includes("vpn")
  onShowsVpnChanged: root.showsVpn ? VpnManager.acquire(root) : VpnManager.release(root)

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

  // Runs a tile's action: pin's own, else the catalogue's (ActionsManager.
  // run), behind a second click where it asks for one
  function run(name) {
    if (name === "pin") {
      EdgeMenuManager.togglePinned(root.host.id);
      return;
    }
    if (gate.pass(name, ActionsManager.destructive(name)))
      ActionsManager.run(name, {
        "fromScreen": true
      });
  }

  // Caffeine's time left, while it's on for a set time
  Component.onCompleted: {
    IdleManager.acquire(root, 1000);
    if (root.showsVpn)
      VpnManager.acquire(root);
  }
  Component.onDestruction: {
    IdleManager.release(root);
    VpnManager.release(root);
  }

  ConfirmGate {
    id: gate
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
        countdown: def.destructive ? gate.timeout : 0
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
        countdown: def.destructive ? gate.timeout : 0
        opens: detail !== ""
        onClicked: root.tap(action, pill)
        onOpened: root.expand(pill.detail, pill.def.detailProperties ?? {}, pill)
      }
    }
  }
}
