pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.ui
import qs.components.reusable
import qs.components.forms

// The top of the axiom updates card (the section's `x-intro`): the
// Developer options switch, which shows the Development category (kept by
// axiom, not in config), and a line on dev mode
ColumnLayout {
  id: root

  readonly property string detail: {
    if (!DevManager.enabled)
      return DevManager.tree === "" ? I18n.tr("Dev mode is off; no dev tree is set.") : I18n.tr("Dev mode is off; the dev tree is {0}.", Paths.shortenHome(DevManager.tree));
    if (DevManager.building)
      return I18n.tr("Dev mode is on, building {0}.", Paths.shortenHome(DevManager.tree));
    if (DevManager.lastBuild && !DevManager.lastBuild.ok)
      return I18n.tr("Dev mode is on, but the last dev build failed.");
    return DevManager.active ? I18n.tr("Dev mode runs {0} on its own config.", Paths.shortenHome(DevManager.tree)) : I18n.tr("Dev mode is on; the installed axiom runs until the dev build is ready.");
  }

  spacing: Widget.spacing
  visible: BackendManager.ready

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    // I18n.tr("Developer options")
    // I18n.tr("Shows the Development category: a dev tree axiom runs and rebuilds as you edit it, on its own config.")
    FieldHeader {
      label: "Developer options"
      description: "Shows the Development category: a dev tree axiom runs and rebuilds as you edit it, on its own config."
    }

    // On while dev mode is: it's turned off in Development first
    StyledSwitch {
      id: optionsSwitch
      enabled: !DevManager.enabled
      checked: DevManager.options || DevManager.enabled
      onToggled: {
        DevManager.setOptions(optionsSwitch.checked);
        // Follows axiom's answer, not the click
        optionsSwitch.checked = Qt.binding(() => DevManager.options || DevManager.enabled);
      }
    }
  }

  RowLayout {
    visible: DevManager.options || DevManager.enabled
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
      implicitHeight: Widget.height - Widget.px(4)
      text: I18n.tr("Open Development")
      onClicked: SettingsManager.openCategory("Development")
    }
  }
}
