import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "CustomWidgetData"

  function test_parse() {
    const json = {
      "text": "3",
      "alt": "pending"
    };
    compare(CustomWidgetData.parse("{…}", json, "waybar", false), json, "waybar json: the object");
    compare(CustomWidgetData.parse("a\nb\nwarning", undefined, "waybar", false), {
      "text": "a",
      "tooltip": "b",
      "class": "warning"
    }, "waybar text: text, tooltip, class lines");
    compare(CustomWidgetData.parse("▁▂▃", undefined, "waybar", true), {
      "text": "▁▂▃"
    }, "a streamed line is only text");
    compare(CustomWidgetData.parse("42", 42, "json", false), {
      "text": "42",
      "value": 42
    }, "json scalar");
    compare(CustomWidgetData.parse("{\"a\":1}", {
      "a": 1
    }, "text", false), {
      "text": "{\"a\":1}"
    }, "text ignores the JSON");
  }

  function test_flatten() {
    const paths = CustomWidgetData.flatten({
      "text": "x",
      "data": {
        "temp": 21.5,
        "ok": true
      },
      "items": [
        {
          "text": "a"
        },
        {
          "text": "b"
        },
        {
          "text": "c"
        },
        {
          "text": "d"
        }
      ]
    });
    const byPath = paths.reduce((m, p) => {
      m[p.path] = p;
      return m;
    }, {});
    compare(byPath["data.temp"].type, "number");
    compare(byPath["data.ok"].value, true);
    compare(byPath["items"].type, "array");
    compare(byPath["items"].value, 4, "an array's value is its length");
    compare(byPath["items.2.text"].value, "c");
    verify(!("items.3" in byPath), "only the first three entries");
  }

  function test_fill() {
    const values = {
      "_sample": {
        "data": {
          "temp": 21
        }
      },
      "text": "hi",
      "icon": "★"
    };
    compare(CustomWidgetData.fill("{icon} {}", values), "★ hi");
    compare(CustomWidgetData.fill("{0}!", values), "hi!", "{0} is the text (waybar-updates)");
    compare(CustomWidgetData.fill("{data.temp}°", values), "21°", "a path in the sample");
    compare(CustomWidgetData.fill("{text:>5}|{nope}|", values), "hi||", "spec ignored, unknown empty");
  }

  function test_pickIcon() {
    const bars = ["▁", "▂", "▃", "▄"];
    compare(CustomWidgetData.pickIcon(bars, "", 0), "▁");
    compare(CustomWidgetData.pickIcon(bars, "", 49), "▂");
    compare(CustomWidgetData.pickIcon(bars, "", 100), "▄", "100 is the last");
    const map = {
      "spotify": "S",
      "default": "D"
    };
    compare(CustomWidgetData.pickIcon(map, "spotify", 0), "S");
    compare(CustomWidgetData.pickIcon(map, "firefox", 0), "D", "unknown alt: default");
    compare(CustomWidgetData.pickIcon({
      "charging": ["a", "b"]
    }, "charging", 80), "b", "an alt's entry may be an array");
    compare(CustomWidgetData.pickIcon(undefined, "x", 1), "");
  }

  function test_states() {
    compare(CustomWidgetData.classes(["a", "b"]), ["a", "b"]);
    compare(CustomWidgetData.classes("a b"), ["a", "b"]);
    compare(CustomWidgetData.stateColor("", ["custom-spotify", "critical"], {}), "error");
    compare(CustomWidgetData.stateColor("", ["playing"], {
      "playing": "accent"
    }), "accent", "a definition's own state");
    compare(CustomWidgetData.stateColor("warning", [], {}), "warning", "state over classes");
    compare(CustomWidgetData.stateColor("#ff0000", [], {}), "#ff0000", "a colour passes");
    compare(CustomWidgetData.stateColor("", ["x"], {}), "");
  }

  function test_pango() {
    compare(CustomWidgetData.pango("<span foreground='#f00' weight=\"bold\">a</span>"), "<span style=\"color:#f00;font-weight:bold\">a</span>");
    compare(CustomWidgetData.pango("<span size='16pt'>x</span>"), "<span style=\"font-size:16pt\">x</span>");
    compare(CustomWidgetData.pango("<span size='20480'>x</span>"), "<span style=\"font-size:20pt\">x</span>", "1024ths of a point");
    compare(CustomWidgetData.pango("<b>a</b>\nb"), "<b>a</b><br>b");
    compare(CustomWidgetData.plain("<b>a&amp;b</b><br>c"), "a&b\nc");
  }

  function test_resolve() {
    const d = {
      "format": "{icon} {}",
      "formatIcons": {
        "pending-updates": "U",
        "default": "-"
      },
      "escape": true
    };
    const f = CustomWidgetData.resolve(d, {
      "text": "3 <new>",
      "alt": "pending-updates",
      "class": "warning",
      "tooltip": "a\nb"
    });
    compare(f.text, "U 3 &lt;new&gt;", "escape before the format");
    compare(f.plain, "U 3 <new>");
    compare(f.tooltip, "a<br>b");
    compare(f.color, "warning");
    compare(f.ratio, -1, "no value");
    verify(!f.hidden);
  }

  function test_resolveValue() {
    const p = CustomWidgetData.resolve({}, {
      "text": "40%",
      "percentage": 40
    });
    compare(p.value, 40);
    compare(p.ratio, 0.4, "percentage is the value on 0-100");
    const v = CustomWidgetData.resolve({
      "fields": {
        "value": "mem.used",
        "max": "mem.total",
        "subtext": "of {mem.total} GiB"
      }
    }, {
      "text": "x",
      "mem": {
        "used": 4,
        "total": 16
      }
    });
    compare(v.ratio, 0.25, "bound paths");
    compare(v.subtext, "of 16 GiB", "a bound format");
  }

  function test_resolveHidden() {
    verify(CustomWidgetData.resolve({}, {
      "text": ""
    }).hidden, "empty text hides, as Waybar");
    verify(!CustomWidgetData.resolve({
      "hideEmpty": false
    }, {
      "text": ""
    }).hidden);
    verify(CustomWidgetData.resolve({
      "format": "{icon} {}",
      "formatIcons": {
        "default": "♪"
      }
    }, {
      "text": ""
    }).hidden, "the format's icon alone doesn't show it");
    verify(CustomWidgetData.resolve({}, {
      "text": "x",
      "hidden": true
    }).hidden);
    compare(CustomWidgetData.resolve({
      "maxLength": 4
    }, {
      "text": "abcdefg"
    }).text, "abc…");
  }

  function test_items() {
    const f = CustomWidgetData.resolve({}, {
      "text": "x",
      "items": ["a",
        {
          "text": "b",
          "value": 2
        }
      ]
    });
    compare(f.items.length, 2);
    compare(f.items[0].text, "a");
    compare(f.items[1].value, 2);
  }

  function test_elementValue() {
    const f = CustomWidgetData.resolve({}, {
      "text": "x",
      "percentage": 50,
      "cpu": {
        "temp": 70
      }
    });
    compare(CustomWidgetData.elementValue(f, "percentage"), 50, "a field");
    compare(CustomWidgetData.elementValue(f, "cpu.temp"), 70, "a path");
    compare(CustomWidgetData.elementValue(f, "{cpu.temp}°C"), "70°C", "a format");
    compare(CustomWidgetData.elementRatio(f, "", 0, 100), 0.5, "no binding: the ratio");
    compare(CustomWidgetData.elementRatio(f, "cpu.temp", 20, 120), 0.5);
  }

  function test_lattice() {
    compare(CustomWidgetData.lattice([4, 2]), {
      "cols": 16,
      "rows": 8
    }, "16 sub-cells a card");
    const r = CustomWidgetData.rect({
      "x": 8,
      "y": 0,
      "w": 8,
      "h": 8
    }, {
      "cols": 16,
      "rows": 8
    }, 210, 100, 10);
    compare(r, {
      "x": 110,
      "y": 0,
      "width": 100,
      "height": 100
    }, "half the width, a gap between");
  }

  function test_scaleElements() {
    const scaled = CustomWidgetData.scaleElements([
      {
        "id": "a",
        "place": {
          "x": 8,
          "y": 4,
          "w": 8,
          "h": 4
        }
      }
    ], [4, 2], [2, 2]);
    compare(scaled[0].place, {
      "x": 4,
      "y": 4,
      "w": 4,
      "h": 4
    });
    compare(scaled[0].id, "a");
    const tiny = CustomWidgetData.scaleElements([
      {
        "place": {
          "x": 15,
          "y": 0,
          "w": 1,
          "h": 1
        }
      }
    ], [4, 2], [1, 1]);
    compare(tiny[0].place, {
      "x": 3,
      "y": 0,
      "w": 1,
      "h": 1
    }, "at least a sub-cell, inside the lattice");
  }

  function test_defaultElements() {
    const els = CustomWidgetData.defaultElements([4, 2], true);
    compare(els.length, 2);
    compare(els[0].kind, "Ring");
    compare(els[1].place.x + els[1].place.w, 16, "the text fills the rest");
    compare(CustomWidgetData.defaultElements([4, 2], false)[0].kind, "Icon");
  }
}
