pragma ComponentBehavior: Bound
import QtQuick

// One element of a custom widget's module, loaded by its kind (the element
// files beside this one, each a CustomElementBase).
Loader {
  id: root

  property var element: ({})
  property var fields: ({})
  property var history: ({})
  property string widgetId: ""
  property bool actionsEnabled: true
  property string fallbackIcon: "widgets"

  readonly property string kind: root.element?.kind ?? "Text"
  readonly property string file: ({
      "Gauge": "CustomRing",
      "Bar": "CustomMeter"
    })[root.kind] ?? ("Custom" + root.kind)

  // Re-set on a kind change only; the rest are bindings
  onFileChanged: root.setSource(Qt.resolvedUrl(root.file + ".qml"), {
    "gauge": root.kind === "Gauge"
  })
  Component.onCompleted: root.setSource(Qt.resolvedUrl(root.file + ".qml"), root.kind === "Gauge" ? {
    "gauge": true
  } : {})

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
