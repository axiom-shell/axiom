import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "Utils"

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

  function test_freeId() {
    compare(Utils.freeId("dock", []), "dock");
    compare(Utils.freeId("dock", ["dock"]), "dock2");
    compare(Utils.freeId("dock2", ["dock", "dock2"]), "dock3");
    compare(Utils.freeId("dock5", ["dock5"]), "dock2", "the stem is numbered from 2");
    compare(Utils.freeId("bar-2", ["bar-1", "bar-2"], "-"), "bar-3");
    compare(Utils.freeId("bar-1", ["bar-1"], "-"), "bar-2");
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

  function test_curlConfigValue() {
    compare(Utils.curlConfigValue("plain"), "\"plain\"");
    compare(Utils.curlConfigValue("a\"b\\c"), "\"a\\\"b\\\\c\"");
    compare(Utils.curlConfigValue("line\nurl = evil"), "\"line\\nurl = evil\"");
    compare(Utils.curlConfigValue("cr\r"), "\"cr\\r\"");
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

  function test_contrast() {
    verify(Utils.isColorDark("#101010"));
    verify(!Utils.isColorDark("#f0f0f0"));
    compare(Utils.getContrastColor("#000000"), "#FFFFFF");
    compare(Utils.getContrastColor("#ffffff"), "#000000");
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

  function test_fadeable() {
    compare(Utils.fadeable("#ff0000", "#00ff00"), "#ff0000");
    const faded = Qt.color(Utils.fadeable("transparent", "#00000000", "#336699"));
    compare([faded.a, Math.round(faded.b * 255)], [0, 0x99]);
    compare(Qt.color(Utils.fadeable("transparent")).a, 0);
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
}
