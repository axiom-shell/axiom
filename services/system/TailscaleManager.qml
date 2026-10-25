pragma Singleton
import QtQuick
import qs.services.core

// Tailscale's state for every widget that shows it: axiom's `tailscale`
// topic (`tailscale status --json` at the shortest interval asked for,
// never more often than every 5 s), subscribed only while something has
// acquire()d it.
QtObject {
  id: root

  // Installed at all (false until axiom says otherwise)
  property bool available: false
  // "Running", "Stopped", "NeedsLogin", ... ("" if unknown)
  property string backendState: ""
  readonly property bool connected: backendState === "Running"
  property string tailnetName: ""
  property string ip: ""

  // request: { interval } (ms)
  function acquire(owner, request) {
    _registry.acquire(owner, {
      "interval": request?.interval ?? 10000
    });
  }

  function release(owner) {
    _registry.release(owner);
  }

  function refresh() {
    BackendManager.refresh("tailscale");
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

  Component.onCompleted: BackendManager.listen("tailscale.state", state => {
    root.available = state.available;
    root.backendState = state.backendState;
    root.tailnetName = state.tailnetName;
    root.ip = state.ip;
  })
}
