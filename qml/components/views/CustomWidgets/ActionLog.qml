pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.reusable

// Custom widgets page: the selected definition's last action commands, newest
// first (CustomWidgetsEditor.actionLog: the page's, never saved), each as
// "Ran: <command> → exit N · 120 ms · <stderr>", or "Refused: <why>" for
// one that wasn't run (busy, disabled, locked…). Test mode and the real
// buttons both land here.
StyledText {
  id: root

  readonly property var editor: CustomWidgetsManager.editor
  // One text, not a row per entry: the log is live
  readonly property string lines: root.editor.actionLog.slice().reverse().map(entry => entry.refused !== "" ? I18n.tr("Refused: {0} ({1})", entry.refused, entry.action) : I18n.tr("Ran: {0} → exit {1} · {2} ms", entry.command.slice(0, 160), entry.exitCode, entry.ms) + (entry.stderr !== "" ? " · " + entry.stderr : "")).join("\n")

  Layout.fillWidth: true
  text: root.lines !== "" ? root.lines : I18n.tr("No action has run yet.")
  textFamily: root.lines !== "" ? "monospace" : ""
  role: "caption"
  tone: root.lines !== "" ? "muted" : "faint"
  overflow: "wrap"
  maxLines: 20
}
