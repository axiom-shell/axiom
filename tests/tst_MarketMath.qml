import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "MarketMath"

  readonly property var items: [
    {
      "id": "aapl",
      "symbol": "AAPL",
      "source": "yahoo",
      "label": "",
      "quantity": 10,
      "averageCost": 100,
      "alertAbove": 0,
      "alertBelow": 0
    },
    {
      "id": "btc",
      "symbol": "bitcoin",
      "source": "coingecko",
      "label": "",
      "quantity": 0,
      "averageCost": 0,
      "alertAbove": 0,
      "alertBelow": 0
    },
    {
      "id": "blank",
      "symbol": "  ",
      "source": "yahoo",
      "label": "",
      "quantity": 0,
      "averageCost": 0,
      "alertAbove": 0,
      "alertBelow": 0
    }
  ]

  function test_key_and_name() {
    compare(MarketMath.key(items[0]), "AAPL");
    compare(MarketMath.key(items[1]), "coingecko:bitcoin");
    // Trimmed, as the request sends it
    compare(MarketMath.key({
      "symbol": " AAPL ",
      "source": "yahoo"
    }), "AAPL");
    compare(MarketMath.displayName(items[0], null), "AAPL");
    compare(MarketMath.displayName(items[1], {
      "name": "Bitcoin"
    }), "Bitcoin");
    compare(MarketMath.displayName(items[1], null), "bitcoin");
    compare(MarketMath.displayName(Object.assign({}, items[0], {
      "label": "Apple"
    }), null), "Apple");
  }

  function test_request() {
    compare(MarketMath.request(items, 120000, true, "EUR"), {
      "symbols": [
        {
          "symbol": "AAPL",
          "source": "yahoo"
        },
        {
          "symbol": "bitcoin",
          "source": "coingecko"
        }
      ],
      "baseCurrency": "EUR",
      "convert": true,
      "pauseWhenClosed": true,
      "interval": 120000
    });
    compare(MarketMath.request([items[1]], 60000, false, "USD").convert, false, "no holdings, no rates");
  }

  function test_pick() {
    compare(MarketMath.pick(items, []).map(i => i.id), ["aapl", "btc"], "all but the blank");
    compare(MarketMath.pick(items, ["btc", "aapl"]).map(i => i.id), ["aapl", "btc"], "in the watchlist's order");
    compare(MarketMath.pick(items, ["gone", "btc"]).map(i => i.id), ["btc"], "a removed symbol is dropped");
    compare(MarketMath.pick(items, ["gone"]).map(i => i.id), ["aapl", "btc"], "none left: all");
  }

  function test_formatting_data() {
    return [
      {
        "tag": "large",
        "got": MarketMath.formatPrice(67432.5, "USD"),
        "want": "$67,432.50"
      },
      {
        "tag": "cents",
        "got": MarketMath.formatPrice(182.4, "EUR"),
        "want": "€182.40"
      },
      {
        "tag": "sub-dollar",
        "got": MarketMath.formatPrice(0.42131, "USD"),
        "want": "$0.4213"
      },
      {
        "tag": "tiny",
        "got": MarketMath.formatPrice(0.0000123456, "USD"),
        "want": "$0.00001235"
      },
      {
        "tag": "pence",
        "got": MarketMath.formatPrice(70.5, "GBp"),
        "want": "70.50p"
      },
      {
        "tag": "unknown currency",
        "got": MarketMath.formatPrice(1234, "SEK"),
        "want": "1,234.00 SEK"
      },
      {
        "tag": "no price",
        "got": MarketMath.formatPrice(undefined, "USD"),
        "want": "—"
      },
      {
        "tag": "change up",
        "got": MarketMath.formatChange(1.2, "USD"),
        "want": "+$1.20"
      },
      {
        "tag": "change down",
        "got": MarketMath.formatChange(-0.0042, "EUR"),
        "want": "−€0.004200"
      },
      {
        "tag": "percent up",
        "got": MarketMath.formatPercent(1.234),
        "want": "+1.23%"
      },
      {
        "tag": "percent down",
        "got": MarketMath.formatPercent(-0.4),
        "want": "−0.40%"
      },
      {
        "tag": "percent zero",
        "got": MarketMath.formatPercent(-0.001),
        "want": "0.00%"
      },
      {
        "tag": "compact",
        "got": [950, 1234, 3400000, 5.6e9, 123e12].map(MarketMath.compact).join(" "),
        "want": "950 1.2K 3.4M 5.6B 123T"
      },
      {
        "tag": "negative grouped",
        "got": MarketMath.formatNumber(-1234567.891, 2),
        "want": "−1,234,567.89"
      }
    ];
  }

  function test_formatting(data) {
    compare(data.got, data.want);
  }

  function test_trend() {
    compare([MarketMath.trend(2), MarketMath.trend(-0.1), MarketMath.trend(0), MarketMath.trend(NaN)], ["up", "down", "flat", "flat"]);
  }

  function test_portfolio() {
    const quotes = {
      "AAPL": {
        "price": 110,
        "change": 10,
        "currency": "USD"
      },
      "SAP.DE": {
        "price": 200,
        "change": -10,
        "currency": "EUR"
      }
    };
    const sap = {
      "id": "sap",
      "symbol": "SAP.DE",
      "source": "yahoo",
      "quantity": 2,
      "averageCost": 0
    };
    const p = MarketMath.portfolio([items[0], sap], quotes, {
      "EUR": 1.5
    }, "USD");
    compare(p.count, 2);
    compare(p.missing, 0);
    compare(p.value, 1100 + 600);
    compare(p.dayChange, 100 - 30);
    compare(p.dayPercent.toFixed(4), (70 / 1630 * 100).toFixed(4));
    compare(p.gain, null, "SAP has no cost");

    const one = MarketMath.portfolio([items[0]], quotes, {}, "USD");
    compare([one.gain, one.gainPercent], [100, 10]);

    const noRate = MarketMath.portfolio([items[0], sap], quotes, {}, "USD");
    compare([noRate.missing, noRate.value], [1, 1100]);
    compare(MarketMath.portfolio([items[1]], quotes, {}, "USD"), null, "no holdings");
    compare(MarketMath.holding(items[0], {
      "price": 1,
      "error": "x"
    }), null, "an errored quote holds nothing");
  }

  function test_crossed_data() {
    return [
      {
        "tag": "rises past",
        "prev": 99,
        "now": 101,
        "above": 100,
        "below": 0,
        "want": "above"
      },
      {
        "tag": "rises to",
        "prev": 99,
        "now": 100,
        "above": 100,
        "below": 0,
        "want": "above"
      },
      {
        "tag": "stays above",
        "prev": 101,
        "now": 102,
        "above": 100,
        "below": 0,
        "want": ""
      },
      {
        "tag": "falls past",
        "prev": 51,
        "now": 49,
        "above": 0,
        "below": 50,
        "want": "below"
      },
      {
        "tag": "first seen",
        "prev": undefined,
        "now": 200,
        "above": 100,
        "below": 0,
        "want": ""
      },
      {
        "tag": "unset",
        "prev": 1,
        "now": 1000,
        "above": 0,
        "below": 0,
        "want": ""
      }
    ];
  }

  function test_crossed(data) {
    compare(MarketMath.crossed(data.prev, data.now, data.above, data.below), data.want);
  }

  function test_closes() {
    const points = [];
    for (let i = 0; i < 100; i++)
      points.push([i, i * 2]);
    const picked = MarketMath.closes(points, 10);
    compare(picked.length, 10);
    compare([picked[0], picked[9]], [0, 198], "first and last kept");
    compare(MarketMath.closes([[0, 1], [1, 2]], 10), [1, 2]);
    compare(MarketMath.closes(null, 10), []);
  }

  function test_spans() {
    const points = [[100, 5], [200, 9], [300, 7]];
    compare(MarketMath.timeSpan(points, 50, 250), {
      "start": 50,
      "end": 300
    }, "stretched to the last point");
    compare(MarketMath.timeSpan(points, 0, 0), {
      "start": 100,
      "end": 300
    });
    compare(MarketMath.timeSpan([], 0, 0).end, 1, "never empty");
    const span = MarketMath.priceSpan(points, 4);
    verify(span.min < 4 && span.max > 9);
    const flat = MarketMath.priceSpan([[0, 10], [1, 10]], 0);
    verify(flat.min < 10 && flat.max > 10, "a flat line sits mid-height");
  }
}
