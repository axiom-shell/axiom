pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.apps
import qs.components.reusable
import qs.components.content.parts
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// A custom widget on the bar (docs/dev/features/custom-widgets.md): its
// script's output (CustomWidgetsManager) in the definition's bar style:
// label (Waybar's look), icon, ring, fill, pill, segments, sparkline,
// ticker or stacked. Clicks and scrolls run its actions; hovering opens its
// module. Hidden while the script says so (empty text, as Waybar).
BarIconWidget {
  id: root

  readonly property string widgetId: properties.definition
  readonly property var definition: CustomWidgetsConfig.definition(root.widgetId)
  readonly property var bar: root.definition?.bar ?? ({
      "style": "label",
      "icon": "material",
      "segments": 5,
      "width": 0,
      "colorText": false,
      "popout": true
    })
  readonly property var fields: CustomWidgetsManager.fields[root.widgetId] ?? null
  readonly property real ratio: Math.max(0, root.fields?.ratio ?? 0)
  readonly property color stateColor: root.fields?.color ? Theme.resolveColor(root.fields.color) : "transparent"
  // Ticker and stacked draw their own text; on a vertical bar they're labels
  readonly property string style: root.isVertical && ["ticker", "stacked"].includes(root.bar.style) ? "label" : root.bar.style
  // A graphic before the icon, along the bar
  readonly property bool graphic: ["ring", "fill", "segments", "sparkline", "ticker", "stacked"].includes(root.style)
  readonly property real graphicLength: {
    switch (root.style) {
    case "ring":
      return root.crossSize * 0.62;
    case "fill":
    case "segments":
    case "sparkline":
      return root.bar.width > 0 ? root.bar.width : root.fontSize * (root.isVertical ? 2.5 : 4);
    case "ticker":
      return root.bar.width > 0 ? root.bar.width : root.fontSize * 12;
    case "stacked":
      return Math.max(stackTop.implicitWidth, stackBottom.implicitWidth);
    }
    return 0;
  }

  Component.onCompleted: CustomWidgetsManager.acquire(root, root.widgetId)
  onWidgetIdChanged: CustomWidgetsManager.acquire(root, root.widgetId)
  Component.onDestruction: CustomWidgetsManager.release(root)

  hidden: root.fields?.hidden ?? false
  icon: root.bar.icon === "material" ? (root.fields?.icon || root.definition?.icon || "widgets") : ""
  text: !root.definition ? I18n.tr("Pick a custom widget") : root.fields === null ? "…" : root.fields.plain
  showText: !["icon", "ticker", "stacked"].includes(root.style)
  leadLength: root.graphic ? root.graphicLength : 0
  accentColor: root.fields?.color ? root.stateColor : Theme.resolveColor(properties.backgroundColor)
  foregroundColor: root.bar.colorText && root.fields?.color ? root.stateColor : colors.text
  iconColor: root.bar.colorText && root.fields?.color ? root.stateColor : colors.icon

  // Urgent: a slow pulse
  dim: root.fields?.urgent ? urgentPulse.level : 1
  property real _pulse: 1
  SequentialAnimation {
    id: urgentPulse
    property real level: root._pulse
    running: (root.fields?.urgent ?? false) && Appearance.animations
    loops: Animation.Infinite
    NumberAnimation {
      target: root
      property: "_pulse"
      to: 0.45
      duration: Appearance.animSlow * 2
      easing.type: Appearance.easing
    }
    NumberAnimation {
      target: root
      property: "_pulse"
      to: 1
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

  // The pill: the widget's box filled to the value
  Rectangle {
    visible: root.style === "pill" && !root.hidden && root.fields !== null
    z: -1
    x: 0
    y: root.isVertical ? root.height * (1 - root.ratio) : 0
    width: root.isVertical ? root.width : root.width * root.ratio
    height: root.isVertical ? root.height * root.ratio : root.height
    radius: root.radius
    color: root.fields?.color ? root.stateColor : Theme.accent
    opacity: 0.35

    Behavior on width {
      NumberAnimation {
        duration: Appearance.animNormal
        easing.type: Appearance.easing
      }
    }
  }

  // The graphic styles, in the lead slot
  Item {
    parent: root.lead
    anchors.fill: parent

    PercentageCircle {
      visible: root.style === "ring"
      anchors.centerIn: parent
      width: Math.min(parent.width, parent.height)
      height: width
      percentage: root.ratio * 100
      thickness: Math.max(2, width * 0.16)
      fillColor: root.fields?.color ? root.stateColor : root.colors.icon
      iconText: ""
    }

    Rectangle {
      visible: root.style === "fill"
      anchors.centerIn: parent
      width: root.isVertical ? Math.max(3, root.fontSize * 0.35) : parent.width
      height: root.isVertical ? parent.height : Math.max(3, root.fontSize * 0.35)
      radius: Math.min(width, height) / 2
      color: Qt.alpha(root.colors.text, 0.2)

      Rectangle {
        x: 0
        y: root.isVertical ? parent.height * (1 - root.ratio) : 0
        width: root.isVertical ? parent.width : parent.width * root.ratio
        height: root.isVertical ? parent.height * root.ratio : parent.height
        radius: parent.radius
        color: root.fields?.color ? root.stateColor : root.colors.icon
      }
    }

    Grid {
      visible: root.style === "segments"
      anchors.centerIn: parent
      columns: root.isVertical ? 1 : root.bar.segments
      spacing: 2

      Repeater {
        model: root.bar.segments

        Rectangle {
          required property int index
          readonly property real cell: (root.leadLength - 2 * (root.bar.segments - 1)) / root.bar.segments
          width: root.isVertical ? root.fontSize * 0.7 : cell
          height: root.isVertical ? cell : root.fontSize * 0.7
          radius: 2
          color: (root.isVertical ? root.bar.segments - 1 - index : index) < Math.round(root.ratio * root.bar.segments) ? (root.fields?.color ? root.stateColor : root.colors.icon) : Qt.alpha(root.colors.text, 0.2)
        }
      }
    }

    Sparkline {
      visible: root.style === "sparkline"
      anchors.fill: parent
      anchors.topMargin: root.crossSize * 0.2
      anchors.bottomMargin: root.crossSize * 0.2
      values: CustomWidgetsManager.history[root.widgetId]?.[""] ?? []
      maxValue: root.fields?.max ?? 0
      lineColor: root.fields?.color ? root.stateColor : root.colors.icon
      showBaseline: false
    }

    // Ticker: the text scrolling when it's longer than its room
    Item {
      visible: root.style === "ticker"
      anchors.fill: parent
      clip: true

      Text {
        id: tickerText
        anchors.verticalCenter: parent.verticalCenter
        text: root.fields?.plain ?? ""
        color: root.foregroundColor
        font.family: Appearance.fontFamily
        font.pixelSize: root.fontSize
        readonly property real overflow: Math.max(0, implicitWidth - parent.width)
        x: 0

        SequentialAnimation on x {
          running: tickerText.overflow > 0 && root.style === "ticker" && Appearance.animations
          loops: Animation.Infinite
          PauseAnimation {
            duration: 1500
          }
          NumberAnimation {
            from: 0
            to: -tickerText.overflow
            duration: tickerText.overflow * 30
          }
          PauseAnimation {
            duration: 1500
          }
          NumberAnimation {
            from: -tickerText.overflow
            to: 0
            duration: Appearance.animSlow
          }
        }
      }
    }

    // Stacked: the value over the caption
    Column {
      visible: root.style === "stacked"
      anchors.centerIn: parent
      spacing: 0

      Text {
        id: stackTop
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.fields?.plain ?? ""
        color: root.foregroundColor
        font.family: Appearance.fontFamily
        font.pixelSize: root.fontSize * 0.8
        font.bold: true
      }
      Text {
        id: stackBottom
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.fields?.subtext || root.fields?.alt || ""
        color: Qt.alpha(root.foregroundColor, 0.7)
        font.family: Appearance.fontFamily
        font.pixelSize: root.fontSize * 0.6
      }
    }
  }

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "CustomWidget"
    active: EdgeMenusConfig.opensOwnPopout(root.properties) && root.bar.popout && root.fields !== null
    extraData: ({
        "definitionId": root.widgetId
      })
  }
}
