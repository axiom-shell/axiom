pragma Singleton
import QtQuick

import qs.config
import qs.components.methods
import qs.services.core

// Pending package updates, shared by every Updates widget: axiom's
// `updates` topic, which runs this distribution's check (Packages.updates:
// checkupdates on Arch, dnf on Fedora; nothing on one it doesn't know,
// `supported` false) and an AUR helper's -Qua, one check at a time.
// Widgets register with acquire(owner, {aurHelper}) (aurHelper "" for no
// AUR) and drop it with release(owner); checks run at UpdatesConfig.interval
// while any widget is registered, and the AUR is checked if any widget asks
// for it and the distribution has one.
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
  // Why the last check failed ("" when it didn't); the packages are then
  // the last check's that worked
  property string error: ""
  // From subscribing or refresh() until axiom's next state
  property bool checking: false

  function acquire(owner, request) {
    _registry.acquire(owner, {
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

  // Runs the upgrade (Updates.upgradeCommand, else upgradeCommand's) in a
  // terminal (Updates.terminal, else Apps.inTerminal's) and checks again
  // once the terminal closes. Ignored while an upgrade is already running.
  function upgrade() {
    const command = UpdatesConfig.upgradeCommand || root.upgradeCommand(UpdatesConfig.activeAurHelper);
    if (root._upgrading || command === "")
      return;
    root._upgrading = true;
    CommandManager.run(Apps.inTerminal(["bash", "-c", `${command}; echo; read -n 1 -s -r -p "Press any key to close"`], UpdatesConfig.terminal), () => {
      root._upgrading = false;
      root.refresh();
    });
  }

  // -- Private --
  property ConsumerRegistry _registry: ConsumerRegistry {}
  readonly property var _requests: _registry.requests
  property bool _upgrading: false

  readonly property bool _subscribed: _registry.active && root.supported
  readonly property int _interval: _registry.active ? UpdatesConfig.interval : 0
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

  // Pending updates as one silent notification (the Quiet section), kept
  // current while a widget checks: noted again only when more are
  // pending, gone once none are. Its Upgrade button runs the widgets'
  // upgrade; a click opens nothing
  readonly property string _desktopEntry: "axiom-updates"
  property int _noted: 0

  function _note() {
    const count = root.repoPackages.length + root.aurPackages.length;
    if (count === 0)
      NotificationManager.dismissKey("updates");
    const summary = count === 1 ? I18n.tr("1 package update") : I18n.tr("{0} package updates", count);
    // _noted starts at 0 after a restart: the note kept from before stays
    // as it is (not new again) if it says the same
    const kept = NotificationManager.entries.find(e => e.key === "updates");
    if (count > root._noted && kept?.summary !== summary)
      NotificationManager.sendNotification("axiom", summary, [].concat(root.repoPackages, root.aurPackages).slice(0, 5).map(p => p.name).join(", ") + (count > 5 ? "…" : ""), {
        "desktopEntry": root._desktopEntry,
        "icon": "system-software-update",
        "key": "updates",
        "silent": true,
        "actions": [
          {
            "id": "upgrade",
            "label": I18n.tr("Upgrade")
          }
        ]
      });
    root._noted = count;
  }

  Component.onCompleted: {
    NotificationManager.registerHandler(root._desktopEntry, (entry, action) => {
      if (action === "upgrade")
        root.upgrade();
    });
    BackendManager.listen("updates.state", state => {
      root.repoPackages = state.repo;
      root.aurPackages = state.aur;
      root.error = state.error;
      root.checking = false;
      if (!state.error)
        root._note();
    });
  }
}
