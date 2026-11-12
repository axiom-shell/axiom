pragma Singleton
import QtQuick

import qs.services.core

/*
 * The uninstall behind Settings › General's "Remove axiom from this system"
 * (docs/dev/backend/uninstall.md): the plan the daemon says an uninstall
 * would carry out (it changes nothing), and starting one. The daemon starts
 * it detached, since it quits this daemon and the shell first: the dialog
 * then ends with the shell. Nothing polls.
 */
QtObject {
  id: root

  // The plan: { actions, manual, backups, greeter, running, counts }; null
  // until the first refresh
  property var plan: null
  // Where the detached uninstall writes its summary
  property string logPath: ""
  // A refresh is waiting for the daemon
  property bool busy: false
  // Why the last refresh or start failed ("" when it didn't)
  property string error: ""

  // Asks for the plan again (a refresh that comes while one waits is run
  // after it); the old plan is dropped first, so a failure never shows a
  // plan that no longer holds
  // rpc: uninstall.plan
  function refresh() {
    if (root.busy) {
      root._again = true;
      return;
    }
    root.busy = true;
    root.plan = null;
    BackendManager.call("uninstall.plan", {}, (error, result) => {
      root.busy = false;
      if (error) {
        root.plan = null;
        root.error = error.message;
        console.warn("[UninstallManager] uninstall.plan:", error.message);
      } else {
        root.error = "";
        root.plan = result.plan;
        root.logPath = result.log;
      }
      if (root._again) {
        root._again = false;
        root.refresh();
      }
    });
  }
  property bool _again: false

  // Starts the uninstall with the answers ({ keepConfig, keepUserContent,
  // keepSecrets, undoInferred, restoreSystem, restartPortal }); done(ok)
  // is called when the daemon has started it
  // rpc: uninstall.start
  function start(answers, done) {
    BackendManager.call("uninstall.start", {
      "answers": answers
    }, (error, result) => {
      if (error) {
        root.error = error.message;
        console.warn("[UninstallManager] uninstall.start:", error.message);
        done?.(false);
        return;
      }
      root.error = "";
      root.logPath = result.log;
      done?.(true);
    });
  }
}
