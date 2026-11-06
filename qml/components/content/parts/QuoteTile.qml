pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable

// One watched symbol as a tile (the markets module's tiles): its name,
// the day's line edge to edge, then its price and change, tinted by the
// trend.
// A click is `clicked`.
ClippingRectangle {
  id: root

  required property var item
  property bool showChart: true
  signal clicked

  readonly property var quote: MarketsManager.quoteFor(root.item)
  readonly property bool hasPrice: !!root.quote && !root.quote.error
  readonly property string trend: MarketMath.trend(root.quote?.change ?? 0)
  readonly property color trendColor: MarketsManager.trendColor(root.trend)

  radius: Widget.radius
  color: mouse.containsMouse ? Qt.alpha(root.trendColor, 0.14) : Qt.alpha(root.trendColor, 0.08)
  border.width: 1
  border.color: Qt.alpha(root.trendColor, 0.25)
  Behavior on color {
    ColorAnimation {
      duration: Appearance.animFast
      easing.type: Appearance.easing
    }
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
    lineColor: root.trendColor
    lineWidth: Widget.px(1.5)
    fillOpacity: 0.35
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
      font.weight: Font.DemiBold
      textSize: Appearance.fontSizeBy(-1)
      elide: Text.ElideRight
    }
    StyledText {
      Layout.fillWidth: true
      text: root.quote?.error ? root.quote.error : MarketsManager.stateLabel(root.quote)
      visible: text !== ""
      textSize: Appearance.fontSizeBy(-3)
      textColor: root.quote?.error ? Theme.error : Theme.foregroundInactive
      elide: Text.ElideRight
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
      textSize: Appearance.fontSize * 1.3
      font.weight: Font.Bold
      font.features: ({
          "tnum": 1
        })
      elide: Text.ElideRight
    }
    StyledText {
      visible: root.hasPrice
      text: (root.trend === "up" ? "▲ " : root.trend === "down" ? "▼ " : "") + MarketMath.formatPercent(root.quote?.changePercent ?? 0).replace(/^[+−]/, "")
      textColor: root.trendColor
      textSize: Appearance.fontSizeBy(-2)
      font.weight: Font.DemiBold
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
