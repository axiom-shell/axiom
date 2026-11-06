pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable

// One watched symbol (the markets popout's and module's rows): its name
// and symbol (or the market's state while it doesn't trade), the day's
// line, the price and the day's change as a pill in the trend's colour,
// and with `showHoldings` what the holding is worth and made today
// under the name.
// `quote` is MarketsManager.quoteFor(item); a click is `clicked`.
Item {
  id: root

  required property var item
  property var quote: MarketsManager.quoteFor(root.item)
  property bool showChart: true
  property bool showHoldings: false
  signal clicked

  readonly property string trend: MarketMath.trend(root.quote?.change ?? 0)
  readonly property color trendColor: MarketsManager.trendColor(root.trend)
  readonly property var holding: root.showHoldings ? MarketMath.holding(root.item, root.quote) : null
  readonly property string stateLabel: MarketsManager.stateLabel(root.quote)
  readonly property bool hasPrice: !!root.quote && !root.quote.error

  implicitHeight: body.implicitHeight + Widget.smallPadding * 2
  implicitWidth: body.implicitWidth + Widget.smallPadding * 2

  Rectangle {
    anchors.fill: parent
    radius: Widget.radius
    color: mouse.containsMouse ? Qt.alpha(Theme.foreground, 0.06) : "transparent"
    Behavior on color {
      ColorAnimation {
        duration: Appearance.animFast
        easing.type: Appearance.easing
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  RowLayout {
    id: body
    anchors.fill: parent
    anchors.margins: Widget.smallPadding
    spacing: Widget.padding

    ColumnLayout {
      Layout.fillWidth: true
      Layout.minimumWidth: Appearance.fontSize * 4
      spacing: 0
      StyledText {
        Layout.fillWidth: true
        text: MarketMath.displayName(root.item, root.quote)
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }
      RowLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing / 2
        StyledIcon {
          visible: !!root.quote?.stale
          text: "history"
          textSize: Appearance.fontSizeBy(-2)
          textColor: Theme.warning
        }
        StyledText {
          Layout.fillWidth: true
          textSize: Appearance.fontSizeBy(-2)
          textColor: root.quote?.error ? Theme.error : Theme.foregroundInactive
          elide: Text.ElideRight
          text: {
            if (root.quote?.error)
              return root.quote.error;
            const name = root.quote?.name && root.quote.name !== MarketMath.displayName(root.item, root.quote) ? root.quote.name : root.item.symbol;
            return root.stateLabel !== "" ? I18n.tr("{0} · {1}", name, root.stateLabel) : name;
          }
        }
      }
      StyledText {
        Layout.fillWidth: true
        visible: root.holding !== null
        textSize: Appearance.fontSizeBy(-2)
        textColor: Theme.foregroundAlt
        elide: Text.ElideRight
        text: root.holding ? I18n.tr("{0} · {1} today", MarketMath.formatPrice(root.holding.value, root.quote.currency), MarketMath.formatChange(root.holding.dayChange, root.quote.currency)) : ""
      }
    }

    PriceChart {
      visible: root.showChart && root.hasPrice
      Layout.preferredWidth: Appearance.fontSize * 5
      Layout.preferredHeight: Appearance.fontSize * 2
      points: root.quote?.points ?? []
      reference: root.quote?.prevClose ?? 0
      start: root.quote?.sessionStart ?? 0
      end: root.quote?.sessionEnd ?? 0
      lineColor: root.trendColor
      lineWidth: Widget.px(1.5)
      fillOpacity: 0.22
    }

    // At least a usual price's width, so the rows' charts line up
    ColumnLayout {
      Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
      Layout.minimumWidth: Appearance.fontSize * 7
      spacing: Widget.spacing / 2
      StyledText {
        Layout.alignment: Qt.AlignRight
        text: root.hasPrice ? MarketMath.formatPrice(root.quote.price, root.quote.currency) : "—"
        font.weight: Font.DemiBold
        font.features: ({
            "tnum": 1
          })
      }
      Rectangle {
        Layout.alignment: Qt.AlignRight
        visible: root.hasPrice
        implicitWidth: change.implicitWidth + Widget.smallPadding * 2
        implicitHeight: change.implicitHeight + Widget.px(2)
        radius: height / 2
        color: Qt.alpha(root.trendColor, 0.16)
        StyledText {
          id: change
          anchors.centerIn: parent
          textSize: Appearance.fontSizeBy(-2)
          textColor: root.trendColor
          font.weight: Font.DemiBold
          font.features: ({
              "tnum": 1
            })
          text: (root.trend === "up" ? "▲ " : root.trend === "down" ? "▼ " : "") + MarketMath.formatPercent(root.quote?.changePercent ?? 0).replace(/^[+−]/, "")
        }
      }
    }
  }
}
