pragma Singleton
import QtQuick
import Quickshell
import qs.config
import qs.components.methods
import qs.services.system
import qs.services.ui

// Dev mode, which axiom switches while it runs (`axiom dev`,
// docs/dev/backend/README.md): turned on, axiom runs a dev tree (any
// clone, `setTree`) with its own build and its own config, rebuilt as its
// Go source is edited; off, the installed tree on the live config. The
// developer options (`options`, kept by axiom, not in config) show the
// Development settings category. State comes from BackendManager.dev; a
// failed build sends a notification, and so does a dev start finding live
// changed since the dev config last took it over (once per start).
Singleton {
  id: root

  readonly property bool enabled: BackendManager.dev.enabled ?? false
  // Settings shows the developer options (the Development category also
  // shows while dev mode is on)
  readonly property bool options: BackendManager.dev.options ?? false
  // The dev image runs: the dev build on the dev tree and the dev config
  readonly property bool active: BackendManager.dev.active ?? false
  // Edits to the Go source can be built here (the tree has it, go is
  // installed); unavailable says why not
  readonly property bool available: BackendManager.dev.available ?? false
  readonly property string unavailable: BackendManager.dev.unavailable ?? ""
  readonly property bool building: BackendManager.dev.building ?? false
  // { ok, at, output }, null before the first build this run (a failure
  // also says why a dev build didn't start: the boot guard, a tree gone)
  readonly property var lastBuild: BackendManager.dev.lastBuild ?? null
  // Running a dev build rather than the installed binary
  readonly property bool onDevBuild: (BackendManager.dev.binary ?? "") !== (BackendManager.dev.installed ?? "")
  // The last build in a line, for the DevMode widget's tooltip and menu:
  // building, built or failed and when, or none yet this run
  readonly property string buildText: {
    if (root.building)
      return I18n.tr("Building…");
    if (!root.lastBuild)
      return I18n.tr("Not built this run");
    const when = root.lastBuild.at ? I18n.formatDate(new Date(root.lastBuild.at), I18n.dateFormat("dateTime")) : "";
    return root.lastBuild.ok ? I18n.tr("Built {0}", when) : I18n.tr("Build failed {0}", when);
  }

  // The dev tree ("" when none is set) and the install tree; the dev
  // tree's checkout: branch, commit, changes, and as `branch@sha`
  readonly property string tree: BackendManager.dev.tree ?? ""
  readonly property string installTree: BackendManager.dev.installTree ?? ""
  readonly property string branch: BackendManager.dev.branch ?? ""
  readonly property string commit: BackendManager.dev.commit ?? ""
  readonly property bool dirty: BackendManager.dev.dirty ?? false
  readonly property string checkout: DevDiff.checkout(root.branch, root.commit, root.dirty)
  // The dev build is built from the dev tree as it is (else buildWhy says
  // why not)
  readonly property bool buildFresh: BackendManager.dev.build?.fresh ?? false
  readonly property string buildWhy: BackendManager.dev.build?.why ?? ""
  // The dev config's file and live's; while the dev image runs, whether
  // live changed since dev last took it over, and what opening it noted
  // (seeded from the defaults: live is newer than the dev tree)
  readonly property string configPath: BackendManager.dev.config?.path ?? ""
  readonly property string livePath: BackendManager.dev.config?.livePath ?? ""
  readonly property bool liveChanged: BackendManager.dev.config?.liveChanged ?? false
  readonly property string configNote: BackendManager.dev.config?.note ?? ""

  // Each method's `done(error, result)` is optional; a refusal is also
  // logged

  function setEnabled(on, done) {
    BackendManager.call("dev.set", {
      "enabled": on
    }, root._answer("dev mode", done));
  }

  function toggle() {
    root.setEnabled(!root.enabled);
  }

  // Makes the clone at `path` the dev tree (axiom checks it is one)
  function setTree(path, done) {
    BackendManager.call("dev.set", {
      "tree": Paths.expandHome(path)
    }, root._answer("the dev tree", done));
  }

  // Clears the dev tree (refused while dev mode is on)
  function clearTree(done) {
    BackendManager.call("dev.set", {
      "tree": ""
    }, root._answer("clearing the dev tree", done));
  }

  // Shows or hides the developer options
  function setOptions(on, done) {
    BackendManager.call("dev.set", {
      "options": on
    }, root._answer("the developer options", done));
  }

  function rebuild(done) {
    BackendManager.call("dev.rebuild", null, (error, result) => {
      if (error)
        console.warn("[DevManager] axiom refused the rebuild:", error.message);
      done?.(error, result);
    });
  }

  // Every setting dev and live differ on (only while `active`): { rows:
  // [{ path, side, dev?, live?, devOnly }], liveChanged } (methods/DevDiff
  // labels them)
  function diff(done) {
    BackendManager.call("dev.config.diff", null, (error, result) => {
      if (error)
        console.warn("[DevManager] dev.config.diff:", error.message);
      done?.(error, result);
    });
  }

  // Copies the settings at `paths` (rows' paths, as given) to "live" or
  // "dev": { copied, diff }. A dev-only setting can't go to live
  function copy(paths, to, done) {
    BackendManager.call("dev.config.copy", {
      "paths": paths,
      "to": to
    }, (error, result) => {
      if (error)
        console.warn("[DevManager] dev.config.copy:", error.message);
      done?.(error, result);
    });
  }

  // Brings live over: "merge" (live's changes where dev left the setting
  // alone) or "replace" (dev becomes live's copy): { merged, conflicts,
  // diff }
  function pull(mode, done) {
    BackendManager.call("dev.config.pull", {
      "mode": mode
    }, (error, result) => {
      if (error)
        console.warn("[DevManager] dev.config.pull:", error.message);
      done?.(error, result);
    });
  }

  // dev.set's answer: a refusal logged, then handed to `done`
  function _answer(what, done) {
    return (error, result) => {
      if (error)
        console.warn("[DevManager] axiom refused " + what + ":", error.message);
      done?.(error, result);
    };
  }

  // From the notification: brings live over, and says what stayed dev's
  function _pullFromNotification(mode) {
    root.pull(mode, (error, result) => {
      if (error) {
        NotificationManager.sendNotification("axiom", I18n.tr("Live changes weren't brought over"), error.message, {
          "key": "dev-live-changed"
        });
        return;
      }
      const conflicts = result.conflicts ?? [];
      if (conflicts.length === 0)
        return;
      NotificationManager.sendNotification("axiom", I18n.tr("Live changes brought over"), conflicts.length === 1 ? I18n.tr("1 setting changed in dev too kept its dev value.") : I18n.tr("{0} settings changed in dev too kept their dev values.", conflicts.length), {
        "key": "dev-live-changed",
        "actions": [
          {
            "id": "open",
            "label": I18n.tr("Open Development")
          }
        ],
        "onAction": id => SettingsManager.openCategory("Development")
      });
    });
  }

  // Once per dev start: live changed since the dev config took it over
  function _noteLiveChanged() {
    if (!_run.ready || !root.active || !root.liveChanged || _run.liveNotified)
      return;
    _run.liveNotified = true;
    NotificationManager.sendNotification("axiom", I18n.tr("Live config changed"), I18n.tr("The live config changed since dev mode last took it over."), {
      "key": "dev-live-changed",
      "actions": [
        {
          "id": "merge",
          "label": I18n.tr("Bring live changes over")
        },
        {
          "id": "replace",
          "label": I18n.tr("Replace dev config with live")
        }
      ],
      "onAction": id => root._pullFromNotification(id)
    });
  }

  function _noteBuild() {
    const build = root.lastBuild;
    if (!_run.ready || !build || build.ok || build.at === _run.notifiedAt)
      return;
    _run.notifiedAt = build.at;
    const lines = (build.output ?? "").trim().split("\n");
    NotificationManager.sendNotification("axiom", I18n.tr("The dev build failed"), lines.slice(-3).join("\n"), {
      "key": "dev-build"
    });
  }

  Connections {
    target: BackendManager

    function onDevChanged() {
      root._noteBuild();
      root._noteLiveChanged();
    }
  }

  // What was notified, kept across hot reloads (a dev start restarts the
  // shell, which starts it again); nothing is noted before it's loaded
  PersistentProperties {
    id: _run
    reloadableId: "axiomDevMode"
    property string notifiedAt: ""
    property bool liveNotified: false
    property bool ready: false

    onLoaded: {
      _run.ready = true;
      root._noteBuild();
      root._noteLiveChanged();
    }
  }
}
