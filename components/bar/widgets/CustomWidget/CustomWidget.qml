pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.apps
import qs.components.methods
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
  // No definition (none picked, or removed): its label asks for one
  readonly property var bar: root.definition?.bar ?? ({
      "style": "label",
      "icon": "material"
    })
  readonly property var fields: CustomWidgetsManager.fields[root.widgetId] ?? null
  readonly property real ratio: Math.max(0, root.fields?.ratio ?? 0)
  readonly property var graphRange: CustomWidgetData.graphRange(root.fields, {})
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
      return (graphicLoader.item as Item)?.implicitWidth ?? 0;
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
  // Colour the text by state only where it isn't the background already
  // (a filled widget's text must read on it)
  readonly property bool _textByState: root.bar.colorText && !!root.fields?.color && root.colors.fill.a < 1
  foregroundColor: root._textByState ? root.stateColor : colors.text
  iconColor: root._textByState ? root.stateColor : colors.icon
  // Graphics draw in the icon's colour for this bar's style: the state's
  // on a tint, outline or plain bar, what reads on it when it's the fill
  readonly property color graphicColor: root.colors.icon

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

  // The pill: its background's shape filled to the value (WidgetGroup
  // draws it, so it takes the bar's caps and radius)
  backgroundLevel: root.style === "pill" && !root.hidden && root.fields !== null ? root.ratio : -1
  backgroundLevelColor: Qt.alpha(root.graphicColor, 0.35)

  // The graphic styles, in the lead slot: only the shown one is built.
  // Sizes from the bar's font, as a bar's pieces are
  Loader {
    id: graphicLoader
    parent: root.lead
    anchors.fill: parent
    sourceComponent: ({
        "ring": ring,
        "fill": fill,
        "segments": segments,
        "sparkline": sparkline,
        "ticker": ticker,
        "stacked": stacked
      })[root.style] ?? null
  }

  Component {
    id: ring
    Item {
      PercentageCircle {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        percentage: root.ratio * 100
        thickness: Math.max(2, width * 0.16)
        trackColor: Qt.alpha(root.colors.text, 0.2)
        fillColor: root.graphicColor
        iconText: ""
      }
    }
  }

  Component {
    id: fill
    LevelMeter {
      share: root.ratio
      vertical: root.isVertical
      thickness: Math.max(3, root.fontSize * 0.35)
      trackColor: Qt.alpha(root.colors.text, 0.2)
      fillColor: root.graphicColor
    }
  }

  Component {
    id: segments
    SegmentMeter {
      count: root.bar.segments
      share: root.ratio
      vertical: root.isVertical
      across: root.fontSize * 0.7
      gap: 2
      cornerRadius: 2
      litColor: root.graphicColor
      offColor: Qt.alpha(root.colors.text, 0.2)
    }
  }

  Component {
    id: sparkline
    Item {
      Sparkline {
        anchors.fill: parent
        anchors.topMargin: root.crossSize * 0.2
        anchors.bottomMargin: root.crossSize * 0.2
        values: CustomWidgetsManager.history[root.widgetId]?.[""] ?? []
        minValue: root.graphRange.min
        maxValue: root.graphRange.max
        lineColor: root.graphicColor
        showBaseline: false
      }
    }
  }

  // Ticker: the text scrolling when it's longer than its room
  Component {
    id: ticker
    Item {
      id: tickerBox
      clip: true

      Text {
        id: tickerText
        anchors.verticalCenter: parent.verticalCenter
        text: root.fields?.plain ?? ""
        color: root.foregroundColor
        font.family: Appearance.fontFamily
        font.pixelSize: root.fontSize
        readonly property real overflow: Math.max(0, implicitWidth - tickerBox.width)
        x: 0

        // The pauses and the scroll's speed are behaviour, not motion
        SequentialAnimation on x {
          running: tickerText.overflow > 0 && Appearance.animations
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
            easing.type: Appearance.easing
          }
        }
      }
    }
  }

  // Stacked: the value over the caption
  Component {
    id: stacked
    Item {
      implicitWidth: stack.implicitWidth

      Column {
        id: stack
        anchors.centerIn: parent
        spacing: 0

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.fields?.plain ?? ""
          color: root.foregroundColor
          font.family: Appearance.fontFamily
          font.pixelSize: root.fontSize * 0.8
          font.bold: true
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.fields?.subtext || root.fields?.alt || ""
          color: Qt.alpha(root.foregroundColor, 0.7)
          font.family: Appearance.fontFamily
          font.pixelSize: root.fontSize * 0.6
        }
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
