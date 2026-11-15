pragma ComponentBehavior: Bound
import QtQuick
import qs.config
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
  property var widgetActions: []
  property bool failing: false
  property bool busy: false
  property string moduleFont: ""
  property bool keysHost: false

  readonly property string kind: root.element?.type ?? "Text"
  // Its kind's bindings (what a colour rule reads by default: the first)
  readonly property var kindSlots: CustomWidgetsConfig.elementKind(root.kind)?.slots ?? []

  // Built with its config, so it never sees itself empty, and bound to it
  function _load() {
    root.setSource(Qt.resolvedUrl("elements/" + root.kind + "/Custom" + root.kind + ".qml"), {
      "element": Qt.binding(() => root.element),
      "fields": Qt.binding(() => root.fields),
      "history": Qt.binding(() => root.history),
      "widgetId": Qt.binding(() => root.widgetId),
      "actionsEnabled": Qt.binding(() => root.actionsEnabled),
      "fallbackIcon": Qt.binding(() => root.fallbackIcon),
      "widgetActions": Qt.binding(() => root.widgetActions),
      "failing": Qt.binding(() => root.failing),
      "busy": Qt.binding(() => root.busy),
      "moduleFont": Qt.binding(() => root.moduleFont),
      "keysHost": Qt.binding(() => root.keysHost),
      "kindSlots": Qt.binding(() => root.kindSlots)
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
