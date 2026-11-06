pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// Watched prices (MarketsManager, the Markets settings' watchlist or the
// symbols picked here): a list of QuoteRows (a click opens one in detail
// in its place), tiles with each day's line behind the price, or one
// symbol's large chart. With holdings on, each row's and the portfolio's
// worth (on the lock screen only with Markets.holdingsOnLockscreen, never
// on the greeter). Compact, the first
// symbol's price.
Card {
  id: root

  Component.onCompleted: MarketsManager.acquire(root)
  Component.onDestruction: MarketsManager.release(root)

  readonly property var items: MarketMath.pick(MarketsConfig.symbols, root.properties.symbols)
  readonly property string layout: root.properties.layout
  // Holdings are private: on the lock screen only with the Markets
  // setting saying so, never on the greeter
  readonly property bool holdings: root.properties.showHoldings && (root.host.kind === "lockscreen" ? MarketsConfig.holdingsOnLockscreen : root.host.kind !== "greeter")
  readonly property var portfolio: root.holdings ? MarketsManager.portfolio : null
  readonly property var first: root.items.length > 0 ? root.items[0] : null
  readonly property var firstQuote: MarketsManager.quoteFor(root.first)
  readonly property bool failed: MarketsManager.error !== ""

  // The symbol a list's click opened ("" for the list)
  property string selectedId: ""
  readonly property var selected: root.items.find(item => item.id === root.selectedId) ?? null

  fullMinWidth: Appearance.fontSize * 12
  fullMinHeight: Appearance.fontSize * 7

  compactContent: CompactFigure {
    readonly property string trend: MarketMath.trend(root.firstQuote?.change ?? 0)
    icon: trend === "up" ? "trending_up" : trend === "down" ? "trending_down" : "show_chart"
    iconColor: MarketsManager.trendColor(trend)
    value: root.firstQuote && !root.firstQuote.error ? MarketMath.formatPrice(root.firstQuote.price, root.firstQuote.currency) : ""
    label: root.first ? I18n.tr("{0} {1}", MarketMath.displayName(root.first, root.firstQuote), MarketMath.formatPercent(root.firstQuote?.changePercent ?? NaN)) : ""
  }

  EmptyState {
    anchors.centerIn: parent
    visible: root.items.length === 0 || (root.failed && !root.firstQuote)
    maxWidth: root.innerWidth
    availableHeight: root.innerHeight
    icon: root.items.length === 0 ? "playlist_add" : "cloud_off"
    text: root.items.length === 0 ? I18n.tr("No symbols on the watchlist yet") : I18n.tr("Couldn't load market prices: {0}", MarketsManager.error)
  }

  ColumnLayout {
    visible: root.items.length > 0 && !(root.failed && !root.firstQuote)
    anchors.fill: parent
    anchors.margins: root.pad
    spacing: Widget.spacing

    ModuleHeader {
      Layout.fillWidth: true
      visible: root.layout !== "focus" || root.selected !== null
      icon: root.selected ? "" : "show_chart"
      title: root.selected ? MarketMath.displayName(root.selected, MarketsManager.quoteFor(root.selected)) : I18n.tr("Markets")

      StyledText {
        visible: root.portfolio !== null && root.selected === null
        textColor: MarketsManager.trendColor(MarketMath.trend(root.portfolio?.dayChange ?? 0))
        font.weight: Font.DemiBold
        text: root.portfolio ? I18n.tr("{0} · {1}", MarketMath.formatPrice(root.portfolio.value, MarketsConfig.baseCurrency), MarketMath.formatPercent(root.portfolio.dayPercent)) : ""
      }
      StyledIconButton {
        visible: root.selected !== null
        iconText: "arrow_back"
        tooltipText: I18n.tr("Back to the list")
        onClicked: root.selectedId = ""
      }
    }

    // A clicked row, or the focus layout's symbol
    Loader {
      Layout.fillWidth: true
      Layout.fillHeight: true
      active: root.selected !== null || root.layout === "focus"
      visible: active
      sourceComponent: QuoteDetail {
        item: root.selected ?? root.first
        range: root.selected ? "1d" : root.properties.range
        pickRange: root.innerHeight >= Appearance.fontSize * 14
        showStats: root.innerHeight >= Appearance.fontSize * 18 && root.innerWidth >= Appearance.fontSize * 16
      }
    }

    Loader {
      Layout.fillWidth: true
      Layout.fillHeight: true
      active: root.selected === null && root.layout === "list"
      visible: active
      sourceComponent: ListView {
        id: list
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.items
        delegate: QuoteRow {
          required property var modelData
          item: modelData
          width: list.width
          showChart: root.properties.showChart && list.width >= Appearance.fontSize * 16
          showHoldings: root.holdings
          onClicked: root.selectedId = modelData.id
        }
      }
    }

    Loader {
      Layout.fillWidth: true
      Layout.fillHeight: true
      active: root.selected === null && root.layout === "tiles"
      visible: active
      sourceComponent: GridLayout {
        id: grid
        readonly property int count: root.items.length
        columns: Math.max(1, Math.min(grid.count, Math.floor((width + columnSpacing) / (Appearance.fontSize * 9 + columnSpacing))))
        columnSpacing: Widget.spacing
        rowSpacing: Widget.spacing

        Repeater {
          model: root.items
          QuoteTile {
            required property var modelData
            item: modelData
            showChart: root.properties.showChart
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            Layout.preferredHeight: 1
            onClicked: root.selectedId = modelData.id
          }
        }
      }
    }
  }
}
