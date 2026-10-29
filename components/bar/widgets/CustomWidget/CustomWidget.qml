pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// A custom widget on the bar (docs/dev/features/custom-widgets.md): its
// script's output (CustomWidgetsManager) in the definition's bar style
// (ValueStyleWidget's: label is Waybar's look). Clicks and scrolls run its
// actions; hovering opens its module. Hidden while the script says so
// (empty text, as Waybar).
ValueStyleWidget {
  id: root

  readonly property string widgetId: properties.definition
  readonly property var definition: CustomWidgetsConfig.definition(root.widgetId)
  // No definition (none picked, or removed): its label asks for one.
  // Every key this file and its base read, so none binds undefined
  readonly property var bar: root.definition?.bar ?? ({
      "style": "label",
      "icon": "material",
      "segments": 5,
      "width": 0,
      "colorText": false,
      "popout": false
    })
  readonly property var fields: CustomWidgetsManager.fields[root.widgetId] ?? null
  readonly property var graphRange: CustomWidgetData.graphRange(root.fields, {})

  Component.onCompleted: CustomWidgetsManager.acquire(root, root.widgetId)
  onWidgetIdChanged: CustomWidgetsManager.acquire(root, root.widgetId)
  Component.onDestruction: CustomWidgetsManager.release(root)

  display: root.bar
  // No sample yet: a label ("…") until the script has printed one
  ratio: root.fields === null ? -1 : Math.max(0, root.fields.ratio ?? 0)
  history: CustomWidgetsManager.history[root.widgetId]?.[""] ?? []
  graphMin: root.graphRange.min
  graphMax: root.graphRange.max
  styleText: root.fields?.plain ?? ""
  subtext: root.fields?.subtext || root.fields?.alt || ""
  hasState: !!root.fields?.color
  stateColor: root.fields?.color ? Theme.resolveColor(root.fields.color) : "transparent"

  hidden: root.fields?.hidden ?? false
  icon: root.bar.icon === "material" ? (root.fields?.icon || root.definition?.icon || "widgets") : ""
  text: !root.definition ? I18n.tr("Pick a custom widget") : root.fields === null ? "…" : root.fields.plain
  accentColor: root.fields?.color ? root.stateColor : Theme.resolveColor(properties.backgroundColor)

  // Urgent: a slow pulse (as Battery's charging one), back to full when
  // it stops
  SequentialAnimation {
    running: (root.fields?.urgent ?? false) && !root.hidden && Appearance.animations
    loops: Animation.Infinite
    onRunningChanged: {
      if (!running)
        root.dim = 1;
    }

    PropertyAnimation {
      target: root
      property: "dim"
      from: 1.0
      to: 0.45
      duration: Appearance.animSlow * 2
      easing.type: Appearance.easing
    }
    PropertyAnimation {
      target: root
      property: "dim"
      from: 0.45
      to: 1.0
      duration: Appearance.animSlow * 2
      easing.type: Appearance.easing
    }
  }

  readonly property var actions: root.definition?.actions ?? ({})
  clickable: !!(root.actions.click || root.actions.rightClick || root.actions.middleClick)
  acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
  onClicked: button => CustomWidgetsManager.act(root.widgetId, button === Qt.RightButton ? "rightClick" : button === Qt.MiddleButton ? "middleClick" : "click")
  scrollable: !!(root.actions.scrollUp || root.actions.scrollDown)
  onScrolled: steps => CustomWidgetsManager.act(root.widgetId, steps > 0 ? "scrollUp" : "scrollDown")

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "CustomWidget"
    active: EdgeMenusConfig.opensOwnPopout(root.properties) && root.bar.popout && root.fields !== null
    extraData: ({
        "definitionId": root.widgetId
      })
  }
}
