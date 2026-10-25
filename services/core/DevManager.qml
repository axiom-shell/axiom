pragma Singleton
import QtQuick
import qs.config
import qs.services.system

// Dev mode, which axiom switches while it runs (`axiom dev`,
// docs/dev/backend/README.md): the schema follows its YAML, a tree whose
// schema isn't the binary's may save, and an edit to the Go source builds
// a binary axiom re-execs into. State comes from BackendManager.dev; a
// build that fails sends a notification.
QtObject {
  id: root

  readonly property bool enabled: BackendManager.dev.enabled ?? false
  // Edits to the Go source can be built here (the tree has it, go is
  // installed); unavailable says why not
  readonly property bool available: BackendManager.dev.available ?? false
  readonly property string unavailable: BackendManager.dev.unavailable ?? ""
  readonly property bool building: BackendManager.dev.building ?? false
  // { ok, at, output }, null before the first build this run
  readonly property var lastBuild: BackendManager.dev.lastBuild ?? null
  // Running a dev build rather than the installed binary
  readonly property bool onDevBuild: (BackendManager.dev.binary ?? "") !== (BackendManager.dev.installed ?? "")
  // Turning dev mode off would leave the config read-only (the tree's
  // schema isn't the binary's) until the binary is rebuilt
  readonly property bool offMakesReadOnly: root.enabled && (BackendManager.dev.offReadOnly ?? false)

  function setEnabled(on) {
    BackendManager.call("dev.set", {
      "enabled": on
    }, (error, result) => {
      if (error)
        console.warn("[DevManager] axiom refused dev mode:", error.message);
    });
  }

  function toggle() {
    root.setEnabled(!root.enabled);
  }

  function rebuild() {
    BackendManager.call("dev.rebuild", null, (error, result) => {
      if (error)
        console.warn("[DevManager] axiom refused the rebuild:", error.message);
    });
  }

  property string _notifiedAt: ""

  property Connections _builds: Connections {
    target: BackendManager

    function onDevChanged() {
      const build = root.lastBuild;
      if (!build || build.ok || build.at === root._notifiedAt)
        return;
      root._notifiedAt = build.at;
      const lines = (build.output ?? "").trim().split("\n");
      NotificationManager.sendNotification("axiom", I18n.tr("The dev build failed"), lines.slice(-3).join("\n"));
    }
  }
}
