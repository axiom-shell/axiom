pragma Singleton
import QtQuick
import Quickshell.Networking

import qs.config
import qs.services.core

// Wi-Fi state and actions over NetworkManager (Quickshell.Networking, D-Bus,
// so nothing polls), and through axiom (nmnet) what it doesn't show: the
// primary device's details, joining hidden, WEP and enterprise networks,
// the saved networks' autoconnect. Airplane mode turns Wi-Fi and
// Bluetooth off together. Named NetworkingManager so it doesn't shadow
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

  // The primary device's details (axiom's net.details: { device, kind,
  // mac, ipv4, ipv6, gateway, dns, speed, bitrate, frequency, band,
  // channel }), null until read; refreshDetails() reads them again
  property var details: null
  // NetworkManager's connectivity check: "portal" (a sign-in page is in
  // the way), "limited" (no internet), else "" (fine, or not checked)
  readonly property string connectivity: {
    if (!Networking.canCheckConnectivity || primaryDevice === null)
      return "";
    if (Networking.connectivity === NetworkConnectivity.Portal)
      return "portal";
    if (Networking.connectivity === NetworkConnectivity.Limited || Networking.connectivity === NetworkConnectivity.None)
      return "limited";
    return "";
  }

  // Saved Wi-Fi profiles by name: { uuid, autoconnect } (axiom's
  // net.savedWifi), read while scanning
  property var saved: ({})

  // Airplane mode: turned on here (remembered), and both radios still
  // off; either coming back on ends it
  readonly property bool airplane: _airplaneOn && !wifiEnabled && !(BluetoothManager.available && BluetoothManager.enabled)
  property bool _airplaneOn: false
  onAirplaneChanged: {
    if (!airplane && _airplaneOn) {
      _airplaneOn = false;
      _airplaneState.save(Object.assign(_airplaneState.load({}), {
        "on": false
      }));
    }
  }

  // The last join (net.join) refused, for the form that asked; "" none
  property string joinError: ""

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

  // On: remembers the radios' states and turns both off. Off: restores
  // them (Wi-Fi at least, so leaving it always reconnects)
  function setAirplane(on) {
    if (on) {
      root._airplaneState.save({
        "on": true,
        "wifi": wifiEnabled,
        "bluetooth": BluetoothManager.enabled
      });
      _airplaneOn = true;
      setWifiEnabled(false);
      BluetoothManager.setEnabled(false);
      return;
    }
    const was = root._airplaneState.load({});
    _airplaneOn = false;
    root._airplaneState.save(Object.assign({}, was, {
      "on": false
    }));
    const bluetooth = was.bluetooth ?? true;
    setWifiEnabled((was.wifi ?? true) || !bluetooth);
    BluetoothManager.setEnabled(bluetooth);
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

  // What joining it takes (net.join's security): "open", "psk", "wep",
  // "eap", "dynamic-wep", "leap", or "unsupported" (WPA3 192-bit, which
  // needs a client certificate)
  function securityKind(network) {
    switch (network?.security) {
    case WifiSecurityType.WpaPsk:
    case WifiSecurityType.Wpa2Psk:
    case WifiSecurityType.Sae:
      return "psk";
    case WifiSecurityType.StaticWep:
      return "wep";
    case WifiSecurityType.WpaEap:
    case WifiSecurityType.Wpa2Eap:
      return "eap";
    case WifiSecurityType.DynamicWep:
      return "dynamic-wep";
    case WifiSecurityType.Leap:
      return "leap";
    case WifiSecurityType.Open:
    case WifiSecurityType.Owe:
      return "open";
    }
    return "unsupported";
  }

  // Connected: disconnect. Saved or open: connect. Secured and new: ask
  // for what it needs (the password, or the enterprise form).
  function toggleNetwork(network) {
    if (!network || network.stateChanging)
      return;
    _clearFailure(network);
    if (network.connected) {
      network.disconnect();
    } else if (network.known || !isSecure(network)) {
      network.connect();
    } else if (securityKind(network) !== "unsupported") {
      joinError = "";
      passwordFor = network;
    } else {
      _setFailure(network, "unsupported");
    }
  }

  // Joins through axiom: network, a network in range (null for a hidden
  // one, named in fields), with fields as net.join's (security, password,
  // identity, eap, phase2, caCert, systemCa, …). done(error), when given,
  // hears how the call went (error null: NetworkManager is connecting)
  // rpc: net.join
  function join(network, fields, done) {
    const ssid = network ? network.name : fields.ssid ?? "";
    if (network)
      _clearFailure(network);
    joinError = "";
    passwordFor = null;
    BackendManager.call("net.join", {
      "device": wifiDevice?.name ?? "",
      "ssid": ssid,
      "hidden": fields.hidden === true,
      "security": fields.security ?? securityKind(network),
      "password": fields.password ?? "",
      "identity": fields.identity ?? "",
      "anonymousIdentity": fields.anonymousIdentity ?? "",
      "eap": fields.eap ?? "",
      "phase2": fields.phase2 ?? "",
      "caCert": fields.caCert ?? "",
      "systemCa": fields.systemCa === true
    }, error => {
      done?.(error ?? null);
      if (!error)
        return;
      console.warn("[NetworkingManager] Could not join", ssid + ":", error.message);
      root.joinError = error.message;
      if (network) {
        root._setFailure(network, "join");
        root.passwordFor = network;
      }
    });
  }

  // A saved network joins on its own when in range (true when unknown)
  function autoconnects(network) {
    return saved[network?.name ?? ""]?.autoconnect ?? true;
  }

  // rpc: net.setAutoconnect
  function setAutoconnect(network, on) {
    const entry = saved[network?.name ?? ""];
    if (!entry)
      return;
    const next = Object.assign({}, saved);
    next[network.name] = Object.assign({}, entry, {
      "autoconnect": on
    });
    saved = next;
    BackendManager.call("net.setAutoconnect", {
      "uuid": entry.uuid,
      "on": on
    }, error => {
      if (error)
        console.warn("[NetworkingManager] Could not change autoconnect for", network.name + ":", error.message);
      root.refreshSaved();
    });
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
    joinError = "";
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

  // Reads the primary device's details again (when the details open, and
  // as the connection changes while something shows them)
  function refreshDetails() {
    Qt.callLater(root._lookUpDetails);
  }

  // Reads the saved networks again
  // rpc: net.savedWifi
  function refreshSaved() {
    BackendManager.call("net.savedWifi", {}, (error, result) => {
      if (error) {
        if (error.kind !== "unavailable")
          console.warn("[NetworkingManager] Could not list the saved networks:", error.message);
        return;
      }
      const next = {};
      for (const n of result.networks)
        next[n.ssid] = {
          "uuid": n.uuid,
          "autoconnect": n.autoconnect
        };
      root.saved = next;
    });
  }

  function networkStatus(network) {
    if (!network)
      return "";
    const failure = failures[network.name];
    if (failure === "unsupported")
      return I18n.tr("Needs a client certificate");
    if (failure === "join")
      return root.joinError || I18n.tr("Couldn't connect");
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
  on_PrimaryKeyChanged: {
    refreshIp();
    if (details !== null)
      refreshDetails();
  }
  Component.onCompleted: {
    refreshIp();
    _airplaneOn = _airplaneState.load({}).on === true;
  }

  // The saved networks, read again as one is saved or forgotten while
  // something scans
  readonly property string _savedKey: _scanRegistry.active ? networks.filter(n => n.known).map(n => n.name).join("\n") + "\n" : ""
  on_SavedKeyChanged: {
    if (_savedKey !== "")
      refreshSaved();
  }

  property var _airplaneState: StateManager.createStateHandler("airplane")

  property int _detailsLookup: 0
  // rpc: net.details
  function _lookUpDetails() {
    const device = primaryDevice?.name ?? "";
    const lookup = ++root._detailsLookup;
    if (device === "") {
      details = null;
      return;
    }
    BackendManager.call("net.details", {
      "device": device
    }, (error, result) => {
      if (lookup !== root._detailsLookup)
        return;
      if (error && error.kind !== "unavailable")
        console.warn("[NetworkingManager] Could not read the details of", device + ":", error.message);
      root.details = error ? null : result;
    });
  }

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
      if (error && error.kind !== "unavailable")
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
        if (reason === ConnectionFailReason.NoSecrets && root.securityKind(modelData) !== "unsupported" && root.securityKind(modelData) !== "open")
          root.passwordFor = modelData;
      }

      function onConnectedChanged() {
        if (modelData.connected)
          root._clearFailure(modelData);
      }
    }
  }
}
