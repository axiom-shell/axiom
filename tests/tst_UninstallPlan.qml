import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "UninstallPlan"

  readonly property var plan: ({
      "actions": [
        {
          "step": "folders",
          "what": "Delete the cache",
          "path": "/h/.cache/axiom"
        },
        {
          "step": "ledger",
          "what": "Delete the file axiom made",
          "path": "/h/a"
        },
        {
          "step": "managed",
          "what": "Give back the config axiom manages",
          "path": "/h/.config/niri/config.kdl"
        },
        {
          "step": "ledger",
          "what": "Put back the default app",
          "path": "/h/mimeapps.list",
          "asks": "RestoreSystem"
        }
      ],
      "counts": {
        "inferred": 0,
        "system": 1,
        "secrets": 0,
        "portal": false
      },
      "greeter": null,
      "running": []
    })

  function test_groups_follow_the_run_order() {
    const groups = UninstallPlan.groups(plan);
    compare(groups.map(g => g.step), ["managed", "ledger", "folders"], "steps in run order, empty ones left out");
    compare(groups[1].actions.length, 2);
    compare(UninstallPlan.groups(null), []);
  }

  function test_a_switch_shows_only_when_there_is_something_to_decide() {
    compare(UninstallPlan.questions(plan).map(q => q.field), ["KeepConfig", "KeepUserContent", "RestoreSystem"]);
    const all = UninstallPlan.questions({
      "counts": {
        "inferred": 2,
        "system": 3,
        "secrets": 4,
        "portal": true
      }
    });
    compare(all.map(q => q.field), ["KeepConfig", "KeepUserContent", "KeepSecrets", "UndoInferred", "RestoreSystem", "RestartPortal"], "the order they are asked in");
    compare(all[2].count, 4);
    compare(UninstallPlan.questions(null).length, 2, "no plan: the two that are always asked");
  }

  function test_answers_are_the_defaults_over_the_choices() {
    const defaults = UninstallPlan.answers({});
    compare(defaults.keepConfig, true);
    compare(defaults.keepUserContent, true);
    compare(defaults.keepSecrets, true);
    compare(defaults.undoInferred, true);
    compare(defaults.restoreSystem, false, "system choices are put back only on the switch");
    compare(defaults.restartPortal, true);
    const chosen = UninstallPlan.answers({
      "keepConfig": false,
      "restoreSystem": true
    });
    compare(chosen.keepConfig, false);
    compare(chosen.restoreSystem, true);
    compare(chosen.keepUserContent, true);
    compare(UninstallPlan.answers(null).keepConfig, true);
  }

  function test_it_starts_when_nothing_stands_in_the_way() {
    verify(UninstallPlan.canStart(plan, false));
    verify(!UninstallPlan.canStart(null, false), "no plan yet");
    verify(!UninstallPlan.canStart(plan, true), "the login screen is being removed");
    verify(!UninstallPlan.canStart({
      "actions": [],
      "greeter": {
        "text": "x",
        "paths": []
      },
      "running": []
    }, false), "the login screen is installed: first");
    verify(!UninstallPlan.canStart({
      "actions": [],
      "greeter": null,
      "running": ["wayland-2"]
    }, false), "another axiom runs");
  }
}
