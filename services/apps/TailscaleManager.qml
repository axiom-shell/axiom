pragma Singleton
import QtQuick
import qs.config
import qs.services.core

// Tailscale's state for every widget and module that shows it: axiom's
// `tailscale` topic (`tailscale status --json` at the shortest interval
// asked for; the setting's minimum is the only floor), subscribed only
// while something has acquire()d it. connect() / disconnect() run
// `tailscale up` / `down` in axiom, which fetches the state again after.
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
  // The peer used as exit node ("" none)
  property string exitNode: ""
  // [{ name, dnsName, os, ips, online, active, exitNode, exitNodeOption,
  // relay, direct, lastSeen, rxBytes, txBytes }], online first, then by name
  property var peers: []
  readonly property int onlineCount: peers.filter(p => p.online).length

  // A connect() or disconnect() is running
  property bool busy: false
  // Why the last one failed, for the user ("" after a success)
  property string lastError: ""

  // request: { interval } (ms)
  function acquire(owner, request) {
    _registry.acquire(owner, {
      "interval": request?.interval ?? TailscaleConfig.interval
    });
  }

  function release(owner) {
    _registry.release(owner);
  }

  function refresh() {
    BackendManager.refresh("tailscale");
  }

  // `tailscale up`, with the node's saved settings
  function connect() {
    root._run("tailscale.up");
  }

  // `tailscale down`
  function disconnect() {
    root._run("tailscale.down");
  }

  // Opens the pending login's link in the browser
  function openLogin() {
    if (root.authURL.startsWith("https://") || root.authURL.startsWith("http://"))
      Qt.openUrlExternally(root.authURL);
  }

  // -- Private --
  property ConsumerRegistry _registry: ConsumerRegistry {}
  // 0 while nothing has acquired it
  readonly property int _interval: _registry.active ? Math.min(..._registry.requests.map(r => r.interval)) : 0

  on_IntervalChanged: {
    if (root._interval > 0)
      BackendManager.acquire("tailscale", {
        "interval": root._interval
      });
    else
      BackendManager.release("tailscale");
  }

  // rpc: tailscale.up, tailscale.down
  function _run(method) {
    if (root.busy)
      return;
    root.busy = true;
    BackendManager.call(method, {}, error => {
      root.busy = false;
      // The daemon's message stays English; the shell words it by kind
      root.lastError = !error ? "" : error.kind === "refused" ? I18n.tr("Not allowed: run `sudo tailscale set --operator=$USER` once, then try again.") : error.kind === "unavailable" ? I18n.tr("Tailscale isn't available.") : String(error.message ?? "");
      if (error)
        console.warn(`[TailscaleManager] ${method}: ${error.message}`);
    });
  }

  Component.onCompleted: BackendManager.listen("tailscale.state", state => {
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
    root.peers = state.peers ?? [];
  })
}
