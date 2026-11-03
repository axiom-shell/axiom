pragma ComponentBehavior: Bound
import QtQuick
import qs.components.reusable
import qs.services.apps
import qs.components.content.parts.custom

// A custom widget's Button element: an icon and label (each from its
// option unless bound) that run its click command ({value} is the label);
// without one, the widget's own click action.
CustomElementBase {
  id: root

  readonly property string label: root.bind.label ? root.text("label") : root.options.label
  readonly property string icon: root.bind.icon ? root.text("icon") : root.options.icon

  StyledTextButton {
    anchors.fill: parent
    enabled: root.actionsEnabled
    iconText: root.icon
    text: root.label
    onClicked: {
      if (root.actions.click !== "")
        root.act("click", root.label);
      else
        CustomWidgetsManager.act(root.widgetId, "click");
    }
  }
}
