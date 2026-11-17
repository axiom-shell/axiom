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
PageCard {
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

  // The one switch for the Development category; follows axiom's answer,
  // not the click
  SwitchRow {
    label: I18n.tr("Enabled")
    description: I18n.tr("Shows the Development category: a dev tree axiom runs and rebuilds as you edit it, on its own config.")
    enabled: BackendManager.ready
    checked: DevManager.options
    onToggled: newValue => DevManager.setOptions(newValue)
  }

  StatusLine {
    visible: DevManager.showsDevelopment
    Layout.fillWidth: true
    chip: DevManager.building ? I18n.tr("Building") : DevManager.enabled ? I18n.tr("Dev mode") : I18n.tr("Dev mode off")
    chipTone: DevManager.buildFailed ? "error" : DevManager.enabled ? "accent" : "neutral"
    text: root.detail

    StyledTextButton {
      text: I18n.tr("Open Development")
      onClicked: DevManager.openDevelopment()
    }
  }
}
