pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.components.reusable
import qs.components.forms

// Settings page, General (the category's last `card`, wide): the Developer
// options switch, which shows the Development category (kept by axiom, not
// in config; the category shows while dev mode is on too), and a line on
// dev mode
FieldGroup {
  id: root

  readonly property string detail: {
    if (!DevManager.enabled)
      return DevManager.tree === "" ? I18n.tr("Dev mode is off; no dev tree is set.") : I18n.tr("Dev mode is off; the dev tree is {0}.", Paths.shortenHome(DevManager.tree));
    if (DevManager.building)
      return I18n.tr("Dev mode is on, building {0}.", Paths.shortenHome(DevManager.tree));
    if (DevManager.buildFailed)
      return I18n.tr("Dev mode is on, but the last dev build failed.");
    return DevManager.active ? I18n.tr("Dev mode runs {0} on its own config.", Paths.shortenHome(DevManager.tree)) : I18n.tr("Dev mode is on; the installed axiom runs until the dev build is ready.");
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    // I18n.tr("Enabled")
    // I18n.tr("Shows the Development category: a dev tree axiom runs and rebuilds as you edit it, on its own config.")
    FieldHeader {
      label: "Enabled"
      description: "Shows the Development category: a dev tree axiom runs and rebuilds as you edit it, on its own config."
    }

    // The one switch for the Development category
    StyledSwitch {
      id: optionsSwitch
      enabled: BackendManager.ready
      checked: DevManager.options
      onToggled: {
        DevManager.setOptions(optionsSwitch.checked);
        // Follows axiom's answer, not the click
        optionsSwitch.checked = Qt.binding(() => DevManager.options);
      }
    }
  }

  RowLayout {
    visible: DevManager.showsDevelopment
    Layout.fillWidth: true
    spacing: Widget.spacing

    StatusChip {
      text: DevManager.building ? I18n.tr("Building") : DevManager.enabled ? I18n.tr("Dev mode") : I18n.tr("Dev mode off")
      color: DevManager.buildFailed ? Theme.error : DevManager.enabled ? Theme.accent : Theme.foregroundAlt
    }

    StyledText {
      text: root.detail
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    StyledTextButton {
      implicitHeight: Widget.height - Widget.px(4)
      text: I18n.tr("Open Development")
      onClicked: DevManager.openDevelopment()
    }
  }
}
