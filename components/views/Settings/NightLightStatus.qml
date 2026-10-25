pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.compositor
import qs.services.system
import qs.components.reusable

// The top of the Night light card (the section's `x-intro`): whether it's
// on, which tool runs it, and a switch to try the settings
ColumnLayout {
  id: root

  readonly property bool missing: NightLightManager.tool === ""
  // What to install: hyprsunset drives only Hyprland (NightLightManager.tool)
  readonly property string wanted: CompositorManager.kind === "hyprland" ? "hyprsunset" : "wlsunset"

  // Empty until the tool is looked up
  readonly property string detail: {
    if (NightLightManager.tool === undefined)
      return "";
    if (root.missing)
      return I18n.tr("Neither hyprsunset nor wlsunset is installed. Install {0} to use the night light.", root.wanted);
    if (NightLight.schedule)
      return I18n.tr("Runs {0}, on from {1} until {2}.", NightLightManager.tool, NightLight.startAt, NightLight.endAt);
    return I18n.tr("Runs {0} when you turn it on.", NightLightManager.tool);
  }

  spacing: Widget.spacing

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    StatusChip {
      text: root.missing ? I18n.tr("Not installed") : NightLightManager.active ? I18n.tr("On") : I18n.tr("Off")
      color: root.missing ? Theme.error : NightLightManager.active ? Theme.success : Theme.foregroundAlt
    }

    StyledText {
      text: root.detail
      textColor: root.missing ? Theme.error : Theme.foreground
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    StyledTextButton {
      visible: NightLightManager.available
      implicitHeight: Widget.height - Widget.px(4)
      text: NightLightManager.active ? I18n.tr("Turn off") : I18n.tr("Turn on")
      onClicked: NightLightManager.toggle()
    }
  }

  // How to install it here (nothing on a distribution axiom has no
  // package names for)
  CodeLine {
    visible: root.missing && text !== ""
    text: DependencyManager.installCommand(root.wanted)
  }
}
