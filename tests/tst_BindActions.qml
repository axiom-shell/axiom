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
    return files.json("config/json/config.schema.json").definitions.Keybind.properties.action.enum;
  }

  function test_everySchemaActionIsKnown() {
    for (const action of _schemaActions())
      verify(action === "exec" || test.table.ipcActions[action] !== undefined || test.table.compositorActions[action] !== undefined, action + " has no entry");
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
      "action": "launcher",
      "call": "open"
    }), "App launcher (open)");
  }

  function test_descriptionFor() {
    compare(shared.calls.BindActions.descriptionFor(test.table, {
      "action": "closeWindow"
    }), "Window: Close");
    compare(shared.calls.BindActions.descriptionFor(test.table, {
      "action": "closeWindow",
      "description": "Kill it"
    }), "Window: Kill it");
    compare(shared.calls.BindActions.descriptionFor(test.table, {
      "action": "closeWindow",
      "description": "Mine: Kill it"
    }), "Mine: Kill it", "a description naming its own section keeps it");
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
      "scratchpad": true
    }), "any one of its capabilities");
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
}
