import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "WindowRuleIssues"

  readonly property var report: ({
      "issues": [
        {
          "rule": "a",
          "path": "windows.0.conditions.1.value",
          "code": "emptyValue",
          "message": "Enter a value.",
          "args": []
        },
        {
          "rule": "b",
          "path": "id",
          "code": "x",
          "message": "m",
          "args": []
        },
        {
          "rule": "a",
          "path": "windows.0",
          "code": "emptyKind",
          "message": "k",
          "args": []
        },
        {
          "rule": "a",
          "path": "windows.1.conditions.10",
          "code": "y",
          "message": "n",
          "args": []
        },
        {
          "rule": "a",
          "path": "windows.0.conditions.1",
          "code": "z",
          "message": "o",
          "args": []
        },
        {
          "rule": "a",
          "path": "window.size",
          "code": "sizePair",
          "message": "s",
          "args": []
        },
        {
          "rule": "a",
          "path": "windows",
          "code": "noKinds",
          "message": "w",
          "args": []
        }
      ],
      "rules": [
        {
          "rule": "a",
          "written": [],
          "placed": ["workspace"],
          "dropped": [],
          "live": [],
          "skipped": [0]
        }
      ]
    })

  function paths(issues) {
    return issues.map(issue => issue.path);
  }

  function test_of() {
    compare(WindowRuleIssues.of(report, "b").length, 1);
    compare(paths(WindowRuleIssues.of(report, "a")), ["windows.0.conditions.1.value", "windows.0", "windows.1.conditions.10", "windows.0.conditions.1", "window.size", "windows"]);
    compare(WindowRuleIssues.of(null, "a"), []);
    compare(WindowRuleIssues.of({}, "a"), []);
  }

  function test_rowOf() {
    compare(WindowRuleIssues.rowOf(report, "a").placed, ["workspace"]);
    compare(WindowRuleIssues.rowOf(report, "zz"), null);
    compare(WindowRuleIssues.rowOf(null, "a"), null);
  }

  function test_atCondition() {
    const issues = WindowRuleIssues.of(report, "a");
    compare(paths(WindowRuleIssues.atCondition(issues, 0, 1)), ["windows.0.conditions.1.value", "windows.0.conditions.1"]);
    compare(paths(WindowRuleIssues.atCondition(issues, 1, 1)), []);
    compare(paths(WindowRuleIssues.atCondition(issues, 1, 10)), ["windows.1.conditions.10"]);
    compare(WindowRuleIssues.atCondition(null, 0, 0), []);
  }

  function test_atKind() {
    const issues = WindowRuleIssues.of(report, "a");
    compare(paths(WindowRuleIssues.atKind(issues, 0)), ["windows.0"]);
    compare(WindowRuleIssues.atKind(issues, 1), []);
  }

  function test_general() {
    compare(paths(WindowRuleIssues.general(WindowRuleIssues.of(report, "a"))), ["window.size", "windows"]);
    compare(paths(WindowRuleIssues.general(WindowRuleIssues.of(report, "b"))), ["id"]);
  }

  function test_countOf() {
    const rows = [
      {
        "rule": "a",
        "windows": ["1", "2"]
      },
      {
        "rule": "b",
        "windows": []
      },
      {
        "rule": "c",
        "windows": ["3"]
      }
    ];
    compare(WindowRuleIssues.countOf(rows, "a", 0), 2);
    compare(WindowRuleIssues.countOf(rows, "c", 0), 1);
    compare(WindowRuleIssues.countOf(rows, "b", 1), 0);
    compare(WindowRuleIssues.countOf(rows, "zz", 0), 0);
    compare(WindowRuleIssues.countOf(null, "a", 0), 0);
    compare(WindowRuleIssues.countOf(rows, "", 0), 0);
  }
}
