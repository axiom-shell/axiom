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
// developer options (`options`, kept by axiom, not in config) or dev mode
// show the Development settings category, whose controls all work with dev
// mode off too. State comes from BackendManager.dev. Unless
// NotificationsConfig.devNotifications is off, a failing streak of builds
// notifies once, and again when a build works (methods/DevBuildStreak, the
// streak kept in StateManager's "dev-build" across the re-exec a build
// starts), and so does a dev start finding live changed since the dev
// config last took it over (once per start).
Singleton {
  id: root

  readonly property bool enabled: BackendManager.dev.enabled ?? false
  // Settings shows the developer options: the Development category (dev
  // mode on or off)
  readonly property bool options: BackendManager.dev.options ?? false
  // Settings shows the Development category: the developer options, or
  // dev mode on (`/$devOptions` in an x-showIf)
  readonly property bool showsDevelopment: root.options || root.enabled
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
  // The last build failed (or a dev start stayed on the installed axiom)
  readonly property bool buildFailed: root.lastBuild?.ok === false
  // The last build in a line, for the DevMode widget's tooltip and menu:
  // building, built or failed and when; before a build this run (as right
  // after the re-exec a build starts), the dev tree's recorded build, or
  // none
  readonly property string buildText: {
    if (root.building)
      return I18n.tr("Building…");
    const build = root.lastBuild ?? (root.builtAt ? {
        "ok": true,
        "at": root.builtAt
      } : null);
    if (!build)
      return I18n.tr("Not built this run");
    const when = build.at ? I18n.formatDate(new Date(build.at), I18n.dateFormat("dateTime")) : "";
    return build.ok ? I18n.tr("Built {0}", when) : I18n.tr("Build failed {0}", when);
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
  // When the build recorded for the dev tree was made ("" for none)
  readonly property string builtAt: BackendManager.dev.build?.at ?? ""
  // The dev config's file; whether live changed since dev last took it
  // over, and what readying it noted (seeded from the defaults: live is
  // newer than the dev tree), as of the dev start or, with dev mode off,
  // the last diff or copy
  readonly property string configPath: BackendManager.dev.config?.path ?? ""
  readonly property bool liveChanged: BackendManager.dev.config?.liveChanged ?? false
  readonly property string configNote: BackendManager.dev.config?.note ?? ""

  // Each method's `done(error, result)` is optional; a refusal is also
  // logged

  function setEnabled(on, done) {
    BackendManager.call("dev.set", {
      "enabled": on
    }, root._answer("dev mode", done));
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

  // Opens Settings › Development, turning the developer options on first
  // unless dev mode is on (the category shows only while one is)
  function openDevelopment() {
    if (root.showsDevelopment) {
      SettingsManager.openCategory("Development");
      return;
    }
    root.setOptions(true, error => {
      if (!error)
        SettingsManager.openCategory("Development");
    });
  }

  // Builds the dev tree (with dev mode off it only builds: the next dev on
  // runs it at once)
  function rebuild(done) {
    BackendManager.call("dev.rebuild", null, (error, result) => {
      if (error)
        console.warn("[DevManager] axiom refused the rebuild:", error.message);
      done?.(error, result);
    });
  }

  // Every setting dev and live differ on (with a dev tree set, dev mode on
  // or off; with it off, against the dev config's file, made from live the
  // first time): { rows:
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
        "onAction": id => root.openDevelopment()
      });
    });
  }

  // Once per dev start: live changed since the dev config took it over
  function _noteLiveChanged() {
    if (!_run.ready || !root.active || !root.liveChanged || _run.liveNotified || !NotificationsConfig.devNotifications)
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

  // The failing streak, kept across the re-exec a successful build starts
  // (and hot reloads): { failing, failedAt }
  readonly property var _streakState: StateManager.createStateHandler("dev-build")
  property var _streak: null

  // A streak's first failure, and the build that ends it
  function _noteBuild() {
    if (!_run.ready || !BackendManager.ready)
      return;
    if (root._streak === null)
      root._streak = root._streakState.load(DevBuildStreak.clear);
    const step = DevBuildStreak.next(root._streak, root.lastBuild, root.builtAt);
    if (JSON.stringify(step.streak) !== JSON.stringify(root._streak)) {
      root._streak = step.streak;
      root._streakState.save(step.streak);
    }
    if (step.notify === "" || !NotificationsConfig.devNotifications)
      return;
    if (step.notify === "works") {
      NotificationManager.sendNotification("axiom", I18n.tr("The dev build works again"), "", {
        "key": "dev-build"
      });
      return;
    }
    const lines = (root.lastBuild.output ?? "").trim().split("\n");
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
    property bool liveNotified: false
    property bool ready: false

    onLoaded: {
      _run.ready = true;
      root._noteBuild();
      root._noteLiveChanged();
    }
  }
}
