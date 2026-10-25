pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.components.reusable

// The top of the axiom updates card (the section's `x-intro`): dev mode,
// a switch for it, and the last dev build (DevManager)
ColumnLayout {
  id: root

  readonly property string detail: {
    if (!DevManager.enabled)
      return I18n.tr("Rebuilds the schema and axiom itself as you edit them, the shell running on.");
    if (!DevManager.available)
      return DevManager.unavailable;
    if (DevManager.building)
      return I18n.tr("Building axiom…");
    const build = DevManager.lastBuild;
    if (build && !build.ok)
      return I18n.tr("The last build failed: axiom runs the one before.");
    return DevManager.onDevBuild ? I18n.tr("Running a dev build: edits to the Go source rebuild it.") : I18n.tr("Edits to the Go source rebuild axiom.");
  }

  spacing: Widget.spacing
  visible: BackendManager.ready

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    StatusChip {
      text: DevManager.building ? I18n.tr("Building") : DevManager.enabled ? I18n.tr("Dev mode") : I18n.tr("Dev mode off")
      color: DevManager.lastBuild && !DevManager.lastBuild.ok ? Theme.error : DevManager.enabled ? Theme.accent : Theme.foregroundAlt
    }

    StyledText {
      text: root.detail
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    StyledTextButton {
      visible: DevManager.enabled && DevManager.available
      enabled: !DevManager.building
      implicitHeight: Widget.height - Widget.px(4)
      text: I18n.tr("Rebuild")
      onClicked: DevManager.rebuild()
    }

    StyledTextButton {
      implicitHeight: Widget.height - Widget.px(4)
      text: DevManager.enabled ? I18n.tr("Turn off") : I18n.tr("Turn on")
      onClicked: DevManager.toggle()
    }
  }

  StyledText {
    visible: DevManager.offMakesReadOnly
    text: I18n.tr("This tree's schema isn't the installed binary's: turned off, settings can't be saved until axiom is rebuilt.")
    textColor: Theme.warning
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  // The compiler's last lines
  CodeLine {
    visible: DevManager.lastBuild !== null && !DevManager.lastBuild.ok
    text: (DevManager.lastBuild?.output ?? "").trim().split("\n").slice(-6).join("\n")
  }
}
