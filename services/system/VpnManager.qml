pragma Singleton
import QtQuick

import qs.config
import qs.services.core
import qs.services.apps

// Every VPN as one list for the widgets, modules and the Wi-Fi menu:
// NetworkManager's (WireGuard, OpenVPN and other plugins) from axiom's
// `vpn.state` push (internal/nmvpn, on NetworkManager's signals, so
// nothing polls), and Tailscale's from TailscaleManager while something
// has acquire()d it and VpnConfig.showTailscale. A VPN asking for its
// password at connect time comes as `secretRequest` (axiom is
// NetworkManager's secret agent); its row shows the fields.
QtObject {
  id: root

  // NetworkManager runs (false until axiom says otherwise)
  property bool available: false
  // NetworkManager's VPNs: [{ uuid, name, kind, plugin, autoconnect,
  // state ("off" | "connecting" | "on" | "disconnecting"), device, ipv4,
  // error }], by name
  property var profiles: []

  // Every row: { id, name, kind, state, ipv4, error, plugin }, by name, so
  // a row never moves under the pointer. Tailscale's id is "tailscale",
  // the others' their uuid
  readonly property var rows: {
    const out = root.profiles.map(p => ({
          "id": p.uuid,
          "name": p.name,
          "kind": p.kind,
          "state": root._pending[p.uuid] ?? p.state,
          "ipv4": p.ipv4,
          "error": p.state === "off" ? p.error : "",
          "plugin": p.plugin
        }));
    if (root._tailscaleShown && TailscaleManager.available)
      out.push({
        "id": "tailscale",
        "name": TailscaleManager.tailnetName || "Tailscale",
        "kind": "tailscale",
        "state": TailscaleManager.busy ? (TailscaleManager.connected ? "disconnecting" : "connecting") : TailscaleManager.connected ? "on" : TailscaleManager.backendState === "Starting" ? "connecting" : "off",
        "ipv4": TailscaleManager.ip,
        "error": TailscaleManager.needsLogin ? "needs-login" : TailscaleManager.lastError !== "" ? "failed" : "",
        "plugin": true
      });
    return out.sort((a, b) => a.name.localeCompare(b.name));
  }
  readonly property var activeRows: rows.filter(r => r.state === "on")
  readonly property bool anyActive: activeRows.length > 0
  // The first VPN up, else null
  readonly property var primary: activeRows[0] ?? null
  // The VPN last brought up from the shell (what the Vpn widget's click
  // toggles), else the first one
  readonly property var lastRow: rows.find(r => r.id === root.lastUsed) ?? rows[0] ?? null
  property string lastUsed: ""
  // The Wi-Fi menu's VPN section shows one summary row (remembered)
  property bool folded: true

  // The address the internet sees (VpnConfig.publicIpUrl's answer), read
  // on checkPublicIp(); "" until then, and again when the VPN up changes
  property string publicIp: ""
  property bool publicIpBusy: false
  // The last import's error ("" none)
  property string importError: ""

  // NetworkManager asking for a VPN's secrets: { id, uuid, name, kind,
  // user, message, fields }, else null
  property var secretRequest: null

  // Tailscale is polled (`tailscale status`): it's listed only while
  // something showing the rows holds acquire()
  function acquire(owner) {
    _registry.acquire(owner, {});
  }

  function release(owner) {
    _registry.release(owner);
  }

  function rowById(id) {
    return root.rows.find(r => r.id === id) ?? null;
  }

  function busy(row) {
    return row?.state === "connecting" || row?.state === "disconnecting";
  }

  // Up when off, down when on (or connecting); busy rows wait, and one
  // whose plugin is missing only says so
  function toggle(row) {
    if (!row || row.state === "disconnecting" || (row.state === "off" && !row.plugin))
      return;
    if (row.state === "off")
      root.up(row);
    else
      root.down(row);
  }

  // The Vpn widget's click: the last one used
  function toggleLast() {
    root.toggle(root.anyActive ? root.primary : root.lastRow);
  }

  function up(row) {
    if (row.kind === "tailscale") {
      if (TailscaleManager.needsLogin)
        TailscaleManager.openLogin();
      else
        TailscaleManager.connect();
    } else {
      root._pend(row, "connecting");
      BackendManager.call("vpn.up", {
        "uuid": row.id
      }, root._settle(row, "vpn.up"));
    }
    root._remember(row.id);
  }

  function down(row) {
    if (root.secretRequest?.uuid === row.id)
      root.cancelSecret();
    if (row.kind === "tailscale")
      TailscaleManager.disconnect();
    else {
      root._pend(row, "disconnecting");
      BackendManager.call("vpn.down", {
        "uuid": row.id
      }, root._settle(row, "vpn.down"));
    }
  }

  function setFolded(on) {
    if (root.folded === on)
      return;
    root.folded = on;
    root._saveState();
  }

  // Asks for a WireGuard (.conf) or OpenVPN (.ovpn) file and imports it.
  // The picker belongs to this service, as the popout asking may close
  // while it's open
  function pickImport() {
    FilePickerManager.pick(root, I18n.tr("Import a VPN"), {
      "filter": I18n.tr("VPN files") + ":*.conf *.ovpn"
    }, path => root.importFile(path));
  }

  // rpc: vpn.import
  function importFile(path) {
    root.importError = "";
    BackendManager.call("vpn.import", {
      "path": path
    }, error => {
      if (!error)
        return;
      console.warn(`[VpnManager] vpn.import ${path}: ${error.message}`);
      root.importError = error.message;
    });
  }

  function checkPublicIp() {
    const url = VpnConfig.publicIpUrl;
    if (url === "" || root.publicIpBusy)
      return;
    root.publicIpBusy = true;
    const asked = root.primary?.id ?? "";
    const xhr = new XMLHttpRequest();
    xhr.onreadystatechange = () => {
      if (xhr.readyState !== XMLHttpRequest.DONE)
        return;
      root.publicIpBusy = false;
      // The VPN changed meanwhile: the answer is about the old one
      if ((root.primary?.id ?? "") !== asked)
        return;
      const text = xhr.status === 200 ? xhr.responseText.trim() : "";
      root.publicIp = text.length > 0 && text.length <= 45 ? text : "?";
    };
    xhr.open("GET", url);
    xhr.send();
  }

  // values: { field: text } for the request's fields
  function answerSecret(values) {
    const req = root.secretRequest;
    if (!req)
      return;
    root.secretRequest = null;
    BackendManager.call("vpn.secret", {
      "id": req.id,
      "secrets": values
    }, root._logFailure("vpn.secret"));
  }

  function cancelSecret() {
    const req = root.secretRequest;
    if (!req)
      return;
    root.secretRequest = null;
    BackendManager.call("vpn.secret", {
      "id": req.id,
      "cancel": true
    }, root._logFailure("vpn.secret"));
  }

  // What a row says under its name
  function statusText(row) {
    if (!row)
      return "";
    switch (row.state) {
    case "connecting":
      return I18n.tr("Connecting…");
    case "disconnecting":
      return I18n.tr("Disconnecting…");
    case "on":
      return row.ipv4 !== "" ? I18n.tr("Connected · {0}", row.ipv4) : I18n.tr("Connected");
    }
    switch (row.error) {
    case "":
      return root.kindLabel(row.kind);
    case "plugin-missing":
      return I18n.tr("Needs networkmanager-{0}", row.kind);
    case "no-secrets":
      return I18n.tr("Needs a password");
    case "login-failed":
      return I18n.tr("Wrong user name or password");
    case "timeout":
      return I18n.tr("The server didn't answer");
    case "service-failed":
      return I18n.tr("The VPN service failed to start");
    case "needs-login":
      return I18n.tr("Needs login: click to open it");
    }
    return I18n.tr("Couldn't connect");
  }

  function kindLabel(kind) {
    switch (kind) {
    case "wireguard":
      return "WireGuard";
    case "openvpn":
      return "OpenVPN";
    case "tailscale":
      return "Tailscale";
    case "openconnect":
      return "OpenConnect";
    }
    return kind;
  }

  function kindIcon(kind) {
    switch (kind) {
    case "wireguard":
      return "vpn_key";
    case "tailscale":
      return "hub";
    }
    return "vpn_lock";
  }

  // A secret field's label, by its key
  function fieldLabel(key) {
    switch (key) {
    case "password":
      return I18n.tr("Password");
    case "cert-pass":
      return I18n.tr("Key passphrase");
    case "http-proxy-password":
      return I18n.tr("Proxy password");
    case "private-key":
      return I18n.tr("Private key");
    }
    return key;
  }

  // -- Private --
  property ConsumerRegistry _registry: ConsumerRegistry {}
  readonly property bool _tailscaleShown: _registry.active && VpnConfig.showTailscale
  on_TailscaleShownChanged: {
    if (root._tailscaleShown)
      TailscaleManager.acquire(root);
    else
      TailscaleManager.release(root);
  }

  // uuid -> the state shown while its call runs, so a click answers at
  // once (axiom's push follows)
  property var _pending: ({})
  property var _lastState: StateManager.createStateHandler("vpn")

  function _remember(id) {
    if (root.lastUsed === id)
      return;
    root.lastUsed = id;
    root._saveState();
  }

  function _saveState() {
    root._lastState.save({
      "lastUsed": root.lastUsed,
      "folded": root.folded
    });
  }

  readonly property string _primaryId: primary?.id ?? ""
  on_PrimaryIdChanged: root.publicIp = ""

  // Shows a row's state at once, while its call runs
  function _pend(row, state) {
    const pending = Object.assign({}, root._pending);
    pending[row.id] = state;
    root._pending = pending;
  }

  // The call's answer: the row follows axiom's state again
  function _settle(row, method) {
    return error => {
      const next = Object.assign({}, root._pending);
      delete next[row.id];
      root._pending = next;
      if (error)
        console.warn(`[VpnManager] ${method} ${row.name}: ${error.message}`);
    };
  }

  function _logFailure(method) {
    return error => {
      if (error)
        console.warn(`[VpnManager] ${method}: ${error.message}`);
    };
  }

  // A VPN that was up and went down on its own (axiom only reports an
  // error for a drop nobody asked for)
  function _show(state) {
    const before = {};
    root.profiles.forEach(p => before[p.uuid] = p.state);
    const next = state?.connections ?? [];
    root.available = state?.available ?? false;
    root.profiles = next;
    if (!VpnConfig.notifyOnDrop)
      return;
    next.forEach(p => {
      if (before[p.uuid] === "on" && p.state === "off" && p.error !== "")
        NotificationManager.sendNotification("axiom", I18n.tr("VPN disconnected"), I18n.tr("{0} went down: {1}", p.name, root.statusText({
          "state": "off",
          "kind": p.kind,
          "error": p.error
        })), {
          "icon": "network-vpn-disconnected"
        });
    });
  }

  function _fetch() {
    BackendManager.call("vpn.get", {}, (error, state) => {
      if (!error)
        root._show(state);
    });
  }

  property Connections _backend: Connections {
    target: BackendManager
    function onGreeted() {
      root._fetch();
    }
  }

  Component.onCompleted: {
    const saved = root._lastState.load({});
    root.lastUsed = saved.lastUsed ?? "";
    root.folded = saved.folded ?? true;
    BackendManager.listen("vpn.state", state => root._show(state));
    BackendManager.listen("vpn.secretRequest", request => root.secretRequest = request);
    BackendManager.listen("vpn.secretDone", done => {
      if (root.secretRequest?.id === done.id)
        root.secretRequest = null;
    });
    // Made after the hello (a QML reload): no greeted to wait for
    if (BackendManager.ready)
      root._fetch();
  }
}
