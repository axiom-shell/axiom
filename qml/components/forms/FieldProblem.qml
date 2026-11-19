pragma ComponentBehavior: Bound
import QtQuick
import qs.components.reusable

// The one line saying what is wrong with a field's value, under its label
// and description (a FieldHeader's `below` slot): `problem`, { level, text }
// (an IssueList issue's shape: "error" red, "warning" amber) or null for
// none. SchemaFormRow and FieldRow draw it; a control or host only sets
// `problem`.
StyledText {
  id: root

  property var problem: null

  // Whether it has a line (the `shows` a FieldHeader's `below` item reports)
  readonly property bool shows: root.problem !== null

  visible: root.shows
  text: root.problem?.text ?? ""
  role: "caption"
  tone: root.problem?.level ?? "error"
  overflow: "wrap"
}
