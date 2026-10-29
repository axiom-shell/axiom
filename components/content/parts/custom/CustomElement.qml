pragma ComponentBehavior: Bound
import QtQuick

// One element of a custom widget's module, loaded by its kind
// (elements/<Type>/<Type>.qml, each a CustomElementBase).
Loader {
  id: root

  property var element: ({})
  property var fields: ({})
  property var history: ({})
  property string widgetId: ""
  property bool actionsEnabled: true
  property string fallbackIcon: "widgets"

  readonly property string kind: root.element?.type ?? "Text"

  // Built with its config, so it never sees itself empty; the Bindings
  // below keep it current
  function _load() {
    root.setSource(Qt.resolvedUrl("elements/" + root.kind + "/" + root.kind + ".qml"), {
      "element": root.element,
      "fields": root.fields,
      "history": root.history,
      "widgetId": root.widgetId,
      "actionsEnabled": root.actionsEnabled,
      "fallbackIcon": root.fallbackIcon
    });
  }
  onKindChanged: root._load()
  Component.onCompleted: root._load()

  Binding {
    when: root.item !== null
    target: root.item
    property: "element"
    value: root.element
  }
  Binding {
    when: root.item !== null
    target: root.item
    property: "fields"
    value: root.fields
  }
  Binding {
    when: root.item !== null
    target: root.item
    property: "history"
    value: root.history
  }
  Binding {
    when: root.item !== null
    target: root.item
    property: "widgetId"
    value: root.widgetId
  }
  Binding {
    when: root.item !== null
    target: root.item
    property: "actionsEnabled"
    value: root.actionsEnabled
  }
  Binding {
    when: root.item !== null
    target: root.item
    property: "fallbackIcon"
    value: root.fallbackIcon
  }
}
