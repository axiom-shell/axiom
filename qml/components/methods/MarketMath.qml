pragma Singleton
import QtQuick

// The markets feature's rules, for MarketsManager and the markets widget,
// popout and module: the daemon request from the watchlist, which symbols a
// widget shows, price and change formatting, holdings and the portfolio,
// and when a price alert fires. A watchlist item is MarketsConfig.symbols'
// { id, symbol, source, label, quantity, averageCost, alertAbove,
// alertBelow }; a quote is the `markets` topic's { price, prevClose,
// change, changePercent, currency, … }.
QtObject {
  id: root

  // A watchlist item's key in the topic's quotes (its symbol trimmed, as
  // `request` sends it)
  function key(item) {
    const symbol = (item.symbol ?? "").trim();
    return item.source === "coingecko" ? "coingecko:" + symbol : symbol;
  }

  // The `markets` topic's request, from the settings only
  function request(items, interval, pauseWhenClosed, baseCurrency) {
    const valid = items.filter(item => (item.symbol ?? "").trim() !== "");
    return {
      "symbols": valid.map(item => ({
            "symbol": item.symbol.trim(),
            "source": item.source === "coingecko" ? "coingecko" : "yahoo"
          })),
      "baseCurrency": baseCurrency,
      "convert": valid.some(item => item.quantity > 0),
      "pauseWhenClosed": pauseWhenClosed,
      "interval": interval
    };
  }

  // The watchlist items `ids` names, in the watchlist's order; no ids is
  // all of them. An id no longer on the watchlist (its symbol removed) is
  // dropped, so a widget stops tracking it: with none left, it shows all
  function pick(items, ids) {
    const valid = items.filter(item => (item.symbol ?? "").trim() !== "");
    const wanted = (ids ?? []).filter(id => valid.some(item => item.id === id));
    return wanted.length === 0 ? valid : valid.filter(item => wanted.includes(item.id));
  }

  // Whether any item has an alert set
  function hasAlerts(items) {
    return items.some(item => item.alertAbove > 0 || item.alertBelow > 0);
  }

  // What to call an item: its label, else a coin's name, else its symbol
  function displayName(item, quote) {
    if (item.label)
      return item.label;
    if (item.source === "coingecko")
      return quote?.name || item.symbol;
    return item.symbol;
  }

  // "up", "down" or "flat"
  function trend(change) {
    if (!(Math.abs(change) > 1e-9))
      return "flat";
    return change > 0 ? "up" : "down";
  }

  // Decimals for a price: two from 1, four from 0.01, else four
  // significant digits (0.00001234)
  function decimals(value) {
    const v = Math.abs(value);
    if (v >= 1 || v === 0)
      return 2;
    if (v >= 0.01)
      return 4;
    return Math.min(12, 3 - Math.floor(Math.log10(v)));
  }

  // `value` with `places` decimals and thousands grouped: "12,345.60"
  function formatNumber(value, places) {
    const fixed = Math.abs(value).toFixed(places);
    const parts = fixed.split(".");
    const whole = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    return (value < 0 && Number(fixed) !== 0 ? "−" : "") + whole + (parts.length > 1 ? "." + parts[1] : "");
  }

  readonly property var _symbols: ({
      "USD": "$",
      "EUR": "€",
      "GBP": "£",
      "JPY": "¥",
      "CNY": "¥",
      "INR": "₹",
      "KRW": "₩",
      "CAD": "CA$",
      "AUD": "A$",
      "HKD": "HK$",
      "CHF": "CHF ",
      "BTC": "₿"
    })

  // A price in its currency: "$182.40", "€0.4213", "1,234.00 SEK", "70.5p"
  function formatPrice(value, currency) {
    if (typeof value !== "number" || isNaN(value))
      return "—";
    const number = root.formatNumber(value, root.decimals(value));
    if (currency === "GBp" || currency === "GBX")
      return number + "p";
    const symbol = root._symbols[currency];
    if (symbol !== undefined)
      return (value < 0 ? "−" + symbol + number.slice(1) : symbol + number);
    return currency ? number + " " + currency : number;
  }

  // A signed change in its currency: "+$1.20", "−€0.0042"
  function formatChange(value, currency) {
    if (typeof value !== "number" || isNaN(value))
      return "—";
    const price = root.formatPrice(Math.abs(value), currency);
    return (value > 0 ? "+" : value < 0 ? "−" : "") + price;
  }

  // A signed percentage: "+1.23%", "−0.40%", "0.00%"
  function formatPercent(value) {
    if (typeof value !== "number" || isNaN(value))
      return "—";
    const fixed = Math.abs(value).toFixed(2);
    const sign = Number(fixed) === 0 ? "" : value > 0 ? "+" : "−";
    return sign + fixed + "%";
  }

  // A large number, short: "950", "1.2K", "3.4M", "5.6B", "7.8T"
  function compact(value) {
    const units = [[1e12, "T"], [1e9, "B"], [1e6, "M"], [1e3, "K"]];
    const v = Math.abs(value);
    for (const [size, unit] of units)
      if (v >= size)
        return (value < 0 ? "−" : "") + Number((v / size).toFixed(v / size >= 100 ? 0 : 1)) + unit;
    return root.formatNumber(value, v >= 100 || Number.isInteger(value) ? 0 : 2);
  }

  // One holding, in its quote's currency: { value, dayChange, gain,
  // gainPercent } (gain null without an average cost), or null without a
  // holding or price
  function holding(item, quote) {
    if (!(item.quantity > 0) || !quote || typeof quote.price !== "number" || quote.error)
      return null;
    const value = item.quantity * quote.price;
    const cost = item.averageCost > 0 ? item.quantity * item.averageCost : 0;
    return {
      "value": value,
      "dayChange": item.quantity * (quote.change ?? 0),
      "gain": cost > 0 ? value - cost : null,
      "gainPercent": cost > 0 ? (value - cost) / cost * 100 : null
    };
  }

  // The holdings in the base currency, converted by `fx` ({ currency:
  // rate to base }): { count, value, dayChange, dayPercent, gain,
  // gainPercent (null unless every holding has a cost), missing (holdings
  // with no price or rate yet) }, or null with no holdings
  function portfolio(items, quotes, fx, base) {
    let count = 0, missing = 0, value = 0, day = 0, cost = 0, costed = 0;
    for (const item of items) {
      if (!(item.quantity > 0))
        continue;
      count++;
      const quote = quotes?.[root.key(item)];
      const held = root.holding(item, quote);
      const rate = quote?.currency === base ? 1 : fx?.[quote?.currency];
      if (!held || !(rate > 0)) {
        missing++;
        continue;
      }
      value += held.value * rate;
      day += held.dayChange * rate;
      if (held.gain !== null) {
        cost += item.quantity * item.averageCost * rate;
        costed++;
      }
    }
    if (count === 0)
      return null;
    const priced = count - missing;
    return {
      "count": count,
      "missing": missing,
      "value": value,
      "dayChange": day,
      "dayPercent": value - day > 0 ? day / (value - day) * 100 : 0,
      "gain": priced > 0 && costed === priced ? value - cost : null,
      "gainPercent": priced > 0 && costed === priced && cost > 0 ? (value - cost) / cost * 100 : null
    };
  }

  // Which alert a move from `prev` to `now` crosses: "above" (rose to
  // `above` or past it), "below" (fell to `below` or past it) or ""; a
  // threshold of 0 is unset, and a price first seen (prev not a number)
  // crosses nothing, so a reload never repeats an alert
  function crossed(prev, now, above, below) {
    if (typeof prev !== "number" || typeof now !== "number" || isNaN(prev) || isNaN(now))
      return "";
    if (above > 0 && prev < above && now >= above)
      return "above";
    if (below > 0 && prev > below && now <= below)
      return "below";
    return "";
  }

  // The prices of `points` ([t, price]), at most `count` of them evenly
  // picked, the last always among them (a bar's sparkline)
  function closes(points, count) {
    const pts = points ?? [];
    if (pts.length <= count)
      return pts.map(p => p[1]);
    const out = [];
    const step = (pts.length - 1) / (count - 1);
    for (let i = 0; i < count; i++)
      out.push(pts[Math.round(i * step)][1]);
    return out;
  }

  // A chart's time axis for a quote or history: { start, end } (unix
  // seconds): its session, stretched to cover every point
  function timeSpan(points, start, end) {
    const first = points.length > 0 ? points[0][0] : 0;
    const last = points.length > 0 ? points[points.length - 1][0] : 0;
    const s = start > 0 ? Math.min(start, first || start) : first;
    const e = end > 0 ? Math.max(end, last) : last;
    return {
      "start": s,
      "end": e > s ? e : s + 1
    };
  }

  // A chart's price range: { min, max } over the points and `reference`
  // (0: none), padded so a flat line sits mid-height
  function priceSpan(points, reference) {
    let min = Infinity, max = -Infinity;
    for (const p of points) {
      min = Math.min(min, p[1]);
      max = Math.max(max, p[1]);
    }
    if (reference > 0) {
      min = Math.min(min, reference);
      max = Math.max(max, reference);
    }
    if (min === Infinity)
      return {
        "min": 0,
        "max": 1
      };
    const pad = max > min ? (max - min) * 0.08 : Math.max(Math.abs(max) * 0.01, 1e-9);
    return {
      "min": min - pad,
      "max": max + pad
    };
  }
}
