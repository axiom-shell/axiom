pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

/**
 * Settings page: label and value facts in two columns, the labels muted. Each
 * of `facts` is { label, value, mono, wrap, middle, shown }: `mono` shows
 * the value in the monospace font, `wrap` lets it wrap instead of eliding at
 * the end, `middle` elides the middle (a path), and a fact with `shown:
 * false` is left out. The cells are made per fact, so the list's length is
 * the only thing the grid builds from.
 */
GridLayout {
  id: root

  property var facts: []
  readonly property var _shown: facts.filter(fact => fact.shown !== false)

  Layout.fillWidth: true
  flow: GridLayout.TopToBottom
  rows: Math.max(1, root._shown.length)
  columnSpacing: Widget.spacing * 2
  rowSpacing: Widget.spacing / 2

  Repeater {
    model: CountModel {
      count: root._shown.length
    }

    delegate: StyledText {
      required property int index
      text: root._shown[index]?.label ?? ""
      tone: "muted"
    }
  }

  Repeater {
    model: CountModel {
      count: root._shown.length
    }

    delegate: StyledText {
      id: value
      required property int index
      readonly property var fact: root._shown[index] ?? ({})
      text: fact.value ?? ""
      textFamily: fact.mono ? "monospace" : Appearance.fontFamily
      overflow: fact.wrap ? "wrap" : "line"
      elide: fact.middle ? Text.ElideMiddle : overflow === "line" ? Text.ElideRight : Text.ElideNone // style-exempt: middle elides an identifier, keeping its end
      Layout.fillWidth: true
    }
  }
}
