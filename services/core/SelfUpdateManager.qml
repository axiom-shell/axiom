pragma Singleton
import QtQuick
import Quickshell
import qs.config
import qs.services.system
import qs.services.ui

/*
 * Updates axiom itself (not packages: that's UpdatesManager). It follows the
 * clone's remote on SelfUpdate.channel: "tags" (releases, `v*` tags) or
 * "main" (every commit on the main branch). The daemon does the git work
 * (selfupdate.status reads the clone, selfupdate.check fetches and
 * compares, selfupdate.apply fast-forwards to the newest, rebuilds the
 * axiom binary and re-execs into it). A clone with changed tracked files,
 * local commits or another branch is `blocked` and never touched.
 *
 * SelfUpdate.mode: "auto" installs a new release and notifies; "notify"
 * notifies, and the notification opens Settings → Updates; "off" never
 * checks. Checks run once per qs launch (not per hot reload), daily, and
 * when the channel changes. Each release (or main's commit) is notified once.
 *
 * A packaged axiom (the AUR's axiom-shell, Paths.packaged) is updated by its
 * package manager: this never checks, and its settings are hidden. A tree
 * with no .git otherwise (`managed`) never checks either; the card says
 * its updates come from the package manager.
 *
 *   axiom ipc selfUpdate check
 *   axiom ipc selfUpdate update
 *   axiom ipc selfUpdate open
 */
Singleton {
  id: root

  readonly property bool checking: _checking
  readonly property bool applying: _applying
  readonly property bool busy: checking || applying

  // The installed release tag ("" before the first one), and HEAD
  readonly property string current: _result.current ?? ""
  readonly property string commit: _result.commit ?? ""
  // The newest release, or main's short commit ("" when the remote has none)
  readonly property string latest: _result.latest ?? ""
  // The channel the result is for: "tags" | "main"
  readonly property string channel: _result.channel ?? "tags"
  // "uptodate" | "available" | "diverged" | "" (no releases, or not checked)
  readonly property string state: _result.state ?? ""
  // Past the newest release (a development clone)
  readonly property bool ahead: _result.ahead ?? false
  readonly property int behind: _result.behind ?? 0
  // Why it can't update: "dirty" | "diverged" | "branch" | "nogit" | ""
  readonly property string blocked: _result.blocked ?? ""
  // Not a git clone: whatever installed it updates it (no check, no apply)
  readonly property bool managed: blocked === "nogit"
  // The newest release's tag message, or main's new commit subjects
  readonly property string notes: _result.notes ?? ""
  readonly property string error: _result.error ?? ""
  // ms since the epoch, 0 before the first check
  readonly property real lastChecked: _saved.lastChecked ?? 0

  readonly property bool available: state === "available" && blocked === "" && !Paths.packaged

  function check() {
    if (root.busy || Paths.packaged || root.managed)
      return;
    root._checking = true;
    BackendManager.call("selfupdate.check", {
      "channel": SelfUpdate.channel
    }, (error, result) => {
      root._checking = false;
      root._onChecked(error ? root._failed(error, SelfUpdate.channel) : result);
    });
  }

  function apply() {
    if (root.busy || !root.available)
      return;
    root._applying = true;
    BackendManager.call("selfupdate.apply", {
      "channel": root.channel,
      "target": root.latest
    }, (error, result) => {
      root._applying = false;
      root._onApplied(error ? root._failed(error, root.channel) : result);
    });
  }

  function openSettings() {
    SettingsManager.openSetting("SelfUpdate");
  }

  // I18n.tr("It has changed files. Commit or discard them to update.")
  // I18n.tr("It has commits of its own that the release doesn't.")
  // I18n.tr("It's on a branch other than main.")
  function blockedReason(reason) {
    switch (reason) {
    case "dirty":
      return I18n.tr("It has changed files. Commit or discard them to update.");
    case "diverged":
      return I18n.tr("It has commits of its own that the release doesn't.");
    case "branch":
      return I18n.tr("It's on a branch other than main.");
    }
    return "";
  }

  // -- Private --

  property var _result: ({})
  property bool _checking: false
  property bool _applying: false
  // { lastChecked, notifiedTag, result }: the last result survives reloads
  // and restarts, so the page has something to show before the next check
  property var _saved: ({})
  readonly property var _state: StateManager.createStateHandler("selfupdate")
  readonly property string _desktopEntry: "axiom-update"

  function _save(changes) {
    root._saved = Object.assign({}, root._saved, changes);
    root._state.save(root._saved);
  }

  // A failed call as a result: the last one's facts, with its message
  function _failed(error, channel) {
    return Object.assign({}, root._result, {
      "channel": channel,
      "error": error.message
    });
  }

  // The clone as it is, without fetching: the installed version, and
  // whether it's a clone at all, before the first check
  function _readStatus() {
    BackendManager.call("selfupdate.status", {
      "channel": SelfUpdate.channel
    }, (error, result) => {
      if (error) {
        console.warn(`[SelfUpdateManager] Reading the clone failed: ${error.message}`);
        return;
      }
      if (!root.busy)
        root._result = result;
    });
  }

  function _notify(summary, body) {
    NotificationManager.sendNotification("axiom", summary, body, {
      desktopEntry: root._desktopEntry
    });
  }

  function _onChecked(result) {
    root._result = result;
    root._save({
      lastChecked: Date.now(),
      result: result
    });
    // The channel changed while it ran
    if ((result.channel ?? "tags") !== SelfUpdate.channel) {
      Qt.callLater(root.check);
      return;
    }
    if (result.error) {
      console.warn(`[SelfUpdateManager] Check failed: ${result.error}`);
      return;
    }
    if (result.state !== "available" && result.state !== "diverged")
      return;
    const auto = SelfUpdate.mode === "auto";
    if (auto && root.available) {
      root.apply();
      return;
    }
    // Once per release
    if (root.latest === root._saved.notifiedTag || SelfUpdate.mode === "off")
      return;
    root._save({
      notifiedTag: root.latest
    });
    const summary = root.channel === "main" ? I18n.tr("axiom has {0} new commits on main", root.behind) : I18n.tr("axiom {0} is available", root.latest);
    if (root.blocked === "")
      root._notify(summary, I18n.tr("Click to see what's new and update."));
    else
      root._notify(summary, I18n.tr("Your copy can't update: {0}", root.blockedReason(root.blocked)));
  }

  function _onApplied(result) {
    root._result = result;
    root._save({
      result: result
    });
    if (result.error) {
      console.warn(`[SelfUpdateManager] Update failed: ${result.error}`);
      root._notify(I18n.tr("axiom update failed"), result.error || I18n.tr("Unknown error"));
      return;
    }
    // On main, the commit: the last tag says little
    const version = result.channel === "main" ? result.commit : result.current;
    console.log(`[SelfUpdateManager] Updated to ${version}`);
    root._save({
      notifiedTag: version
    });
    // The "available" notification is done with
    NotificationManager.dismissApp(root._desktopEntry);
    root._notify(I18n.tr("axiom updated to {0}", version), result.notes || I18n.tr("Click to see what's new."));
    // With the binary rebuilt, the daemon re-execs into it; when the
    // update changed the schema, it restarts the shell itself
    if (result.buildError) {
      console.warn(`[SelfUpdateManager] The axiom binary didn't build: ${result.buildError}`);
      root._notify(I18n.tr("The axiom binary didn't build"), I18n.tr("Until it does, settings can't be saved after the next start: {0}", result.buildError));
    }
    // git replaces files rather than editing them, which qs's file
    // watcher can miss, so reload explicitly
    _reloadTimer.restart();
  }

  // Survives hot reloads, so a reload (including the one after an update)
  // doesn't check again
  PersistentProperties {
    id: _run
    reloadableId: "axiomSelfUpdate"
    property bool checked: false
  }

  // Let the startup settle (and the network come up) before fetching
  Timer {
    id: _startup
    interval: 15000
    onTriggered: {
      _run.checked = true;
      root.check();
    }
  }

  Timer {
    interval: 24 * 60 * 60 * 1000
    repeat: true
    running: SelfUpdate.mode !== "off" && !Paths.packaged && !root.managed
    onTriggered: root.check()
  }

  // Gives the notification a moment to go out first
  Timer {
    id: _reloadTimer
    interval: 1000
    onTriggered: Quickshell.reload(false)
  }

  IpcTarget {
    target: "selfUpdate"

    function check(): void {
      root.check();
    }

    function update(): void {
      root.apply();
    }

    // Settings → Updates
    function open(): void {
      root.openSettings();
    }
  }

  Connections {
    target: SelfUpdate
    function onModeChanged() {
      if (SelfUpdate.mode !== "off" && !_run.checked && !Paths.packaged)
        _startup.restart();
    }
    // The last result was for the other channel
    function onChannelChanged() {
      if (_run.checked)
        root.check();
    }
  }

  Component.onCompleted: {
    root._saved = root._state.load({});
    root._result = root._saved.result ?? {};
    NotificationManager.registerHandler(root._desktopEntry, () => root.openSettings());
    if (!Paths.packaged)
      root._readStatus();
    if (SelfUpdate.mode !== "off" && !_run.checked && !Paths.packaged)
      _startup.start();
  }
}
