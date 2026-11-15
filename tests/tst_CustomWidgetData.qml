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
    }, 3);
    const byPath = paths.reduce((m, p) => {
      m[p.path] = p;
      return m;
    }, {});
    compare(byPath["data.temp"].type, "number");
    compare(byPath["data.ok"].value, true);
    compare(byPath["items"].type, "array");
    compare(byPath["items"].value, 4, "an array's value is its length");
    compare(byPath["items.2.text"].value, "c");
    verify(!("items.3" in byPath), "only the first maxItems entries");
    compare(CustomWidgetData.flatten({
      "items": [1, 2, 3, 4, 5]
    }).filter(p => /^items\.\d$/.test(p.path)).length, 5, "every entry of a short list by default");
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
    const names = ["accent", "warning", "error", "success"];
    compare(CustomWidgetData.classes(["a", "b"]), ["a", "b"]);
    compare(CustomWidgetData.classes("a b"), ["a", "b"]);
    compare(CustomWidgetData.stateColor("", ["custom-spotify", "critical"], {}, names), "error");
    compare(CustomWidgetData.stateColor("", ["playing"], {
      "playing": "accent"
    }, names), "accent", "a definition's own state");
    compare(CustomWidgetData.stateColor("front", [], {
      "front": "accent"
    }, names), "accent", "a state is a mode, mapped by states");
    compare(CustomWidgetData.stateColor("front", [], {}, names), "", "an unmapped word colours nothing");
    compare(CustomWidgetData.stateColor("warning", [], {}, names), "warning", "state over classes");
    compare(CustomWidgetData.stateColor("accent", [], {}, names), "accent", "a theme name passes");
    compare(CustomWidgetData.stateColor("#ff0000", [], {}, names), "", "a hex colours nothing");
    compare(CustomWidgetData.stateColor("", ["x"], {}, names), "");
    compare(CustomWidgetData.stateColor("zzz", ["critical"], {}, names), "error", "an unmapped state falls to the classes");
    compare(CustomWidgetData.stateColor("constructor", [], {}, names), "", "not an Object member");
    compare(CustomWidgetData.stateColor("accent", [], {}), "", "no colour names: a theme name isn't known");
  }

  function test_isThemeColor() {
    verify(CustomWidgetData.isThemeColor("accent", ["accent", "error"]));
    verify(!CustomWidgetData.isThemeColor("#ff0000", ["accent"]));
    verify(!CustomWidgetData.isThemeColor("front", ["accent"]));
    verify(!CustomWidgetData.isThemeColor("accent", undefined), "no names: false");
  }

  function test_truthy() {
    for (const on of [true, 1, -2, 0.5, "yes", "true", "1", "x", [0],
      {
        "a": 1
      }
    ])
      verify(CustomWidgetData.truthy(on), JSON.stringify(on));
    for (const off of [false, 0, NaN, Infinity, "", "false", "FALSE", "0", "No", "off", " Off ", [],
      {},
      null, undefined])
      verify(!CustomWidgetData.truthy(off), String(off));
  }

  function test_actionsOf() {
    compare(CustomWidgetData.actionsOf(undefined), null, "missing");
    compare(CustomWidgetData.actionsOf("x"), null, "not an object");
    compare(CustomWidgetData.actionsOf([1]), null, "a list");
    compare(CustomWidgetData.actionsOf({
      "undo": {
        "enabled": false
      },
      "next": {},
      "a": {
        "enabled": "no"
      },
      "b": {
        "enabled": "false"
      },
      "c": {
        "enabled": "yes"
      },
      "bad id": {},
      "axiom:refresh": {},
      "": {}
    }), {
      "undo": {
        "enabled": false
      },
      "next": {
        "enabled": true
      },
      "a": {
        "enabled": false
      },
      "b": {
        "enabled": false
      },
      "c": {
        "enabled": true
      }
    });
    compare(CustomWidgetData.actionsOf({}), {}, "an empty list: every action off");
    const own = CustomWidgetData.actionsOf(JSON.parse('{"__proto__":{"enabled":false},"constructor":{},"ok":{}}'));
    compare(Object.keys(own), ["ok"], "names every object has aren't action ids");
    verify(Object.getPrototypeOf(own) === Object.prototype, "the prototype stays");
  }

  readonly property var _words: ({
      "exited": "exited {0}",
      "exitedWith": "exited {0}: {1}"
    })

  function _ctx(interactive, stream) {
    return {
      "interactive": interactive,
      "stream": stream,
      "words": _words
    };
  }

  function test_failure() {
    const sample = {
      "text": "x"
    };
    const ok = {
      "exitCode": 0,
      "error": "",
      "stderr": "",
      "text": "x",
      "exited": false
    };
    const start = CustomWidgetData.failure(sample, {
      "exitCode": -1,
      "error": "no such file",
      "stderr": "",
      "text": "",
      "exited": false
    }, _ctx(true, false));
    compare(start.kind, "start");
    compare(start.message, "no such file");
    const stopped = CustomWidgetData.failure(sample, {
      "exitCode": 3,
      "error": "",
      "stderr": "boom",
      "text": "",
      "exited": true
    }, _ctx(true, true));
    compare(stopped.kind, "stopped");
    compare(stopped.message, "exited 3: boom");
    compare(stopped.exitCode, 3);
    compare(stopped.stderr, "boom");
    compare(CustomWidgetData.failure(sample, {
      "exitCode": 3,
      "error": "",
      "stderr": "",
      "text": "",
      "exited": true
    }, _ctx(true, true)).message, "exited 3", "no stderr line");
    compare(CustomWidgetData.failure(sample, {
      "exitCode": 1,
      "error": "",
      "stderr": "",
      "text": "",
      "exited": false
    }, _ctx(true, false)).kind, "exit", "a poll exiting non-zero with no output");
    compare(CustomWidgetData.failure({
      "error": "bad"
    }, ok, _ctx(true, false)).kind, "script");
    compare(CustomWidgetData.failure({
      "error": "bad"
    }, ok, _ctx(true, false)).message, "bad");
    // Precedence
    compare(CustomWidgetData.failure({
      "error": "bad"
    }, {
      "exitCode": 3,
      "error": "",
      "stderr": "boom",
      "text": "{\"error\":\"bad\"}",
      "exited": true
    }, _ctx(true, true)).kind, "stopped", "a stopped stream whose last sample has an error");
    compare(CustomWidgetData.failure({
      "error": "bad"
    }, {
      "exitCode": -1,
      "error": "x",
      "stderr": "",
      "text": "",
      "exited": false
    }, _ctx(true, false)).kind, "start", "start before script");
    // No failure
    compare(CustomWidgetData.failure(sample, {}, _ctx(true, false)), null, "an empty run");
    compare(CustomWidgetData.failure(sample, undefined, _ctx(true, false)), null, "no run");
    compare(CustomWidgetData.failure(sample, {
      "exitCode": 1,
      "text": ""
    }, _ctx(false, false)), null, "non-interactive exit 1 with no text");
    compare(CustomWidgetData.failure({
      "error": "bad"
    }, ok, _ctx(false, false)), null, "non-interactive error");
    compare(CustomWidgetData.failure(sample, {
      "exitCode": 1,
      "error": "",
      "stderr": "",
      "text": "some output",
      "exited": false
    }, _ctx(true, false)), null, "non-zero with output, not a stream");
    compare(CustomWidgetData.failure(sample, {
      "exitCode": 0,
      "error": "",
      "stderr": "",
      "text": "x",
      "exited": true
    }, _ctx(true, true)), null, "a stream that exited 0");
    compare(CustomWidgetData.failure({
      "error": ""
    }, ok, _ctx(true, false)), null, "an empty error");
    for (const off of [false, 0,
      {},
      "  "])
      compare(CustomWidgetData.failure({
        "error": off
      }, ok, _ctx(true, false)), null, "error " + JSON.stringify(off) + " is no error");
    const on = CustomWidgetData.failure({
      "error": true
    }, ok, _ctx(true, false));
    compare(on.kind, "script", "error true");
    compare(on.message, "true");
    compare(CustomWidgetData.failure(sample, ok, undefined), null, "no context");
    compare(CustomWidgetData.failure(sample, {
      "exitCode": 3,
      "error": "",
      "stderr": "",
      "text": "",
      "exited": true
    }, {
      "interactive": true,
      "stream": true
    }).message, "", "words missing");
  }

  function test_resolveContext() {
    const names = ["accent", "error"];
    const f = CustomWidgetData.resolve({
      "states": {
        "front": "accent"
      }
    }, {
      "text": "x",
      "state": "front",
      "rev": 4,
      "actions": {
        "undo": {
          "enabled": false
        }
      }
    }, {
      "colorNames": names
    });
    compare(f.color, "accent", "state through states");
    compare(f.state, "front");
    compare(f.rev, "4");
    compare(f.actions.undo.enabled, false);
    compare(f.failure, null);
    compare(f.error, "");
    verify(!f.interactive);
    compare(CustomWidgetData.resolve({}, {
      "text": "x",
      "state": "back"
    }, {
      "colorNames": names
    }).color, "", "without the entry, the widget's own colour");
    compare(CustomWidgetData.resolve({}, {
      "text": "x",
      "state": "#ff0000"
    }, {
      "colorNames": names
    }).color, "", "a hex colours nothing");
    compare(CustomWidgetData.resolve({}, {
      "text": "x"
    }).actions, null);
    // A failing, interactive widget isn't hidden for want of text
    const failing = CustomWidgetData.resolve({}, {
      "error": "boom"
    }, {
      "interactive": true,
      "stream": false,
      "words": _words,
      "run": {
        "exitCode": 0,
        "error": "",
        "stderr": "",
        "text": "{}",
        "exited": false
      }
    });
    compare(failing.error, "boom");
    compare(failing.failure.kind, "script");
    verify(!failing.hidden, "not hidden while failing");
    verify(!failing.hiddenByScript);
    verify(failing.interactive);
    // The same sample, not interactive: hidden as Waybar hides empty text
    const quiet = CustomWidgetData.resolve({}, {
      "error": "boom"
    }, {
      "interactive": false
    });
    verify(quiet.hidden);
    compare(quiet.error, "");
    // An error of false doesn't fail, and the script's own hidden stands
    const off = CustomWidgetData.resolve({}, {
      "text": "",
      "error": false,
      "hidden": true
    }, {
      "interactive": true,
      "stream": false,
      "words": _words
    });
    compare(off.failure, null);
    verify(off.hidden, "hidden by the script");
    // hidden by the script, apart from empty text
    const byScript = CustomWidgetData.resolve({}, {
      "text": "x",
      "hidden": "true"
    });
    verify(byScript.hiddenByScript);
    verify(byScript.hidden);
    // A sample's own bookkeeping-named keys bind to the sample's value
    compare(CustomWidgetData.elementValue(CustomWidgetData.resolve({}, {
      "text": "x",
      "interactive": "mine"
    }), "interactive"), "mine");
    compare(CustomWidgetData.elementValue(CustomWidgetData.resolve({}, {
      "text": "x",
      "failure": "mine"
    }), "failure"), "mine");
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

  // The bar widget's tooltip: a multi-line Pango tooltip, as rich text
  function test_resolveTooltip() {
    const f = CustomWidgetData.resolve({}, {
      "text": "x",
      "tooltip": "<span foreground='#f00'>CPU</span> 40%\n<b>RAM</b> 3 GiB"
    });
    compare(f.tooltip, "<span style=\"color:#f00\">CPU</span> 40%<br><b>RAM</b> 3 GiB");
    compare(CustomWidgetData.resolve({}, {
      "text": "x"
    }).tooltip, "", "none: no tooltip");
  }

  function test_resolveValue() {
    const p = CustomWidgetData.resolve({}, {
      "text": "40%",
      "percentage": 40
    });
    compare(p.value, 40);
    compare(p.ratio, 0.4, "percentage is the value on 0-100");
    const v = CustomWidgetData.resolve({}, {
      "text": "x",
      "value": 4,
      "max": 16
    });
    compare(v.ratio, 0.25, "the script's own max");
    compare(CustomWidgetData.resolve({}, {
      "text": "37"
    }).value, 37, "text that's a number is the value");
    compare(CustomWidgetData.resolve({}, {
      "text": "37 %"
    }).ratio, 0.37);
    compare(CustomWidgetData.resolve({}, {
      "text": "37",
      "percentage": 50
    }).value, 50, "a percentage wins over the text");
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
    compare(CustomWidgetData.elementValue(f, "100"), 100, "a number typed");
    compare(CustomWidgetData.elementValue(f, "=Show answer"), "Show answer", "a literal");
    compare(CustomWidgetData.elementValue(f, "=5"), "5", "a literal number is text");
    compare(CustomWidgetData.elementValue(f, "={x}"), "{x}", "a literal format is not filled");
    compare(CustomWidgetData.elementValue(f, "="), "", "an empty literal");
    compare(CustomWidgetData.elementValue(f, "=cpu.temp"), "cpu.temp", "a literal is no path");
    compare(CustomWidgetData.elementRatio(f, {}), 0.5, "no binding: the output's own");
    compare(CustomWidgetData.elementRatio(f, {
      "value": "cpu.temp",
      "min": "20",
      "max": "120"
    }), 0.5, "value, min and max bound");
    const mem = CustomWidgetData.resolve({}, {
      "text": "x",
      "value": 5,
      "max": 20,
      "items": [
        {
          "value": 10
        }
      ]
    });
    compare(CustomWidgetData.elementRatio(mem, {}), 0.25, "the output's max, not 100");
    compare(CustomWidgetData.elementRatio(mem, {
      "value": "items.0.value"
    }), 0.5, "a bound value keeps the output's max");
    compare(CustomWidgetData.elementRange(mem, {
      "value": "nope"
    }).value, undefined);
  }

  // resolve hands states and colorNames on for `tone`; a sample's own keys
  // of those names still bind to the sample (C-B9)
  function test_resolveStatesAndOwnKeys() {
    const states = {
      "low": "error"
    };
    const names = ["accent", "error"];
    const f = CustomWidgetData.resolve({
      "states": states
    }, {
      "text": "x"
    }, {
      "colorNames": names
    });
    compare(f.states, states, "the definition's map");
    compare(f.colorNames, names, "the context's names");
    compare(CustomWidgetData.resolve({}, {
      "text": "x"
    }).colorNames, [], "no context: none");
    const own = CustomWidgetData.resolve({
      "states": states
    }, {
      "text": "x",
      "states": "mine",
      "actions": "ours",
      "failure": "f",
      "colorNames": "c",
      "interactive": "i"
    });
    compare(CustomWidgetData.elementValue(own, "states"), "mine", "a sample's own states");
    compare(CustomWidgetData.elementValue(own, "actions"), "ours", "its own actions");
    compare(CustomWidgetData.elementValue(own, "failure"), "f", "its own failure");
    compare(CustomWidgetData.elementValue(own, "colorNames"), "c", "its own colorNames");
    compare(CustomWidgetData.elementValue(own, "interactive"), "i", "its own interactive");
    compare(CustomWidgetData.elementValue(own, "{states}"), "mine", "a format reads the sample's too");
  }

  function test_elementShown() {
    const f = CustomWidgetData.resolve({}, {
      "text": "x",
      "on": true,
      "off": false,
      "zero": "0",
      "blank": "",
      "word": "yes"
    });
    verify(CustomWidgetData.elementShown(f, undefined), "no bind: shown");
    verify(CustomWidgetData.elementShown(f, {}), "no show: shown");
    verify(CustomWidgetData.elementShown(f, {
      "show": "on"
    }), "true");
    verify(!CustomWidgetData.elementShown(f, {
      "show": "off"
    }), "false");
    verify(!CustomWidgetData.elementShown(f, {
      "show": "zero"
    }), "\"0\"");
    verify(!CustomWidgetData.elementShown(f, {
      "show": "blank"
    }), "empty");
    verify(!CustomWidgetData.elementShown(f, {
      "show": "missing.path"
    }), "a missing path");
    verify(CustomWidgetData.elementShown(f, {
      "show": "word"
    }), "yes");
    verify(CustomWidgetData.elementShown(f, {
      "show": "=1"
    }), "a literal 1");
  }

  function test_elementTone() {
    const f = CustomWidgetData.resolve({
      "states": {
        "low": "error",
        "playing": "accent"
      }
    }, {
      "text": "x",
      "level": "low",
      "mode": "playing",
      "other": "nope",
      "hex": "#ff0000",
      "theme": "warning",
      "class": "critical",
      "kind": "critical"
    }, {
      "colorNames": ["accent", "error", "warning"]
    });
    compare(CustomWidgetData.elementTone(f, {
      "tone": "level"
    }), "error", "a word in states");
    compare(CustomWidgetData.elementTone(f, {
      "tone": "mode"
    }), "accent");
    compare(CustomWidgetData.elementTone(f, {
      "tone": "theme"
    }), "warning", "a theme name passes through");
    compare(CustomWidgetData.elementTone(f, {
      "tone": "hex"
    }), "", "a hex colours nothing");
    compare(CustomWidgetData.elementTone(f, {
      "tone": "other"
    }), "", "an unknown word");
    compare(CustomWidgetData.elementTone(f, {
      "tone": "kind"
    }), "error", "a built-in state word");
    compare(CustomWidgetData.elementTone(f, {}), "", "unbound");
    compare(CustomWidgetData.elementTone(f, undefined), "", "no bind");
    compare(CustomWidgetData.elementTone(f, {
      "tone": "toString"
    }), "", "a word naming an Object member is no state");
    compare(CustomWidgetData.elementTone(f, {
      "tone": "=error"
    }), "error", "a literal word");
  }

  function test_lattice() {
    compare(CustomWidgetData.lattice([], [4, 2]), {
      "cols": 16,
      "rows": 8
    }, "16 sub-cells a card");
    const els = [
      {
        "place": {
          "x": 0,
          "y": 0,
          "w": 6,
          "h": 2
        }
      },
      {
        "place": {
          "x": 2,
          "y": 2,
          "w": 8,
          "h": 3
        }
      }
    ];
    compare(CustomWidgetData.lattice(els, [4, 2]), {
      "cols": 10,
      "rows": 5
    }, "the box fits the elements");
    compare(CustomWidgetData.designSize(els, [4, 2]), [2.5, 1.25]);
    compare(CustomWidgetData.pageSize(els, [4, 2]), [3, 2], "whole units on a page");
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
    compare(CustomWidgetData.rect(undefined, {
      "cols": 16,
      "rows": 8
    }, 210, 100, 10), {
      "x": 0,
      "y": 0,
      "width": 0,
      "height": 0
    }, "no place yet: an empty rect");
  }

  function test_rows() {
    compare(CustomWidgetData.rows([
      {
        "text": "a",
        "value": "3"
      },
      "b"]), [
      {
        "text": "a",
        "icon": "",
        "value": 3,
        "subtext": "",
        "id": "",
        "state": "",
        "max": undefined,
        "image": ""
      },
      {
        "text": "b",
        "icon": "",
        "value": undefined,
        "subtext": "",
        "id": "",
        "state": "",
        "max": undefined,
        "image": ""
      }
    ], "objects read, plain entries are their text");
    compare(CustomWidgetData.rows([
      {
        "text": "a",
        "id": "/home"
      },
      {
        "text": "b",
        "id": 7
      }
    ])[0].id, "/home", "an id is kept");
    compare(CustomWidgetData.rows([
      {
        "text": "b",
        "id": 7
      }
    ])[0].id, "7", "an id is text");
    compare(CustomWidgetData.rows(["plain"])[0].id, "", "a plain string has no id");
    compare(CustomWidgetData.rows("nope"), [], "not a list: none");
    const full = CustomWidgetData.rows([
      {
        "text": "/",
        "value": 40,
        "max": "200",
        "state": "warning",
        "image": "/tmp/a.png"
      }
    ])[0];
    compare(full.max, 200, "a max is a number");
    compare(full.state, "warning", "a state is kept");
    compare(full.image, "/tmp/a.png", "an image is kept");
    compare(CustomWidgetData.rows([
      {
        "text": "a",
        "max": 10
      }
    ])[0].max, undefined, "a max without a value");
    compare(CustomWidgetData.rows([
      {
        "text": "a",
        "value": 3,
        "max": 0
      }
    ])[0].max, undefined, "a max of 0");
    compare(CustomWidgetData.rows([
      {
        "text": "a",
        "value": "x",
        "max": 10
      }
    ])[0].max, undefined, "a value that is no number");
    compare(CustomWidgetData.rows([
      {
        "text": "a",
        "value": 3,
        "max": -5
      }
    ])[0].max, undefined, "a negative max");
  }

  function test_graphRange() {
    const def = {
      "format": "{}"
    };
    compare(CustomWidgetData.graphRange(CustomWidgetData.resolve(def, {
      "value": 3
    }), {}), {
      "min": 0,
      "max": 0
    }, "no max in the output: scale to the largest");
    compare(CustomWidgetData.graphRange(CustomWidgetData.resolve(def, {
      "value": 3,
      "min": 1,
      "max": 8
    }), {}), {
      "min": 1,
      "max": 8
    }, "the output's own");
    compare(CustomWidgetData.graphRange(CustomWidgetData.resolve(def, {
      "text": "x",
      "percentage": 40
    }), {}).max, 100, "a percentage goes to 100");
    compare(CustomWidgetData.graphRange(CustomWidgetData.resolve(def, {
      "value": 3
    }), {
      "max": "50"
    }).max, 50, "a bound max");
  }

  function test_defaultElements() {
    const els = CustomWidgetData.defaultElements([4, 2], true);
    compare(els.length, 2);
    compare(els[0].type, "Ring");
    compare(els[1].place.x + els[1].place.w, 16, "the text fills the rest");
    compare(CustomWidgetData.defaultElements([4, 2], false)[0].type, "Icon");
    compare(els[1].options.align, "left", "the text against the icon");
  }

  function test_stripJsonc() {
    compare(JSON.parse(CustomWidgetData.stripJsonc('{"a": "http://x", // c\n"b": [1, 2,], /* d */ "c": "/* no */",}')), {
      "a": "http://x",
      "b": [1, 2],
      "c": "/* no */"
    }, "comments and trailing commas go, strings stay");
  }

  function test_fromWaybar() {
    const block = '"custom/media": {\n  "format": "{icon} {}", // shown\n  "return-type": "json",\n  "max-length": 40,\n  "escape": true,\n  "format-icons": {"spotify": "S", "default": "D"},\n  "exec": "$HOME/mediaplayer.py 2> /dev/null",\n  "on-click": "playerctl play-pause",\n}';
    const defs = CustomWidgetData.fromWaybar(block);
    compare(defs.length, 1);
    compare(defs[0].name, "Media");
    compare(defs[0].mode, "stream", "no interval: Waybar reads it line by line");
    compare(defs[0].command, "$HOME/mediaplayer.py 2> /dev/null");
    compare(defs[0].formatIcons.spotify, "S");
    compare(defs[0].maxLength, 40);
    compare(defs[0].actions.click, "playerctl play-pause");
    const polled = CustomWidgetData.fromWaybar('{"exec": "x", "interval": 60, "signal": 6}')[0];
    compare(polled.mode, "poll");
    compare(polled.interval, 60000, "seconds to ms");
    compare(polled.refreshName, "script");
    compare(CustomWidgetData.fromWaybar('{"exec": "x", "interval": "once"}')[0].mode, "once");
    const config = CustomWidgetData.fromWaybar('{"modules-left": ["custom/a"], "clock": {}, "custom/a": {"exec": "a"}, "custom/b-c": {"exec": "b"}}');
    compare(config.map(d => d.name), ["A", "B c"], "every custom module of a whole config");
  }

  function test_iconPick() {
    const d = {
      "formatIcons": {
        "on": "vpn_lock",
        "off": "vpn_key_off"
      }
    };
    const f = CustomWidgetData.resolve(d, {
      "text": "on"
    });
    compare(f.alt, "on", "text matching an icon key is the alt");
    compare(f.icon, "vpn_lock", "a Material Symbols name picked is the icon");
    compare(CustomWidgetData.resolve(d, {
      "text": "on",
      "icon": "wifi"
    }).icon, "wifi", "the script's own icon first");
    compare(CustomWidgetData.resolve({
      "formatIcons": ["▁", "█"]
    }, {
      "text": "x",
      "percentage": 90
    }).icon, "", "a glyph isn't an icon name");
  }

  function test_presetsLoad() {
    for (const preset of CustomWidgetData.presets) {
      verify(preset.name && (preset.command || preset.template), preset.name);
      if (!preset.command)
        continue;
      const f = CustomWidgetData.resolve(preset, CustomWidgetData.parse("on", undefined, preset.output ?? "waybar", preset.mode === "stream"));
      verify(typeof f.text === "string", preset.name);
    }
  }

  function test_presetDailyHabits() {
    const preset = CustomWidgetData.presets.find(p => p.name === "Daily habits");
    verify(preset, "the preset is listed");
    verify(preset.command.includes("{tree}data/custom-widgets/habits.sh"), "the script is found through {tree}");
    verify(preset.invoke.command.includes("{action} {value}"), "the action command takes the action and its value");
    const views = preset.module.views;
    compare(views.map(v => v.id), ["open", "done", "empty"], "a screen per state");
    compare(preset.module.keys, {
      "u": "undo"
    }, "undo on a key");
    compare(Object.keys(preset.samples).sort(), ["done", "empty", "open"], "a sample per screen");
    const context = {
      "interactive": true,
      "colorNames": ["accent", "success"]
    };
    views.forEach((view, index) => {
      const fields = CustomWidgetData.resolve(preset, preset.samples[view.id], context);
      compare(CustomWidgetData.pickView(preset.module, fields).index, index, "the " + view.id + " sample picks its screen");
    });
    // The actions the elements and keys name are ones the samples list
    const named = new Set(CustomWidgetData.allElements(preset.module).map(e => e.action).filter(a => a).concat(Object.values(preset.module.keys)));
    for (const action of named) {
      verify(Object.values(preset.samples).some(sm => action in sm.actions), "a sample lists " + action);
      verify(/^[A-Za-z0-9_.-]{1,64}$/.test(action), action + " is an action id");
    }
    const open = CustomWidgetData.resolve(preset, preset.samples.open, context);
    compare(open.color, "accent", "open is the accent");
    compare(CustomWidgetData.resolve(preset, preset.samples.done, context).color, "success", "done is success");
    compare(CustomWidgetData.actionEnabled(CustomWidgetData.resolve(preset, preset.samples.empty, context).actions, "check"), false, "nothing to check while empty");
    compare(CustomWidgetData.fillCommand(preset.invoke.command, {
      "action": "add",
      "value": "it's",
      "tree": "/opt/axiom/"
    }), "bash '/opt/axiom/data/custom-widgets/habits.sh' do 'add' 'it'\\''s'", "the action command filled in");
  }

  function test_preview_zoom_fits_width() {
    const sizes = [[4, 4], [4, 4], [8, 2], [8, 4], [4, 1]];
    for (const card of [450, 624, 990]) {
      for (const width of [1180, 1500, 2600]) {
        const reserved = 400;
        const spacing = 20;
        const zoom = CustomWidgetData.previewZoom(sizes, card, width, 900, reserved, spacing);
        verify(zoom <= 0.3, "never above 0.3");
        const used = sizes.reduce((sum, size) => sum + GridPlacement.span(size[0], card) * zoom, 0) + reserved + spacing * sizes.length;
        verify(used <= width + 0.001, "card " + card + " at " + width + ": " + used);
      }
    }
    // Wide enough: the height rule alone, as before
    compare(CustomWidgetData.previewZoom(sizes, 450, 100000, 900, 400, 20), Math.min(0.3, 900 * 0.22 / GridPlacement.span(4, 450)), "wide page: height only");
  }

  // --- Screens ---

  function test_allElements() {
    compare(CustomWidgetData.allElements(null).length, 0, "none");
    compare(CustomWidgetData.allElements({
      "elements": [
        {
          "id": "a"
        }
      ]
    }).length, 1, "base only");
    compare(CustomWidgetData.allElements({
      "elements": [],
      "views": [
        {
          "elements": [
            {
              "id": "b"
            }
          ]
        },
        {
          "elements": [
            {
              "id": "c"
            },
            {
              "id": "d"
            }
          ]
        }
      ]
    }).length, 3, "views only");
    compare(CustomWidgetData.allElements({
      "elements": [
        {
          "id": "a"
        }
      ],
      "views": [
        {
          "elements": [
            {
              "id": "b"
            }
          ]
        }
      ]
    }).map(e => e.id).join(), "a,b", "base first");
  }

  function _fields(sample, failure) {
    return {
      "sample": sample,
      "failure": failure ?? null,
      "error": failure?.message ?? ""
    };
  }

  function test_matches() {
    const errWhen = (test, values) => ({
          "key": "error",
          "test": test,
          "values": values
        });
    compare(CustomWidgetData.matches(errWhen("isNot", ["x"]), _fields({})), false, "error isNot: never while healthy");
    compare(CustomWidgetData.matches(errWhen("is", [""]), _fields({})), false, "error is [\"\"]: never while healthy");
    compare(CustomWidgetData.matches(errWhen("isNot", ["x"]), _fields({}, {
      "kind": "script",
      "message": "y"
    })), true, "error isNot: another message");
    const is = values => ({
          "key": "state",
          "test": "is",
          "values": values
        });
    compare(CustomWidgetData.matches(is(["front"]), _fields({
      "state": "front"
    })), true, "is");
    compare(CustomWidgetData.matches(is(["front"]), _fields({
      "state": "back"
    })), false, "is, another");
    compare(CustomWidgetData.matches({
      "key": "state",
      "test": "isNot",
      "values": ["front"]
    }, _fields({
      "state": "back"
    })), true, "isNot");
    compare(CustomWidgetData.matches({
      "key": "state",
      "test": "isNot",
      "values": []
    }, _fields({
      "state": "back"
    })), false, "isNot with no values");
    compare(CustomWidgetData.matches(is([]), _fields({
      "state": "front"
    })), false, "is with no values");
    compare(CustomWidgetData.matches({
      "key": "ready",
      "test": "set"
    }, _fields({
      "ready": true
    })), true, "set: true");
    compare(CustomWidgetData.matches({
      "key": "ready",
      "test": "set"
    }, _fields({
      "ready": "false"
    })), false, "set: the string false");
    compare(CustomWidgetData.matches({
      "key": "ready",
      "test": "unset"
    }, _fields({})), true, "unset: missing");
    compare(CustomWidgetData.matches(is(["true"]), _fields({
      "state": true
    })), true, "true is the text true");
    compare(CustomWidgetData.matches({
      "key": "player.status",
      "test": "is",
      "values": ["playing"]
    }, _fields({
      "player": {
        "status": "playing"
      }
    })), true, "a nested path");
    compare(CustomWidgetData.matches({
      "key": "",
      "test": "is",
      "values": ["x"]
    }, _fields({
      "state": "x"
    })), true, "an empty key is state");
    compare(CustomWidgetData.matches(is(["front"]), null), false, "null fields");
    const failing = _fields({}, {
      "kind": "exit",
      "message": "boom"
    });
    compare(CustomWidgetData.matches({
      "key": "error",
      "test": "set"
    }, failing), true, "error set");
    compare(CustomWidgetData.matches({
      "key": "error",
      "test": "unset"
    }, failing), false, "error unset while failing");
    compare(CustomWidgetData.matches({
      "key": "error",
      "test": "unset"
    }, _fields({})), true, "error unset");
    compare(CustomWidgetData.matches({
      "key": "error",
      "test": "is",
      "values": ["boom"]
    }, failing), true, "error is its message");
  }

  function test_pickView() {
    const view = (id, when) => ({
          "id": id,
          "when": when
        });
    const front = view("front", {
      "key": "state",
      "test": "is",
      "values": ["front"]
    });
    const back = view("back", {
      "key": "state",
      "test": "is",
      "values": ["back", "front"]
    });
    const error = view("err", {
      "key": "error",
      "test": "set"
    });
    const fields = _fields({
      "state": "front"
    });
    compare(CustomWidgetData.pickView({}, fields).index, -1, "no views");
    compare(CustomWidgetData.pickView({
      "views": [front]
    }, fields).index, 0, "front");
    compare(CustomWidgetData.pickView({
      "views": [back, front]
    }, fields).index, 0, "two matches: the first");
    const failing = _fields({
      "state": "front"
    }, {
      "kind": "script",
      "message": "x"
    });
    compare(CustomWidgetData.pickView({
      "views": [front, error]
    }, failing).index, 1, "failure: the error view");
    const stale = CustomWidgetData.pickView({
      "views": [front]
    }, failing);
    compare(stale.index, -1, "failure: no stale state view");
    compare(stale.builtinError, true, "failure: the stock screen");
    compare(CustomWidgetData.pickView({
      "views": [view("e", {
          "key": "error",
          "test": "isNot",
          "values": ["x"]
        }), front]
    }, fields).index, 1, "healthy: an error isNot screen is skipped");
    const none = CustomWidgetData.pickView({
      "views": [front]
    }, null);
    compare(none.index, -1, "null fields");
    compare(none.builtinError, false, "null fields: no error");
  }

  function test_historyBindings() {
    compare(CustomWidgetData.historyBindings({}).length, 0, "none");
    const spark = value => ({
          "type": "Sparkline",
          "bind": {
            "value": value
          }
        });
    const module = {
      "elements": [spark("cpu"),
        {
          "type": "Text",
          "bind": {
            "value": "x"
          }
        },
        spark("")],
      "views": [
        {
          "elements": [spark("net"), spark("cpu")]
        }
      ]
    };
    compare(CustomWidgetData.historyBindings(module).join(), "cpu,net", "base and views, duplicates once");
    compare(CustomWidgetData.historyBindings({
      "elements": [
        {
          "type": "Sparkline",
          "bind": {
            "value": "up",
            "value2": "down"
          }
        },
        {
          "type": "Sparkline",
          "bind": {
            "value2": "up"
          }
        },
        {
          "type": "Text",
          "bind": {
            "value2": "no"
          }
        }
      ]
    }).join(), "up,down", "value2 too, once, Sparklines only");
  }

  function test_series() {
    compare(CustomWidgetData.series([1, "2", "x", null], 240), [1, 2], "numbers kept, numeric strings parsed, others dropped");
    compare(CustomWidgetData.series(5, 240), null, "a number is no series");
    compare(CustomWidgetData.series("1,2", 240), null, "nor a string");
    compare(CustomWidgetData.series(undefined, 240), null, "nor nothing");
    compare(CustomWidgetData.series({}, 240), null, "nor an object");
    compare(CustomWidgetData.series([], 240), [], "an empty list is an empty series");
    const long = [];
    for (let i = 0; i < 300; i++)
      long.push(i);
    const kept = CustomWidgetData.series(long, 240);
    compare(kept.length, 240, "the last 240");
    compare(kept[0], 60);
    compare(kept[239], 299);
    compare(CustomWidgetData.series([1, Infinity, NaN, 3], 240), [1, 3], "non-finite dropped");
  }

  // --- Named actions ---

  function test_actionEnabled() {
    const actions = {
      "undo": {
        "enabled": false
      },
      "check": {
        "enabled": true
      }
    };
    compare(CustomWidgetData.actionEnabled(null, "next"), true, "no actions: all on");
    compare(CustomWidgetData.actionEnabled(undefined, "next"), true, "no sample: on");
    compare(CustomWidgetData.actionEnabled(actions, "check"), true, "listed on");
    compare(CustomWidgetData.actionEnabled(actions, "undo"), false, "listed off");
    compare(CustomWidgetData.actionEnabled(actions, "next"), false, "unlisted: off");
    compare(CustomWidgetData.actionEnabled(actions, "axiom:refresh"), true, "a built-in is always on");
    compare(CustomWidgetData.actionEnabled({}, "axiom:restart"), true, "a built-in with an empty list");
    compare(CustomWidgetData.actionEnabled(actions, "constructor"), false, "an Object.prototype name isn't listed");
    compare(CustomWidgetData.actionEnabled(actions, "toString"), false, "toString isn't listed");
  }

  function test_shellQuote() {
    compare(CustomWidgetData.shellQuote("42.5"), "42.5", "a number is bare");
    compare(CustomWidgetData.shellQuote("."), "'.'", "a dot is quoted");
    compare(CustomWidgetData.shellQuote("1.2.3"), "'1.2.3'", "two dots are quoted");
    compare(CustomWidgetData.shellQuote("-."), "'-.'", "-. is quoted");
    compare(CustomWidgetData.shellQuote(".5"), ".5", ".5 is a number");
    compare(CustomWidgetData.shellQuote("-3"), "-3", "a negative number");
    compare(CustomWidgetData.shellQuote("seek"), "'seek'", "a word is quoted");
    compare(CustomWidgetData.shellQuote("it's"), "'it'\\''s'", "a quote survives");
    compare(CustomWidgetData.shellQuote(""), "''", "nothing is ''");
    compare(CustomWidgetData.shellQuote("a$&b"), "'a$&b'", "shell characters stay inside the quotes");
  }

  function test_fillCommand() {
    compare(CustomWidgetData.fillCommand("playerctl-do {action} {value}", {
      "action": "seek",
      "value": "42.5"
    }), "playerctl-do 'seek' 42.5", "the spec's example");
    compare(CustomWidgetData.fillCommand("x {value}", {
      "value": "{rev}",
      "rev": "9"
    }), "x '{rev}'", "a filled value is not filled again");
    compare(CustomWidgetData.fillCommand("x ${rev}", {
      "rev": "9"
    }), "x ${rev}", "after a $: untouched");
    compare(CustomWidgetData.fillCommand("{action}{value}", {
      "action": "a",
      "value": "b"
    }), "'a''b'", "both filled");
    compare(CustomWidgetData.fillCommand("{action}", {
      "value": "1"
    }), "{action}", "no value for it: kept");
    compare(CustomWidgetData.fillCommand("x {text}", {
      "value": "1"
    }), "x {text}", "{text} stays as typed");
    compare(CustomWidgetData.fillCommand("{value} {value}", {
      "value": "z"
    }), "'z' 'z'", "the same placeholder twice");
    compare(CustomWidgetData.fillCommand("bash {tree}run {value}", {
      "tree": "/opt/axiom/",
      "value": ""
    }), "bash /opt/axiom/run ''", "{tree} as is, an empty value ''");
    compare(CustomWidgetData.fillCommand("ls ${tree} {tree}x {value}", {
      "tree": "/t/"
    }), "ls ${tree} /t/x {value}", "a shell ${tree} stays, unfilled placeholders stay");
    compare(CustomWidgetData.fillCommand("x {value}", {
      "value": "a$&b"
    }), "x 'a$&b'", "shell characters intact");
  }

  function test_builtinAllowed() {
    const refused = ["poweroff", "lock", "reboot"];
    compare(CustomWidgetData.builtinAllowed("axiom:poweroff", refused), false, "poweroff");
    compare(CustomWidgetData.builtinAllowed("axiom:lock", refused), false, "lock");
    compare(CustomWidgetData.builtinAllowed("axiom:toggleMute", refused), true, "mute");
    compare(CustomWidgetData.builtinAllowed("axiom:refresh", refused), true, "refresh");
    compare(CustomWidgetData.builtinAllowed("poweroff", refused), true, "a script's own id isn't a built-in");
    compare(CustomWidgetData.builtinAllowed("axiom:poweroff", undefined), true, "nothing refused");
  }

  // --- Keys ---

  function test_keyName() {
    const none = Qt.NoModifier;
    compare(CustomWidgetData.keyName(Qt.Key_3, "3", none, false), "3", "a digit");
    compare(CustomWidgetData.keyName(Qt.Key_Space, " ", none, false), "space", "space");
    compare(CustomWidgetData.keyName(Qt.Key_Return, "\r", none, false), "return", "return");
    compare(CustomWidgetData.keyName(Qt.Key_Enter, "\r", none, false), "return", "the keypad's enter");
    compare(CustomWidgetData.keyName(Qt.Key_Left, "", none, false), "left", "an arrow");
    compare(CustomWidgetData.keyName(Qt.Key_Backspace, "\b", none, false), "backspace", "backspace");
    compare(CustomWidgetData.keyName(Qt.Key_Escape, "", none, false), "escape", "escape");
    compare(CustomWidgetData.keyName(Qt.Key_Z, "\x1a", Qt.ControlModifier, false), "ctrl+z", "ctrl+z: the name from the key, not the control character");
    compare(CustomWidgetData.keyName(Qt.Key_Z, "z", Qt.ControlModifier | Qt.AltModifier, false), "ctrl+alt+z", "ctrl and alt");
    compare(CustomWidgetData.keyName(Qt.Key_5, "", Qt.AltModifier, false), "alt+5", "alt+5");
    compare(CustomWidgetData.keyName(Qt.Key_Backtab, "", Qt.ShiftModifier, false), "shift+tab", "shift+tab");
    compare(CustomWidgetData.keyName(Qt.Key_Tab, "\t", none, false), "tab", "tab");
    compare(CustomWidgetData.keyName(Qt.Key_Left, "", Qt.ShiftModifier, false), "shift+left", "shift on a non-printing key");
    compare(CustomWidgetData.keyName(Qt.Key_Question, "?", Qt.ShiftModifier, false), "?", "a printed key has no shift+");
    compare(CustomWidgetData.keyName(Qt.Key_A, "A", Qt.ShiftModifier, false), "a", "A is a");
    compare(CustomWidgetData.keyName(Qt.Key_3, "3", none, true), "", "a held key (auto-repeat) is none");
    compare(CustomWidgetData.keyName(Qt.Key_Shift, "", Qt.ShiftModifier, false), "", "a modifier alone");
    compare(CustomWidgetData.keyName(Qt.Key_F1, "", none, false), "", "a key with no name");
    compare(CustomWidgetData.keyName(Qt.Key_Slash, "/", Qt.ControlModifier, false), "", "ctrl on a key outside A-Z and 0-9");
    compare(CustomWidgetData.keyName(Qt.Key_U, "u", Qt.MetaModifier, false), "", "a Super chord is none");
    compare(CustomWidgetData.keyName(Qt.Key_Z, "\x1a", Qt.ControlModifier | Qt.MetaModifier, false), "", "ctrl+super is none");
    compare(CustomWidgetData.keyName(Qt.Key_A, "a", none, undefined), "a", "no auto-repeat flag");
  }

  function test_keyAction() {
    const keys = {
      "3": "check",
      "u": "undo",
      "escape": "close",
      "tab": "next"
    };
    compare(CustomWidgetData.keyAction(keys, "3"), "check", "mapped");
    compare(CustomWidgetData.keyAction(keys, "x"), "", "not mapped");
    compare(CustomWidgetData.keyAction(keys, ""), "", "no key");
    compare(CustomWidgetData.keyAction(keys, "escape"), "", "escape is reserved");
    compare(CustomWidgetData.keyAction(keys, "tab"), "", "tab is reserved");
    compare(CustomWidgetData.keyAction(keys, "shift+tab"), "", "shift+tab is reserved");
    compare(CustomWidgetData.keyAction(keys, "constructor"), "", "an Object.prototype name isn't mapped");
    compare(CustomWidgetData.keyAction(keys, "toString"), "", "toString either");
    compare(CustomWidgetData.keyAction(null, "3"), "", "no keys");
    compare(CustomWidgetData.keyAction(undefined, "3"), "", "undefined keys");
  }

  function test_within() {
    const outer = createTemporaryObject(plain, this);
    const inner = createTemporaryObject(plain, outer);
    const deep = createTemporaryObject(plain, inner);
    const other = createTemporaryObject(plain, this);
    verify(CustomWidgetData.within(outer, outer), "itself");
    verify(CustomWidgetData.within(outer, deep), "a descendant: the focus sits in the layout (an Entry)");
    verify(!CustomWidgetData.within(inner, outer), "not an ancestor");
    verify(!CustomWidgetData.within(outer, other), "a sibling");
    verify(!CustomWidgetData.within(outer, null), "no focus item");
    verify(!CustomWidgetData.within(outer, undefined), "undefined");
  }

  Component {
    id: plain
    Item {}
  }

  // --- Samples ---

  function test_viewKey() {
    const module = {
      "views": [
        {
          "id": "front"
        },
        {
          "id": "back"
        }
      ]
    };
    compare(CustomWidgetData.viewKey(module, 1), "back", "a screen's id");
    compare(CustomWidgetData.viewKey(module, -1), "", "no screen");
    compare(CustomWidgetData.viewKey(module, 5), "", "past the list");
    compare(CustomWidgetData.viewKey(null, 0), "", "no module");
  }

  function test_keepSample() {
    const limits = {
      "entries": 2,
      "bytes": 100
    };
    const samples = {
      "a": {
        "x": 1
      }
    };
    const kept = CustomWidgetData.keepSample(samples, "b", {
      "y": 2
    }, limits);
    compare(kept.refused, "", "kept");
    compare(Object.keys(kept.samples).join(), "a,b", "added");
    compare(Object.keys(samples).join(), "a", "the argument is not changed");
    const replaced = CustomWidgetData.keepSample(kept.samples, "a", {
      "x": 9
    }, limits);
    compare(replaced.refused, "", "an existing key is replaced at the cap");
    compare(replaced.samples.a.x, 9, "its new value");
    const full = CustomWidgetData.keepSample(kept.samples, "c", {}, limits);
    compare(full.refused, "count", "a third key is refused");
    compare(Object.keys(full.samples).join(), "a,b", "the map is as it was");
    const big = CustomWidgetData.keepSample({}, "a", {
      "text": "x".repeat(200)
    }, limits);
    compare(big.refused, "size", "too big");
    compare(Object.keys(big.samples).length, 0, "nothing kept");
    compare(CustomWidgetData.keepSample(undefined, "", {}, limits).refused, "", "no map yet");
    const cjk = n => ({
          "text": "語".repeat(n)
        });
    compare(CustomWidgetData.keepSample({}, "a", cjk(30000), {
      "bytes": 65536
    }).refused, "size", "30000 CJK characters are over 64 KB of UTF-8");
    compare(CustomWidgetData.keepSample({}, "a", cjk(20000), {
      "bytes": 65536
    }).refused, "", "20000 fit");
  }

  function test_utf8Length() {
    compare(CustomWidgetData.utf8Length("a"), 1);
    compare(CustomWidgetData.utf8Length("é"), 2);
    compare(CustomWidgetData.utf8Length("語"), 3);
    compare(CustomWidgetData.utf8Length("😀"), 4);
  }

  function test_sampleForView() {
    const module = {
      "views": [
        {
          "id": "front",
          "when": {
            "key": "state",
            "test": "is",
            "values": ["front"]
          }
        },
        {
          "id": "back",
          "when": {
            "key": "state",
            "test": "is",
            "values": ["back"]
          }
        }
      ]
    };
    const def = {
      "module": module,
      "samples": {
        "front": {
          "state": "front",
          "saved": true
        }
      }
    };
    const live = _fields({
      "state": "back",
      "live": true
    });
    compare(CustomWidgetData.sampleForView(def, 0, {
      "front": {
        "seen": true
      }
    }, live).saved, true, "saved wins over seen and live");
    compare(CustomWidgetData.sampleForView(def, 1, {
      "back": {
        "seen": true
      }
    }, live).seen, true, "seen over live");
    compare(CustomWidgetData.sampleForView(def, 1, {}, live).live, true, "live when it picks that screen");
    compare(CustomWidgetData.sampleForView({
      "module": module
    }, 0, {}, live), null, "live that picks another screen: none");
    compare(CustomWidgetData.sampleForView(def, -1, {}, _fields({
      "state": "other"
    })).state, "other", "live that picks no screen is the base's");
    compare(CustomWidgetData.sampleForView({
      "module": module
    }, 0, {}, null), null, "no live fields");
    compare(CustomWidgetData.sampleForView({
      "module": module,
      "samples": {
        "": {
          "kept": 1
        }
      }
    }, -1, {}, null).kept, 1, "the empty key is no screen");
  }

  function test_baseSlotsLast() {
    compare(CustomWidgetData.baseSlotsLast([["show", "tone", "label", "icon"], ["show", "tone"]]), [["label", "icon", "show", "tone"], ["show", "tone"]]);
    compare(CustomWidgetData.baseSlotsLast([]), []);
    // One list: every slot is shared, so it stays as it is
    compare(CustomWidgetData.baseSlotsLast([["show", "tone", "text"]]), [["show", "tone", "text"]]);
  }

  function test_moveItem() {
    compare(CustomWidgetData.moveItem(["a", "b", "c"], 0, 2), ["b", "c", "a"]);
    compare(CustomWidgetData.moveItem(["a", "b", "c"], 2, 1), ["a", "c", "b"]);
    compare(CustomWidgetData.moveItem(["a", "b"], 0, 5), ["a", "b"], "out of range: as it is");
    compare(CustomWidgetData.moveItem(["a", "b"], 1, 1), ["a", "b"], "same place");
    compare(CustomWidgetData.moveItem(null, 0, 1), [], "none");
    const list = ["a", "b"];
    CustomWidgetData.moveItem(list, 0, 1);
    compare(list, ["a", "b"], "not changed in place");
  }

  function test_viewCopy() {
    const views = [
      {
        "id": "open",
        "name": "Open",
        "base": false,
        "when": {
          "key": "state",
          "test": "is",
          "values": ["open"]
        },
        "elements": [
          {
            "id": "a",
            "type": "Text"
          }
        ]
      }
    ];
    const copy = CustomWidgetData.viewCopy(views, 0, "Open (copy)");
    compare(copy.id, "open-copy", "a new id from the name");
    compare(copy.name, "Open (copy)");
    compare(copy.when.values, ["open"], "the condition is copied");
    compare(copy.base, false);
    compare(copy.elements, views[0].elements, "its elements are copied");
    verify(copy.elements !== views[0].elements, "not the same array");
    compare(CustomWidgetData.viewCopy(views, 0, "Open").id, "open-2", "a clash is numbered");
    compare(CustomWidgetData.viewCopy(views, 3, "x"), null);
  }

  function test_elementCopy() {
    const element = {
      "id": "a",
      "type": "Text",
      "place": {
        "x": 1,
        "y": 2,
        "w": 3,
        "h": 4
      }
    };
    compare(CustomWidgetData.elementCopy([], element).id, "a", "no clash: the same id");
    compare(CustomWidgetData.elementCopy([
      {
        "id": "a"
      }
    ], element).id, "a-2", "a clash: a new id");
    compare(CustomWidgetData.elementCopy([
      {
        "id": "a"
      }
    ], element).place, element.place, "the same place");
  }

  function test_bindChoices() {
    const choices = CustomWidgetData.bindChoices([
      {
        "text": "x",
        "data": {
          "temp": 21
        },
        "items": [1, 2]
      },
      null,
      {
        "text": "other",
        "extra": "y".repeat(60)
      }
    ]);
    compare(choices.map(c => c.path), ["text", "data.temp", "items", "items.0", "items.1", "extra"], "each path once, objects left out");
    compare(choices[0].preview, "x", "the first seen value");
    compare(choices[2].type, "array");
    compare(choices[2].preview, "", "a list has no preview");
    compare(choices[5].preview.length, 40, "long values are cut");
    compare(CustomWidgetData.bindChoices([
      {
        "a": 1,
        "b": 2,
        "c": 3
      }
    ], 2).length, 2, "capped");
    compare(CustomWidgetData.bindChoices(null), []);
  }

  function test_commandsOf() {
    compare(CustomWidgetData.commandsOf({
      "command": "a.sh",
      "execIf": "  ",
      "invoke": {
        "command": "b.sh {action}"
      },
      "actions": {
        "click": "c",
        "rightClick": "",
        "refreshAfter": true,
        "named": {
          "click": "act"
        }
      },
      "module": {
        "elements": [
          {
            "id": "go",
            "actions": {
              "click": "d"
            }
          }
        ],
        "views": [
          {
            "id": "open",
            "elements": [
              {
                "id": "list",
                "actions": {
                  "submit": "e"
                }
              }
            ]
          }
        ]
      }
    }), [
      {
        "where": "command",
        "command": "a.sh"
      },
      {
        "where": "invoke.command",
        "command": "b.sh {action}"
      },
      {
        "where": "actions.click",
        "command": "c"
      },
      {
        "where": "base/go/actions.click",
        "command": "d"
      },
      {
        "where": "open/list/actions.submit",
        "command": "e"
      }
    ], "the non-empty commands, each with where it is; named actions aren't commands");
    const template = CustomWidgetData.galleryPresets.find(p => p.name === "Slider");
    compare(CustomWidgetData.commandsOf(template), [], "a template holds none");
    compare(CustomWidgetData.commandsOf(null), []);
  }

  function test_exportAndImport() {
    const def = {
      "id": "x",
      "name": "X",
      "command": "x.sh",
      "samples": {
        "": {
          "text": "1"
        }
      }
    };
    const text = CustomWidgetData.exportOf(def);
    const wrapped = JSON.parse(text);
    compare(wrapped.axiomCustomWidget, 1, "versioned");
    compare("id" in wrapped.definition, false, "no id");
    compare(wrapped.definition.samples, def.samples, "samples travel");
    compare(def.id, "x", "the definition is not changed");
    const back = CustomWidgetData.fromExport(text);
    compare(back.error, "");
    compare(back.definitions.length, 1);
    compare(back.definitions[0].command, "x.sh");
    compare(CustomWidgetData.fromExport("{\"command\": \"a\", \"id\": \"q\"}").definitions[0].id, undefined, "a bare definition, id dropped");
    compare(CustomWidgetData.fromExport("[" + text + ", {\"module\": {}}]").definitions.length, 2, "a list of either");
    compare(CustomWidgetData.fromExport("// c\n{\"command\": \"a\",}").error, "", "comments and trailing commas");
    verify(CustomWidgetData.fromExport("{nope").error.startsWith("Not valid JSON"), "bad JSON");
    verify(CustomWidgetData.fromExport("{\"name\": \"x\"}").error !== "", "no module and no command");
    verify(CustomWidgetData.fromExport("[1]").error !== "", "not objects");
    verify(CustomWidgetData.fromExport("{\"axiomCustomWidget\": 2, \"definition\": {\"command\": \"a\"}}").error !== "", "a newer wrapper");
    compare(CustomWidgetData.fromExport("[]").error, "Nothing in it.");
  }

  function test_readImport() {
    compare(CustomWidgetData.readImport(CustomWidgetData.exportOf({
      "command": "a"
    })).kind, "widget");
    const waybar = CustomWidgetData.readImport("\"custom/x\": { \"exec\": \"a.sh\", \"interval\": 5 }");
    compare(waybar.kind, "waybar", "a Waybar module is the second mode");
    compare(waybar.definitions[0].command, "a.sh");
    const bad = CustomWidgetData.readImport("{\"nothing\": 1}");
    compare(bad.kind, "");
    verify(bad.error !== "");
    verify(CustomWidgetData.readImport("{nope").error.startsWith("Not valid JSON"));
  }

  function test_pushLogAndKeys() {
    compare(CustomWidgetData.pushLog([1, 2, 3], 4, 3), [2, 3, 4], "the last `cap`");
    compare(CustomWidgetData.pushLog(null, 1, 3), [1]);
    compare(CustomWidgetData.mappableKey("3"), "3");
    compare(CustomWidgetData.mappableKey("escape"), "", "reserved");
    compare(CustomWidgetData.mappableKey("shift+tab"), "", "reserved");
    compare(CustomWidgetData.mappableKey(""), "");
  }

  function test_templates() {
    const names = CustomWidgetData.galleryPresets.map(p => p.name);
    compare(names, ["Daily habits", "Toggle", "Slider", "List with a row action", "Media card", "Status with an error screen"]);
    compare(CustomWidgetData.scriptPresets.some(p => p.template), false, "the known scripts have commands");
    for (const t of CustomWidgetData.galleryPresets) {
      const module = t.module;
      const ids = CustomWidgetData.allElements(module).map(e => e.id);
      verify(ids.length > 0, t.name + " has elements");
      // Element ids are unique in a layer (a screen's may repeat the base's)
      for (const layer of [module.elements].concat((module.views ?? []).map(v => v.elements)))
        compare(new Set(layer.map(e => e.id)).size, layer.length, t.name + ": unique ids");
      const keys = Object.keys(t.samples);
      verify(keys.length > 0, t.name + " has a sample");
      const context = {
        "interactive": true,
        "colorNames": ["accent", "success", "warning", "error"]
      };
      for (const key of keys) {
        const fields = CustomWidgetData.resolve(t, t.samples[key], context);
        const views = module.views ?? [];
        const index = views.findIndex(v => v.id === key);
        verify(key === "" || index >= 0, t.name + ": sample " + key + " is a screen's");
        // A screen's sample picks its screen; the base's picks none
        if (key !== "")
          compare(CustomWidgetData.pickView(module, fields).index, index, t.name + ": the " + key + " sample picks its screen");
      }
      // Every action an element or key names is one a sample lists
      const named = CustomWidgetData.allElements(module).map(e => e.action).filter(a => a && !a.startsWith("axiom:"));
      for (const action of named)
        verify(Object.values(t.samples).some(sm => sm.actions && action in sm.actions), t.name + ": a sample lists " + action);
    }
    const media = CustomWidgetData.galleryPresets.find(p => p.name === "Media card");
    const nothing = CustomWidgetData.resolve(media, media.samples.nothing, {
      "interactive": true
    });
    compare(CustomWidgetData.pickView(media.module, nothing).index, 2, "nothing playing is the third screen");
    const status = CustomWidgetData.galleryPresets.find(p => p.name === "Status with an error screen");
    const failing = CustomWidgetData.resolve(status, status.samples.error, {
      "interactive": true
    });
    compare(CustomWidgetData.pickView(status.module, failing).index, 0, "a script's error picks the error screen");
  }

  function test_unmatchedStatesAndSource() {
    const module = {
      "views": [
        {
          "id": "a",
          "when": {
            "key": "state",
            "test": "is",
            "values": ["playing"]
          }
        },
        {
          "id": "e",
          "when": {
            "key": "error",
            "test": "set"
          }
        }
      ]
    };
    compare(CustomWidgetData.unmatchedStates(module, ["playing", "paused", "idle"]), ["paused", "idle"], "the states no screen is for");
    compare(CustomWidgetData.unmatchedStates(null, ["x"]), ["x"]);
    compare(CustomWidgetData.unmatchedStates(module, null), []);
    const def = {
      "module": module,
      "samples": {
        "a": {
          "state": "playing"
        }
      }
    };
    compare(CustomWidgetData.sampleSource(def, 0, {}, null), "saved");
    compare(CustomWidgetData.sampleSource(def, 1, {
      "e": {
        "error": "x"
      }
    }, null), "live", "seen is live");
    compare(CustomWidgetData.sampleSource(def, 1, {}, null), "none");
    compare(CustomWidgetData.sampleSource(def, -1, {}, null), "none");
  }

  function test_fitZoom() {
    compare(CustomWidgetData.fitZoom([4, 4], 100, 10000, 10000), 1, "never past full size");
    verify(CustomWidgetData.fitZoom([4, 4], 100, 50, 10000) < 1, "narrow: smaller");
    verify(CustomWidgetData.fitZoom([4, 4], 100, 10000, 50) < 1, "short: smaller");
    compare(CustomWidgetData.fitZoom([4, 4], 100, 0, 0), 0.05, "at least 0.05");
    verify(CustomWidgetData.fitZoom([8, 2], 100, 150, 400) < CustomWidgetData.fitZoom([2, 2], 100, 150, 400), "a wider module is drawn smaller");
  }

  function test_keyMaps() {
    compare(Object.keys(CustomWidgetData.withKey({
      "a": 1,
      "b": 2
    }, "a", 9)), ["a", "b"], "a set key keeps its place");
    compare(CustomWidgetData.withKey({
      "a": 1
    }, "b", 2), {
      "a": 1,
      "b": 2
    });
    compare(CustomWidgetData.withoutKey({
      "a": 1,
      "b": 2
    }, "a"), {
      "b": 2
    });
    const map = {
      "a": 1,
      "b": 2,
      "c": 3
    };
    compare(Object.keys(CustomWidgetData.renameKey(map, "b", "x")), ["a", "x", "c"], "renamed in place");
    compare(CustomWidgetData.renameKey(map, "b", "x").x, 2);
    verify(CustomWidgetData.renameKey(map, "b", "") === map, "an empty name: as it is");
    verify(CustomWidgetData.renameKey(map, "b", "c") === map, "a taken name: as it is");
    verify(CustomWidgetData.renameKey(map, "b", "b") === map, "the same name");
    compare(map.b, 2, "not changed in place");
  }

  function test_lockIssues() {
    compare(CustomWidgetData.lockIssues(null), []);
    compare(CustomWidgetData.lockIssues({
      "module": {
        "elements": [
          {
            "type": "Text",
            "bind": {
              "text": "=Hello"
            }
          },
          {
            "type": "Ring"
          }
        ]
      }
    }), [], "literals and graphics are fine");
    compare(CustomWidgetData.lockIssues({
      "module": {
        "keys": {
          "u": "undo"
        },
        "elements": [
          {
            "type": "Button",
            "action": "undo"
          },
          {
            "type": "Entry"
          }
        ],
        "views": [
          {
            "id": "a",
            "elements": [
              {
                "type": "Text",
                "bind": {
                  "text": "{text}"
                }
              }
            ]
          }
        ]
      }
    }), ["actions", "keys", "entry", "text"], "each, screens included");
    compare(CustomWidgetData.lockIssues({
      "module": {
        "elements": [
          {
            "type": "Button",
            "action": "",
            "actions": {
              "click": "  "
            }
          }
        ]
      }
    }), [], "an empty command is none");
    compare(CustomWidgetData.lockIssues({
      "module": {
        "elements": [
          {
            "type": "Button",
            "actions": {
              "click": "x"
            }
          }
        ]
      }
    }), ["actions"], "a command");
  }
}
