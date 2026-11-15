pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable

// A custom widget's module drawn at any size: its elements placed on their
// lattice (CustomWidgetData: 4 sub-cells a grid unit, the box fitting them),
// laid out proportionally over this item, a gap between neighbours. Two
// layers: the base elements, then the screen `viewIndex` (module.views) over
// them; the lattice covers every layer, so they stay aligned. A definition
// with no screens and no elements draws CustomWidgetsConfig.defaultElements
// (its icon, or a ring, and the text against it).
// Used by the CustomWidget module and popout and the editor's previews.
Item {
  id: root

  // A CustomWidget definition (CustomWidgetsConfig.definition(id))
  property var definition: null
  property var fields: ({})
  property var history: ({})
  property bool actionsEnabled: true
  // The host can take typed keys (CustomWidget.keysHost)
  property bool keysHost: false
  property real gap: Widget.px(6)
  // The screen drawn over the base (an index in module.views), -1: the base alone
  property int viewIndex: -1

  readonly property var size: root.definition?.module?.size ?? [4, 2]
  readonly property var grid: CustomWidgetData.lattice(CustomWidgetData.allElements(root.definition?.module), root.size)
  // Whether there's a value (a ring, else an icon, without elements): a
  // bool that holds still across samples, so they don't rebuild the defaults
  readonly property bool _hasValue: (root.fields?.ratio ?? -1) >= 0
  readonly property var _view: root.definition?.module?.views?.[root.viewIndex] ?? null
  // Each layer's key (nothing is built while it's empty) and elements,
  // from one binding. The view's key is its id, so a screen change
  // rebuilds only that layer
  readonly property var _layers: {
    const module = root.definition?.module;
    const own = module?.elements ?? [];
    const baseShown = root._view === null || root._view.base;
    const bare = own.length === 0 && (module?.views?.length ?? 0) === 0;
    return [
      {
        "key": baseShown ? "base" : "",
        "elements": bare ? CustomWidgetsConfig.defaultElements(root.size, root._hasValue) : own
      },
      {
        "key": root._view ? "v:" + root._view.id : "",
        "elements": root._view?.elements ?? []
      }
    ];
  }

  // By count: a new sample never rebuilds the elements
  Repeater {
    model: 2

    KeyedLoader {
      id: lyr
      required property int index
      readonly property var spec: root._layers[lyr.index]
      anchors.fill: parent
      key: lyr.spec.key

      sourceComponent: Item {
        Repeater {
          model: lyr.spec.elements.length

          CustomElement {
            required property int index
            readonly property var r: CustomWidgetData.rect(element.place, root.grid, root.width, root.height, root.gap)
            x: r.x
            y: r.y
            width: r.width
            height: r.height
            // Built either way (it can flip every sample); only drawn while shown
            visible: CustomWidgetData.elementShown(root.fields, element.bind)
            element: lyr.spec.elements[index] ?? ({})
            fields: root.fields
            history: root.history
            widgetId: root.definition?.id ?? ""
            actionsEnabled: root.actionsEnabled
            fallbackIcon: root.definition?.icon ?? "widgets"
            widgetActions: root.definition?.actions?.items ?? []
            failing: !!root.fields?.failure && root.fields.failure.kind !== "script"
            busy: CustomWidgetsManager.busy[root.definition?.id ?? ""] !== undefined
            moduleFont: root.definition?.module?.font ?? ""
            keysHost: root.keysHost
          }
        }
      }
    }
  }
}
