pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.reusable

// One group of settings (a section's own fields, or one nested object) as
// a card: title, help text, then its rows, which flow into up to two
// columns of blocks (FlowColumns; an `x-beside` pair shares a line).
// Clicking the header folds it (remembered by SettingsManager); search
// results are always unfolded. With unsaved edits, Discard drops just those.
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
  statusTone: introLoader.intro?.statusTone ?? (root._hookup?.tone || "neutral")
  // Unsaved edits inside: Discard shows, and folded the dot, so they
  // aren't forgotten
  marked: root.group.rows.some(row => SettingsManager.hasChangesUnder(row.path.join(".")))
  onToggled: SettingsManager.setCollapsed(root.group.key, !root.collapsed)

  // The rows' indent tree (RowTree), from the schema rows only (never live values)
  readonly property var tree: RowTree.plan(root.group.rows)

  // Its rows are in `rowArea`, not direct children: FoldingCard's end rule
  // reads each SettingsField's `shown` and `shutFold`, through `count`
  endRows: Array.from({
    length: fieldRows.count
  }, (_, i) => fieldRows.itemAt(i))

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
    kind: "text"
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

  // The first shown row of each column in the card's first run, keyed by
  // column ("-1" a heading), for FormRow.first: no divider on the top of
  // the card. An object, not an array: -1 is no array slot
  readonly property var _firstRows: {
    const rows = rowArea.placed.rows;
    const result = {};
    for (const key of ["-1"].concat(Array.from({
      length: rowArea.count
    }, (_, i) => String(i))))
      result[key] = Utils.firstFormRow(fieldRows.count, i => rows[i]?.run === 0 && String(rows[i].column) === key ? fieldRows.itemAt(i) : null);
    return result;
  }

  // The rows in blocks (FlowColumns.blocks), placed in `count` newspaper
  // columns, headings and `x-wide` rows across them. Positions follow the rows' live heights;
  // the splits follow their heights as if every fold were open, only while
  // settling (SettledColumns), so a fold opening never moves a row across
  // columns
  Item {
    id: rowArea
    Layout.fillWidth: true
    implicitHeight: rowArea.placed.height

    // One column under 840 px (at defaults), two from there
    readonly property int count: FlowColumns.count(rowArea.width, Style.columnTarget, Style.columnMin, 2, Style.space5)
    // From the schema only
    readonly property var blocks: FlowColumns.blocks(root.group.rows)
    readonly property var lines: FlowColumns.lines(root.group.rows)
    // Each row's live height, and its height as if every fold were open
    property var liveHeights: root.group.rows.map(() => 0)
    property var flowHeights: root.group.rows.map(() => 0)
    readonly property var placed: FlowColumns.place(rowArea.blocks, rowArea.lines, rowArea.liveHeights, columns.placed, rowArea.width, Style.space5, Style.space4)

    function setHeights(i, live, flow) {
      if (rowArea.liveHeights[i] !== live) {
        const next = rowArea.liveHeights.slice();
        next[i] = live;
        rowArea.liveHeights = next;
      }
      if (rowArea.flowHeights[i] !== flow) {
        const next = rowArea.flowHeights.slice();
        next[i] = flow;
        rowArea.flowHeights = next;
      }
    }

    onWidthChanged: columns.relayout()

    SettledColumns {
      id: columns
      count: rowArea.count
      fill: false
      wide: rowArea.blocks.map(block => block.wide)
      starts: rowArea.blocks.map(block => block.start)
      heights: FlowColumns.blockHeights(rowArea.blocks, rowArea.lines, rowArea.liveHeights)
      splitHeights: FlowColumns.blockHeights(rowArea.blocks, rowArea.lines, rowArea.flowHeights)
    }

    Repeater {
      id: fieldRows
      model: root.group.rows

      delegate: SettingsField {
        id: field
        required property var modelData
        required property int index
        readonly property var spot: rowArea.placed.rows[field.index] ?? ({
            "x": 0,
            "y": 0,
            "width": rowArea.width,
            "run": 0,
            "column": 0
          })
        // The top of its column in the card's first run, or the right half
        // of a pair whose left half is. The `Settings` fold under an intro
        // keeps its divider, also as the top row (the intro isn't a row)
        first: (field.index === root._firstRows[String(field.spot.column)] && !(field.modelData.foldRows && introLoader.visible)) || (rowArea.lines[field.index]?.side === 1 && field.index - 1 === root._firstRows[String(rowArea.placed.rows[field.index - 1]?.column)])
        row: field.modelData
        form: root.form
        level: root.tree.levels[field.index]
        x: field.spot.x
        y: field.spot.y
        width: field.spot.width
        onImplicitHeightChanged: rowArea.setHeights(field.index, field.implicitHeight, field.flowHeight)
        onFlowHeightChanged: rowArea.setHeights(field.index, field.implicitHeight, field.flowHeight)
        Component.onCompleted: rowArea.setHeights(field.index, field.implicitHeight, field.flowHeight)
      }
    }
  }
}
