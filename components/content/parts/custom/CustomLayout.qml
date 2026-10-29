pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods

// A custom widget's module drawn at any size: its elements placed on their
// lattice (CustomWidgetData: 4 sub-cells a grid unit, the box fitting them),
// laid out proportionally over this item, a gap between neighbours. A
// definition with no elements draws CustomWidgetsConfig.defaultElements
// (its icon, or a ring, and the text against it).
// Used by the CustomWidget module and popout and the editor's previews.
Item {
  id: root

  // A CustomWidget definition (CustomWidgetsConfig.definition(id))
  property var definition: null
  property var fields: ({})
  property var history: ({})
  property bool actionsEnabled: true
  property real gap: Widget.px(6)

  readonly property var size: root.definition?.module?.size ?? [4, 2]
  readonly property var grid: CustomWidgetData.lattice(root.definition?.module?.elements, root.size)
  readonly property var elements: {
    const own = root.definition?.module?.elements ?? [];
    return own.length ? own : CustomWidgetsConfig.defaultElements(root.size, (root.fields?.ratio ?? -1) >= 0);
  }

  // By count: a new sample never rebuilds the elements
  Repeater {
    model: root.elements.length

    CustomElement {
      required property int index
      readonly property var r: CustomWidgetData.rect(element.place, root.grid, root.width, root.height, root.gap)
      x: r.x
      y: r.y
      width: r.width
      height: r.height
      element: root.elements[index] ?? ({})
      fields: root.fields
      history: root.history
      widgetId: root.definition?.id ?? ""
      actionsEnabled: root.actionsEnabled
      fallbackIcon: root.definition?.icon ?? "widgets"
    }
  }
}
