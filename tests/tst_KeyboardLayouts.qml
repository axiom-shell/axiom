import QtQuick
import QtTest
import qs.components.methods

// KeyboardLayouts: a keyboard's layouts from their full names.
TestCase {
  name: "KeyboardLayouts"

  function test_shape() {
    compare(KeyboardLayouts.shape(["English (US)", "German"], 1, "us, de"), {
      "layouts": ["us", "de"],
      "index": 1,
      "keymap": "German"
    });
    // Codes that don't match the layouts are left alone
    compare(KeyboardLayouts.shape(["English (US)", "German"], 0, "us").layouts, ["us", "ge"]);
    compare(KeyboardLayouts.shape(["English (US)"], undefined, "").index, 0);
  }

  readonly property var registry: ({
      "layouts": [
        {
          "name": "us",
          "description": "English (US)",
          "variants": [
            {
              "name": "dvorak",
              "description": "English (Dvorak)"
            }
          ]
        },
        {
          "name": "de",
          "description": "German",
          "variants": [
            {
              "name": "neo",
              "description": "German (Neo 2)"
            }
          ]
        }
      ]
    })

  function test_code_from_registry() {
    compare(KeyboardLayouts.code("German", registry), "de", "not its first two letters");
    compare(KeyboardLayouts.code("German (Neo 2)", registry), "de", "a variant's name: its layout");
    compare(KeyboardLayouts.code("English (Dvorak)", registry), "us");
    compare(KeyboardLayouts.code("Klingon", registry), "kl", "not listed: guessed");
    compare(KeyboardLayouts.shape(["English (US)", "German"], 0, "us", registry).layouts, ["us", "de"]);
  }

  function test_code() {
    compare(KeyboardLayouts.code("English (US)"), "us");
    compare(KeyboardLayouts.code("German"), "ge", "no registry: guessed");
    compare(KeyboardLayouts.code("English (Dvorak, intl.)"), "en");
  }
}
