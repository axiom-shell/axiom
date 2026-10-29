pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.content.base
import qs.components.content.parts
import qs.components.content.parts.custom

// A custom widget's module (docs/dev/features/custom-widgets.md): its
// elements laid out proportionally over the card (CustomLayout), from the
// definition's script (CustomWidgetsManager). Also the CustomWidget bar
// widget's popout, drawn at the definition's design size. No actions on
// the lock screen or in an editor's preview.
// properties: { definition }
Panel {
  id: root

  // A popout's (the bar widget's extraData); a card reads properties
  property string definitionId: ""
  readonly property string widgetId: root.embedded ? (root.properties.definition ?? "") : root.definitionId
  readonly property var definition: CustomWidgetsConfig.definition(root.widgetId)
  readonly property var fields: CustomWidgetsManager.fields[root.widgetId] ?? null
  readonly property var output: CustomWidgetsManager.outputs[root.widgetId] ?? null
  readonly property bool actionsEnabled: root.host?.kind !== "lockscreen" && !root.host?.preview

  // A popout is the design size, at the screen's card size
  readonly property real _card: OverlayConfig.cardUnitOn(Screen.width, Screen.height)
  readonly property var _size: CustomWidgetData.designSize(root.definition?.module?.elements, root.definition?.module?.size)
  readonly property real _popoutWidth: GridPlacement.span(root._size[0], root._card)
  readonly property real _popoutHeight: GridPlacement.span(root._size[1], root._card)
  implicitWidth: root._popoutWidth
  implicitHeight: root._popoutHeight
  maxImplicitWidth: root._popoutWidth
  maxImplicitHeight: root._popoutHeight

  onWidgetIdChanged: CustomWidgetsManager.acquire(root, root.widgetId)
  Component.onCompleted: CustomWidgetsManager.acquire(root, root.widgetId)
  Component.onDestruction: CustomWidgetsManager.release(root)

  Item {
    id: box
    implicitWidth: root._popoutWidth
    implicitHeight: root._popoutHeight
    Layout.fillWidth: true
    Layout.fillHeight: true

    // The layout, or why there's nothing to show: only one is built
    Loader {
      anchors.fill: parent
      sourceComponent: root.fields !== null && !root.fields.hidden ? layout : empty
    }

    Component {
      id: layout
      CustomLayout {
        definition: root.definition
        fields: root.fields ?? ({})
        history: CustomWidgetsManager.history[root.widgetId] ?? ({})
        actionsEnabled: root.actionsEnabled
      }
    }

    Component {
      id: empty
      Item {
        EmptyState {
          anchors.centerIn: parent
          maxWidth: box.width
          availableHeight: box.height
          icon: root.definition?.icon ?? "widgets"
          text: !root.definition ? I18n.tr("Pick a custom widget in this module's settings") : !root.definition.command ? I18n.tr("No command set") : root.output?.error ? root.output.error : root.fields ? I18n.tr("No output") : I18n.tr("Waiting for output…")
        }
      }
    }
  }
}
