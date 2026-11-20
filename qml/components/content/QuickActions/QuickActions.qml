pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.core
import qs.services.session
import qs.services.system
import qs.services.ui
import qs.components.content.parts
import qs.components.content.base

// A grid of action tiles: any action of the shell's catalogue that takes
// no argument (ActionsManager: toggles, session actions, opening
// something), and a few tiles of its own that open a module (Brightness's
// sliders, Volume's mixer, the Theme and Wallpaper pickers) or pin its
// edge menu, in any mix. Tiles that can't work here are hidden
// (ActionsManager.available: night light without a way to tint the
// screen, power saver without power-profiles-daemon, …; pin outside an
// edge menu). Log out, restart and shut down ask for a second click.
// Names show on each tile where it fits ("auto"), always ("show", elided)
// or never ("hide"). "pills" draws wide tiles with a status line, as
// Android's quick settings do; "auto" picks by the card's height
// (ActionTiles). Some tiles have a detail that grows over the grid (Wi-Fi's networks,
// Bluetooth's devices, Do not disturb's notifications, the VPNs, the audio
// mixer for the mutes, the recorder's options): a pill opens it from
// beside its icon, a tile on a right click or long press. The tiles of
// its own have nothing to switch: a tap opens theirs.
// properties: { actions: [ActionsManager ids, or "brightness", "volume", "themePicker", "wallpaperPicker", "pin"],
//               labels: "auto" | "show" | "hide", style: "auto" | "tiles" | "pills" }
Card {
  id: root

  readonly property bool inMenu: MenuManager.canPin(root.host)
  readonly property bool pinned: root.inMenu && MenuManager.isPinned(root.host.id)

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
      "tone": destructive ? "error" : "accent"
    };
  }

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

  // Runs a tile's action: pin's own, else the catalogue's (ActionsManager.
  // run), behind a second click where it asks for one
  function run(name) {
    if (name === "pin") {
      MenuManager.togglePinned(root.host.id);
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

  ActionTiles {
    anchors.fill: parent
    anchors.margins: root.pad
    style: root.properties.style
    labels: root.properties.labels
    tiles: root.shown.map(a => {
      const d = root.def(a);
      return {
        "icon": d.icon,
        "label": d.label,
        "status": d.status ?? "",
        "active": d.active,
        "tone": d.tone,
        "countdown": d.destructive ? gate.timeout : 0,
        "opens": root.detailOf(d) !== ""
      };
    })
    onClicked: (index, tile) => root.tap(root.shown[index], tile)
    onOpened: (index, tile) => root.expand(root.detailOf(root.def(root.shown[index])), root.def(root.shown[index]).detailProperties ?? {}, tile)
  }
}
