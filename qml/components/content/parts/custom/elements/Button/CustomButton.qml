pragma ComponentBehavior: Bound
import QtQuick
import qs.components.reusable
import qs.components.methods
import qs.services.apps
import qs.components.content.parts.custom

// A custom widget's Button element: an icon and label (each from its
// option unless bound, else its action's name) that run its named action
// (`value` is the {value}; off while the sample or a failing script turns it
// off, or its `enabled` slot is false), else its click command ({value} is
// the label); without either, the widget's own click action.
CustomElementBase {
  id: root

  readonly property string label: root.bind.label ? root.text("label") : root.options.label || CustomWidgetsManager.actionLabel(root.actionId) // lock-inert: a name, nothing runs
  readonly property string icon: root.bind.icon ? root.text("icon") : root.options.icon

  StyledTextButton {
    anchors.fill: parent
    enabled: root.canRun && (root.bind.enabled ? CustomWidgetData.truthy(root.value("enabled")) : true)
    iconText: root.icon
    text: root.label
    onClicked: {
      if (root.actionId !== "")
        root.run("click", root.text("value"));
      else if (root.actions.click !== "")
        root.act("click", root.label);
      else
        CustomWidgetsManager.act(root.widgetId, "click"); // lock-inert: the button is disabled without actionsEnabled
    }
  }
}
