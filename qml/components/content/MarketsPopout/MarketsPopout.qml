pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.apps
import qs.services.ui
import qs.components.methods
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// The Markets widget's popout, from MarketsManager (the widget keeps it
// acquired): the portfolio, then the widget's symbols as QuoteRows; a
// click on one swaps the list for its detail (a large chart over 1D to 1Y,
// the day's range and the previous close). The body is as tall as what it
// shows (the rows, up to 8 before the list scrolls; the empty state; the
// detail's chart), and the window keeps room for the tallest of them
// (maxImplicitHeight), as the Wi-Fi popout does. Refresh and a link to
// the watchlist's settings in the header.
Panel {
  id: root

  // From the widget's extraData: the symbols it shows (none: all) and
  // whether it shows the portfolio
  property var symbols: []
  property bool showPortfolio: false

  readonly property var items: MarketMath.pick(MarketsConfig.symbols, root.symbols)
  readonly property var portfolio: MarketsManager.portfolio

  // The symbol shown in detail ("" for the list), and its chart's range
  property string selectedId: ""
  readonly property var selected: root.items.find(item => item.id === root.selectedId) ?? null

  readonly property bool showsEmpty: root.items.length === 0 || (MarketsManager.error !== "" && root.selected === null)
  // The body's height in each view: the rows (rows are alike, so 8 of them
  // is the list's height over its count), the empty state, the detail
  readonly property real listHeight: list.count === 0 ? 0 : list.contentHeight / list.count * Math.min(list.count, 8)
  readonly property real emptyHeight: empty.implicitHeight + Widget.padding * 2
  readonly property real detailHeight: Appearance.fontSize * 17
  readonly property real bodyHeight: root.selected !== null ? root.detailHeight : root.showsEmpty ? root.emptyHeight : root.listHeight

  spacing: Widget.padding
  implicitWidth: Widget.px(400)
  // Room for the tallest view, and for the portfolio the detail hides
  maxImplicitHeight: root.implicitHeight - root.bodyHeight + Math.max(root.detailHeight, root.listHeight, root.emptyHeight) + (root.selected !== null && root.showPortfolio && root.portfolio !== null ? portfolioBox.implicitHeight + root.spacing : 0)
  flips: true

  ModuleHeader {
    Layout.fillWidth: true
    icon: root.selected ? "" : "show_chart"
    title: root.selected ? MarketMath.displayName(root.selected, MarketsManager.quoteFor(root.selected)) : I18n.tr("Markets")

    StyledIconButton {
      visible: root.selected !== null
      iconText: "arrow_back"
      tooltipText: I18n.tr("Back to the list")
      onClicked: root.selectedId = ""
    }
    StyledIconButton {
      iconText: "refresh"
      tooltipText: I18n.tr("Refresh prices")
      onClicked: MarketsManager.refresh()
    }
    StyledIconButton {
      iconText: "tune"
      tooltipText: I18n.tr("Edit the watchlist")
      onClicked: SettingsManager.openSetting("Markets")
    }
  }

  // The holdings' total, today's change and the total gain
  Rectangle {
    id: portfolioBox
    visible: root.selected === null && root.showPortfolio && root.portfolio !== null
    Layout.fillWidth: true
    implicitHeight: portfolioRow.implicitHeight + Widget.padding * 2
    radius: Widget.radius
    color: Qt.alpha(MarketsManager.trendColor(MarketMath.trend(root.portfolio?.dayChange ?? 0)), 0.1)

    RowLayout {
      id: portfolioRow
      anchors.fill: parent
      anchors.margins: Widget.padding
      spacing: Widget.padding
      ColumnLayout {
        spacing: 0
        StyledLabel {
          text: I18n.tr("Portfolio")
          textSize: Appearance.fontSizeBy(-2)
          textColor: Theme.foregroundAlt
        }
        StyledLabel {
          text: root.portfolio ? MarketMath.formatPrice(root.portfolio.value, MarketsConfig.baseCurrency) : ""
          textSize: Appearance.fontSize * 1.6
          font.weight: Font.Bold
        }
      }
      Item {
        Layout.fillWidth: true
      }
      ColumnLayout {
        spacing: 0
        StyledLabel {
          Layout.alignment: Qt.AlignRight
          textColor: MarketsManager.trendColor(MarketMath.trend(root.portfolio?.dayChange ?? 0))
          font.weight: Font.DemiBold
          text: root.portfolio ? I18n.tr("{0} ({1}) today", MarketMath.formatChange(root.portfolio.dayChange, MarketsConfig.baseCurrency), MarketMath.formatPercent(root.portfolio.dayPercent)) : ""
        }
        StyledLabel {
          Layout.alignment: Qt.AlignRight
          visible: root.portfolio?.gain !== null && root.portfolio?.gain !== undefined
          textSize: Appearance.fontSizeBy(-2)
          textColor: Theme.foregroundAlt
          text: visible ? I18n.tr("{0} ({1}) in all", MarketMath.formatChange(root.portfolio.gain, MarketsConfig.baseCurrency), MarketMath.formatPercent(root.portfolio.gainPercent)) : ""
        }
      }
    }
  }

  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: root.bodyHeight

    EmptyState {
      id: empty
      anchors.centerIn: parent
      visible: root.showsEmpty
      maxWidth: parent.width
      icon: root.items.length === 0 ? "playlist_add" : "cloud_off"
      text: root.items.length === 0 ? I18n.tr("No symbols on the watchlist yet") : I18n.tr("Couldn't load market prices: {0}", MarketsManager.error)
    }

    ListView {
      id: list
      anchors.fill: parent
      visible: root.selected === null && !root.showsEmpty
      clip: true
      spacing: 0
      boundsBehavior: Flickable.StopAtBounds
      model: root.items
      delegate: QuoteRow {
        required property var modelData
        item: modelData
        width: list.width
        showHoldings: root.showPortfolio
        onClicked: root.selectedId = modelData.id
      }
    }

    Loader {
      anchors.fill: parent
      active: root.selected !== null
      sourceComponent: QuoteDetail {
        item: root.selected
      }
    }
  }

  StyledText {
    Layout.fillWidth: true
    horizontalAlignment: Text.AlignHCenter
    textSize: Appearance.fontSizeBy(-3)
    textColor: Theme.foregroundInactive
    text: MarketsManager.updatedAt > 0 ? I18n.tr("Updated {0} · Yahoo Finance, CoinGecko", I18n.formatDate(new Date(MarketsManager.updatedAt), I18n.timeFormat("default"))) : MarketsManager.loading ? I18n.tr("Loading prices…") : ""
  }
}
