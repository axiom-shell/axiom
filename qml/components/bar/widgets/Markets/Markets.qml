pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// Watched prices (from MarketsManager, for the Markets settings' watchlist,
// or the symbols this widget picks), with the portfolio first when asked.
// Label and stacked show one symbol at a time, cycling (or, label, all side
// by side), ticker scrolls them all, sparkline draws the shown one's day.
// The change is coloured by its trend. Hovering opens the watchlist. Drawn
// one box per symbol (Boxes: One per item), each box is this widget
// showing its one symbol (or the portfolio): `box`, its id.
ValueStyleWidget {
  id: root

  Component.onCompleted: MarketsManager.acquire(root)
  Component.onDestruction: MarketsManager.release(root)

  // What it shows, from config only: { item } per symbol, a { portfolio }
  // first when asked
  readonly property var _all: MarketMath.entries(MarketsConfig.symbols, root.properties.symbols, root.properties.showPortfolio)
  // Its one entry in a box of its own
  readonly property var entries: root.box === "" ? root._all : root._all.filter(entry => root.box === "portfolio" ? entry.portfolio === true : entry.item?.id === root.box)
  readonly property bool cycles: root.properties.rotate && root.style !== "ticker" && root.entries.length > 1
  property int _index: 0
  readonly property var shown: root.entries.length > 0 ? root.entries[root._index % root.entries.length] : null

  // An entry's figures: { name, price, change, percent, currency, trend,
  // points, reference, start, end }, or null without a price yet
  function figures(entry) {
    if (!entry)
      return null;
    if (entry.portfolio) {
      const p = MarketsManager.portfolio;
      if (!p || p.count === p.missing)
        return null;
      return {
        "name": I18n.tr("Portfolio"),
        "price": p.value,
        "change": p.dayChange,
        "percent": p.dayPercent,
        "currency": MarketsConfig.baseCurrency,
        "trend": MarketMath.trend(p.dayChange),
        "points": []
      };
    }
    const q = MarketsManager.quoteFor(entry.item);
    const name = MarketMath.displayName(entry.item, q);
    if (!q || q.error)
      return {
        "name": name,
        "price": NaN
      };
    return {
      "name": name,
      "price": q.price,
      "change": q.change,
      "percent": q.changePercent,
      "currency": q.currency,
      "trend": MarketMath.trend(q.change),
      "points": q.points
    };
  }

  // The value part (price, change or both), the change in its trend's
  // colour when `rich`
  function valueText(f, rich) {
    if (!f || isNaN(f.price))
      return "…";
    const price = MarketMath.formatPrice(f.price, f.currency);
    const percent = MarketMath.formatPercent(f.percent);
    const change = root.properties.value === "change" ? MarketMath.formatChange(f.change, f.currency) : percent;
    const colored = rich && root.properties.colorize ? `<font color="${MarketsManager.trendColor(f.trend)}">${change}</font>` : change;
    switch (root.properties.value) {
    case "price":
      return price;
    case "percent":
    case "change":
      return colored;
    }
    return price + " " + colored;
  }

  function entryText(entry, rich) {
    const f = root.figures(entry);
    return (f ? f.name : "") + " " + root.valueText(f, rich);
  }

  readonly property var current: root.figures(root.shown)
  // The change coloured inline only where the text doesn't sit on a fill
  // (`textOnFill`: it must read on it; there `colorText` colours it all,
  // or not)
  readonly property bool rich: root.properties.colorize && !root.colors.textOnFill

  icon: {
    if (MarketsManager.error !== "" && !root.current)
      return "error";
    const trend = root.current?.trend ?? "flat";
    return trend === "up" ? "trending_up" : trend === "down" ? "trending_down" : "show_chart";
  }
  textFormat: root.rich ? Text.StyledText : Text.PlainText
  text: root.cycles || root.entries.length <= 1 ? root.entryText(root.shown, root.rich) : root.entries.map(entry => root.entryText(entry, root.rich)).join("   ")
  // The widest entry, so cycling never resizes it
  minimumText: root.cycles ? root.entries.map(entry => root.entryText(entry, false)).reduce((a, b) => b.length > a.length ? b : a, "") : ""

  styleText: root.style === "ticker" ? root.entries.map(entry => root.entryText(entry, root.rich)).join("     ") : (root.current?.name ?? "")
  subtext: root.valueText(root.current, false)

  history: root.current?.points?.length > 1 ? MarketMath.closes(root.current.points, 48) : null
  readonly property var _span: MarketMath.priceSpan(root.current?.points ?? [], 0)
  graphMin: root._span.min
  graphMax: root._span.max

  stateColor: MarketsManager.trendColor(root.current?.trend ?? "flat")
  hasState: root.properties.colorize && !!root.current && !isNaN(root.current.price)

  // Cycling through the entries, while animations are on (off, the first
  // stays)
  SequentialAnimation {
    running: root.cycles && Appearance.animations
    loops: Animation.Infinite
    PauseAnimation {
      duration: root.properties.rotateInterval // behaviour timing: how long each symbol shows (a setting)
    }
    ScriptAction {
      script: root._index = (root._index + 1) % Math.max(1, root.entries.length)
    }
  }

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "MarketsPopout"
    extraData: ({
        "symbols": root.properties.symbols,
        "showPortfolio": root.properties.showPortfolio
      })
    active: MenusConfig.opensOwnPopout(root.properties)
  }

  // With no price at all, why, on the bar's inner side
  BarToolTip {
    widget: root
    shown: MarketsManager.error !== ""
    text: I18n.tr("Couldn't load market prices: {0}", MarketsManager.error)
  }
}
