pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A custom widget's Toggle element: a switch showing its state binding
// (true, on, yes, 1, or a non-zero number is on), with a label; flipping it
// runs its on or off command and holds the new state until the next sample.
// options: label
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
  // The state just set, until the next sample (-1: none)
  property int held: -1
  onFieldsChanged: root.held = -1

  RowLayout {
    anchors.fill: parent
    spacing: Widget.spacing

    StyledText {
      visible: text !== ""
      Layout.fillWidth: true
      text: root.bind.label ? root.text("label") : root.opt("label", "")
      elide: Text.ElideRight
    }
    StyledSwitch {
      Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
      enabled: root.actionsEnabled
      checked: root.held >= 0 ? root.held === 1 : root.on
      onToggled: {
        root.held = checked ? 1 : 0;
        root.act(checked ? "on" : "off", checked ? "on" : "off");
      }
    }
  }
}
