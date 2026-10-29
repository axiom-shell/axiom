pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable
import qs.components.content.parts.custom

// A custom widget's Toggle element: its state binding (true, on, yes, 1,
// enabled, active or a non-zero number is on) as a switch beside its label,
// or as a quick-settings ActionPill; flipping it runs its on or off command
// and holds the new state until the next sample.
CustomElementBase {
  id: root

  readonly property bool on: {
    const v = root.value("state", "alt");
    if (typeof v === "boolean")
      return v;
    if (typeof v === "number")
      return v !== 0;
    return ["true", "on", "yes", "1", "enabled", "active"].indexOf(String(v ?? "").toLowerCase()) >= 0;
  }
  readonly property string label: root.bind.label ? root.text("label") : root.options.label
  // The state just set, until the next sample (-1: none)
  property int held: -1
  onFieldsChanged: root.held = -1
  readonly property bool shownOn: root.held >= 0 ? root.held === 1 : root.on

  function flip(on) {
    root.held = on ? 1 : 0;
    root.act(on ? "on" : "off", on ? "on" : "off");
  }

  Loader {
    anchors.fill: parent
    sourceComponent: root.options.look === "pill" ? pill : switchRow
  }

  Component {
    id: switchRow
    RowLayout {
      spacing: Widget.spacing

      StyledText {
        visible: text !== ""
        Layout.fillWidth: true
        text: root.label
        elide: Text.ElideRight
      }
      StyledSwitch {
        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
        enabled: root.actionsEnabled
        checked: root.shownOn
        onToggled: root.flip(checked)
      }
    }
  }

  Component {
    id: pill
    ActionPill {
      enabled: root.actionsEnabled
      icon: root.options.icon
      label: root.label
      status: root.shownOn ? I18n.tr("On") : I18n.tr("Off")
      active: root.shownOn
      onClicked: root.flip(!root.shownOn)
    }
  }
}
