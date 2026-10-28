import QtQuick
import QtTest
import qs.components.methods

TestCase {
  id: test
  name: "BindGroups"

  RepoFiles {
    id: files
  }

  // The bind actions' table the daemon sends (compositor.bindActions)
  readonly property var table: files.json("backend/internal/compositor/actions/table.json")

  function bind(key, action, argument, extra) {
    return Object.assign({
      "key": key,
      "action": action,
      "argument": argument ?? "",
      "description": ""
    }, extra ?? {});
  }

  function test_runKey() {
    verify(BindGroups.runKey(test.table, bind("SUPER + 1", "workspaceNth", "1")) !== "");
    compare(BindGroups.runKey(test.table, bind("SUPER + 1", "workspaceNth", "1")), BindGroups.runKey(test.table, bind("SUPER + 5", "workspaceNth", "5")));
    compare(BindGroups.runKey(test.table, bind("SUPER + 0", "workspaceNth", "10")), BindGroups.runKey(test.table, bind("SUPER + 1", "workspaceNth", "1")));
    compare(BindGroups.runKey(test.table, bind("SUPER + 2", "workspaceNth", "3")), "", "key and number differ");
    compare(BindGroups.runKey(test.table, bind("SUPER + 1", "workspaceNth", "1", {
      "description": "Mail"
    })), "", "a label of its own");
    compare(BindGroups.runKey(test.table, bind("SUPER + Q", "terminal")), "");
    verify(BindGroups.runKey(test.table, bind("SUPER + 1", "workspaceNth", "1")) !== BindGroups.runKey(test.table, bind("SUPER + SHIFT + 1", "workspaceNth", "1")));
    verify(BindGroups.runKey(test.table, bind("SUPER + 1", "workspaceNth", "1")) !== BindGroups.runKey(test.table, bind("SUPER + 2", "workspaceNth", "2", {
      "paused": true
    })));
  }

  function test_groups() {
    const binds = [bind("SUPER + Q", "terminal"), bind("SUPER + 2", "workspaceNth", "2"), bind("SUPER + C", "closeWindow"), bind("SUPER + 1", "workspaceNth", "1"), bind("SUPER + 3", "workspaceNth", "3"), bind("SUPER + SHIFT + 1", "moveWindowNth", "1"), bind("SUPER + space", "launcher")];
    const sections = ["Apps", "Workspace", "Window", "Workspace", "Workspace", "Workspace", "Axiom"];
    const groups = BindGroups.groups(test.table, binds, [0, 1, 2, 3, 4, 5, 6], sections, ["Axiom", "Apps", "Workspace"]);
    compare(groups.map(g => g.key), ["Axiom", "Apps", "Workspace", "Window"]);
    compare(groups[2].indices, [1, 3, 4, 5]);
    // The run sits where its first bind shows, its binds by number; a
    // single numbered bind is a row of its own
    compare(groups[2].rows, [[3, 1, 4], [5]]);
    compare(BindGroups.runNumbers(binds, [3, 1, 4]), "1–3");
    compare(BindGroups.runKeys(binds, [3, 1, 4]), "1–3");
  }

  function test_groupsOnlyShown() {
    const binds = [bind("SUPER + 1", "workspaceNth", "1"), bind("SUPER + 2", "workspaceNth", "2"), bind("SUPER + Q", "terminal")];
    const groups = BindGroups.groups(test.table, binds, [1, 2], ["Workspace", "Workspace", "Apps"], []);
    compare(groups.map(g => g.key), ["Apps", "Workspace"]);
    compare(groups[1].rows, [[1]]);
  }

  function test_runText() {
    const binds = [bind("SUPER + 1", "workspaceNth", "1"), bind("SUPER + 2", "workspaceNth", "2"), bind("SUPER + 4", "workspaceNth", "4"), bind("SUPER + 0", "workspaceNth", "10")];
    compare(BindGroups.runNumbers(binds, [0, 1, 2]), "1 2 4");
    compare(BindGroups.runKeys(binds, [0, 1, 2]), "1 2 4");
    compare(BindGroups.runNumbers(binds, [0, 1]), "1 2");
  }
}
