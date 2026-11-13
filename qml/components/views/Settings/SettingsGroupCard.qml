pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.reusable

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
  // The `x-intro`'s own status, when it has one (read, not worked out here)
  // or, on a theme integration's card, its hookup's (HookupStatus decides)
  status: introLoader.intro?.status ?? root._hookup?.word ?? ""
  statusColor: introLoader.intro?.status !== undefined ? introLoader.intro.statusColor ?? Theme.foregroundAlt : root._hookup?.tone === "success" ? Theme.success : root._hookup?.tone === "warning" ? Theme.warning : Theme.foregroundAlt
  // Unsaved edits inside: Discard shows, and folded the dot, so they
  // aren't forgotten
  marked: root.group.rows.some(row => SettingsManager.hasChangesUnder(row.path.join(".")))
  onToggled: SettingsManager.setCollapsed(root.group.key, !root.collapsed)

  // The hookup chip of a theme integration's card (its unsaved switch value)
  // I18n.tr("Off") I18n.tr("Checking") I18n.tr("Set up") I18n.tr("Not set up") I18n.tr("Copy the text")
  readonly property bool _hookupOn: !!root.group.hookup && root.form.valueAt(root.group.path.concat([root.group.hookup])) === true
  on_HookupOnChanged: if (root._hookupOn)
    IntegrationHookupManager.check(root.group.hookup)
  Component.onCompleted: if (root._hookupOn)
    IntegrationHookupManager.check(root.group.hookup)
  readonly property var _hookup: {
    if (!root.group.hookup)
      return null;
    const s = HookupStatus.of(root._hookupOn, IntegrationHookupManager.status[root.group.hookup]?.targets ?? []);
    return {
      "word": I18n.tr(s.word),
      "tone": s.tone
    };
  }

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
      // (An `x-row` object's own row: its fields' rows are there too)
      SettingsManager.discard(root.group.rows.filter(row => row.kind !== "group" && row.kind !== "object").map(row => row.path));
    }
  }

  // The section's `x-intro` (settings/<name>.qml): status and actions
  // above the fields, gone while its `shown` (if it has one) is false
  Loader {
    id: introLoader
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
        // Beside the top row, it's on the top line too. The `Settings` fold
        // under an intro keeps its divider, also as the top row (the intro
        // isn't a row)
        first: (index === root._firstRow && !(modelData.foldRows && introLoader.visible)) || (modelData.schema?.["x-beside"] === true && index - 1 === root._firstRow)
        row: modelData
        form: root.form
        Layout.columnSpan: half ? 1 : 2
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
      }
    }
  }
}
