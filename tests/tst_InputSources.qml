import QtQuick
import QtTest
import qs.components.methods

// InputSources: the input sources as the compositor, fcitx5 and ibus take
// them. xkb() goes through Shared: its cases are replayed by the Go port
// (render.XkbLayouts).
TestCase {
  id: test
  name: "InputSources"

  Shared {
    id: shared
    testCase: test
  }

  function xkbSource(id, layout, variant) {
    return {
      "id": id,
      "kind": "xkb",
      "layout": layout,
      "variant": variant ?? "",
      "engine": ""
    };
  }

  function imeSource(id, engine, layout, variant) {
    return {
      "id": id,
      "kind": "ime",
      "layout": layout ?? "",
      "variant": variant ?? "",
      "engine": engine
    };
  }

  readonly property var registry: ({
      "layouts": [
        {
          "name": "us",
          "short": "en",
          "description": "English (US)",
          "languages": ["eng"],
          "variants": [
            {
              "name": "dvorak",
              "short": "",
              "description": "English (Dvorak)",
              "languages": []
            }
          ]
        },
        {
          "name": "de",
          "short": "de",
          "description": "German",
          "languages": ["ger"],
          "variants": [
            {
              "name": "neo",
              "short": "",
              "description": "German (Neo 2)",
              "languages": ["deu"]
            }
          ]
        }
      ]
    })

  readonly property var mixed: [xkbSource("us", "us"), imeSource("mozc", "mozc"), xkbSource("neo", "de", "neo"), imeSource("pinyin", "pinyin", "jp")]

  function test_xkb() {
    compare(shared.calls.InputSources.xkb([xkbSource("us", "us")]), {
      "layouts": ["us"],
      "variants": [""],
      "layout": "us",
      "variant": ""
    });
    compare(shared.calls.InputSources.xkb([xkbSource("us", "us"), xkbSource("de", "de")]).variant, "", "no variant at all is written empty");
    compare(shared.calls.InputSources.xkb(test.mixed), {
      "layouts": ["us", "de", "jp"],
      "variants": ["", "neo", ""],
      "layout": "us,de,jp",
      "variant": ",neo,"
    }, "xkb sources first, then the layouts an ime one adds");
    compare(shared.calls.InputSources.xkb([xkbSource("a", "us"), xkbSource("b", "us"), xkbSource("c", "us", "dvorak")]).layout, "us,us", "each pair once");
    compare(shared.calls.InputSources.xkb([imeSource("mozc", "mozc")]).layout, "us", "never empty");
    compare(shared.calls.InputSources.xkb([]).layout, "us");
    compare(shared.calls.InputSources.xkb(null).layout, "us");
    compare(shared.calls.InputSources.xkb([xkbSource("x", " de "), xkbSource("e", "")]).layout, "de", "trimmed, an empty layout skipped");
  }

  function test_typingLayout() {
    compare(InputSources.typingLayout(test.mixed, test.mixed[1]), {
      "layout": "us",
      "variant": ""
    }, "an ime source naming none types on the first");
    compare(InputSources.typingLayout(test.mixed, test.mixed[3]).layout, "jp");
    compare(InputSources.xkbIndex(test.mixed, test.mixed[2]), 1);
    compare(InputSources.xkbIndex(test.mixed, test.mixed[3]), 2);
  }

  function test_fcitx5() {
    compare(InputSources.fcitx5Name(test.mixed[0]), "keyboard-us");
    compare(InputSources.fcitx5Name(test.mixed[2]), "keyboard-de-neo");
    compare(InputSources.fcitx5Group(test.mixed), {
      "defaultLayout": "us",
      "items": [
        {
          "name": "keyboard-us",
          "layout": "us"
        },
        {
          "name": "mozc",
          "layout": "us"
        },
        {
          "name": "keyboard-de-neo",
          "layout": "de-neo"
        },
        {
          "name": "pinyin",
          "layout": "jp"
        }
      ]
    });
    compare(InputSources.fcitx5Group([imeSource("x", "")]).items, [], "an ime source without an engine is left out");
  }

  function test_ibus() {
    compare(InputSources.ibusEngines(test.mixed, test.registry), ["xkb:us::eng", "mozc", "xkb:de:neo:deu", "pinyin"]);
    compare(InputSources.ibusName(xkbSource("d", "us", "dvorak"), test.registry), "xkb:us:dvorak:eng", "a variant without languages takes its layout's");
    compare(InputSources.ibusName(xkbSource("f", "fr"), null), "xkb:fr::", "without the registry no language");
  }

  function test_target() {
    compare(InputSources.target(test.mixed, "mozc", "fcitx5", null), {
      "xkbIndex": 0,
      "im": "mozc"
    });
    compare(InputSources.target(test.mixed, "neo", "ibus", test.registry), {
      "xkbIndex": 1,
      "im": "xkb:de:neo:deu"
    });
    compare(InputSources.target(test.mixed, "neo", "none", null).im, "");
    compare(InputSources.target(test.mixed, "gone", "fcitx5", null), null);
  }

  function test_current() {
    compare(InputSources.current(test.mixed, 0, "mozc", "fcitx5", null), "mozc");
    compare(InputSources.current(test.mixed, 0, "keyboard-us", "fcitx5", null), "us");
    compare(InputSources.current(test.mixed, 1, "", "none", null), "neo", "without a framework, the xkb index");
    compare(InputSources.current(test.mixed, 1, "something-else", "fcitx5", null), "neo", "an input method not listed falls back to the index");
    compare(InputSources.current(test.mixed, 2, "", "none", null), "pinyin", "no xkb source on that index: any");
    compare(InputSources.current(test.mixed, 7, "", "none", null), "");
    const twice = [xkbSource("us", "us"), xkbSource("de", "de"), imeSource("m1", "mozc"), imeSource("m2", "mozc", "de")];
    compare(InputSources.current(twice, 1, "mozc", "fcitx5", null), "m2", "of two on one engine, the one on the index");
    compare(InputSources.current(twice, 0, "mozc", "fcitx5", null), "m1");
  }

  function test_label() {
    compare(InputSources.label(test.mixed[2], "code", test.registry, ""), "de");
    compare(InputSources.label(test.mixed[2], "name", test.registry, ""), "German (Neo 2)");
    compare(InputSources.label(test.mixed[0], "name", test.registry, ""), "English (US)");
    compare(InputSources.label(xkbSource("f", "fr", "azerty"), "name", null, ""), "fr azerty", "no registry: the code");
    compare(InputSources.label(test.mixed[1], "code", null, "あ"), "あ", "an engine's own label");
    compare(InputSources.label(test.mixed[1], "name", null, ""), "mozc");
  }

  function test_effective() {
    compare(InputSources.effective(test.mixed, ["us", "de", "jp"]), test.mixed, "the compositor has the sources' layouts");
    compare(InputSources.effective(test.mixed, []), test.mixed, "not known yet");
    const own = InputSources.effective(test.mixed, ["fr", "us"]);
    compare(own.map(s => s.id), ["xkb:0:fr", "xkb:1:us", "mozc", "pinyin"], "the compositor's own layouts, then the engines");
    compare(own[0].layout, "fr");
    compare(InputSources.effective([xkbSource("x", ""), imeSource("e", "")], []), [], "only usable ones");
  }

  function test_xkbOnly() {
    compare(InputSources.xkbOnly(test.mixed).map(s => s.id), ["us", "neo"]);
  }

  function test_step() {
    compare(InputSources.step(test.mixed, "us", 1), "mozc");
    compare(InputSources.step(test.mixed, "pinyin", 1), "us", "wraps");
    compare(InputSources.step(test.mixed, "us", -1), "pinyin", "wraps back");
    compare(InputSources.step(test.mixed, "gone", 1), "us");
    compare(InputSources.step(test.mixed, "gone", -1), "pinyin");
    compare(InputSources.step([], "us", 1), "");
  }

  function test_groupMatches() {
    const sources = [xkbSource("us", "us"), imeSource("mozc", "mozc")];
    verify(InputSources.groupMatches("fcitx5", sources, null, {
      "defaultLayout": "us",
      "group": [
        {
          "name": "keyboard-us",
          "layout": ""
        },
        {
          "name": "mozc",
          "layout": "us"
        }
      ]
    }), "an empty layout is the default one");
    verify(!InputSources.groupMatches("fcitx5", sources, null, {
      "defaultLayout": "us",
      "group": [
        {
          "name": "keyboard-us",
          "layout": "us"
        }
      ]
    }), "an engine missing");
    verify(!InputSources.groupMatches("fcitx5", sources, null, {
      "defaultLayout": "de",
      "group": [
        {
          "name": "keyboard-us",
          "layout": "us"
        },
        {
          "name": "mozc",
          "layout": "us"
        }
      ]
    }), "another default layout");
    verify(InputSources.groupMatches("ibus", sources, test.registry, {
      "group": [
        {
          "name": "xkb:us::eng",
          "layout": ""
        },
        {
          "name": "mozc",
          "layout": ""
        }
      ]
    }));
    verify(InputSources.groupMatches("none", sources, null, null));
  }

  function test_fromGroup() {
    compare(InputSources.fromGroup("fcitx5", {
      "defaultLayout": "us",
      "group": [
        {
          "name": "keyboard-us",
          "layout": ""
        },
        {
          "name": "keyboard-de-neo",
          "layout": "de-neo"
        },
        {
          "name": "mozc",
          "layout": "us"
        },
        {
          "name": "anthy",
          "layout": "jp"
        },
        {
          "name": "keyboard-us",
          "layout": ""
        }
      ]
    }), [xkbSource("us", "us"), xkbSource("de-neo", "de", "neo"), imeSource("mozc", "mozc"), imeSource("anthy", "anthy", "jp"), xkbSource("us2", "us")]);
    compare(InputSources.fromGroup("ibus", {
      "group": [
        {
          "name": "xkb:de:neo:deu",
          "layout": ""
        },
        {
          "name": "mozc-jp",
          "layout": ""
        }
      ]
    }), [xkbSource("de-neo", "de", "neo"), imeSource("mozc-jp", "mozc-jp")]);
    compare(InputSources.fromGroup("fcitx5", null), []);
  }
}
