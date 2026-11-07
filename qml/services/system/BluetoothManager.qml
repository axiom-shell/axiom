pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.ui

// Bluetooth state and actions over the default adapter, from axiom's
// `bluetooth` part (BlueZ on the system bus, internal/bluez:
// `bluetooth.state` on every change, `bluetooth.event` as devices connect
// or disconnect), and a device's battery dropping to low or critical
// (BluetoothConfig's levels), said on the OSD or as a notification. Devices are plain objects
// ({ address, name, deviceName, icon, paired, bonded, trusted, blocked,
// connected, state, pairing, battery, batteryAvailable }), made anew on
// every push: compare them by address. The daemon is BlueZ's pairing
// agent (Bluetooth.pairingAgent): each of its requests (a PIN, a passkey,
// a code to confirm or type, an authorization) is shown through the
// shared prompt (PromptManager) and answered with bluetooth.agentReply.
// Not named Bluetooth: the bar widget's file has that name. Inert on the
// login screen.
QtObject {
  id: root

  // The default adapter ({ address, name, powered, blocked, hardBlocked,
  // discovering, discoverable, discoverableTimeout (s, 0 forever),
  // discoverableUntil (Unix ms, 0 unknown), pairable }), else null
  property var adapter: null
  readonly property bool available: adapter !== null
  readonly property bool enabled: adapter?.powered ?? false
  readonly property bool blocked: adapter?.blocked ?? false
  // A hardware switch blocks it: unblock() can't clear that
  readonly property bool hardBlocked: adapter?.hardBlocked ?? false
  readonly property bool discovering: adapter?.discovering ?? false
  readonly property bool discoverable: adapter?.discoverable ?? false
  // When it stops being discoverable (ms), 0 when not known
  readonly property real discoverableUntil: root.discoverable ? (adapter?.discoverableUntil ?? 0) : 0
  // Seconds left discoverable, ticking while something holds
  // acquireCountdown(owner) (a BluetoothDevices menu); -1 when not known
  property int discoverableLeft: -1

  // Every device, by name. Lists stay in a fixed order (not connected
  // first), so a row never jumps away from the pointer that just clicked it
  readonly property var devices: [...root._devices].sort((a, b) => deviceLabel(a).localeCompare(deviceLabel(b)))
  readonly property var pairedDevices: devices.filter(d => d.paired || d.bonded)
  // Nearby devices found by a scan, in the order they turned up (so new
  // ones join the end); unnamed ones (bare addresses) are noise
  readonly property var discoveredDevices: root._devices.filter(d => !d.paired && !d.bonded && d.deviceName)
  readonly property var connectedDevices: devices.filter(d => d.connected)

  // rpc: bluetooth.setPowered
  function setEnabled(on) {
    if (!root.available || root._inert)
      return;
    BackendManager.call("bluetooth.setPowered", {
      "on": on
    }, () => {});
  }

  function toggleEnabled() {
    setEnabled(!enabled);
  }

  // Discovery runs while anything has acquireDiscovery()ed it (a
  // BluetoothDevices menu on its Discover tab) and the radio is on
  function acquireDiscovery(owner) {
    _discoveryRegistry.acquire(owner, {});
  }

  function releaseDiscovery(owner) {
    _discoveryRegistry.release(owner);
  }

  // rpc: bluetooth.setDiscoverable
  // Visible to devices scanning (a phone pairing from its side), for
  // BlueZ's timeout (3 minutes when it had none)
  function setDiscoverable(on) {
    if (!root.available || root._inert)
      return;
    BackendManager.call("bluetooth.setDiscoverable", {
      "on": on
    }, () => {});
  }

  // rpc: bluetooth.unblock
  // Clears rfkill's soft block (not a hardware switch's)
  function unblock() {
    if (root._inert)
      return;
    BackendManager.call("bluetooth.unblock", {}, () => {});
  }

  function acquireCountdown(owner) {
    _countdownRegistry.acquire(owner, {});
    root._tickCountdown();
  }

  function releaseCountdown(owner) {
    _countdownRegistry.release(owner);
  }

  // rpc: bluetooth.setAlias
  // A new name for a device; "" is its own name again
  function setAlias(device, name) {
    if (!device || root._inert)
      return;
    BackendManager.call("bluetooth.setAlias", {
      "address": device.address,
      "name": name.trim()
    }, () => {});
  }

  // rpc: bluetooth.setTrusted
  // Trusted: it connects by itself (auto-connect)
  function setTrusted(device, on) {
    if (!device || root._inert)
      return;
    BackendManager.call("bluetooth.setTrusted", {
      "address": device.address,
      "on": on
    }, () => {});
  }

  // rpc: bluetooth.setBlocked
  // Blocked: disconnected, and its connections refused
  function setBlocked(device, on) {
    if (!device || root._inert)
      return;
    BackendManager.call("bluetooth.setBlocked", {
      "address": device.address,
      "on": on
    }, () => {});
  }

  // A call on the device is running: connecting, disconnecting or pairing
  function busy(device) {
    return !!device && (device.pairing || device.state === "connecting" || device.state === "disconnecting");
  }

  // The device as the last state shows it, by its address (a list handed
  // out earlier holds an older copy)
  function deviceByAddress(address) {
    return root._devices.find(d => d.address === address) ?? null;
  }

  // rpc: bluetooth.connect, bluetooth.disconnect, bluetooth.pair
  // Connected: disconnect. Paired: connect. New: trust, pair, then
  // connect (the daemon does all three). A failure shows only as the row
  // going back to what it was, as it did over Quickshell.
  function toggleDevice(device) {
    const d = root.deviceByAddress(device?.address ?? "");
    if (!d || root.busy(d) || root._inert)
      return;
    if (d.connected)
      BackendManager.call("bluetooth.disconnect", {
        "address": d.address
      }, () => {});
    else if (d.paired || d.bonded)
      BackendManager.call("bluetooth.connect", {
        "address": d.address
      }, () => {});
    else
      BackendManager.call("bluetooth.pair", {
        "address": d.address
      }, () => {});
  }

  // rpc: bluetooth.forget
  function forget(device) {
    if (!device || root._inert)
      return;
    BackendManager.call("bluetooth.forget", {
      "address": device.address
    }, () => {});
  }

  function deviceLabel(device) {
    return device?.name || device?.deviceName || device?.address || I18n.tr("Unknown");
  }

  function deviceStatus(device) {
    if (!device)
      return "";
    if (device.pairing)
      return I18n.tr("Pairing…");
    if (device.blocked)
      return I18n.tr("Blocked");
    switch (device.state) {
    case "connecting":
      return I18n.tr("Connecting…");
    case "disconnecting":
      return I18n.tr("Disconnecting…");
    case "connected":
      return device.batteryAvailable ? I18n.tr("Connected · {0}%", Math.round(device.battery * 100)) : I18n.tr("Connected");
    }
    return I18n.tr(device.paired || device.bonded ? "Paired" : "Not paired");
  }

  // Glyph for a device's freedesktop icon name (BlueZ "icon" property)
  function deviceIcon(device) {
    const icon = device?.icon || "";
    if (icon.includes("headset"))
      return "headset";
    if (icon.includes("headphone") || icon === "audio-card")
      return "headphones";
    if (icon.startsWith("audio"))
      return "speaker";
    if (icon.includes("mouse"))
      return "mouse";
    if (icon.includes("keyboard"))
      return "keyboard";
    if (icon.includes("gaming"))
      return "sports_esports";
    if (icon.includes("phone"))
      return "smartphone";
    if (icon.includes("computer"))
      return "laptop";
    return "bluetooth";
  }

  // The last thing said of devices, for the OSD's `bluetooth` card:
  // { kind: "connected" | "disconnected" (bluetooth.event, devices joined)
  // | "low" | "critical" (a battery drop, one device, set only when the
  // OSD says it: _sayLevel), devices: [{ address, name, icon (BlueZ's),
  // glyph (deviceIcon's), battery (0-100, -1 none) }], serial }, else null
  property var lastEvent: null
  property int _eventSerial: 0

  function _setEvent(kind, devices) {
    root._eventSerial += 1;
    root.lastEvent = {
      "kind": kind,
      "devices": devices.map(d => ({
            "address": d.address,
            "name": root.deviceLabel(d),
            "icon": d.icon ?? "",
            "glyph": root.deviceIcon(d),
            "battery": d.battery
          })),
      "serial": root._eventSerial
    };
  }

  // Each connected device's battery level as last judged
  // (DeviceBatteries.step's), null until a state is taken as it stands:
  // at the start, after a hello, while BlueZ is gone
  property var _levels: null

  function _checkLevels(devices) {
    const step = DeviceBatteries.step(root._levels, devices, BluetoothConfig.lowBattery, BluetoothConfig.criticalBattery);
    root._levels = step.last;
    for (const drop of step.drops) {
      const d = devices.find(x => x.address === drop.address);
      if (d)
        root._sayLevel(d, drop.level);
    }
  }

  // A device's battery dropping to `level` (`device` the daemon's), where
  // the OSD's `bluetooth` status puts it (NotificationManager.announce):
  // its card (lastEvent), else a notification. One entry per device:
  // critical replaces low
  function _sayLevel(device, level) {
    const body = level === "critical" ? I18n.tr("Battery critically low: {0}%", device.battery) : I18n.tr("Battery low: {0}%", device.battery);
    const route = NotificationManager.announce("bluetooth", true, root.deviceLabel(device), body, {
      "icon": device.icon || "bluetooth",
      "key": "bluetooth-battery:" + device.address
    });
    if (route === "osd")
      root._setEvent(level, [device]);
  }

  // The daemon's devices, in its order (the order they turned up),
  // battery as a 0–1 ratio
  property var _devices: []
  readonly property bool _inert: Paths.greeter

  // --- The pairing agent ---

  // The agent's requests shown: the daemon's id -> PromptManager's id
  property var _agentPrompts: ({})

  // bluetooth.agentRequest: a new request, or a code shown changing as
  // the keyboard types
  function _agentRequest(req) {
    const shown = root._agentPrompts[req.id];
    if (shown !== undefined) {
      PromptManager.update(shown, {
        "code": req.code,
        "entered": req.entered
      });
      return;
    }
    const name = req.device.name || req.device.address;
    const cancel = {
      "id": "cancel",
      "label": I18n.tr("Cancel")
    };
    const pair = {
      "id": "accept",
      "label": I18n.tr("Pair"),
      "primary": true
    };
    const deny = {
      "id": "cancel",
      "label": I18n.tr("Deny")
    };
    const allow = {
      "id": "accept",
      "label": I18n.tr("Allow"),
      "primary": true
    };
    const spec = {
      "source": "bluetooth",
      "icon": root.deviceIcon(req.device)
    };
    switch (req.kind) {
    case "confirm":
      Object.assign(spec, {
        "title": I18n.tr("Pair with {0}?", name),
        "message": I18n.tr("Does {0} show {1}?", name, req.code),
        "actions": [cancel, pair]
      });
      break;
    case "pin":
    case "passkey":
      Object.assign(spec, {
        "title": I18n.tr("Pair with {0}", name),
        "message": req.kind === "pin" ? I18n.tr("Type the PIN {0} asks for.", name) : I18n.tr("Type the passkey {0} asks for.", name),
        "fields": [
          {
            "key": "value",
            "label": req.kind === "pin" ? I18n.tr("PIN") : I18n.tr("Passkey"),
            "secret": false,
            "digits": req.kind === "passkey",
            "maxLength": req.kind === "pin" ? 16 : 6
          }
        ],
        "actions": [cancel, pair]
      });
      break;
    case "display":
      Object.assign(spec, {
        "title": I18n.tr("Pair with {0}", name),
        "message": I18n.tr("Type this code on {0}, then press Enter.", name),
        "code": req.code,
        "entered": req.entered,
        "actions": [cancel]
      });
      break;
    case "authorizeService":
      Object.assign(spec, {
        "title": I18n.tr("Allow {0}?", name),
        "message": I18n.tr("{0} wants to use a service of this computer.", name),
        "actions": [deny, allow]
      });
      break;
    default:
      // authorize
      Object.assign(spec, {
        "title": I18n.tr("Pair with {0}?", name),
        "message": I18n.tr("{0} wants to pair with this computer.", name),
        "actions": [deny, allow]
      });
    }
    const answer = (accept, value) => root._agentAnswer(req, accept, value);
    const prompts = Object.assign({}, root._agentPrompts);
    prompts[req.id] = PromptManager.request(spec, (action, values) => answer(action === "accept", values.value ?? ""), () => answer(false, ""));
    root._agentPrompts = prompts;
  }

  // rpc: bluetooth.agentReply, bluetooth.cancelPair
  // A code shown has nothing to answer: declining it cancels the pairing.
  // Accepting is the user's doing, as a menu's click is: the connect it
  // leads to updates an open OSD but opens none (the prompt may have
  // waited past the click's window)
  function _agentAnswer(req, accept, value) {
    root._forgetPrompt(req.id);
    if (accept)
      ShellManager.onScreen("bluetooth");
    if (req.kind === "display")
      BackendManager.call("bluetooth.cancelPair", {
        "address": req.device.address
      }, () => {});
    BackendManager.call("bluetooth.agentReply", {
      "id": req.id,
      "accept": accept,
      "value": value
    }, () => {});
  }

  // bluetooth.agentDone: BlueZ, the pairing's end or an answer ended it
  function _agentDone(id) {
    const shown = root._agentPrompts[id];
    if (shown === undefined)
      return;
    PromptManager.withdraw(shown);
    root._forgetPrompt(id);
  }

  function _forgetPrompt(id) {
    const prompts = Object.assign({}, root._agentPrompts);
    delete prompts[id];
    root._agentPrompts = prompts;
  }

  // A daemon started again asks nothing of what the last one asked
  function _dropAgentPrompts() {
    for (const id of Object.keys(root._agentPrompts))
      PromptManager.withdraw(root._agentPrompts[id]);
    root._agentPrompts = {};
  }

  function _show(state) {
    if (state?.available)
      root._checkLevels(state.devices ?? []);
    else
      root._levels = null;
    root.adapter = state?.adapter ?? null;
    root._devices = (state?.devices ?? []).map(d => Object.assign({}, d, {
        "battery": d.battery >= 0 ? d.battery / 100 : 0,
        "batteryAvailable": d.battery >= 0
      }));
  }

  // rpc: bluetooth.discovery
  function _discover(on) {
    BackendManager.call("bluetooth.discovery", {
      "on": on
    }, () => {});
  }

  function _fetch() {
    BackendManager.call("bluetooth.get", {}, (error, state) => {
      if (!error)
        root._show(state);
    });
  }

  property ConsumerRegistry _countdownRegistry: ConsumerRegistry {}

  function _tickCountdown() {
    root.discoverableLeft = root.discoverableUntil > 0 ? Math.max(0, Math.ceil((root.discoverableUntil - Date.now()) / 1000)) : -1;
  }
  onDiscoverableUntilChanged: root._tickCountdown()

  property Timer _countdown: Timer {
    interval: 1000
    repeat: true
    running: root._countdownRegistry.active && root.discoverableUntil > 0
    onTriggered: root._tickCountdown()
  }

  property ConsumerRegistry _discoveryRegistry: ConsumerRegistry {}
  readonly property bool _wantsDiscovery: _discoveryRegistry.active && enabled

  // The daemon's scan is a session of its own (BlueZ keeps one per
  // client): stopping it never ends another app's
  on_WantsDiscoveryChanged: {
    if (!root._inert)
      root._discover(root._wantsDiscovery);
  }

  property Connections _backend: Connections {
    target: BackendManager
    enabled: !root._inert
    function onGreeted() {
      root._dropAgentPrompts();
      // A new daemon's state is taken as it stands
      root._levels = null;
      root._fetch();
      // The scan is the daemon's, not this shell's: one a shell gone
      // mid-scan left running stops, one a daemon started again lost starts
      root._discover(root._wantsDiscovery);
    }
  }

  Component.onCompleted: {
    if (root._inert)
      return;
    BackendManager.listen("bluetooth.state", state => root._show(state));
    BackendManager.listen("bluetooth.agentRequest", request => root._agentRequest(request));
    BackendManager.listen("bluetooth.agentDone", done => root._agentDone(done.id));
    BackendManager.listen("bluetooth.event", event => root._setEvent(event.kind, event.devices));
    // Made after the hello (a QML reload): no greeted to wait for
    if (BackendManager.ready)
      root._fetch();
  }

  // address -> label of the connected devices, replaced only when that
  // changes: every push makes new device objects, and each change would
  // start the notes' settle again
  property var _connectedLabels: ({})
  onConnectedDevicesChanged: {
    const next = root.connectedDevices.reduce((all, device) => {
      all[device.address] = root.deviceLabel(device);
      return all;
    }, {});
    if (JSON.stringify(next) !== JSON.stringify(root._connectedLabels))
      root._connectedLabels = next;
  }

  // Devices connecting and disconnecting, as silent notes
  property ConnectionNotes _notes: ConnectionNotes {
    prefix: "bluetooth"
    icon: "bluetooth"
    connected: root._connectedLabels
  }

  // Keybind action bluetooth: axiom ipc bluetooth toggle|enable|disable
  property IpcTarget _ipc: IpcTarget {
    target: "bluetooth"

    function toggle(): void {
      root.toggleEnabled();
    }

    function enable(): void {
      root.setEnabled(true);
    }

    function disable(): void {
      root.setEnabled(false);
    }
  }
}
