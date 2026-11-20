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
// under the name. `value` picks the figures: "pricePercent", "price",
// "percent" or "change" (the change in its currency).
// `quote` is MarketsManager.quoteFor(item); a click is `clicked`.
Item {
  id: root

  required property var item
  property var quote: MarketsManager.quoteFor(root.item)
  property bool showChart: true
  property bool showHoldings: false
  property string value: "pricePercent"
  signal clicked

  readonly property string trend: MarketMath.trend(root.quote?.change ?? 0)
  readonly property string trendTone: MarketMath.trendTone(root.trend, MarketsConfig.redForGains)
  readonly property color trendLine: Style.trendLine(root.trendTone)
  readonly property var holding: root.showHoldings ? MarketMath.holding(root.item, root.quote) : null
  readonly property string stateLabel: MarketsManager.stateLabel(root.quote)
  readonly property bool hasPrice: !!root.quote && !root.quote.error

  implicitHeight: body.implicitHeight + Widget.smallPadding * 2
  implicitWidth: body.implicitWidth + Widget.smallPadding * 2

  StateLayer {
    hovered: mouse.containsMouse
    pressed: mouse.pressed
    radius: Style.radius
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
      StyledLabel {
        Layout.fillWidth: true
        text: MarketMath.displayName(root.item, root.quote)
        role: "label"
      }
      RowLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing / 2
        StyledIcon {
          visible: !!root.quote?.stale
          text: "history"
          size: "xs"
          tone: "warning"
        }
        StyledLabel {
          Layout.fillWidth: true
          role: "caption"
          tone: root.quote?.error ? "error" : "faint"
          overflow: "line"
          text: {
            if (root.quote?.error)
              return root.quote.error;
            const name = root.quote?.name && root.quote.name !== MarketMath.displayName(root.item, root.quote) ? root.quote.name : root.item.symbol;
            return root.stateLabel !== "" ? I18n.tr("{0} · {1}", name, root.stateLabel) : name;
          }
        }
      }
      StyledLabel {
        Layout.fillWidth: true
        visible: root.holding !== null
        role: "caption"
        overflow: "line"
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
      lineColor: root.trendLine
      lineWidth: Widget.px(1.5)
      fillOpacity: 0.22 // style-exempt: the chart fill fades its data colour
    }

    // At least a usual price's width, so the rows' charts line up
    ColumnLayout {
      Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
      Layout.minimumWidth: Appearance.fontSize * 7
      spacing: Widget.spacing / 2
      StyledLabel {
        Layout.alignment: Qt.AlignRight
        visible: !root.hasPrice || root.value === "pricePercent" || root.value === "price"
        text: root.hasPrice ? MarketMath.formatPrice(root.quote.price, root.quote.currency) : "—"
        role: "label"
        font.weight: Style.weightStrong
        font.features: ({
            "tnum": 1
          })
      }
      Surface {
        id: chip
        tone: root.trendTone === "faint" ? "highest" : root.trendTone + "Container"
        Layout.alignment: Qt.AlignRight
        visible: root.hasPrice && root.value !== "price"
        implicitWidth: change.implicitWidth + Widget.smallPadding * 2
        implicitHeight: change.implicitHeight + Widget.px(2)
        radius: height / 2
        StyledLabel {
          id: change
          anchors.centerIn: parent
          role: "caption"
          textColor: chip.ink.text
          font.weight: Style.weightStrong
          font.features: ({
              "tnum": 1
            })
          text: MarketMath.arrowed(root.trend, MarketMath.formatChangeAs(root.quote?.change, root.quote?.changePercent ?? 0, root.quote?.currency, root.value))
        }
      }
    }
  }
}
