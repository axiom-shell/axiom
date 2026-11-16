pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable

// One watched symbol as a tile (the markets module's tiles): its name,
// the day's line edge to edge, then its price and change, the trend in the
// change figure and the line.
// A click is `clicked`.
ClippingRectangle {
  id: root

  required property var item
  property bool showChart: true
  signal clicked

  readonly property var quote: MarketsManager.quoteFor(root.item)
  readonly property bool hasPrice: !!root.quote && !root.quote.error
  readonly property string trend: MarketMath.trend(root.quote?.change ?? 0)
  readonly property string trendTone: MarketMath.trendTone(root.trend, MarketsConfig.redForGains)
  readonly property color trendText: Style.toneColor(root.trendTone)
  readonly property color trendLine: Style.trendLine(root.trendTone)

  radius: Style.radius
  color: Style.surfaceSunken
  border.width: Style.hairline
  border.color: Style.borderSubtle

  StateLayer {
    hovered: mouse.containsMouse
    pressed: mouse.pressed
    radius: root.radius
  }

  // Between the name and the price, edge to edge
  PriceChart {
    visible: root.showChart && root.hasPrice
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: head.bottom
    anchors.bottom: foot.top
    anchors.topMargin: Widget.spacing / 2
    points: root.quote?.points ?? []
    reference: root.quote?.prevClose ?? 0
    start: root.quote?.sessionStart ?? 0
    end: root.quote?.sessionEnd ?? 0
    lineColor: root.trendLine
    lineWidth: Widget.px(1.5)
    fillOpacity: 0.35 // style-exempt: the chart fill fades its data colour
    showReference: false
  }

  ColumnLayout {
    id: head
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Widget.smallPadding
    spacing: 0
    StyledText {
      Layout.fillWidth: true
      text: MarketMath.displayName(root.item, root.quote)
      role: "label"
    }
    StyledText {
      Layout.fillWidth: true
      text: root.quote?.error ? root.quote.error : MarketsManager.stateLabel(root.quote)
      visible: text !== ""
      role: "micro"
      tone: root.quote?.error ? "error" : "faint"
    }
  }

  ColumnLayout {
    id: foot
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Widget.smallPadding
    spacing: 0
    StyledText {
      Layout.fillWidth: true
      text: root.hasPrice ? MarketMath.formatPrice(root.quote.price, root.quote.currency) : "—"
      role: "title"
      font.features: ({
          "tnum": 1
        })
    }
    StyledText {
      visible: root.hasPrice
      text: (root.trend === "up" ? "▲ " : root.trend === "down" ? "▼ " : "") + MarketMath.formatPercent(root.quote?.changePercent ?? 0).replace(/^[+−]/, "")
      role: "caption"
      textColor: root.trendText
      font.weight: Style.weightStrong
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
