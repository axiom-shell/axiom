pragma Singleton
import QtQuick
import qs.config
import qs.services.core

// Tailscale's state for every widget and module that shows it: axiom's
// `tailscale` topic (`tailscale status --json` every Tailscale.interval;
// the setting's minimum is the only floor), subscribed only
// while something has acquire()d it, and the `tailscaledetails` topic
// (the node's prefs and the accounts logged in) while something has
// acquireDetails()d it. The actions (connect, switching account, the exit
// node, the switches, granting operator rights) run in axiom, which
// fetches both again after.
QtObject {
  id: root

  // Installed at all (false until axiom says otherwise)
  property bool available: false
  // "Running", "Stopped", "NeedsLogin", ... ("" if unknown)
  property string backendState: ""
  readonly property bool connected: backendState === "Running"
  readonly property bool needsLogin: backendState === "NeedsLogin"
  property string tailnetName: ""
  // This machine's first Tailscale address, and all of them
  property string ip: ""
  property var ips: []
  property string version: ""
  // This machine's OS host name and MagicDNS name
  property string hostName: ""
  property string dnsName: ""
  property string magicDNSSuffix: ""
  // Where to log in while a login waits ("" otherwise)
  property string authURL: ""
  // tailscaled's warnings
  property var health: []
  // The peer used as exit node ("" none), and its address
  property string exitNode: ""
  property string exitNodeIP: ""
  // Who this machine is logged in as: { loginName, displayName }
  property var account: ({
      "loginName": "",
      "displayName": ""
    })
  // When this machine's key expires (RFC 3339, "" never)
  property string keyExpiry: ""
  // From acquireDetails() only. { known, acceptRoutes, acceptDNS,
  // shieldsUp, exitNodeAllowLAN }; known false hides the switches
  property var prefs: ({
      "known": false
    })
  // The accounts logged in: [{ id, nickname, tailnet, account, selected }]
  property var profiles: []
  // Listing them needs operator rights, which this user doesn't have
  property bool profilesDenied: false
  // [{ name, dnsName, os, ips, online, active, exitNode, exitNodeOption,
  // relay, direct, lastSeen, rxBytes, txBytes }], online first, then by name
  property var peers: []
  readonly property int onlineCount: peers.filter(p => p.online).length

  // A connect() or disconnect() is running
  property bool busy: false
  // Why the last one failed, for the user ("" after a success)
  property string lastError: ""

  // Every consumer shares TailscaleConfig.interval: no request
  function acquire(owner) {
    _registry.acquire(owner, {});
  }

  function release(owner) {
    _registry.release(owner);
  }

  // The prefs and accounts too (the popout and the module)
  function acquireDetails(owner) {
    _detailsRegistry.acquire(owner, {});
  }

  function releaseDetails(owner) {
    _detailsRegistry.release(owner);
  }

  function refresh() {
    BackendManager.refresh("tailscale");
    if (root._detailsInterval > 0)
      BackendManager.refresh("tailscaledetails");
  }

  // `tailscale up`, with the node's saved settings
  function connect() {
    root._run("tailscale.up");
  }

  // `tailscale down`
  function disconnect() {
    root._run("tailscale.down");
  }

  // `tailscale switch <id>`, to one of profiles
  function switchAccount(id) {
    root._run("tailscale.switch", {
      "id": id
    });
  }

  // `tailscale login`: another account, its login link then in authURL
  function addAccount() {
    root._run("tailscale.login");
  }

  // `tailscale set --exit-node=<ip>` ("" for none)
  function setExitNode(ip) {
    root._run("tailscale.set", {
      "exitNode": ip
    });
  }

  // `tailscale set` for one of prefs' switches: "acceptRoutes",
  // "acceptDNS", "shieldsUp" or "exitNodeAllowLAN"
  function setPref(key, value) {
    // rpc: unchecked (the field is one of tailscale.SetRequest's, named by the caller)
    root._run("tailscale.set", {
      [key]: value
    });
  }

  // `pkexec tailscale set --operator=$USER`: polkit asks for an
  // administrator's password once, then every action runs without
  function grantOperator() {
    root._run("tailscale.grantOperator");
  }

  // Opens the pending login's link in the browser
  function openLogin() {
    if (root.authURL.startsWith("https://") || root.authURL.startsWith("http://"))
      Qt.openUrlExternally(root.authURL);
  }

  // -- Private --
  property ConsumerRegistry _registry: ConsumerRegistry {}
  // 0 while nothing has acquired it
  readonly property int _interval: _registry.active ? TailscaleConfig.interval : 0
  property ConsumerRegistry _detailsRegistry: ConsumerRegistry {}
  readonly property int _detailsInterval: _detailsRegistry.active ? TailscaleConfig.interval : 0

  on_IntervalChanged: {
    if (root._interval > 0)
      BackendManager.acquire("tailscale", {
        "interval": root._interval
      });
    else
      BackendManager.release("tailscale");
  }

  on_DetailsIntervalChanged: {
    if (root._detailsInterval > 0)
      BackendManager.acquire("tailscaledetails", {
        "interval": root._detailsInterval
      });
    else
      BackendManager.release("tailscaledetails");
  }

  // rpc: tailscale.up, tailscale.down, tailscale.switch, tailscale.login, tailscale.set, tailscale.grantOperator
  function _run(method, params) {
    if (root.busy)
      return;
    root.busy = true;
    BackendManager.call(method, params ?? {}, error => {
      root.busy = false;
      // The daemon's message stays English; the shell words it by kind
      root.lastError = !error ? "" : error.kind === "refused" ? I18n.tr("Your user can't change Tailscale: allow it with Grant access.") : error.kind === "unauthorized" ? I18n.tr("Access wasn't granted.") : error.kind === "unavailable" ? I18n.tr("Tailscale isn't available.") : String(error.message ?? "");
      if (error)
        console.warn(`[TailscaleManager] ${method}: ${error.message}`);
    });
  }

  Component.onCompleted: {
    BackendManager.listen("tailscale.state", state => {
      root.available = state.available;
      root.backendState = state.backendState;
      root.tailnetName = state.tailnetName;
      root.ip = state.ip;
      root.ips = state.ips ?? [];
      root.version = state.version ?? "";
      root.hostName = state.hostName ?? "";
      root.dnsName = state.dnsName ?? "";
      root.magicDNSSuffix = state.magicDNSSuffix ?? "";
      root.authURL = state.authURL ?? "";
      root.health = state.health ?? [];
      root.exitNode = state.exitNode ?? "";
      root.exitNodeIP = state.exitNodeIP ?? "";
      root.account = state.account;
      root.keyExpiry = state.keyExpiry ?? "";
      root.peers = state.peers ?? [];
    });
    BackendManager.listen("tailscaledetails.state", state => {
      root.prefs = state.prefs;
      root.profiles = state.profiles;
      root.profilesDenied = state.profilesDenied;
    });
  }
}
