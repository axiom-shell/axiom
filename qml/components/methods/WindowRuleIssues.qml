pragma Singleton

import QtQuick

// Where a window rules report's issues sit (pure): the report is
// compositor.state's windowRules, or compositor.checkRules' answer,
// `{ issues: [{ rule, path, code, message, args }], rules: [{ rule, written,
// placed, dropped, live, skipped, missing }] }`. An issue's path is relative to its
// rule ("id", "windows.0", "windows.0.conditions.1.value", "window.size").
// Every function tolerates a null report and missing keys.
QtObject {
  // The issues of one rule in a report, in order
  function of(report, ruleId) {
    return (report?.issues ?? []).filter(issue => issue.rule === ruleId);
  }

  // The report's row for a rule ({rule, written, placed, dropped, live,
  // skipped, missing}), or null
  function rowOf(report, ruleId) {
    return (report?.rules ?? []).find(row => row.rule === ruleId) ?? null;
  }

  // How many open windows a rule matches, from windowRules.match's rows
  // (`[{ rule, windows }]`, one per draft rule in order): the row at `index`
  // when it is the rule's, else the first row with its id; 0 for none
  function countOf(rows, ruleId, index) {
    if (!rows || !ruleId)
      return 0;
    const at = rows[index];
    const row = at && at.rule === ruleId ? at : rows.find(r => r.rule === ruleId);
    return row?.windows?.length ?? 0;
  }

  // Issues at a condition (path windows.k.conditions.c, or under it)
  function atCondition(issues, k, c) {
    const base = "windows." + k + ".conditions." + c;
    return (issues ?? []).filter(issue => issue.path === base || String(issue.path).startsWith(base + "."));
  }

  // Issues on the kind itself (path exactly windows.k)
  function atKind(issues, k) {
    return (issues ?? []).filter(issue => issue.path === "windows." + k);
  }

  // The rest: paths not starting with "windows."
  function general(issues) {
    return (issues ?? []).filter(issue => !String(issue.path).startsWith("windows."));
  }
}
