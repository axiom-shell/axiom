pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

/**
 * Label and value facts in columns, the labels muted (the self-update and dev
 * tree cards, the system info card, the custom widgets' contract). Each of
 * `facts` is { label, value, mono, wrap, middle }: `mono` shows the value in
 * the monospace font, `wrap` lets it wrap instead of eliding at the end and
 * `middle` elides the middle (a path). `pairsPerLine` is 1 (a pair a line) or
 * 2 (two pairs side by side); `monoLabels` sets the labels in the monospace
 * font too (a list of keys). The cells are made per fact, so the list's
 * length is the only thing the grid builds from.
 */
GridLayout {
  id: root

  property var facts: []
  // 1 or 2 pairs on a line
  property int pairsPerLine: 1
  property bool monoLabels: false

  Layout.fillWidth: true
  columns: root.pairsPerLine === 2 ? 4 : 2
  columnSpacing: Widget.spacing * 2
  rowSpacing: Widget.spacing / 2

  // Two cells a fact: its label, then its value
  Repeater {
    model: CountModel {
      count: root.facts.length * 2
    }

    delegate: StyledText {
      id: cell
      required property int index
      readonly property bool isLabel: cell.index % 2 === 0
      readonly property var fact: root.facts[Math.floor(cell.index / 2)] ?? ({})
      text: (cell.isLabel ? cell.fact.label : cell.fact.value) ?? ""
      tone: cell.isLabel ? "muted" : ""
      textFamily: cell.isLabel ? (root.monoLabels ? "monospace" : Appearance.fontFamily) : cell.fact.mono ? "monospace" : Appearance.fontFamily
      overflow: !cell.isLabel && cell.fact.wrap ? "wrap" : "line"
      elide: !cell.isLabel && cell.fact.middle ? Text.ElideMiddle : cell.overflow === "line" ? Text.ElideRight : Text.ElideNone // style-exempt: middle elides an identifier, keeping its end
      Layout.fillWidth: !cell.isLabel
    }
  }
}
