import QtQuick
import QtTest
import qs.components.methods

// SwayConf: sway's command and config text from axiom's settings.
TestCase {
  id: test
  name: "SwayConf"

  // Records the helpers' calls as shared fixtures for the axiom binary
  Shared {
    id: shared
    testCase: test
  }

  RepoFiles {
    id: files
  }

  readonly property var ctx: ({
      "shellCommand": "'/opt/axiom'",
      "restartCommand": "'/usr/bin/axiom' restart",
      "terminal": "foot",
      "fileManager": "nautilus --new-window",
      "browser": "firefox"
    })

  function test_quote() {
    compare(shared.calls.SwayConf.quote("DP-1"), "DP-1");
    compare(shared.calls.SwayConf.quote("AOC CU34G4Z XJ9"), "\"AOC CU34G4Z XJ9\"");
    // Sway keeps a backslash before a quote, so a `"` is single-quoted
    compare(shared.calls.SwayConf.quote("say \"hi\""), "\"say \"'\"'\"hi\"'\"'");
    compare(shared.calls.SwayConf.quote("\""), "'\"'");
    compare(shared.calls.SwayConf.quote(""), "\"\"");
    compare(shared.calls.SwayConf.quote("it's"), "\"it's\"");
  }

  // WindowLook with every part off, `parts` over it
  function off(parts) {
    const look = {};
    for (const part of ["borders", "shape", "gaps", "blur", "shadow", "dim", "opacity"])
      look[part] = Object.assign({
        "enabled": false
      }, parts[part] ?? {});
    return look;
  }

  function test_inputLines() {
    const schema = files.json("config/json/config.schema.json").properties.Input;
    const input = shared.calls.CompositorLayer.input({
      "keyboard": {
        "enabled": true,
        "layout": "us,de",
        "variant": "",
        "options": "caps:escape",
        "repeatRate": 50,
        "repeatDelay": 300,
        "numlock": true
      },
      "mouse": {
        "enabled": true,
        "accel": "default",
        "sensitivity": -25,
        "leftHanded": false
      },
      "touchpad": {
        "enabled": false,
        "naturalScroll": true
      },
      "cursor": {
        "enabled": true,
        "theme": "Bibata Modern",
        "size": 24
      }
    });
    verify(!shared.calls.SwayConf.inputLines(input, schema, true).includes("input type:keyboard xkb_numlock enabled"));
    compare(shared.calls.SwayConf.inputLines(input, schema, false), ["input type:keyboard xkb_layout \"us,de\"", "input type:keyboard xkb_variant \"\"", "input type:keyboard xkb_options caps:escape", "input type:keyboard repeat_rate 50", "input type:keyboard repeat_delay 300", "input type:keyboard xkb_numlock enabled", "input type:pointer pointer_accel -0.25", "input type:pointer left_handed disabled", "seat * xcursor_theme \"Bibata Modern\" 24"]);
  }
}
