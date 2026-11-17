pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A tool page's toolbar (ToolPane's `toolbar` slot): `leading` controls, a
// search field that fills the row, `trailing` controls and a `count`. Under
// `wrapAt` the trailing controls and the count move to a second line, the
// search never narrower than 160 px of text. `filters` is a second row of
// its own, taking no room while nothing in it shows.
ColumnLayout {
  id: root

  property alias leading: leadingRow.data
  // A search field, always present while set (so its width never jumps)
  property bool searchable: false
  property alias searchText: search.text
  property string searchPlaceholder: ""
  property alias trailing: trailingRow.data
  // A caption at the end (the shown count); hidden below 0
  property int count: -1
  // How many there are before the search and chips narrow them (-1 when not
  // known): while `count` is under it, the caption reads "count of total"
  property int total: -1
  // A plain slot (the active filter chips, in a page that has them)
  property alias filters: filtersRow.data
  // Narrower than this, `trailing` and `count` go to a second line
  property real wrapAt: Widget.textPx(480)

  readonly property bool wrapped: root.width < root.wrapAt
  signal searchEdited

  Layout.fillWidth: true
  spacing: 0

  RowLayout {
    id: firstLine
    Layout.fillWidth: true
    spacing: Widget.spacing

    RowLayout {
      id: leadingRow
      visible: children.length > 0
      spacing: Widget.spacing
    }

    StyledTextEntry {
      id: search
      visible: root.searchable
      Layout.fillWidth: true
      Layout.minimumWidth: Widget.textPx(160)
      Layout.preferredHeight: Widget.height
      placeholderText: root.searchPlaceholder
      clearable: true
      escapeClears: true
      onTextEdited: root.searchEdited()
    }

    // Leading alone fills the row when there is no search
    Item {
      visible: !root.searchable
      Layout.fillWidth: true
    }

    // The tail goes to the second line while wrapped
    RowLayout {
      id: tail
      parent: root.wrapped ? secondLine : firstLine
      Layout.fillWidth: root.wrapped
      spacing: Widget.spacing

      RowLayout {
        id: trailingRow
        visible: children.length > 0
        spacing: Widget.spacing
      }

      Item {
        visible: root.wrapped
        Layout.fillWidth: true
      }

      StyledText {
        visible: root.count >= 0
        role: "caption"
        tone: "muted"
        text: root.total >= 0 && root.count < root.total ? I18n.tr("{0} of {1}", root.count, root.total) : String(root.count)
      }
    }
  }

  RowLayout {
    id: secondLine
    Layout.fillWidth: true
    Layout.topMargin: root.wrapped && (trailingRow.visible || root.count >= 0) ? Widget.spacing : 0
    spacing: Widget.spacing
  }

  // Always shown (a row of no visible child is no height); the margin is
  // only there while something shows
  RowLayout {
    id: filtersRow
    Layout.fillWidth: true
    Layout.topMargin: filtersRow.visibleChildren.length > 0 ? Widget.spacing : 0
    spacing: Widget.spacing
  }
}
