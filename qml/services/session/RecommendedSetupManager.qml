pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.compositor
import qs.services.apps
import qs.services.ui

/*
 * The Recommended setup of managed mode: one list of what axiom can run for
 * the user (managed mode, its lock screen, Idle, Polkit, the screen-sharing
 * picker, App colors for installed apps, the greeter), ticked by default
 * and applied in one go. The entries come from the schema's
 * `x-recommended` annotations and the rows (what's available, done, ticked)
 * from methods/RecommendedSetup; this keeps the facts they need, the user's
 * ticks and the run, which lives here and not in the list so it outlives the
 * page or card showing it (the greeter's password prompt and the hookups'
 * callbacks can come back after it's gone) and carries across onboarder
 * pages.
 *
 * An Apply runs RecommendedSetup.steps one at a time: the later rows (the
 * onboarder's compositor mode, applied on Finish), one commit of every
 * setting (a takeover save: an explicit user action, so nothing else may
 * commit these paths this way), the screen-sharing hookup and portal step,
 * the app hookups, and the greeter install last (its root prompt). A failed
 * commit fails every row in it and stops the run; a hookup or portal failure
 * marks only its own row.
 *
 * `offered` (the Compositor card shows the list once after a save into
 * managed mode) is kept across reloads. IPC `recommendedSetup`: rows, check,
 * apply. Created from shell.qml's `_services`.
 */
Singleton {
  id: root

  // --- What the list has ---

  readonly property var entries: RecommendedSetup.entries(ConfigManager.configSchema)
  // The entries' ids, which never change: a Repeater's model (the rows
  // themselves follow live values)
  readonly property var ids: root.entries.map(entry => entry.id)
  // The recommended integrations whose app is installed (the App colors
  // page's "Turn on for installed apps" too)
  readonly property var appKeys: RecommendedSetup.appKeys(ConfigManager.configSchema.properties.ThemeIntegrations, DependencyManager.found)

  // Every row by id: RecommendedSetup.rows with the user's tick (`checked`,
  // only while it's available and not done) and the run's state: `state`
  // ("idle" | "pending" | "running" | "later" | "done" | "skipped" |
  // "failed"), `note` ("later" | "deferred" | "") and `error` (translated)
  // I18n.tr("Your compositor can't do this") I18n.tr("axiom won't take over this config")
  // I18n.tr("axiom's own portal file (axiom.portal) isn't installed: run axiom's install.sh again, or reinstall its package.")
  // I18n.tr("None of the apps axiom colors is installed") I18n.tr("greetd or agreety isn't installed")
  // I18n.tr("Needs sway or Hyprland to run in") I18n.tr("Nothing to install from: axiom isn't a git clone or a package")
  // I18n.tr("Checking...") I18n.tr("Waiting") I18n.tr("Applying...") I18n.tr("Done") I18n.tr("Skipped") I18n.tr("Failed")
  // I18n.tr("Already on") I18n.tr("Applies when you finish")
  readonly property var rows: {
    const base = RecommendedSetup.rows(root.entries, root._facts);
    const result = {};
    for (const id in base) {
      const row = Object.assign({}, base[id]);
      const run = root._runState[id] ?? {};
      row.checked = row.available && !row.done && (id in root._userChoice ? root._userChoice[id] : row.checkedByDefault);
      row.state = run.state ?? "idle";
      row.note = run.note ?? "";
      row.error = run.error ?? "";
      result[id] = row;
    }
    return result;
  }

  // An Apply is running
  readonly property bool running: root._running
  // The Compositor card offers the list (after a save into managed mode)
  readonly property bool offered: _persist.offered

  // The facts RecommendedSetup.rows reads
  readonly property var _facts: ({
      "config": ConfigManager.config,
      "schema": ConfigManager.configSchema,
      "valueOf": SettingsManager.showIfValue,
      "later": root._later,
      "modeAllowed": OnboardingManager.compositorSupported && OnboardingManager.modeAllowed,
      // A config of the user's own starts detached (the user's answer): the
      // row is tickable by hand
      "modeDefault": OnboardingManager.recommendedMode === "managed",
      "managedBlocked": CompositorConfigManager.managedCheck === "blocked",
      "portal": {
        "known": !!ScreenShareManager.portal,
        "installed": ScreenShareManager.portalInstalled,
        "axiomInstalled": ScreenShareManager.axiomPortalInstalled,
        "hookedUp": IntegrationHookupManager.isDone("screenSharing")
      },
      "apps": {
        "installed": root.appKeys,
        "hookups": root._hookups
      },
      "greeter": GreeterManager.status
    })

  // Per recommended integration: "none" when Apply has nothing to do for it
  // (no targets, or only copy-only or skipped ones once checked), else
  // "done" or "todo" (not checked yet counts as todo)
  readonly property var _hookups: {
    const status = IntegrationHookupManager.status;
    const result = {};
    for (const key of root.appKeys) {
      const targets = status[key]?.targets;
      const actionable = targets ? targets.filter(t => !t.copyOnly && !t.skipped) : null;
      if (IntegrationHookupManager.targets(key).length === 0 || (actionable && actionable.length === 0))
        result[key] = "none";
      else
        result[key] = IntegrationHookupManager.isDone(key) ? "done" : "todo";
    }
    return result;
  }

  // --- The host's hooks and the user's ticks ---

  // Called by a host as it shows (the list): forgets ticks and the last
  // run unless one is running, keeps the host's `later` paths (rows
  // checked but not committed) and `choose(path, value)`, and checks what the
  // facts need. Without an Apply of its own the list is read-only data
  function begin(options) {
    if (root._running)
      return;
    root._userChoice = {};
    root._runState = {};
    root._later = options?.later ?? [];
    root._choose = options?.choose ?? null;
    root.refresh();
  }

  // Looks at what the facts need: the greeter, the portal, which apps are
  // installed and which hookups are done
  function refresh() {
    GreeterManager.check();
    ScreenShareManager.checkPortal();
    const apps = root.entries.find(entry => entry.step === "apps");
    const keys = apps ? apps.keys : [];
    DependencyManager.check([].concat(...keys.map(key => ThemeManager.integrationCommands(key))));
    IntegrationHookupManager.check("screenSharing");
    for (const key of keys)
      IntegrationHookupManager.check(key);
  }

  function setChecked(id, on) {
    const next = Object.assign({}, root._userChoice);
    next[id] = on;
    root._userChoice = next;
  }

  // The Compositor card's offer: set by a save into managed mode, cleared
  // by Not now or Close, or when the mode leaves managed
  function offer() {
    root.begin({});
    _persist.offered = true;
  }

  function dismiss() {
    _persist.offered = false;
  }

  // --- The run ---

  // `options` ({ later, choose }, optional) are the caller's own, as
  // begin's: another host's begin since can't make this Apply commit or
  // choose what that host's list had
  function apply(options) {
    if (root._running)
      return;
    if (options) {
      root._later = options.later ?? [];
      root._choose = options.choose ?? null;
    }
    const rows = root.rows;
    const checked = {};
    for (const id in rows)
      checked[id] = rows[id].checked;
    const plan = RecommendedSetup.steps(root.entries, rows, checked);
    if (plan.length === 0)
      return;
    const named = {};
    for (const step of plan) {
      if (step.row)
        named[step.row] = true;
      for (const id of step.rows ?? [])
        named[id] = true;
    }
    const state = {};
    for (const id in rows) {
      if (named[id])
        state[id] = {
          "state": "pending"
        };
      else if (rows[id].available && !rows[id].done)
        state[id] = {
          "state": "skipped"
        };
    }
    root._runState = state;
    root._plan = plan;
    root._index = 0;
    root._runId++;
    root._commitRows = [];
    root._polkitCommitted = plan.some(step => step.step === "commit" && "Polkit.enabled" in step.values);
    root._shareHookupFailed = false;
    root._running = true;
    root._next();
  }

  // The portal row's Restart button: restarts the portal now, takes the
  // "takes effect later" note away once it did
  function restartPortal() {
    const id = "ScreenSharing.enabled";
    ScreenShareManager.restartPortal((ok, stderr) => {
      if (ok) {
        const failed = root._runState[id]?.state === "failed" && !root._shareHookupFailed;
        root._setRow(id, failed ? {
          "state": "done",
          "note": "",
          "error": ""
        } : {
          "note": ""
        });
      } else {
        root._setRow(id, {
          "state": "failed",
          "error": I18n.tr("Couldn't restart the portal: {0}", stderr)
        });
      }
    });
  }

  property bool _running: false
  property var _plan: []
  property int _index: 0
  // Bumped per Apply, so a stale callback does nothing
  property int _runId: 0
  property var _commitRows: []
  property bool _polkitCommitted: false
  property bool _shareHookupFailed: false
  property bool _waitingForPolkit: false
  property bool _awaitingGreeter: false
  property string _greeterRow: ""
  property var _userChoice: ({})
  property var _runState: ({})
  property var _later: []
  property var _choose: null

  function _setRow(id, patch) {
    const next = Object.assign({}, root._runState);
    next[id] = Object.assign({}, next[id] ?? {}, patch);
    root._runState = next;
  }

  // Marks the row failed; a row failed more than once (apps) joins the texts
  function _fail(id, error) {
    const before = root._runState[id];
    root._setRow(id, {
      "state": "failed",
      "error": before?.error ? before.error + ", " + error : error
    });
  }

  // A row left running that no step to come names is done
  function _settle() {
    const named = {};
    for (const step of root._plan.slice(root._index)) {
      if (step.row)
        named[step.row] = true;
    }
    for (const id in root._runState) {
      if (root._runState[id].state === "running" && !named[id])
        root._setRow(id, {
          "state": "done"
        });
    }
  }

  // Ends the run: what's still pending was never reached
  function _stop() {
    for (const id in root._runState) {
      if (root._runState[id].state === "pending" || root._runState[id].state === "running")
        root._setRow(id, {
          "state": "skipped"
        });
    }
    root._plan = [];
    root._running = false;
    // The greeter install must not start after a stop
    root._waitingForPolkit = false;
    _polkitWait.stop();
  }

  function _next() {
    if (!root._running)
      return;
    root._settle();
    if (root._index >= root._plan.length) {
      root._running = false;
      return;
    }
    const step = root._plan[root._index++];
    if (step.step === "later")
      root._runLater(step);
    else if (step.step === "commit")
      root._runCommit(step);
    else if (step.step === "hookup")
      root._runHookup(step);
    else if (step.step === "portal")
      root._runPortal(step);
    else if (step.step === "greeter")
      root._runGreeter(step);
  }

  function _runLater(step) {
    if (root._choose)
      root._choose(step.path, step.value);
    root._setRow(step.row, {
      "state": "later",
      "note": "later"
    });
    root._next();
  }

  function _runCommit(step) {
    for (const id of step.rows)
      root._setRow(id, {
        "state": "running"
      });
    root._commitRows = step.rows;
    const run = root._runId;
    // The step goes on once axiom has answered: a refusal fails its rows
    if (!SettingsManager.commitValues(step.values, ok => {
      if (run !== root._runId || !root._running)
        return;
      if (ok) {
        root._next();
        return;
      }
      for (const id of step.rows)
        root._fail(id, I18n.tr("axiom refused the change"));
      root._stop();
    })) {
      for (const id of step.rows)
        root._fail(id, I18n.tr("Settings can't be saved right now"));
      root._stop();
    }
  }

  function _runHookup(step) {
    const id = root._runId;
    // Several app hookups share a row: a failed one stays failed
    if (root._runState[step.row]?.state !== "failed")
      root._setRow(step.row, {
        "state": "running"
      });
    IntegrationHookupManager.apply(step.key, (ok, error) => {
      if (id !== root._runId || !root._running)
        return;
      if (!ok) {
        if (step.key === "screenSharing") {
          root._shareHookupFailed = true;
          root._fail(step.row, error);
        } else {
          // i18n: keys from the schema (integration titles)
          root._fail(step.row, I18n.tr(ThemeManager.integrationTitle(step.key)));
        }
      }
      root._next();
    });
  }

  function _runPortal(step) {
    if (root._shareHookupFailed) {
      root._next();
      return;
    }
    root._setRow(step.row, {
      "state": "running"
    });
    if (RecommendedSetup.portalAction(ScreenShareManager.shareActive) === "defer") {
      root._setRow(step.row, {
        "note": "deferred"
      });
      root._next();
      return;
    }
    const id = root._runId;
    ScreenShareManager.restartPortal((ok, stderr) => {
      if (id !== root._runId || !root._running)
        return;
      if (!ok)
        root._fail(step.row, I18n.tr("Couldn't restart the portal: {0}", stderr));
      root._next();
    });
  }

  // Axiom stops other polkit agents as it turns on, and pkexec fails with
  // none registered: the install waits for it (at most 10 s)
  function _runGreeter(step) {
    root._greeterRow = step.row;
    root._setRow(step.row, {
      "state": "running"
    });
    if (root._polkitCommitted && PolkitManager.status === "starting") {
      root._waitingForPolkit = true;
      _polkitWait.restart();
      return;
    }
    root._installGreeter();
  }

  function _installGreeter() {
    root._waitingForPolkit = false;
    _polkitWait.stop();
    if (GreeterManager.elevating) {
      root._fail(root._greeterRow, I18n.tr("Another install is running"));
      root._next();
      return;
    }
    root._awaitingGreeter = true;
    GreeterManager.install();
  }

  property Timer _polkitWait: Timer {
    interval: 10000 // axiom's polkit agent registering
    onTriggered: {
      if (root._waitingForPolkit)
        root._installGreeter();
    }
  }

  // Earlier steps stay applied whatever the install does
  property Connections _greeterPhase: Connections {
    target: GreeterManager
    enabled: root._awaitingGreeter

    function onPhaseChanged() {
      if (GreeterManager.phase === "done" || GreeterManager.phase === "failed") {
        root._awaitingGreeter = false;
        if (GreeterManager.phase === "failed")
          root._fail(root._greeterRow, GreeterManager.lastError);
        root._next();
      }
    }
  }

  property Connections _polkitStatus: Connections {
    target: PolkitManager
    enabled: root._waitingForPolkit

    function onStatusChanged() {
      if (PolkitManager.status !== "starting")
        root._installGreeter();
    }
  }

  // Leaving managed mode closes the offer
  property Connections _mode: Connections {
    target: CompositorConfig

    function onModeChanged() {
      if (CompositorConfig.mode !== "managed")
        root.dismiss();
    }
  }

  PersistentProperties {
    id: _persist
    reloadableId: "axiomRecommendedSetup"
    property bool offered: false
  }

  property IpcTarget _ipc: IpcTarget {
    target: "recommendedSetup"

    // The rows by id as JSON: { id: { checked, state, note, error, ... } }
    function rows(): string {
      return JSON.stringify(root.rows);
    }

    // Ticks or unticks a row ("on" | "off")
    function check(id: string, on: string): void {
      root.setChecked(id, on === "on" || on === "true");
    }

    function apply(): void {
      root.apply();
    }
  }
}
