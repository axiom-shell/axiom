import QtQuick
import QtTest
import qs.components.methods

// InputSources: the input sources as the compositor, fcitx5 and ibus take
// them. xkb() goes through Shared: its cases are replayed by the Go port
// (render.XkbLayouts, with Input.method.enabled as `engines`).
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
    compare(shared.calls.InputSources.xkb(test.mixed, true), {
      "layouts": ["us", "de", "jp"],
      "variants": ["", "neo", ""],
      "layout": "us,de,jp",
      "variant": ",neo,"
    }, "xkb sources first, then the layouts an ime one adds");
    compare(shared.calls.InputSources.xkb(test.mixed, false), {
      "layouts": ["us", "de"],
      "variants": ["", "neo"],
      "layout": "us,de",
      "variant": ",neo"
    }, "with the input method off, only the xkb sources count");
    compare(shared.calls.InputSources.xkb([xkbSource("a", "us"), xkbSource("b", "us"), xkbSource("c", "us", "dvorak")]).layout, "us,us", "each pair once");
    compare(shared.calls.InputSources.xkb([imeSource("mozc", "mozc")], true).layout, "us", "never empty");
    compare(shared.calls.InputSources.xkb([imeSource("pinyin", "pinyin", "jp")], false).layout, "us", "an engine's layout left out while off");
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
    compare(InputSources.current(test.mixed, 1, "keyboard-us", "fcitx5", null), "neo", "the compositor switched layouts itself: its index, not fcitx5's keyboard-us");
    compare(InputSources.current(test.mixed, 1, "mozc", "fcitx5", null), "mozc", "an engine stays current on another layout");
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
    compare(InputSources.effective(test.mixed, ["us", "de", "jp"], true), test.mixed, "the compositor has the sources' layouts");
    compare(InputSources.effective(test.mixed, ["us", "de"], false), test.mixed, "off: without the engines' typing layouts");
    compare(InputSources.effective(test.mixed, ["us", "de", "jp"], false).map(s => s.id), ["xkb:0:us", "xkb:1:de", "xkb:2:jp", "mozc", "pinyin"], "off, an engine's layout is the compositor's own");
    compare(InputSources.effective(test.mixed, [], true), test.mixed, "not known yet");
    const own = InputSources.effective(test.mixed, ["fr", "us"], true);
    compare(own.map(s => s.id), ["xkb:0:fr", "xkb:1:us", "mozc", "pinyin"], "the compositor's own layouts, then the engines");
    compare(own[0].layout, "fr");
    compare(own[3].layout, "", "an engine's layout the compositor lacks: the first");
    compare(InputSources.xkbIndex(own, own[3]), 0, "never an index past the compositor's list");
    compare(InputSources.effective([xkbSource("x", "fr"), imeSource("p", "pinyin", "us", "intl")], ["us", "fr"], true)[2].layout, "us", "one the compositor has stays");
    compare(InputSources.effective([xkbSource("x", ""), imeSource("e", "")], [], true), [], "only usable ones");
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

  // Only the engines the framework has installed are pushed, and compared
  function test_installedEngines() {
    const available = [
      {
        "name": "keyboard-us"
      },
      {
        "name": "pinyin"
      }
    ];
    compare(InputSources.installed(test.mixed, "fcitx5", null, available).map(s => s.id), ["us", "neo", "pinyin"], "an engine not installed is left out, xkb sources kept");
    compare(InputSources.installed(test.mixed, "fcitx5", null, undefined).length, test.mixed.length, "without a list every engine stays");
    compare(InputSources.fcitx5Group(test.mixed, available), {
      "defaultLayout": "us",
      "items": [
        {
          "name": "keyboard-us",
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
    }, "mozc missing: left out, pinyin's layout kept");
    compare(InputSources.fcitx5Group([imeSource("m", "mozc", "jp")], []), {
      "defaultLayout": "jp",
      "items": []
    }, "the default layout still counts a left-out engine's");
    compare(InputSources.ibusEngines(test.mixed, test.registry, available), ["xkb:us::eng", "xkb:de:neo:deu", "pinyin"]);
    const sources = [xkbSource("us", "us"), imeSource("mozc", "mozc")];
    verify(InputSources.groupMatches("fcitx5", sources, null, {
      "defaultLayout": "us",
      "group": [
        {
          "name": "keyboard-us",
          "layout": "us"
        }
      ],
      "available": [
        {
          "name": "keyboard-us"
        }
      ]
    }), "a read-back without an engine not installed matches");
    verify(!InputSources.groupMatches("fcitx5", sources, null, {
      "defaultLayout": "us",
      "group": [
        {
          "name": "keyboard-us",
          "layout": "us"
        }
      ],
      "available": [
        {
          "name": "keyboard-us"
        },
        {
          "name": "mozc"
        }
      ]
    }), "an installed engine missing still doesn't");
    verify(InputSources.groupMatches("ibus", sources, test.registry, {
      "group": [
        {
          "name": "xkb:us::eng"
        }
      ],
      "available": []
    }), "ibus: the same");
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

  function test_searchLayouts() {
    compare(InputSources.searchLayouts(test.registry, "german").map(r => r.layout + ":" + r.variant), ["de:", "de:neo"], "a layout before its variants");
    compare(InputSources.searchLayouts(test.registry, "NEO"), [
      {
        "layout": "de",
        "variant": "neo",
        "description": "German (Neo 2)"
      }
    ], "any case, by the variant's name");
    compare(InputSources.searchLayouts(test.registry, "us dvorak").length, 1, "every word holds");
    compare(InputSources.searchLayouts(test.registry, "").length, 4, "everything without a query");
    compare(InputSources.searchLayouts(test.registry, "", 3).length, 3, "at most limit");
    compare(InputSources.searchLayouts(null, "de"), [], "none without a registry");
  }

  function test_freeId() {
    compare(InputSources.freeId(test.mixed, "de"), "de");
    compare(InputSources.freeId(test.mixed, "us"), "us2", "numbered when taken");
    compare(InputSources.freeId([xkbSource("us", "us"), xkbSource("us2", "us")], "us"), "us3");
    compare(InputSources.freeId([], "mozc:jp"), "mozc-jp", "made an id");
    compare(InputSources.freeId(null, " -x"), "x", "starting with a letter or digit");
    compare(InputSources.freeId([], ""), "source");
  }

  // Through Shared: render.InputMethodEnv / InputMethodCommand replay these
  function test_methodSetup() {
    compare(shared.calls.InputSources.methodSetup("fcitx5", false), {
      "env": [
        {
          "name": "XMODIFIERS",
          "value": "@im=fcitx"
        },
        {
          "name": "QT_IM_MODULES",
          "value": "wayland;fcitx;ibus"
        },
        {
          "name": "SDL_IM_MODULE",
          "value": "fcitx"
        },
        {
          "name": "GLFW_IM_MODULE",
          "value": "ibus"
        }
      ],
      "command": "fcitx5 -d --replace"
    });
    const legacy = shared.calls.InputSources.methodSetup("fcitx5", true).env.map(e => e.name + "=" + e.value);
    compare(legacy.slice(4), ["GTK_IM_MODULE=fcitx", "QT_IM_MODULE=fcitx"], "legacyApps adds the im modules");
    const ibus = shared.calls.InputSources.methodSetup("ibus", true);
    compare(ibus.env.map(e => e.name + "=" + e.value), ["XMODIFIERS=@im=ibus", "QT_IM_MODULES=wayland;ibus", "SDL_IM_MODULE=ibus", "GLFW_IM_MODULE=ibus", "GTK_IM_MODULE=ibus", "QT_IM_MODULE=ibus"]);
    compare(ibus.command, "ibus-daemon -drxR");
    compare(shared.calls.InputSources.methodSetup("ibus", false).env.length, 4);
    for (const none of ["none", "auto", ""])
      compare(shared.calls.InputSources.methodSetup(none, true), {
        "env": [],
        "command": ""
      }, none);
  }
}
