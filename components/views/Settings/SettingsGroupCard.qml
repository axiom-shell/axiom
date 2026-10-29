pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.reusable

// i18n: keys from the schema (titles, descriptions)
// One group of settings (a section's own fields, or one nested object) as
// a card: title, help text, then its rows. Clicking the header folds it
// (remembered by SettingsManager); search results are always unfolded.
// With unsaved edits, Discard drops just those.
FoldingCard {
  id: root

  // A SchemaLayout.groups() entry, rows possibly filtered by a search
  required property var group
  // Provides valueAt(path) and edited(path, value) (SettingsContent)
  required property var form
  // Searching: name the section too, since cards come from all over
  property bool showSection: false

  title: I18n.tr(root.group.title)
  description: root.group.description === "" ? "" : I18n.tr(root.group.description)
  section: root.showSection && root.group.section !== root.group.title ? I18n.tr(root.group.section) : ""
  foldable: !root.showSection
  collapsed: !root.showSection && SettingsManager.isCollapsed(root.group.key)
  // Unsaved edits inside: Discard shows, and folded the dot, so they
  // aren't forgotten
  marked: root.group.rows.some(row => SettingsManager.hasChangesUnder(row.path.join(".")))
  onToggled: SettingsManager.setCollapsed(root.group.key, !root.collapsed)

  // The row showing a setting (a key path), or null (a jump flashes it)
  function rowItem(path) {
    const key = path.join(".");
    for (let i = 0; i < fieldRows.count; i++) {
      const row = fieldRows.itemAt(i) as SettingsField;
      if (row && row.row.path.join(".") === key)
        return row;
    }
    return null;
  }

  // Discard: only this card's unsaved edits (and text typed in it), the
  // rest of the page's kept
  headerExtras: StyledTextButton {
    visible: root.foldable && root.marked
    Layout.preferredHeight: Widget.height - Widget.px(4)
    text: I18n.tr("Discard")
    iconText: "undo"
    onClicked: {
      EditsManager.discardTypingIn(root);
      SettingsManager.discard(root.group.rows.filter(row => row.kind !== "group").map(row => row.path));
    }
  }

  // The section's `x-intro` (settings/<name>.qml): status and actions
  // above the fields, gone while its `shown` (if it has one) is false
  Loader {
    readonly property var intro: item
    active: !!root.group.intro
    visible: active && intro?.shown !== false
    Layout.fillWidth: true
    source: active ? Qt.resolvedUrl(root.group.intro + ".qml") : ""
  }

  // The top row drawn (FormRow.first)
  readonly property int _firstRow: Utils.firstFormRow(fieldRows.count, i => fieldRows.itemAt(i))

  // Rows a field marked `x-beside` shares with the field before it, each
  // taking half; every other field takes the whole width. The pair should
  // share an `x-showIf`, or one shown alone keeps half the width
  GridLayout {
    Layout.fillWidth: true
    columns: 2
    columnSpacing: Widget.spacing * 2
    // The rows keep their gaps themselves (FormRow.dividerGap)
    rowSpacing: 0

    Repeater {
      id: fieldRows
      model: root.group.rows

      delegate: SettingsField {
        required property var modelData
        required property int index
        readonly property bool half: modelData.schema?.["x-beside"] === true || root.group.rows[index + 1]?.schema?.["x-beside"] === true
        // Beside the top row, it's on the top line too
        first: index === root._firstRow || (modelData.schema?.["x-beside"] === true && index - 1 === root._firstRow)
        row: modelData
        form: root.form
        Layout.columnSpan: half ? 1 : 2
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
      }
    }
  }
}
