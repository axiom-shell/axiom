pragma Singleton
import QtQuick
import Quickshell.Networking

import qs.config

// Wi-Fi state and actions over NetworkManager (Quickshell.Networking, D-Bus,
// so nothing polls). Named NetworkingManager so it doesn't shadow
// Quickshell's `Networking` singleton. Scanning runs only while something
// has acquireScan()ed it (the Wi-Fi popout or card).
QtObject {
  id: root

  readonly property var devices: Networking.devices?.values ?? []
  readonly property var wifiDevice: devices.find(d => d.type === DeviceType.Wifi) ?? null
  readonly property bool available: wifiDevice !== null
  readonly property bool wifiEnabled: Networking.wifiEnabled
  readonly property bool hardwareBlocked: !Networking.wifiHardwareEnabled
  readonly property bool scanning: wifiDevice?.scannerEnabled ?? false

  // Named networks: connected first, then saved, then by name. The order
  // doesn't follow signal strength, so a row never jumps away from the
  // pointer that's about to click it
  readonly property var networks: (wifiDevice?.networks?.values ?? []).filter(n => n.name).sort((a, b) => {
    const rank = n => n.connected ? 0 : n.known ? 1 : 2;
    return rank(a) - rank(b) || a.name.localeCompare(b.name);
  })
  readonly property var activeNetwork: networks.find(n => n.connected) ?? null

  // The primary connection: a connected wired device first (NetworkManager's
  // default route metrics prefer it), else the connected Wi-Fi device
  readonly property var primaryDevice: devices.find(d => d.type === DeviceType.Wired && d.connected) ?? devices.find(d => d.type === DeviceType.Wifi && d.connected) ?? null
  readonly property string primaryKind: primaryDevice === null ? "" : primaryDevice.type === DeviceType.Wifi ? "wifi" : "ethernet"
  // SSID on Wi-Fi; when wired, the connection profile's id ("Wired
  // connection 1"), since a wired Network is named after its interface
  readonly property string primaryName: {
    if (primaryDevice === null)
      return "";
    if (primaryKind === "wifi")
      return activeNetwork?.name || primaryDevice.name;
    const settings = primaryDevice.network?.nmSettings ?? [];
    return (settings.length > 0 ? settings[0].id : "") || primaryDevice.name;
  }
  // 0-100, Wi-Fi only
  readonly property int primarySignal: primaryKind === "wifi" ? Math.round((activeNetwork?.signalStrength ?? 0) * 100) : 0
  // IPv4 address: Quickshell.Networking doesn't expose IP configuration, so
  // it's looked up once with `ip` whenever the primary connection changes
  property string primaryIp: ""
  // { kind, name, device, signal, ip }
  readonly property var netInfo: ({
      "kind": primaryKind,
      "name": primaryName,
      "device": primaryDevice?.name ?? "",
      "signal": primarySignal,
      "ip": primaryIp
    })

  // The network whose password was just asked for (a secured network
  // clicked, or a failed attempt), and the last failure per network name
  property var passwordFor: null
  property var failures: ({})

  function setWifiEnabled(on) {
    Networking.wifiEnabled = on;
  }

  function toggleWifi() {
    setWifiEnabled(!wifiEnabled);
  }

  function acquireScan(owner) {
    _scanRegistry.acquire(owner, {});
  }

  function releaseScan(owner) {
    _scanRegistry.release(owner);
  }

  function isSecure(network) {
    const s = network?.security;
    return s !== undefined && s !== WifiSecurityType.Open && s !== WifiSecurityType.Owe;
  }

  // Only these take a PSK (see WifiNetwork.connectWithPsk)
  function takesPsk(network) {
    const s = network?.security;
    return s === WifiSecurityType.WpaPsk || s === WifiSecurityType.Wpa2Psk || s === WifiSecurityType.Sae;
  }

  // Connected: disconnect. Saved or open: connect. Secured and new: ask
  // for the password.
  function toggleNetwork(network) {
    if (!network || network.stateChanging)
      return;
    _clearFailure(network);
    if (network.connected) {
      network.disconnect();
    } else if (network.known || !isSecure(network)) {
      network.connect();
    } else if (takesPsk(network)) {
      passwordFor = network;
    } else {
      // Enterprise and WEP networks need settings this menu can't enter
      _setFailure(network, "unsupported");
    }
  }

  function connectWithPsk(network, psk) {
    if (!network || psk === "")
      return;
    _clearFailure(network);
    passwordFor = null;
    network.connectWithPsk(psk);
  }

  function cancelPassword() {
    passwordFor = null;
  }

  function forget(network) {
    _clearFailure(network);
    network?.forget();
  }

  // Looks the IP up again (e.g. when a card showing it opens, to catch a
  // DHCP renewal)
  function refreshIp() {
    Qt.callLater(root._lookUpIp);
  }

  function networkStatus(network) {
    if (!network)
      return "";
    const failure = failures[network.name];
    if (failure === "unsupported")
      return I18n.tr("Needs settings this menu can't set");
    if (failure === ConnectionFailReason.NoSecrets)
      return I18n.tr("Wrong password");
    if (failure !== undefined)
      return I18n.tr("Couldn't connect");
    switch (network.state) {
    case ConnectionState.Connecting:
      return I18n.tr("Connecting…");
    case ConnectionState.Disconnecting:
      return I18n.tr("Disconnecting…");
    case ConnectionState.Connected:
      return I18n.tr("Connected");
    }
    if (network.known)
      return I18n.tr("Saved");
    return I18n.tr(isSecure(network) ? "Secured" : "Open");
  }

  function failed(network) {
    return network ? failures[network.name] !== undefined : false;
  }

  // Signal strength 0-1
  function signalIcon(strength) {
    if (strength >= 0.75)
      return "signal_wifi_4_bar";
    if (strength >= 0.5)
      return "network_wifi_3_bar";
    if (strength >= 0.25)
      return "network_wifi_2_bar";
    return "network_wifi_1_bar";
  }

  // -- Private --
  property ConsumerRegistry _scanRegistry: ConsumerRegistry {}

  // Scan while anything wants it and the radio is on
  property Binding _scanner: Binding {
    when: root.wifiDevice !== null
    target: root.wifiDevice
    property: "scannerEnabled"
    value: root._scanRegistry.active && root.wifiEnabled
    restoreMode: Binding.RestoreNone
  }

  readonly property string _primaryKey: primaryDevice ? `${primaryDevice.name}:${primaryDevice.state}:${activeNetwork?.name ?? ""}` : ""
  on_PrimaryKeyChanged: refreshIp()
  Component.onCompleted: refreshIp()

  // From axiom (net.addresses); an answer for a lookup since replaced is
  // dropped
  property int _ipLookup: 0
  function _lookUpIp() {
    const device = primaryDevice?.name ?? "";
    const lookup = ++root._ipLookup;
    if (device === "") {
      primaryIp = "";
      return;
    }
    BackendManager.call("net.addresses", {
      "device": device
    }, (error, result) => {
      if (lookup !== root._ipLookup)
        return;
      if (error)
        console.warn("[NetworkingManager] Could not read the address of", device + ":", error.message);
      root.primaryIp = result?.ipv4 ?? "";
    });
  }

  function _setFailure(network, reason) {
    const next = Object.assign({}, failures);
    next[network.name] = reason;
    failures = next;
  }

  function _clearFailure(network) {
    if (!network || failures[network.name] === undefined)
      return;
    const next = Object.assign({}, failures);
    delete next[network.name];
    failures = next;
  }

  // A wrong or missing password asks again
  property Instantiator _failureWatcher: Instantiator {
    model: root.networks

    delegate: Connections {
      required property var modelData
      target: modelData

      function onConnectionFailed(reason) {
        root._setFailure(modelData, reason);
        if (reason === ConnectionFailReason.NoSecrets && root.takesPsk(modelData))
          root.passwordFor = modelData;
      }

      function onConnectedChanged() {
        if (modelData.connected)
          root._clearFailure(modelData);
      }
    }
  }
}
