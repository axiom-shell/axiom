pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable
import qs.services.apps

// A custom widget's Button element: an icon and label that run its click
// command ({value} is the label's text); without a command, the widget's
// own click action.
// options: icon, label (shown as is unless bound), color
CustomElementBase {
  id: root

  readonly property string label: root.bind.label ? root.text("label") : root.opt("label", "")
  readonly property string icon: root.bind.icon ? root.text("icon") : root.opt("icon", "")

  StyledTextButton {
    anchors.fill: parent
    enabled: root.actionsEnabled
    iconText: root.icon
    text: root.label
    backgroundColor: root.colorOf("color", Theme.backgroundHighlight)
    onClicked: {
      if (root.actions.click)
        root.act("click", root.label);
      else if (root.actionsEnabled)
        CustomWidgetsManager.act(root.widgetId, "click");
    }
  }
}
