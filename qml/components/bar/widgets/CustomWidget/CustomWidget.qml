pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// A custom widget on the bar (docs/dev/features/custom-widgets.md): its
// script's output (CustomWidgetsManager) in the definition's bar style
// (BarWidget's display styles: label is Waybar's look). Clicks and scrolls run its
// actions; hovering opens its module, else shows the output's tooltip
// (Waybar's; the definition's Tooltip switch). Hidden while the script
// says so (empty text, as Waybar).
BarWidget {
  id: root

  readonly property string widgetId: properties.definition
  readonly property var definition: CustomWidgetsConfig.definition(root.widgetId)
  // No definition (none picked, or removed): its label asks for one.
  // Every key this file and its base read, so none binds undefined
  readonly property var bar: root.definition?.bar ?? ({
      "style": "label",
      "icon": "material",
      "segments": 5,
      "width": null,
      "popout": false
    })
  readonly property var fields: CustomWidgetsManager.fields[root.widgetId] ?? null
  readonly property var graphRange: CustomWidgetData.graphRange(root.fields, {})

  Component.onCompleted: CustomWidgetsManager.acquire(root, root.widgetId)
  onWidgetIdChanged: CustomWidgetsManager.acquire(root, root.widgetId)
  Component.onDestruction: CustomWidgetsManager.release(root)

  appearance: root.bar
  // No sample yet: a label ("…") until the script has printed one
  ratio: root.fields === null ? -1 : Math.max(0, root.fields.ratio ?? 0)
  history: CustomWidgetsManager.history[root.widgetId]?.[""] ?? []
  graphMin: root.graphRange.min
  graphMax: root.graphRange.max
  styleText: root.fields?.plain ?? ""
  subtext: root.fields?.subtext || root.fields?.alt || ""

  // News: its state went to warning, or to critical (its colour's
  // name, CustomWidgetData's state color), from a calmer one
  attentionLevel: root.fields === null ? -1 : root.fields.color === "error" ? 2 : root.fields.color === "warning" ? 1 : 0

  hidden: root.fields?.hidden ?? false
  icon: root.bar.icon === "material" ? (root.fields?.icon || root.definition?.icon || "widgets") : ""
  text: !root.definition ? I18n.tr("Pick a custom widget") : root.fields === null ? "…" : root.fields.plain
  // The script's state color (a theme color's name), which the base
  // resolves; none: the widget's own color
  stateColorName: root.fields?.color ?? ""
  // Urgent: a slow colour pulse
  pulsing: root.fields?.urgent ?? false

  readonly property var actions: root.definition?.actions ?? ({})
  clickable: !!(root.actions.click || root.actions.rightClick || root.actions.middleClick)
  acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
  onClicked: button => CustomWidgetsManager.act(root.widgetId, button === Qt.RightButton ? "rightClick" : button === Qt.MiddleButton ? "middleClick" : "click")
  scrollable: !!(root.actions.scrollUp || root.actions.scrollDown)
  onScrolled: steps => CustomWidgetsManager.act(root.widgetId, steps > 0 ? "scrollUp" : "scrollDown")

  // Whether hovering opens its module; the tooltip shows only when not
  readonly property bool popoutOpens: MenusConfig.opensOwnPopout(root.properties) && root.bar.popout && root.fields !== null

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "CustomWidget"
    active: root.popoutOpens
    extraData: ({
        "definitionId": root.widgetId
      })
  }

  BarToolTip {
    widget: root
    shown: !!root.definition?.tooltip && !root.popoutOpens
    text: root.fields?.tooltip ?? ""
    rich: true
  }
}
