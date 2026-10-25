pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Bluetooth

import qs.config

// Bluetooth state and actions over the default adapter (BlueZ via
// Quickshell.Bluetooth). Named BluetoothManager so it doesn't shadow
// Quickshell's `Bluetooth` singleton.
QtObject {
  id: root

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property bool available: adapter !== null
  readonly property bool enabled: adapter?.enabled ?? false
  readonly property bool blocked: adapter?.state === BluetoothAdapterState.Blocked
  readonly property bool discovering: adapter?.discovering ?? false

  // Every device, by name. Lists stay in a fixed order (not connected
  // first), so a row never jumps away from the pointer that just clicked it
  readonly property var devices: [...(adapter?.devices?.values ?? [])].sort((a, b) => deviceLabel(a).localeCompare(deviceLabel(b)))
  readonly property var pairedDevices: devices.filter(d => d.paired || d.bonded)
  // Nearby devices found by a scan, in the order they turned up (so new
  // ones join the end); unnamed ones (bare addresses) are noise
  readonly property var discoveredDevices: (adapter?.devices?.values ?? []).filter(d => !d.paired && !d.bonded && d.deviceName)
  readonly property var connectedDevices: devices.filter(d => d.connected)

  // Devices whose connect should follow a pair started from here
  property var _connectAfterPair: []

  function setEnabled(on) {
    if (adapter)
      adapter.enabled = on;
  }

  function toggleEnabled() {
    setEnabled(!enabled);
  }

  function setDiscovering(on) {
    if (adapter && enabled && adapter.discovering !== on)
      adapter.discovering = on;
  }

  // Connected: disconnect. Paired: connect. New: trust, pair, then connect.
  function toggleDevice(device) {
    if (!device || device.pairing || device.state === BluetoothDeviceState.Connecting || device.state === BluetoothDeviceState.Disconnecting)
      return;
    if (device.connected) {
      device.disconnect();
    } else if (device.paired || device.bonded) {
      device.connect();
    } else {
      device.trusted = true;
      _connectAfterPair = _connectAfterPair.concat([device]);
      device.pair();
    }
  }

  function forget(device) {
    device?.forget();
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
    case BluetoothDeviceState.Connecting:
      return I18n.tr("Connecting…");
    case BluetoothDeviceState.Disconnecting:
      return I18n.tr("Disconnecting…");
    case BluetoothDeviceState.Connected:
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

  // Finish "pair then connect" for devices paired from here
  property Instantiator _pairWatcher: Instantiator {
    model: root._connectAfterPair

    delegate: Connections {
      required property var modelData
      target: modelData

      function onPairedChanged() {
        root._connectAfterPair = root._connectAfterPair.filter(d => d !== modelData);
        if (modelData.paired)
          modelData.connect();
      }

      function onPairingChanged() {
        // Pairing ended without success (rejected, timed out)
        if (!modelData.pairing && !modelData.paired)
          root._connectAfterPair = root._connectAfterPair.filter(d => d !== modelData);
      }
    }
  }
}
