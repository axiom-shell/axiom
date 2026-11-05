pragma Singleton
import QtQuick
import Quickshell
import qs.config
import qs.services.core
import qs.services.system

/*
 * This machine, for Settings › System › System info: its name, operating
 * system, kernel, processor, graphics, memory, root disk and boot time,
 * and the bug report's lines (system.info, backend/internal/sysinfo and
 * buginfo). Read on `refresh()` (the card's opening), never polled.
 * `copyReport()` copies the bug report's lines, which hold nothing
 * personal (no hostname); `rename(name)` renames the machine through
 * hostnamed, polkit asking the user.
 */
Singleton {
  id: root

  // sysinfo.Info, {} before the first answer
  readonly property var info: _answer.info ?? ({})
  // buginfo.Report: { axiom, binary, quickshell, compositor, monitors, distro, config }
  readonly property var report: _answer.report ?? ({})
  readonly property bool loaded: _answer.info !== undefined
  readonly property bool loading: _loading
  // The last rename's error ("" when it worked or none ran)
  readonly property string renameError: _renameError
  readonly property bool renaming: _renaming

  // The install's kind: "package" (Paths.packaged), "dev" (dev mode runs a
  // dev tree), "clone" (a git clone updating itself) or "copy" (neither)
  readonly property string installKind: {
    if (Paths.packaged)
      return "package";
    if (DevManager.active)
      return "dev";
    return SelfUpdateManager.managed ? "copy" : "clone";
  }

  // Seconds since boot when the answer came (the card refreshes on opening)
  readonly property real uptime: root.info.boot > 0 ? Math.max(0, _answeredAt / 1000 - root.info.boot) : 0

  function refresh() {
    if (root._loading)
      return;
    root._loading = true;
    BackendManager.call("system.info", {}, (error, result) => {
      root._loading = false;
      if (error) {
        if (error.kind !== "unavailable")
          console.warn("[SystemInfoManager] system.info failed:", error.message);
        return;
      }
      root._answeredAt = Date.now();
      root._answer = result;
    }, {
      "repeatable": true
    });
  }

  // The bug report's lines, as `axiom bug-info` prints them
  function reportText() {
    const r = root.report;
    const lines = [["axiom", r.axiom], ["Binary", r.binary], ["Quickshell", r.quickshell], ["Compositor", r.compositor], ["Monitors", r.monitors], ["Distro", r.distro], ["Config", r.config]];
    return lines.map(line => (line[0] + ":").padEnd(12) + (line[1] ?? "unknown")).join("\n");
  }

  function copyReport() {
    ClipboardManager.copyText(root.reportText());
  }

  function rename(name, done) {
    if (root._renaming)
      return;
    root._renaming = true;
    root._renameError = "";
    BackendManager.call("system.setHostname", {
      "name": String(name ?? "")
    }, error => {
      root._renaming = false;
      root._renameError = error ? root.errorText(error) : "";
      if (!error)
        root.refresh();
      if (done)
        done(error);
    });
  }

  // What a polkit-guarded change's failure says to the user
  function errorText(error) {
    switch (error?.kind) {
    case "refused":
      return I18n.tr("Not allowed: authentication was cancelled or refused.");
    case "unavailable":
      return I18n.tr("The system service isn't available.");
    case "bad_request":
      return error.message;
    }
    return error?.message ?? "";
  }

  property var _answer: ({})
  property real _answeredAt: 0
  property bool _loading: false
  property bool _renaming: false
  property string _renameError: ""
}
