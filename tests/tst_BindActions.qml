import QtQuick
import QtTest
import qs.components.methods

// BindActions: what each keybind action is (labels, sections, calls,
// arguments), read off the daemon's table, checked against the schema's
// action list.
TestCase {
  id: test
  name: "BindActions"

  // Records the helpers' calls as shared fixtures for the axiom binary
  Shared {
    id: shared
    testCase: test
  }

  RepoFiles {
    id: files
  }

  // The table the daemon sends (compositor.bindActions)
  readonly property var table: files.json("backend/internal/compositor/actions/table.json")

  function _schemaActions() {
    return files.json("qml/config/json/config.schema.json").definitions.Keybind.properties.action.enum;
  }

  function test_everySchemaActionIsKnown() {
    for (const action of _schemaActions())
      verify(action === "exec" || test.table.ipcActions[action] !== undefined || test.table.compositorActions[action] !== undefined, action + " has no entry");
  }

  // Every action has its icon in the table (the picker, a tile, a
  // launcher command show it)
  function test_everyActionHasAnIcon() {
    for (const action of _schemaActions())
      verify(test.table.icons[action] !== undefined, action + " has no icon");
    compare(BindActions.iconOf(test.table, "wifi"), "wifi");
    compare(BindActions.iconOf(test.table, "nope"), "keyboard", "an unknown action's icon");
    compare(BindActions.iconOf(null, "wifi"), "keyboard", "no table yet");
  }

  // The theme action takes a theme (or random), random by default
  function test_theme() {
    compare(BindActions.argumentKind(test.table, "theme"), "theme");
    compare(BindActions.ipcCall(test.table, "theme", "", "toggle"), {
      "target": "theme",
      "function": "set",
      "args": ["random"]
    });
    compare(BindActions.ipcCall(test.table, "theme", "tokyo-night", "toggle").args, ["tokyo-night"]);
    compare(BindActions.ipcCall(test.table, "airplane", "", "open"), {
      "target": "airplane",
      "function": "enable",
      "args": []
    });
    compare(BindActions.ipcCall(test.table, "reboot", "", "toggle"), {
      "target": "session",
      "function": "reboot",
      "args": []
    });
  }

  function test_noActionIsBoth() {
    for (const action of Object.keys(test.table.ipcActions))
      verify(test.table.compositorActions[action] === undefined, action + " is both an IPC and a compositor action");
  }

  function test_calls() {
    verify(shared.calls.BindActions.hasCalls(test.table, "launcher"));
    verify(!shared.calls.BindActions.hasCalls(test.table, "lock"));
    compare(shared.calls.BindActions.callOf(test.table, {
      "action": "overlay",
      "call": "open"
    }), "open");
    compare(shared.calls.BindActions.callOf(test.table, {
      "action": "lock",
      "call": "open"
    }), "toggle", "an action without calls always toggles");
    compare(shared.calls.BindActions.callFunction(test.table, {
      "action": "workspaceOverview",
      "call": "close"
    }), "hide", "the call's IPC function");
    compare(shared.calls.BindActions.callFunction(test.table, {
      "action": "overlay"
    }), "toggle");
    compare(shared.calls.BindActions.callFunction(test.table, {
      "action": "workspaceOverview",
      "call": "open"
    }), "open", "workspaceOverlay has open, not show");
    compare(shared.calls.BindActions.callFunction(test.table, {
      "action": "wifi",
      "call": "close"
    }), "disable", "an on/off action's off");
  }

  function test_ipcCall() {
    compare(BindActions.ipcCall(test.table, "overlayPage", " Themes "), {
      "target": "overlay",
      "function": "page",
      "args": ["Themes"]
    });
    compare(BindActions.ipcCall(test.table, "workspaceOverview", ""), {
      "target": "workspaceOverlay",
      "function": "toggle",
      "args": []
    }, "a call's toggle");
    compare(BindActions.ipcCall(test.table, "launcherSearch", "two words"), {
      "target": "appLauncher",
      "function": "search",
      "args": ["two words"]
    }, "an argument with spaces stays one");
    compare(BindActions.ipcCall(test.table, "launcherSearch", "US$'s $& rate").args, ["US$'s $& rate"], "$ in an argument is no replacement pattern");
    compare(BindActions.ipcCall(test.table, "workspaceNth", "3").args, ["3", "go"]);
    compare(BindActions.ipcCall(test.table, "workspaceNth", ""), null, "missing its argument");
    compare(BindActions.ipcCall(test.table, "screenshot", "").args, ["region"], "the table's default argument");
    compare(BindActions.ipcCall(test.table, "timerStart", "10m tea"), {
      "target": "stopwatch",
      "function": "timer",
      "args": ["10m tea"]
    });
    compare(BindActions.ipcCall(test.table, "clipboard", ""), {
      "target": "appLauncher",
      "function": "clipboard",
      "args": []
    });
    compare(BindActions.ipcCall(test.table, "closeWindow", ""), null, "a compositor action");
    compare(BindActions.ipcCall(test.table, "toggleMicMute", "", "open"), {
      "target": "microphone",
      "function": "enable",
      "args": []
    }, "a call: the microphone on");
    compare(BindActions.ipcCall(test.table, "toggleDnd", "", "close").function, "disable");
    compare(BindActions.ipcCall(test.table, "lock", "", "open").function, "lock", "an action without calls ignores one");
  }

  // The Keybinds page's names for the actions (the schema's) and the
  // compositor's bind descriptions (the table's, where they take no
  // argument) are one name each; a hot corner's call (the table's calls,
  // as the schema build fills it) shows where a bind's does
  function test_labelsAgree() {
    const schema = files.json("qml/config/json/config.schema.json");
    const binds = schema.definitions.Keybind.properties;
    const corners = schema.properties.HotCorners.properties.items.items.properties;
    for (const [action, label] of Object.entries(binds.action["x-enumLabels"])) {
      const own = test.table.ipcActions[action]?.[1] ?? test.table.compositorActions[action]?.[0];
      if (own !== undefined && !own.includes("{0}"))
        compare(own, label, action + " in table.json");
    }
    compare(corners.call["x-showIf"].action.filter(action => !binds.call["x-showIf"].action.includes(action)), [], "a corner's call shows where a bind's does");
  }

  function test_needsArgument() {
    verify(shared.calls.BindActions.needsArgument(test.table, "exec"));
    verify(shared.calls.BindActions.needsArgument(test.table, "workspaceNth"), "{0} in the IPC call");
    verify(shared.calls.BindActions.needsArgument(test.table, "focusDir"), "{0} in a compositor action's label");
    verify(shared.calls.BindActions.needsArgument(test.table, "raw"));
    verify(!shared.calls.BindActions.needsArgument(test.table, "launcher"));
    verify(!shared.calls.BindActions.needsArgument(test.table, "closeWindow"));
  }

  // An argument is needed exactly where the IPC call or the label has a
  // place for it ({0}), and by exec
  function test_argumentsMatchTheTemplates() {
    for (const action of _schemaActions()) {
      const template = test.table.ipcActions[action]?.[0] ?? test.table.compositorActions[action]?.[0] ?? "";
      compare(shared.calls.BindActions.needsArgument(test.table, action), action === "exec" || template.includes("{0}"), action);
    }
    compare(shared.calls.BindActions.argumentKind(test.table, "workspaceNth"), "workspace");
    compare(shared.calls.BindActions.argumentKind(test.table, "closeWindow"), "");
  }

  function test_labels() {
    compare(shared.calls.BindActions.sectionFor(test.table, "volumeUp"), "Media");
    compare(shared.calls.BindActions.sectionFor(test.table, "toggleSpecial"), "Special");
    compare(shared.calls.BindActions.sectionFor(test.table, "pomodoro"), "Tools");
    compare(shared.calls.BindActions.sectionFor(test.table, "nightLight"), "System");
    compare(shared.calls.BindActions.sectionFor(test.table, "nope"), "Axiom", "unknown actions file under Axiom");
    compare(shared.calls.BindActions.defaultLabel(test.table, {
      "action": "workspaceNth",
      "argument": " 3 "
    }), "Go to workspace 3");
    compare(shared.calls.BindActions.defaultLabel(test.table, {
      "action": "exec",
      "argument": "kitty"
    }), "kitty", "exec shows its command");
    compare(shared.calls.BindActions.defaultLabel(test.table, {
      "action": "launcherSearch",
      "argument": "US$'s $& rate"
    }), "Launcher: US$'s $& rate", "$ in an argument is no replacement pattern");
    compare(shared.calls.BindActions.defaultLabel(test.table, {
      "action": "launcher",
      "call": "open"
    }), "App launcher (open)");
  }

  function test_splitDescription() {
    compare(shared.calls.BindActions.splitDescription("Media: Play"), {
      "section": "Media",
      "label": "Play"
    });
    compare(shared.calls.BindActions.splitDescription(" Media : Play "), {
      "section": "Media",
      "label": "Play"
    }, "trimmed, a leading space too");
    compare(shared.calls.BindActions.splitDescription("a:b: c"), {
      "section": "",
      "label": "a:b: c"
    }, "a colon before the section's names none, as hasOwnSection reads it");
    compare(shared.calls.BindActions.splitDescription("Mine:no space"), {
      "section": "",
      "label": "Mine:no space"
    });
    compare(shared.calls.BindActions.splitDescription(undefined), {
      "section": "",
      "label": ""
    });
  }

  function test_hasOwnSection() {
    verify(shared.calls.BindActions.hasOwnSection("Mine: Kill it"));
    verify(!shared.calls.BindActions.hasOwnSection("Mine:no space"));
  }

  function test_supported() {
    const hyprland = {
      "strips": true,
      "namedSpecial": true,
      "switcher": true
    };
    verify(shared.calls.BindActions.supported(test.table, "closeWindow", {}), "needs nothing");
    verify(shared.calls.BindActions.supported(test.table, "stripWider", hyprland));
    verify(!shared.calls.BindActions.supported(test.table, "stripWider", {}));
    verify(shared.calls.BindActions.supported(test.table, "toggleSpecial", {
      "namedSpecial": true
    }), "its capability");
    for (const action in test.table.needs)
      verify(_schemaActions().includes(action), action + " is an action");
  }

  function test_appliesUnder() {
    const raw = {
      "action": "raw",
      "compositor": "hyprland",
      "argument": "hl.dsp.layout(\"swapsplit\")"
    };
    verify(shared.calls.BindActions.appliesUnder(test.table, raw, "hyprland", {}));
    verify(!shared.calls.BindActions.appliesUnder(test.table, raw, "sway", {}), "written for another compositor");
    verify(!shared.calls.BindActions.appliesUnder(test.table, {
      "action": "pseudo"
    }, "sway", {}));
  }

  function test_tapsNeedModifierTap() {
    const tap = {
      "key": "Super_L",
      "action": "launcher"
    };
    verify(shared.calls.BindActions.appliesUnder(test.table, tap, "sway", {
      "modifierTap": true
    }));
    verify(!shared.calls.BindActions.appliesUnder(test.table, tap, "niri", {}));
    verify(shared.calls.BindActions.keySupported("SUPER + Q", {}));
  }

  function test_switcherHeld() {
    compare(shared.calls.BindActions.switcherHeld(["ALT"]), ["ALT"]);
    compare(shared.calls.BindActions.switcherHeld(["ALT", "SHIFT"]), ["ALT"], "SHIFT only turns it around");
    compare(shared.calls.BindActions.switcherHeld(["SHIFT"]), ["SHIFT"], "unless it's all there is");
    compare(shared.calls.BindActions.switcherHeld([]), [], "nothing to hold");
  }
}
