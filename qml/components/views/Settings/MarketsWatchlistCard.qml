pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.ui
import qs.services.apps
import qs.components.forms
import qs.components.methods
import qs.components.reusable

// The Markets section's first card (its `x-card`): the watchlist. A search
// (Yahoo Finance and CoinGecko, as you type) adds symbols; each one on the
// list shows its price, moves up or down, and opens to its label, holding
// and alerts. Edits go through the settings draft like any other row.
FoldingCard {
  id: root

  // The settings group key it folds under, from SettingsContent
  property string foldKey

  readonly property var itemSchema: ConfigManager.configSchema.properties.Markets.properties.symbols.items
  readonly property var symbols: MarketsConfig.symbols
  // The entry opened for editing ("" for none)
  property string openId: ""

  // The search: what was typed, and its answer
  property string query: ""
  property var matches: []
  property string searchError: ""
  property bool searching: false
  property bool _alive: true
  // Prices for the list while the card is shown
  Component.onCompleted: MarketsManager.acquire(root)
  Component.onDestruction: {
    root._alive = false;
    MarketsManager.release(root);
  }

  collapsed: SettingsManager.isCollapsed(root.foldKey)
  onToggled: SettingsManager.setCollapsed(root.foldKey, !root.collapsed)

  function _commit(symbols) {
    SettingsManager.setValue(["Markets", "symbols"], symbols);
  }

  function has(match) {
    return root.symbols.some(item => item.symbol === match.symbol && (item.source === "coingecko") === (match.source === "coingecko"));
  }

  function add(match) {
    if (root.has(match))
      return;
    const symbols = Utils.clone(root.symbols);
    const base = match.display.toLowerCase().replace(/[^a-z0-9]+/g, "") || "symbol";
    symbols.push(SchemaValidation.applyDefaults({
      "id": Utils.freeId(base, symbols.map(item => item.id)),
      "symbol": match.symbol,
      "source": match.source,
      // A coin's id ("bitcoin") reads worse than its ticker
      "label": match.source === "coingecko" ? match.display : ""
    }, root.itemSchema, ConfigManager.configSchema));
    root._commit(symbols);
  }

  function move(index, by) {
    const to = index + by;
    if (to < 0 || to >= root.symbols.length)
      return;
    const symbols = Utils.clone(root.symbols);
    const [moved] = symbols.splice(index, 1);
    symbols.splice(to, 0, moved);
    root._commit(symbols);
  }

  function remove(index) {
    const symbols = Utils.clone(root.symbols);
    symbols.splice(index, 1);
    root._commit(symbols);
  }

  function edit(index, values) {
    const symbols = Utils.clone(root.symbols);
    Object.assign(symbols[index], values);
    root._commit(symbols);
  }

  function search() {
    const text = root.query.trim();
    if (text === "") {
      root.matches = [];
      root.searchError = "";
      root.searching = false;
      return;
    }
    root.searching = true;
    MarketsManager.search(text, (error, result) => {
      if (!root || !root._alive || root.query.trim() !== text)
        return;
      root.searching = false;
      root.matches = error ? [] : result.matches;
      root.searchError = error ? (error.message ?? String(error)) : "";
    });
  }

  // Searching a moment after the typing stops
  Timer {
    id: debounce
    interval: 350 // behaviour timing: the search waits for a pause in typing
    onTriggered: root.search()
  }

  StyledTextEntry {
    Layout.fillWidth: true
    placeholderText: I18n.tr("Search stocks, ETFs, indices, currencies and crypto…")
    clearable: true
    escapeClears: true
    onTextEdited: {
      root.query = text;
      debounce.restart();
    }
  }

  StyledText {
    Layout.fillWidth: true
    visible: root.searching || root.searchError !== "" || (root.query.trim() !== "" && !root.searching && root.matches.length === 0 && !debounce.running)
    textSize: Appearance.fontSizeBy(-1)
    textColor: root.searchError ? Theme.error : Theme.foregroundInactive
    wrapMode: Text.Wrap
    text: root.searching ? I18n.tr("Searching…") : root.searchError ? I18n.tr("Couldn't search: {0}", root.searchError) : I18n.tr("Nothing found")
  }

  // The matches, each with Add
  ColumnLayout {
    Layout.fillWidth: true
    visible: root.matches.length > 0
    spacing: 0
    Repeater {
      model: root.matches.length
      RowLayout {
        id: match
        required property int index
        readonly property var found: root.matches[index]
        readonly property bool added: root.has(match.found)
        Layout.fillWidth: true
        spacing: Widget.spacing * 1.5
        StatusChip {
          shown: true
          text: match.found.kind === "crypto" ? I18n.tr("Crypto") : match.found.kind === "etf" ? I18n.tr("ETF") : match.found.kind === "index" ? I18n.tr("Index") : match.found.kind === "fx" ? I18n.tr("Currency") : match.found.kind === "future" ? I18n.tr("Future") : match.found.kind === "fund" ? I18n.tr("Fund") : I18n.tr("Stock")
          color: match.found.kind === "crypto" ? Theme.warning : Theme.accent
        }
        StyledLabel {
          text: match.found.display
          font.weight: Font.DemiBold
        }
        StyledLabel {
          Layout.fillWidth: true
          text: match.found.exchange ? I18n.tr("{0} · {1}", match.found.name, match.found.exchange) : match.found.name
          textColor: Theme.foregroundAlt
          elide: Text.ElideRight
        }
        StyledIconButton {
          iconText: match.added ? "check" : "add"
          iconColor: match.added ? Theme.success : Theme.accent
          tooltipText: match.added ? I18n.tr("On the watchlist") : I18n.tr("Add to the watchlist")
          enabled: !match.added
          onClicked: root.add(match.found)
        }
      }
    }
  }

  StyledSeparator {
    Layout.fillWidth: true
    visible: root.matches.length > 0
  }

  StyledText {
    Layout.fillWidth: true
    visible: root.symbols.length === 0
    textColor: Theme.foregroundInactive
    text: I18n.tr("The watchlist is empty: search above to add symbols.")
  }

  // The watchlist, in order
  Repeater {
    model: root.symbols.length
    ColumnLayout {
      id: entry
      required property int index
      readonly property var item: root.symbols[index]
      readonly property var quote: MarketsManager.quoteFor(entry.item)
      readonly property bool open: root.openId === entry.item.id
      Layout.fillWidth: true
      spacing: Widget.spacing

      ListEntryRow {
        id: listRow
        Layout.fillWidth: true
        icon: entry.item.source === "coingecko" || entry.quote?.kind === "crypto" ? "currency_bitcoin" : entry.quote?.kind === "index" ? "monitoring" : "show_chart"
        label: entry.item.label ? I18n.tr("{0} ({1})", entry.item.label, entry.item.symbol) : entry.item.symbol
        selected: entry.open
        onClicked: root.openId = entry.open ? "" : entry.item.id
        badges: Row {
          spacing: Widget.spacing
          StyledLabel {
            visible: !!entry.quote
            textSize: Appearance.fontSizeBy(-1)
            textColor: entry.quote?.error ? Theme.error : MarketsManager.trendColor(MarketMath.trend(entry.quote?.change ?? 0))
            text: entry.quote?.error ? entry.quote.error : entry.quote ? I18n.tr("{0} {1}", MarketMath.formatPrice(entry.quote.price, entry.quote.currency), MarketMath.formatPercent(entry.quote.changePercent)) : ""
          }
          StyledIcon {
            visible: entry.item.alertAbove > 0 || entry.item.alertBelow > 0
            text: "notifications_active"
            textSize: Appearance.fontSizeBy(-1)
            textColor: listRow.ink
          }
          StyledIcon {
            visible: entry.item.quantity > 0
            text: "account_balance_wallet"
            textSize: Appearance.fontSizeBy(-1)
            textColor: listRow.ink
          }
        }
        RowAction {
          row: listRow
          iconText: "arrow_upward"
          tooltipText: I18n.tr("Move up")
          enabled: entry.index > 0
          onClicked: root.move(entry.index, -1)
        }
        RowAction {
          row: listRow
          iconText: "arrow_downward"
          tooltipText: I18n.tr("Move down")
          enabled: entry.index < root.symbols.length - 1
          onClicked: root.move(entry.index, 1)
        }
        RowAction {
          row: listRow
          danger: true
          iconText: "delete"
          tooltipText: I18n.tr("Remove")
          onClicked: root.remove(entry.index)
        }
      }

      // Its options, built only while open
      Loader {
        Layout.fillWidth: true
        Layout.leftMargin: Widget.padding
        active: entry.open
        visible: active
        sourceComponent: SchemaPropertiesForm {
          propertiesSchema: Object.keys(root.itemSchema.properties).filter(key => key !== "id").reduce((out, key) => {
            out[key] = root.itemSchema.properties[key];
            return out;
          }, {})
          order: ["symbol", "source", "label", "quantity", "averageCost", "alertAbove", "alertBelow"]
          values: entry.item
          onEdited: (path, value) => root.edit(entry.index, {
              [path[0]]: value
            })
        }
      }
    }
  }
}
