pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable

// One symbol in detail (the markets popout's detail view, the module's
// focus layout): the price and the change over `range` in its trend's
// colour, a large chart with a crosshair, the range picker (1D to 1Y, when
// `pickRange`) and the day's figures. The day is the live quote; longer
// ranges through MarketsManager.history each time one is picked (axiom's
// cache answers a repeat).
ColumnLayout {
  id: root

  required property var item
  property string range: "1d"
  property bool pickRange: true
  property bool showStats: true

  readonly property var quote: MarketsManager.quoteFor(root.item)
  // A longer range's chart: { points, reference, high, low, currency }
  property var _history: null
  property string _historyKey: ""
  property string _error: ""
  property bool _alive: true
  Component.onDestruction: root._alive = false

  readonly property bool isDay: root.range === "1d"
  readonly property var points: root.isDay ? (root.quote?.points ?? []) : (root._history?.points ?? [])
  readonly property real reference: root.isDay ? (root.quote?.prevClose ?? 0) : (root._history?.reference ?? 0)
  readonly property real price: root.quote?.price ?? NaN
  readonly property real change: root.isDay ? (root.quote?.change ?? 0) : root.price - root.reference
  readonly property real percent: root.isDay ? (root.quote?.changePercent ?? 0) : root.reference > 0 ? root.change / root.reference * 100 : 0
  readonly property string trend: MarketMath.trend(root.change)
  readonly property color trendColor: MarketsManager.trendColor(root.trend)
  readonly property string currency: root.quote?.currency ?? ""

  readonly property string _wantedKey: root.isDay || !root.item ? "" : root.item.source + ":" + root.item.symbol + ":" + root.range
  on_WantedKeyChanged: root._fetch()
  Component.onCompleted: root._fetch()

  function _fetch() {
    const key = root._wantedKey;
    if (key === "" || key === root._historyKey)
      return;
    root._history = null;
    root._error = "";
    root._historyKey = key;
    MarketsManager.history(root.item, root.range, (error, history) => {
      if (!root || !root._alive || root._historyKey !== key)
        return;
      if (error)
        root._error = error.message ?? String(error);
      else
        root._history = history;
    });
  }

  spacing: Widget.spacing * 1.5

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.padding
    StyledText {
      text: MarketMath.formatPrice(root.price, root.currency)
      textSize: Appearance.fontSize * 1.8
      font.weight: Font.Bold
      font.features: ({
          "tnum": 1
        })
    }
    ColumnLayout {
      spacing: 0
      StyledText {
        textColor: root.trendColor
        font.weight: Font.DemiBold
        text: isNaN(root.price) ? "" : I18n.tr("{0} ({1})", MarketMath.formatChange(root.change, root.currency), MarketMath.formatPercent(root.percent))
      }
      StyledText {
        textSize: Appearance.fontSizeBy(-2)
        textColor: Theme.foregroundInactive
        text: {
          const state = MarketsManager.stateLabel(root.quote);
          const name = root.quote?.name ?? "";
          return state !== "" ? I18n.tr("{0} · {1}", name, state) : name;
        }
      }
    }
    Item {
      Layout.fillWidth: true
    }
  }

  Item {
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumHeight: Appearance.fontSize * 4

    PriceChart {
      anchors.fill: parent
      visible: root.points.length > 1
      points: root.points
      reference: root.reference
      start: root.isDay ? (root.quote?.sessionStart ?? 0) : 0
      end: root.isDay ? (root.quote?.sessionEnd ?? 0) : 0
      lineColor: root.trendColor
      currency: root.currency
      showDate: !root.isDay
      detailed: true
    }

    StyledText {
      anchors.centerIn: parent
      visible: root.points.length <= 1
      textColor: root._error ? Theme.error : Theme.foregroundInactive
      textSize: Appearance.fontSizeBy(-1)
      width: Math.min(implicitWidth, parent.width)
      wrapMode: Text.Wrap
      horizontalAlignment: Text.AlignHCenter
      text: root._error ? I18n.tr("Couldn't load the chart: {0}", root._error) : I18n.tr("Loading the chart…")
    }
  }

  SegmentRow {
    visible: root.pickRange
    Layout.alignment: Qt.AlignHCenter
    Repeater {
      // I18n.tr("1D") I18n.tr("5D") I18n.tr("1M") I18n.tr("6M") I18n.tr("1Y")
      model: [["1d", "1D"], ["5d", "5D"], ["1mo", "1M"], ["6mo", "6M"], ["1y", "1Y"]]
      SegmentButton {
        required property var modelData
        Layout.fillWidth: false
        text: I18n.tr(modelData[1])
        active: root.range === modelData[0]
        onClicked: root.range = modelData[0]
      }
    }
  }

  GridLayout {
    visible: root.showStats
    Layout.fillWidth: true
    columns: 4
    columnSpacing: Widget.padding
    rowSpacing: 0
    Repeater {
      // I18n.tr("Prev. close") I18n.tr("Day high") I18n.tr("Day low") I18n.tr("Exchange")
      model: ["Prev. close", "Day high", "Day low", "Exchange"]
      StyledText {
        required property string modelData
        Layout.fillWidth: true
        text: I18n.tr(modelData)
        textSize: Appearance.fontSizeBy(-3)
        textColor: Theme.foregroundInactive
      }
    }
    Repeater {
      model: 4
      StyledText {
        required property int index
        Layout.fillWidth: true
        elide: Text.ElideRight
        textSize: Appearance.fontSizeBy(-1)
        font.features: ({
            "tnum": 1
          })
        text: {
          const q = root.quote;
          if (!q || q.error)
            return "—";
          switch (index) {
          case 0:
            return MarketMath.formatPrice(q.prevClose, q.currency);
          case 1:
            return MarketMath.formatPrice(q.dayHigh, q.currency);
          case 2:
            return MarketMath.formatPrice(q.dayLow, q.currency);
          }
          return q.exchange || "—";
        }
      }
    }
  }
}
