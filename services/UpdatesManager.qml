pragma Singleton
import QtQuick

import qs.config
import qs.components.methods

// Pending package updates, shared by every Updates widget: axiom's
// `updates` topic, which runs this distribution's check (Packages.updates:
// checkupdates on Arch, dnf on Fedora; nothing on one it doesn't know,
// `supported` false) and an AUR helper's -Qua, one check at a time.
// Widgets register with acquire(owner, {interval (ms), aurHelper})
// (aurHelper "" for no AUR) and drop it with release(owner); checks run at
// the shortest requested interval, and the AUR is checked if any widget
// asks for it and the distribution has one.
QtObject {
  id: root

  // { check, found, none, format, upgrade, aur }, or null where updates
  // can't be checked
  readonly property var backend: Packages.updates(DependencyManager.distro)
  readonly property bool supported: root.backend !== null
  // An AUR helper's updates count here
  readonly property bool hasAur: root.backend?.aur === true

  // [{ name, from, to }]
  property var repoPackages: []
  property var aurPackages: []
  // From subscribing or refresh() until axiom's next state
  property bool checking: false

  function acquire(owner, request) {
    _registry.acquire(owner, {
      "interval": request?.interval ?? 1800000,
      "aurHelper": request?.aurHelper ?? ""
    });
  }

  function release(owner) {
    _registry.release(owner);
  }

  function refresh() {
    if (!root._subscribed)
      return;
    root.checking = true;
    BackendManager.refresh("updates");
  }

  // What upgrades by default: the AUR helper's -Syu (with `aurHelper` set
  // and an AUR here), else the distribution's own upgrade
  function upgradeCommand(aurHelper) {
    if (aurHelper && root.hasAur)
      return `${aurHelper} -Syu`;
    return root.backend?.upgrade ?? "";
  }

  // Runs `command` in a terminal (`terminal`, else Apps.inTerminal's) and
  // checks again once the terminal closes. Ignored while an upgrade is
  // already running.
  function upgrade(command, terminal) {
    if (root._upgrading || command === "")
      return;
    root._upgrading = true;
    CommandManager.run(Apps.inTerminal(["bash", "-c", `${command}; echo; read -n 1 -s -r -p "Press any key to close"`], terminal), () => {
      root._upgrading = false;
      root.refresh();
    });
  }

  // -- Private --
  property ConsumerRegistry _registry: ConsumerRegistry {}
  readonly property var _requests: _registry.requests
  property bool _upgrading: false

  readonly property bool _subscribed: _registry.active && root.supported
  readonly property int _interval: _registry.active ? Math.min(..._requests.map(r => r.interval)) : 0
  readonly property string _aurHelper: root.hasAur ? (_requests.find(r => r.aurHelper !== "")?.aurHelper ?? "") : ""
  // The request as one value, so a change resubscribes once. axiom checks
  // at once for a request it hasn't seen (another AUR helper), and only
  // moves the next check for another interval
  readonly property var _request: root._subscribed ? {
    "interval": root._interval,
    "check": {
      "command": root.backend.check,
      "found": root.backend.found,
      "none": root.backend.none,
      "format": root.backend.format
    },
    "aurHelper": root._aurHelper
  } : null

  on_RequestChanged: {
    if (root._request) {
      root.checking = true;
      BackendManager.acquire("updates", root._request);
    } else {
      root.checking = false;
      BackendManager.release("updates");
    }
  }

  Component.onCompleted: BackendManager.listen("updates.state", state => {
    root.repoPackages = state.repo;
    root.aurPackages = state.aur;
    root.checking = false;
  })
}
