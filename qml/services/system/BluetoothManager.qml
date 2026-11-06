pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.core

// Bluetooth state and actions over the default adapter, from axiom's
// `bluetooth` part (BlueZ on the system bus, internal/bluez:
// `bluetooth.state` on every change). Devices are plain objects
// ({ address, name, deviceName, icon, paired, bonded, trusted, blocked,
// connected, state, pairing, battery, batteryAvailable }), made anew on
// every push: compare them by address. Not named Bluetooth: the bar
// widget's file has that name. Inert on the login screen.
QtObject {
  id: root

  // The default adapter ({ address, name, powered, blocked, discovering,
  // discoverable, pairable }), else null
  property var adapter: null
  readonly property bool available: adapter !== null
  readonly property bool enabled: adapter?.powered ?? false
  readonly property bool blocked: adapter?.blocked ?? false
  readonly property bool discovering: adapter?.discovering ?? false

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

  // The daemon's devices, in its order (the order they turned up),
  // battery as a 0–1 ratio
  property var _devices: []
  readonly property bool _inert: Paths.greeter

  function _show(state) {
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
      root._fetch();
      // A daemon started again has no scan running
      if (root._wantsDiscovery)
        root._discover(true);
    }
  }

  Component.onCompleted: {
    if (root._inert)
      return;
    BackendManager.listen("bluetooth.state", state => root._show(state));
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
