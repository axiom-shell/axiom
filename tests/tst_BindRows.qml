import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "BindRows"

  function row(label, mods, keys, extra) {
    return Object.assign({
      "label": label,
      "combos": [
        {
          "mods": mods,
          "keys": keys
        }
      ],
      "axiom": true,
      "user": false,
      "ids": [label],
      "action": "",
      "overrides": ""
    }, extra ?? {});
  }

  function test_collapseNumbered() {
    const rows = BindRows.collapseNumbered([row("Terminal", ["SUPER"], ["Return"]), row("Go to workspace 1", ["SUPER"], ["1"]), row("Go to workspace 2", ["SUPER"], ["2"]), row("Go to workspace 10", ["SUPER"], ["0"]), row("Move to workspace 1", ["SUPER", "SHIFT"], ["1"]), row("Move to workspace 3", ["SUPER", "SHIFT"], ["3"])]);
    compare(rows.map(r => r.label), ["Terminal", "Go to workspace", "Move to workspace"]);
    compare(rows[1].combos[0].keys, ["1", "2", "10"]);
    compare(rows[2].combos[0].keys, ["1", "3"], "gaps list each number");
    compare(rows[1].ids, ["Go to workspace 1", "Go to workspace 2", "Go to workspace 10"]);
    const contiguous = BindRows.collapseNumbered([row("Go to workspace 1", ["SUPER"], ["1"]), row("Go to workspace 2", ["SUPER"], ["2"]), row("Go to workspace 3", ["SUPER"], ["3"])]);
    compare(contiguous[0].combos[0].keys, ["1–3"]);
    compare(BindRows.collapseNumbered([row("Go to workspace 1", ["SUPER"], ["1"])])[0].label, "Go to workspace 1", "a lone number stays");
  }

  function test_collapseDirections() {
    const rows = BindRows.collapseDirections([row("Focus right", ["SUPER"], ["L", "→"]), row("Focus left", ["SUPER"], ["H", "←"], {
        "action": "focusLeft",
        "user": true
      }), row("Terminal", ["SUPER"], ["Return"]), row("Focus up", ["SUPER"], ["K", "↑"]), row("Focus down", ["SUPER"], ["J", "↓"]), row("Move window left", ["SUPER", "SHIFT"], ["H"]), row("Move window right", ["SUPER", "SHIFT"], ["L"])]);
    compare(rows.map(r => r.label), ["Focus", "Terminal", "Move window"]);
    compare(rows[0].combos[0].cluster, [["H", "J", "K", "L"], ["←", "↓", "↑", "→"]]);
    compare(rows[0].combos[0].keys, ["H", "J", "K", "L", "←", "↓", "↑", "→"]);
    compare(rows[0].action, "focusLeft");
    verify(rows[0].user);
    compare(rows[2].combos[0].cluster, [["H", "L"]], "only the directions bound");
    const mixed = BindRows.collapseDirections([row("Focus left", ["SUPER"], ["H"]), row("Focus right", ["SUPER", "SHIFT"], ["L"])]);
    compare(mixed.map(r => r.label), ["Focus left", "Focus right"], "different modifiers stay apart");
    const twice = BindRows.collapseDirections([row("Focus left", ["SUPER"], ["H"]), row("Focus Left", ["SUPER"], ["A"], {
        "axiom": false,
        "user": true,
        "overrides": "Focus left"
      }), row("Focus right", ["SUPER"], ["L"])]);
    compare(twice[0].combos[0].cluster, [["H", "L"]], "the first row per direction shows");
    compare(twice[0].ids, ["Focus left", "Focus Left", "Focus right"], "every row's ids are kept");
    verify(twice[0].user);
    compare(twice[0].overrides, "Focus left");
  }

  function test_byModifiers() {
    const groups = BindRows.byModifiers([row("Mute", [], ["XF86AudioMute"]), row("Browser", ["SUPER", "SHIFT"], ["B"]), row("Terminal", ["SUPER"], ["Return"]), row("Lock", ["SUPER", "CTRL"], ["L"]), row("Files", ["SUPER"], ["E"])]);
    compare(groups.map(g => g.mods.join("+")), ["SUPER", "SUPER+CTRL", "SUPER+SHIFT", ""]);
    compare(groups[0].rows.map(r => r.label), ["Terminal", "Files"]);
    compare(BindRows.byModifiers([]).length, 0);
  }
}
