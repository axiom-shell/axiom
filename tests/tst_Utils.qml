import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "Utils"

  RepoFiles {
    id: files
  }

  property Item item: Item {}

  Component {
    id: itemComponent

    Item {}
  }

  function test_valueAt() {
    const object = {
      "Bar": {
        "items": [
          {
            "id": "main"
          }
        ],
        "zero": 0,
        "empty": null
      }
    };
    const rows = [[["Bar", "items", 0, "id"], "main", "through an array index"], [["Bar", "zero"], 0, "a falsy value is kept"], [["Bar", "empty"], null, "null is kept"], [["Bar", "empty", "x"], undefined, "past null"], [["Bar", "missing", "deeper"], undefined, "past a missing key"], [[], object, "the empty path is the object"]];
    for (const [path, expected, message] of rows)
      compare(Utils.valueAt(object, path), expected, message);
    compare(Utils.valueAt(undefined, ["a"]), undefined, "no object");
  }

  function test_spaceWords() {
    compare(Utils.spaceWords("SystemTray"), "System Tray");
    compare(Utils.spaceWords("Grid2x2"), "Grid 2x2");
    compare(Utils.spaceWords("HalfWide"), "Half Wide");
    compare(Utils.spaceWords("Time"), "Time");
    compare(Utils.spaceWords(undefined), "");
  }

  // An enum value with no label, as the form shows it (check_i18n.py's
  // enum_label makes the same keys)
  function test_enumLabel() {
    compare(Utils.enumLabel("top"), "Top");
    compare(Utils.enumLabel("accentText"), "Accent text");
    compare(Utils.enumLabel("grid2x2"), "Grid 2x2");
    compare(Utils.enumLabel("on-overflow"), "on-overflow", "not lowerCamel: as it is");
    compare(Utils.enumLabel(""), "");
  }

  function test_edgeArrow() {
    compare(Utils.edgeArrow("top"), "arrow_upward");
    compare(Utils.edgeArrow("bottom"), "arrow_downward");
    compare(Utils.edgeArrow("left"), "arrow_back");
    compare(Utils.edgeArrow("right"), "arrow_forward");
  }

  function test_horizontalAlignment() {
    compare(Utils.horizontalAlignment("left"), Text.AlignLeft);
    compare(Utils.horizontalAlignment("center"), Text.AlignHCenter);
    compare(Utils.horizontalAlignment("right"), Text.AlignRight);
    compare(Utils.horizontalAlignment("sideways"), Text.AlignHCenter, "an unknown value centres, as Greeting, Login, Password and custom elements' align all did");
  }

  function test_freeId() {
    compare(Utils.freeId("dock", []), "dock");
    compare(Utils.freeId("dock", ["dock"]), "dock2");
    compare(Utils.freeId("dock2", ["dock", "dock2"]), "dock3");
    compare(Utils.freeId("dock5", ["dock5"]), "dock2", "the stem is numbered from 2");
    compare(Utils.freeId("bar-2", ["bar-1", "bar-2"], "-"), "bar-3");
    compare(Utils.freeId("bar-1", ["bar-1"], "-"), "bar-2");
  }

  function test_newId() {
    compare(Utils.newId("ClockCalendar", []), "clockCalendar");
    compare(Utils.newId("", null), "item");
    compare(Utils.newId("clock", [
      {
        "id": "clock"
      }
    ]), "clock-2");
    // A new monitor layout, as MonitorManager names it: "Layout 3" beside
    // two layouts, one without an id
    compare(Utils.newId(Utils.slug("Layout 3"), [
      {
        "id": "layout-1"
      },
      {}
    ]), "layout-3");
    compare(Utils.newId(Utils.slug("Layout 2"), [
      {
        "id": "layout-2"
      }
    ]), "layout-3", "a taken id is numbered on from its stem");
  }

  function test_keepEqual() {
    const id = e => e.id;
    const mk = (i, c) => ({
          "id": i,
          "c": Qt.color(c ?? "#ff0000"),
          "n": {
            "col": Qt.color(c ?? "#ff0000")
          }
        });
    const first = Utils.keepEqual({
      "items": [],
      "keys": []
    }, [mk("a"), mk("b")], id);
    compare(first.items.length, 2);
    compare(first.keys.length, 2);
    const same = Utils.keepEqual(first, [mk("a"), mk("b")], id);
    verify(same.items === first.items, "equal content keeps the array");
    const fresh = [mk("a"), mk("b", "#00ff00")];
    const changed = Utils.keepEqual(same, fresh, id);
    verify(changed.items !== first.items);
    verify(changed.items[0] === first.items[0]);
    verify(changed.items[1] === fresh[1]);
    const added = Utils.keepEqual(changed, [mk("a"), mk("b", "#00ff00"), mk("c")], id);
    verify(added.items !== changed.items);
    verify(added.items[0] === changed.items[0] && added.items[1] === changed.items[1]);
    const removed = Utils.keepEqual(added, [mk("b", "#00ff00")], id);
    compare(removed.items.length, 1);
    verify(removed.items[0] === changed.items[1]);
    const order = Utils.keepEqual(added, [mk("c"), mk("a"), mk("b", "#00ff00")], id);
    verify(order.items !== added.items);
    verify(order.items[0] === added.items[2] && order.items[1] === added.items[0]);
  }

  function test_deepEqual() {
    verify(Utils.deepEqual({
      "a": 1,
      "b": [1,
        {
          "c": null
        }
      ]
    }, {
      "b": [1,
        {
          "c": null
        }
      ],
      "a": 1
    }), "key order doesn't matter");
    verify(!Utils.deepEqual({
      "a": 1
    }, {
      "a": 1,
      "b": 2
    }));
    verify(!Utils.deepEqual({
      "a": undefined
    }, {
      "b": undefined
    }));
    verify(!Utils.deepEqual([1, 2], [2, 1]), "array order matters");
    verify(!Utils.deepEqual([], {}));
    verify(!Utils.deepEqual(null, {}));
    verify(!Utils.deepEqual("1", 1));
    verify(Utils.deepEqual("x", "x"));
    verify(Utils.deepEqual([Qt.rect(1, 2, 3, 4)], [Qt.rect(1, 2, 3, 4)]), "equal rects");
    verify(!Utils.deepEqual([Qt.rect(1, 2, 3, 4)], [Qt.rect(1, 2, 3, 5)]), "a rect's size differs");
    verify(!Utils.deepEqual([Qt.rect(1, 2, 3, 4)], [Qt.rect(1, 2, 3, 4), Qt.rect(0, 0, 1, 1)]), "a rect more");
  }

  function test_deepEqual_identity_data() {
    return [
      {
        "tag": "key order is ignored in plain data",
        "a": () => ({
              "x": 1,
              "y": [1, 2]
            }),
        "b": () => ({
              "y": [1, 2],
              "x": 1
            }),
        "equal": true
      },
      {
        "tag": "items differ by identity",
        "a": () => itemComponent.createObject(this),
        "b": () => itemComponent.createObject(this),
        "equal": false
      },
      {
        "tag": "one item equals itself",
        "a": () => this.item,
        "b": () => this.item,
        "equal": true
      },
      {
        "tag": "equal rects stay equal",
        "a": () => [Qt.rect(1, 2, 3, 4)],
        "b": () => [Qt.rect(1, 2, 3, 4)],
        "equal": true
      },
      {
        "tag": "equal points stay equal",
        "a": () => Qt.point(1, 2),
        "b": () => Qt.point(1, 2),
        "equal": true
      }
    ];
  }

  function test_deepEqual_identity(data) {
    compare(Utils.deepEqual(data.a.call(this), data.b.call(this)), data.equal);
  }

  function test_isPlainObject_data() {
    return [
      {
        "tag": "an object literal is plain",
        "value": () => ({}),
        "plain": true
      },
      {
        "tag": "an array is not plain",
        "value": () => [],
        "plain": false
      },
      {
        "tag": "null is not plain",
        "value": () => null,
        "plain": false
      },
      {
        "tag": "an item is not plain",
        "value": () => this.item,
        "plain": false
      }
    ];
  }

  function test_isPlainObject(data) {
    compare(Utils.isPlainObject(data.value.call(this)), data.plain);
  }

  function test_withEntry() {
    const map = {
      "a": 1,
      "b": 2
    };
    compare(Utils.withEntry(map, "c", 3), {
      "a": 1,
      "b": 2,
      "c": 3
    });
    compare(Utils.withEntry(map, "a", undefined), {
      "b": 2
    }, "undefined leaves it out");
    verify(Utils.withEntry(map, "a", 5) !== map, "a new object");
    compare(map.a, 1, "the original is untouched");

    const kept = new Map([["a", 1], ["b", 2]]);
    const set = Utils.withEntry(kept, "c", 3);
    verify(set instanceof Map && set !== kept, "a new Map");
    compare(set.get("c"), 3);
    const gone = Utils.withEntry(kept, "a", undefined);
    verify(!gone.has("a") && gone.has("b"), "undefined leaves it out of a Map");
    verify(kept.has("a") && !kept.has("c"), "the input Map is untouched");
  }

  function test_pick() {
    compare(Utils.pick({
      "a": 1,
      "b": 2,
      "c": 3
    }, ["c", "a", "x"]), {
      "c": 3,
      "a": 1
    }, "only the keys it has");
    compare(Utils.pick(null, ["a"]), {});
  }

  function test_clone() {
    const original = {
      "a": [1,
        {
          "b": 2
        }
      ]
    };
    const copy = Utils.clone(original);
    compare(copy, original);
    copy.a[1].b = 3;
    compare(original.a[1].b, 2);
    compare(Utils.clone(undefined), null);
  }

  function test_recordUse() {
    const first = Utils.recordUse({}, "x", 100);
    compare(first, {
      "x": {
        "count": 1,
        "last": 100
      }
    });
    const second = Utils.recordUse(first, "x", 200);
    compare(second.x, {
      "count": 2,
      "last": 200
    });
    // A new object; the old one is untouched
    compare(first.x.count, 1);
    compare(Utils.recordUse(null, "y", 5).y.count, 1);
  }

  function test_visualWidth_counts_wide_chars_twice() {
    compare(Utils.visualWidth("abc"), 3);
    compare(Utils.visualWidth("日本"), 4);
    compare(Utils.visualWidth("😀"), 1);
  }

  function test_truncate() {
    compare(Utils.truncate("short", 10), "short");
    compare(Utils.truncate("abcdefgh", 6), "abc...");
    compare(Utils.truncate("日本語テキスト", 7, "…"), "日本語…");
  }

  function test_rates() {
    compare(Utils.rateParts(0), [0, "B/s"]);
    compare(Utils.rateParts(900), [900, "B/s"]);
    compare(Utils.rateParts(1536), [1.5, "KB/s"]);
    compare(Utils.rateParts(512 * 1024), [512, "KB/s"]);
    compare(Utils.rateParts(3 * 1024 * 1024 * 1024 * 1024), [3072, "GB/s"]);
    compare(Utils.formatRate(1.5 * 1024 * 1024), "1.5 MB/s");
    compare(Utils.formatRate(undefined), "0 B/s");
  }

  function test_formatBytes() {
    compare(Utils.formatBytes(820), "820 B");
    compare(Utils.formatBytes(4.2 * 1024 * 1024), "4.2 MiB");
    compare(Utils.formatBytes(37 * 1024 * 1024 + 5000), "37 MiB");
    compare(Utils.formatBytes(1.25 * 1024 * 1024 * 1024), "1.3 GiB");
    compare(Utils.formatBytes(0), "0 B");
    compare(Utils.formatBytes(undefined), "0 B");
  }

  function test_formatSize() {
    compare(Utils.formatSize(512 * Utils.bytesPerGiB), "512G");
    compare(Utils.formatSize(1843 * Utils.bytesPerGiB), "1.8T");
  }

  function test_monthGrid() {
    // September 2026 starts on a Tuesday
    const sunday = Utils.monthGrid(2026, 8, 0, new Date(2026, 8, 26).toDateString());
    compare(sunday.length, 42);
    compare([sunday[0].day, sunday[0].month, sunday[0].inMonth], [30, 7, false]);
    compare([sunday[2].day, sunday[2].inMonth], [1, true]);
    compare(sunday.filter(d => d.isToday).map(d => d.day), [26]);
    compare([sunday[0].key, sunday[2].key, sunday[41].key], ["2026-08-30", "2026-09-01", "2026-10-10"]);
    const monday = Utils.monthGrid(2026, 8, 1, "");
    compare(monday[1].day, 1);
    // A month starting on the first day starts the grid
    compare(Utils.monthGrid(2026, 1, 0, "")[0].day, 1);
  }

  function test_subtractSpans() {
    compare(Utils.subtractSpans(0, 100, []), [
      {
        "start": 0,
        "end": 100
      }
    ]);
    compare(Utils.subtractSpans(0, 100, [
      {
        "start": 60,
        "end": 70
      },
      {
        "start": 20,
        "end": 40
      },
      {
        "start": 30,
        "end": 50
      }
    ]), [
      {
        "start": 0,
        "end": 20
      },
      {
        "start": 50,
        "end": 60
      },
      {
        "start": 70,
        "end": 100
      }
    ]);
    // Cuts past the ends, or outside it
    compare(Utils.subtractSpans(10, 90, [
      {
        "start": 0,
        "end": 20
      },
      {
        "start": 80,
        "end": 120
      },
      {
        "start": 200,
        "end": 300
      }
    ]), [
      {
        "start": 20,
        "end": 80
      }
    ]);
    compare(Utils.subtractSpans(10, 90, [
      {
        "start": 0,
        "end": 100
      }
    ]), []);
  }

  function test_firstFormRow() {
    const rows = [null,
      {
        "shown": false,
        "bodyHeight": 20
      },
      {
        "shown": true,
        "bodyHeight": 0
      },
      {
        "shown": undefined,
        "bodyHeight": 20
      },
      {
        "shown": true,
        "bodyHeight": 20
      }
    ];
    compare(Utils.firstFormRow(rows.length, i => rows[i]), 3, "skips missing, hidden and empty rows; unknown counts as shown");
    compare(Utils.firstFormRow(3, i => rows[i]), -1);
  }

  function test_isSymbolName() {
    verify(Utils.isSymbolName("terminal"));
    verify(!Utils.isSymbolName("Web"), "capitals: words");
    verify(!Utils.isSymbolName(""), "a glyph");
    verify(!Utils.isSymbolName(""));
  }

  function test_fromCelsius() {
    compare(Utils.fromCelsius(0, "celsius"), 0);
    compare(Utils.fromCelsius(0, "fahrenheit"), 32);
    compare(Utils.fromCelsius(100, "fahrenheit"), 212);
    compare(Utils.fromCelsius(-40, "fahrenheit"), -40);
    compare(Utils.fromCelsius(36.6, "celsius"), 36.6);
  }

  // The pieces are disjoint, inside `bounds`, none overlapping a rect, and
  // their area is `bounds`' less the rects' union (counted per unit cell)
  function checkRects(bounds, rects) {
    const pieces = Utils.subtractRects(bounds, rects);
    let area = 0;
    for (let i = 0; i < pieces.length; i++) {
      const p = pieces[i];
      verify(p.x >= bounds.x && p.y >= bounds.y && p.x + p.width <= bounds.x + bounds.width && p.y + p.height <= bounds.y + bounds.height, "inside bounds");
      for (let j = i + 1; j < pieces.length; j++) {
        const q = pieces[j];
        verify(p.x >= q.x + q.width || q.x >= p.x + p.width || p.y >= q.y + q.height || q.y >= p.y + p.height, "disjoint");
      }
      for (const r of rects)
        verify(p.x >= r.x + r.width || r.x >= p.x + p.width || p.y >= r.y + r.height || r.y >= p.y + p.height, "outside the rects");
      area += p.width * p.height;
    }
    let covered = 0;
    for (let y = bounds.y; y < bounds.y + bounds.height; y++) {
      for (let x = bounds.x; x < bounds.x + bounds.width; x++) {
        if (rects.some(r => x >= r.x && x < r.x + r.width && y >= r.y && y < r.y + r.height))
          covered++;
      }
    }
    compare(area, bounds.width * bounds.height - covered);
    return pieces;
  }

  function test_subtractRects() {
    const bounds = Qt.rect(10, 10, 100, 50);
    // None taken
    compare(checkRects(bounds, []).length, 1);
    compare(checkRects(bounds, [Qt.rect(200, 200, 5, 5)]).length, 1);
    // One inside: four pieces
    compare(checkRects(bounds, [Qt.rect(30, 20, 10, 10)]).length, 4);
    // One reaching past an edge
    checkRects(bounds, [Qt.rect(100, 40, 50, 50)]);
    // Two overlapping
    checkRects(bounds, [Qt.rect(20, 15, 40, 20), Qt.rect(40, 25, 40, 30)]);
    // One covering all
    compare(checkRects(bounds, [Qt.rect(0, 0, 200, 200)]), []);
  }

  function test_insetUnion() {
    const flat = rs => rs.map(r => [r.x, r.y, r.width, r.height]);
    const bounds = Qt.rect(0, 0, 100, 100);
    // Two meeting at x 30: the shared edge stays
    compare(flat(Utils.insetUnion(bounds, [Qt.rect(10, 10, 20, 10), Qt.rect(30, 10, 20, 10)], 0.5)), [[10.5, 10.5, 39, 9]]);
    // An L
    compare(flat(Utils.insetUnion(bounds, [Qt.rect(10, 10, 40, 4), Qt.rect(46, 14, 4, 6)], 0.25)), [[10.25, 10.25, 39.5, 3.5], [46.25, 13.75, 3.5, 0.5], [46.25, 14.25, 3.5, 5.5]]);
    // By 0: as it is
    compare(flat(Utils.insetUnion(bounds, [Qt.rect(10, 10, 20, 10)], 0)), [[10, 10, 20, 10]]);
    // None
    compare(Utils.insetUnion(bounds, [], 0.5), []);
    // One reaching past bounds: its edge on bounds stays
    compare(flat(Utils.insetUnion(bounds, [Qt.rect(90, 40, 20, 10)], 0.5)), [[90.5, 40.5, 9.5, 9]]);
  }

  function test_subtractHoles() {
    const flat = rs => rs.map(r => [r.x, r.y, r.width, r.height]);
    const bounds = Qt.rect(0, 0, 100, 100);
    const t = Utils.tieInset;
    // No holes: bounds as it is
    compare(flat(Utils.subtractHoles(bounds, [])), [[0, 0, 100, 100]]);
    // One hole: its edges drawn in by tieInset
    const one = Utils.subtractHoles(bounds, [Qt.rect(10, 10, 20, 10)]);
    compare(flat(one), flat(Utils.subtractRects(bounds, [Qt.rect(10 + t, 10 + t, 20 - 2 * t, 10 - 2 * t)])));
    verify(t > 0);
    // Two meeting at x 30: the shared edge keeps its place
    compare(flat(Utils.subtractHoles(bounds, [Qt.rect(10, 10, 20, 10), Qt.rect(30, 10, 20, 10)])), flat(Utils.subtractRects(bounds, [Qt.rect(10 + t, 10 + t, 40 - 2 * t, 10 - 2 * t)])));
    // One past bounds: its edge on bounds stays
    compare(flat(Utils.subtractHoles(bounds, [Qt.rect(90, 40, 20, 10)])), flat(Utils.subtractRects(bounds, [Qt.rect(90 + t, 40 + t, 10 - t, 10 - 2 * t)])));
  }

  function test_cut_rule_has_one_place() {
    // The holes' cut is Utils.subtractHoles: no other file calls insetUnion
    for (const path of ["qml/components/methods/FrameOutline.qml", "qml/components/reusable/HoledCopy.qml"]) {
      const source = files.text(path);
      verify(source.indexOf("insetUnion(") < 0, path);
      verify(source.indexOf("Utils.subtractHoles(") >= 0, path);
    }
  }

  function test_temperatureSymbol() {
    compare(Utils.temperatureSymbol("celsius"), "°C");
    compare(Utils.temperatureSymbol("fahrenheit"), "°F");
  }
}
