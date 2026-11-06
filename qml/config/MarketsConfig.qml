pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Markets section: the watchlist every markets widget and
// module shows, and how its prices are fetched (see MarketsManager).
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.Markets

  // [{ id, symbol, source, label, quantity, averageCost, alertAbove, alertBelow }]
  readonly property var symbols: _c.symbols
  // How often prices are fetched (ms)
  readonly property int interval: _c.interval
  readonly property bool pauseWhenClosed: _c.pauseWhenClosed
  // The holdings' currency (a three-letter code)
  readonly property string baseCurrency: _c.baseCurrency
  readonly property bool alerts: _c.alerts
  // Rises drawn in the error colour and falls in the success one
  readonly property bool redForGains: _c.redForGains
  // Lock screen modules show holdings too (their own showHoldings on)
  readonly property bool holdingsOnLockscreen: _c.holdingsOnLockscreen
}
