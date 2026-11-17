import QtQuick

// Stand-in for Quickshell's ScriptModel in the layout harness: a ListModel
// rebuilt from `values` (a row each, its value under `value`)
ListModel {
  id: root

  property var values: []

  onValuesChanged: {
    root.clear();
    for (const v of root.values)
      root.append({
        "value": v
      });
  }
}
