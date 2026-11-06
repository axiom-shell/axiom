pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.services.core
import qs.services.system

// Stock and crypto prices shared by every markets widget, for the Markets
// settings' watchlist: axiom's `markets` topic (Yahoo Finance and
// CoinGecko), fetched every `interval` while some widget wants it or a
// price alert is set. axiom keeps the last prices (also across restarts),
// so a widget created again shows them at once while they refresh.
//   MarketsManager.acquire(owner) / release(owner)
//   MarketsManager.quoteFor(item)       the item's quote, or null
//   MarketsManager.search(text, done)   done(error, { matches, error })
//   MarketsManager.history(item, range, done)
QtObject {
  id: root

  // Quotes by MarketMath.key: { symbol, name, kind, currency, exchange,
  // price, prevClose, change, changePercent, dayHigh, dayLow, marketState,
  // sessionStart, sessionEnd, points [[t, price]], updatedAt, stale, error }
  readonly property var quotes: _state?.quotes ?? ({})
  // Each quote currency's rate to the portfolio currency
  readonly property var fx: _state?.fx ?? ({})
  // When the newest price was fetched (epoch ms, 0 before any)
  readonly property real updatedAt: _state?.updatedAt ?? 0
  // Why no symbol has a price ("" while one has, or while loading)
  readonly property string error: _state?.error ?? ""
  // Whether the first prices are still on their way
  readonly property bool loading: _state === null && _registry.active
  // The holdings in MarketsConfig.baseCurrency (MarketMath.portfolio), or
  // null with none
  readonly property var portfolio: MarketMath.portfolio(MarketsConfig.symbols, root.quotes, root.fx, MarketsConfig.baseCurrency)

  function acquire(owner) {
    _registry.acquire(owner, true);
  }

  function release(owner) {
    _registry.release(owner);
  }

  function quoteFor(item) {
    return item ? root.quotes[MarketMath.key(item)] ?? null : null;
  }

  // Fetches every price now
  function refresh() {
    BackendManager.refresh("markets");
  }

  // The symbols matching `text`, Yahoo's then CoinGecko's
  // rpc: markets.search
  function search(text, done) {
    BackendManager.call("markets.search", {
      "query": text
    }, done, {
      "repeatable": true
    });
  }

  // An item's chart over `range` (1d, 5d, 1mo, 6mo, 1y): done(error,
  // { points, reference, high, low, currency, start, end })
  // rpc: markets.history
  function history(item, range, done) {
    BackendManager.call("markets.history", {
      "symbol": item.symbol,
      "source": item.source,
      "range": range,
      "baseCurrency": MarketsConfig.baseCurrency
    }, done, {
      "repeatable": true
    });
  }

  // The theme colour for a trend ("up", "down", "flat"), red for gains
  // when the settings say so
  function trendColor(trend) {
    if (trend === "flat")
      return Theme.foregroundInactive;
    return (trend === "up") !== MarketsConfig.redForGains ? Theme.success : Theme.error;
  }

  // A market state's short label ("" while it trades)
  function stateLabel(quote) {
    switch (quote?.marketState) {
    case "pre":
      return I18n.tr("Pre-market");
    case "post":
      return I18n.tr("After hours");
    case "closed":
      return I18n.tr("Closed");
    }
    return "";
  }

  // -- Private --
  property ConsumerRegistry _registry: ConsumerRegistry {}

  property var _state: null

  // Prices are wanted while shown, or while an alert waits
  readonly property bool _alertsWanted: !Paths.greeter && MarketsConfig.alerts && MarketMath.hasAlerts(MarketsConfig.symbols)
  readonly property bool _wanted: _registry.active || _alertsWanted

  // The request as one string, so axiom is asked again only when it
  // really changes
  readonly property string _requestKey: _wanted ? JSON.stringify(MarketMath.request(MarketsConfig.symbols, MarketsConfig.interval, MarketsConfig.pauseWhenClosed, MarketsConfig.baseCurrency)) : ""

  // (also at completion: a request already wanted then, by a price alert,
  // changes nothing until the watchlist does)
  on_RequestKeyChanged: root._subscribe()

  function _subscribe() {
    if (root._requestKey !== "")
      BackendManager.acquire("markets", JSON.parse(root._requestKey));
    else
      BackendManager.release("markets");
  }

  // The last price seen per key and currency, for alerts: a price first
  // seen crosses nothing, so a reload, alerts turned back on or a coin
  // priced in another base currency never fires one
  property var _lastPrices: ({})

  function _onState(state) {
    root._state = state;
    if (!root._alertsWanted) {
      root._lastPrices = {};
      return;
    }
    const last = root._lastPrices;
    const next = {};
    for (const item of MarketsConfig.symbols) {
      const quote = state?.quotes?.[MarketMath.key(item)];
      if (!quote || quote.error || quote.stale)
        continue;
      const key = MarketMath.key(item) + " " + quote.currency;
      next[key] = quote.price;
      const crossed = MarketMath.crossed(last[key], quote.price, item.alertAbove, item.alertBelow);
      if (crossed)
        root._notify(item, quote, crossed);
    }
    root._lastPrices = next;
  }

  function _notify(item, quote, crossed) {
    const name = MarketMath.displayName(item, quote);
    const threshold = MarketMath.formatPrice(crossed === "above" ? item.alertAbove : item.alertBelow, quote.currency);
    const summary = crossed === "above" ? I18n.tr("{0} rose above {1}", name, threshold) : I18n.tr("{0} fell below {1}", name, threshold);
    const body = I18n.tr("Now {0} ({1} today)", MarketMath.formatPrice(quote.price, quote.currency), MarketMath.formatPercent(quote.changePercent));
    NotificationManager.sendNotification(I18n.tr("Markets"), summary, body, {
      "desktopEntry": "axiom-markets",
      "icon": "office-chart-line"
    });
  }

  property IpcTarget _ipc: IpcTarget {
    target: "markets"
    enabled: !Paths.greeter

    // Fetches every price now
    function refresh(): void {
      root.refresh();
    }

    // One line per watched symbol: "AAPL 344.17 USD -1.53%", and the
    // portfolio's total last with holdings (for scripts and status bars)
    function status(): string {
      const lines = MarketsConfig.symbols.map(item => {
        const quote = root.quoteFor(item);
        const name = MarketMath.displayName(item, quote);
        if (!quote || quote.error)
          return name + " " + (quote?.error || "-");
        return name + " " + quote.price + " " + quote.currency + " " + quote.changePercent.toFixed(2) + "%";
      });
      const p = root.portfolio;
      if (p && p.count > p.missing)
        lines.push("Portfolio " + p.value.toFixed(2) + " " + MarketsConfig.baseCurrency + " " + p.dayPercent.toFixed(2) + "%");
      return lines.join("\n");
    }
  }

  Component.onCompleted: {
    BackendManager.listen("markets.state", state => root._onState(state));
    root._subscribe();
  }
}
