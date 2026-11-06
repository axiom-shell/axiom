pragma Singleton
import QtQuick

import qs.config
import qs.components.methods
import qs.services.compositor
import qs.services.session
import qs.services.system
import qs.services.apps

/*
 * The shell's one catalogue of actions: the keybind table's (KeybindManager.
 * actionTable, from backend/internal/compositor/actions/table.json: ids,
 * labels, icons, their IPC calls) with each one's state now. Every place
 * that offers an action reads it here and runs it through run(): the
 * QuickActions tiles, the OSD's status icons, the launcher's commands, the
 * bar widgets' clicks, the Button widget and hot corners, as keybinds do
 * (`axiom ipc`), so each runs the same IPC function.
 * docs/dev/core/actions.md says how to add one.
 */
QtObject {
  id: root

  // The session actions, run through SessionManager (run())
  readonly property var sessionActions: ["lock", "suspend", "hibernate", "logout", "reboot", "poweroff"]

  // An action's name: the table's, as the Keybinds page shows it, or a
  // tile's shorter one
  function label(id) {
    switch (id) {
    case "toggleMute":
      return I18n.tr("Mute");
    case "toggleMicMute":
      return I18n.tr("Mute mic");
    case "vpn":
      return I18n.tr("VPN");
    case "screenRecord":
      return I18n.tr("Record");
    }
    const session = root.sessionActions.includes(id) ? SessionManager.sessionActionInfo(id) : null;
    return session?.label ?? KeybindManager.actionLabels[id] ?? id;
  }

  // Whether it asks for a second click on a tile or in the launcher
  function destructive(id) {
    return SessionManager.destructiveActions.includes(id);
  }

  // Whether whatever it needs is here (a device, a tool, what the
  // compositor can do): reads no on/off state, so a list of the actions
  // shown (a Repeater's model) isn't rebuilt when one is switched
  function available(id) {
    switch (id) {
    case "wifi":
      return NetworkingManager.available;
    case "bluetooth":
      return BluetoothManager.available;
    case "airplane":
      return NetworkingManager.available || BluetoothManager.available;
    case "vpn":
      return VpnManager.available;
    case "nightLight":
      return NightLightManager.available;
    case "powerSaver":
      return BatteryManager.hasPowerProfiles;
    case "toggleMute":
      return AudioManager.defaultSink !== null;
    case "toggleMicMute":
      return AudioManager.defaultSource !== null;
    case "screenRecord":
      return ScreenshotManager.hasRecorder;
    }
    if (root.sessionActions.includes(id))
      return SessionManager.sessionActionInfo(id) !== null;
    return KeybindManager.actionLabels[id] !== undefined && BindActions.supported(KeybindManager.actionTable, id, CompositorManager.supports);
  }

  // Its state now: { active, status, icon }. `active`: it's on;
  // `status`: a line for a pill or a command's row ("" for none). Reads
  // only its own action's service, so a binding on it wakes only for that
  // one
  function info(id) {
    switch (id) {
    case "wifi":
      return {
        "active": NetworkingManager.wifiEnabled,
        "icon": NetworkingManager.wifiEnabled ? "wifi" : "wifi_off",
        "status": !NetworkingManager.wifiEnabled ? I18n.tr("Off") : NetworkingManager.netInfo.kind === "wifi" ? NetworkingManager.netInfo.name : I18n.tr("Not connected")
      };
    case "bluetooth":
      return {
        "active": BluetoothManager.enabled,
        "icon": BluetoothManager.enabled ? "bluetooth" : "bluetooth_disabled",
        "status": root._bluetoothStatus()
      };
    case "airplane":
      return {
        "active": NetworkingManager.airplane,
        "icon": NetworkingManager.airplane ? "flight" : "airplanemode_inactive",
        "status": root._onOff(NetworkingManager.airplane)
      };
    case "vpn":
      return {
        "active": VpnManager.anyActive,
        "icon": "vpn_lock",
        "status": VpnManager.primary?.name ?? I18n.tr("Off")
      };
    case "idleInhibit":
      return {
        "active": IdleManager.caffeine,
        "icon": "coffee",
        "status": IdleManager.caffeineTimed ? IdleManager.caffeineText : root._onOff(IdleManager.caffeine)
      };
    case "toggleDnd":
      return {
        "active": NotificationManager.dnd,
        "icon": NotificationManager.dnd ? "notifications_off" : "notifications",
        "status": root._onOff(NotificationManager.dnd)
      };
    case "darkMode":
      return {
        "active": Appearance.darkMode,
        "icon": "clear_night",
        "status": root._onOff(Appearance.darkMode)
      };
    case "nightLight":
      return {
        "active": NightLightManager.active,
        "icon": "nightlight",
        "status": root._onOff(NightLightManager.active)
      };
    case "powerSaver":
      return {
        "active": BatteryManager.powerSaver,
        "icon": "eco",
        "status": root._onOff(BatteryManager.powerSaver)
      };
    case "toggleMute":
      return {
        "active": AudioManager.muted,
        "icon": AudioManager.outputIcon(AudioManager.deviceKind(AudioManager.defaultSink), AudioManager.muted, AudioManager.volume),
        "status": AudioManager.muted ? I18n.tr("Muted") : I18n.tr("{0}%", Math.round(AudioManager.volume * 100))
      };
    case "toggleMicMute":
      return {
        "active": AudioManager.sourceMuted,
        "icon": AudioManager.inputIcon(AudioManager.deviceKind(AudioManager.defaultSource), AudioManager.sourceMuted),
        "status": AudioManager.sourceMuted ? I18n.tr("Muted") : I18n.tr("{0}%", Math.round(AudioManager.sourceVolume * 100))
      };
    case "screenRecord":
      return {
        "active": ScreenshotManager.recording,
        "icon": ScreenshotManager.recording ? "stop_circle" : "videocam",
        "status": ScreenshotManager.recording ? StopwatchClock.format(ScreenshotManager.recordingElapsed * 1000) : I18n.tr("Off")
      };
    }
    if (root.sessionActions.includes(id)) {
      return {
        "active": false,
        "icon": SessionManager.sessionActionInfo(id)?.icon ?? "power_settings_new",
        "status": ""
      };
    }
    return {
      "active": false,
      "icon": KeybindManager.actionIcon(id),
      "status": ""
    };
  }

  // Runs it as its keybind would (ShellManager.runAction: its IPC
  // function, in place). `options`: { call: "toggle" | "open" | "close",
  // argument, fromScreen }; fromScreen marks the change as the pointer's
  // first (ShellManager.onScreen), so an OSD stays shut for it unless
  // OSD.onScreenChanges
  function run(id, options) {
    const opts = options ?? {};
    const kind = root.osdKind(id);
    if (opts.fromScreen && kind !== "")
      ShellManager.onScreen(kind);
    // The session's through SessionManager, as its own buttons ran them:
    // lock with a locker of the user's own (Lockscreen.mode "none"), whose
    // lockscreen IPC target is off, and log out, which isn't a table action
    if (root.sessionActions.includes(id))
      SessionManager.sessionAction(id);
    else
      ShellManager.runAction(id, opts.argument ?? "", opts.call ?? "toggle");
  }

  // The on-screen mark (ShellManager.onScreen's kind: OSDItems.
  // onScreenKind's) an action's change is judged by, or "" for none
  function osdKind(id) {
    return root._osdKinds[id] ?? "";
  }
  readonly property var _osdKinds: ({
      "wifi": "wifi",
      "bluetooth": "bluetooth",
      "airplane": "airplane",
      "vpn": "vpn",
      "idleInhibit": "caffeine",
      "toggleDnd": "dnd",
      "nightLight": "nightLight",
      "powerSaver": "powerProfile",
      "toggleMute": "audio",
      "volumeUp": "audio",
      "volumeDown": "audio",
      "toggleMicMute": "microphone",
      "brightnessUp": "brightness",
      "brightnessDown": "brightness",
      "inputSourceNext": "keyboardLayout",
      "inputSourcePrev": "keyboardLayout",
      "screenRecord": "recording"
    })

  // The action a click on an OSD status icon runs (its status type's), or
  // "" for a status nothing switches (a lock key, the battery, a drive)
  function osdStatusAction(type) {
    return root._statusActions[type] ?? "";
  }
  readonly property var _statusActions: ({
      "keyboardLayout": "inputSourceNext",
      "audio": "toggleMute",
      "microphone": "toggleMicMute",
      "powerProfile": "powerSaver",
      "caffeine": "idleInhibit",
      "dnd": "toggleDnd",
      "nightLight": "nightLight",
      "wifi": "wifi",
      "bluetooth": "bluetooth",
      "airplane": "airplane",
      "vpn": "vpn",
      "recording": "screenRecord"
    })

  function _onOff(on) {
    return on ? I18n.tr("On") : I18n.tr("Off");
  }

  function _bluetoothStatus() {
    if (!BluetoothManager.enabled)
      return I18n.tr("Off");
    const connected = BluetoothManager.connectedDevices;
    if (connected.length === 1)
      return BluetoothManager.deviceLabel(connected[0]);
    return connected.length > 1 ? I18n.tr("{0} connected", connected.length) : I18n.tr("On");
  }
}
