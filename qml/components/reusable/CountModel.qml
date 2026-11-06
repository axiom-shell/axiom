pragma ComponentBehavior: Bound
import Quickshell

// A ListView's model of `count` rows, for rows that read their data by
// index: a new count adds or removes rows at the end, so the view keeps
// its place (a plain number as the model rebuilds every row and scrolls
// back to the top)
ScriptModel {
  id: root

  property int count: 0

  values: Array.from({
    length: root.count
  }, (_, i) => i)
}
