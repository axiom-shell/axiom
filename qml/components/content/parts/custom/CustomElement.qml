pragma ComponentBehavior: Bound
import QtQuick
import qs.components.content.parts.custom.elements.List // qmllint disable unused-imports

// One element of a custom widget's module, loaded by its kind
// (elements/<Type>/Custom<Type>.qml, each a CustomElementBase).
Loader {
  id: root

  property var element: ({})
  property var fields: ({})
  property var history: ({})
  property string widgetId: ""
  property bool actionsEnabled: true
  property string fallbackIcon: "widgets"
  property bool invokeSet: false
  property bool failing: false
  property bool busy: false
  property string moduleFont: ""

  readonly property string kind: root.element?.type ?? "Text"

  // Built with its config, so it never sees itself empty, and bound to it
  function _load() {
    root.setSource(Qt.resolvedUrl("elements/" + root.kind + "/Custom" + root.kind + ".qml"), {
      "element": Qt.binding(() => root.element),
      "fields": Qt.binding(() => root.fields),
      "history": Qt.binding(() => root.history),
      "widgetId": Qt.binding(() => root.widgetId),
      "actionsEnabled": Qt.binding(() => root.actionsEnabled),
      "fallbackIcon": Qt.binding(() => root.fallbackIcon),
      "invokeSet": Qt.binding(() => root.invokeSet),
      "failing": Qt.binding(() => root.failing),
      "busy": Qt.binding(() => root.busy),
      "moduleFont": Qt.binding(() => root.moduleFont)
    });
  }
  // A binding sets `kind` during creation, before completion; the element
  // loads once, on completion
  property bool _completed: false
  onKindChanged: {
    if (root._completed)
      root._load();
  }
  Component.onCompleted: {
    root._completed = true;
    root._load();
  }
}
