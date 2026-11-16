pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.methods
import qs.components.reusable
import qs.components.content.parts.custom

// A custom widget's Toggle element: its state binding as truthy reads it
// (false, 0, no, off, disabled, inactive and "" are off) as a switch beside its label,
// or as a quick-settings ActionPill; flipping it runs its turn-on or
// turn-off action (`{value}` on or off) and holds the new state until the
// next sample.
CustomElementBase {
  id: root

  readonly property bool on: CustomWidgetData.truthy(root.value("state", "alt"))
  readonly property string label: root.text("label")
  // The state just set, until the next sample (-1: none)
  property int held: -1
  onFieldsChanged: root.held = -1
  // A failed run never reached the sample: the switch shows the sample's state again
  onFailedRunChanged: {
    if (root.failedRun)
      root.held = -1;
  }
  readonly property bool shownOn: root.held >= 0 ? root.held === 1 : root.on

  function flip(on) {
    root.held = on ? 1 : 0;
    if (root.runTrigger(on ? "on" : "off", on ? "on" : "off") !== "")
      root.held = -1;
  }

  Loader {
    anchors.fill: parent
    sourceComponent: root.options.look === "pill" ? pill : switchRow
  }

  Component {
    id: switchRow
    RowLayout {
      spacing: Widget.spacing

      StyledLabel {
        visible: text !== ""
        Layout.fillWidth: true
        text: root.label
        overflow: "line"
      }
      StyledSwitch {
        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
        enabled: root.canRun(root.shownOn ? "off" : "on")
        checked: root.shownOn
        onToggled: root.flip(checked)
      }
    }
  }

  Component {
    id: pill
    ActionPill {
      enabled: root.canRun(root.shownOn ? "off" : "on")
      icon: root.options.icon
      label: root.label
      status: root.shownOn ? I18n.tr("On") : I18n.tr("Off")
      active: root.shownOn
      onClicked: root.flip(!root.shownOn)
    }
  }
}
