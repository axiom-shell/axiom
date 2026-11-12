pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.ui
import qs.components.forms
import qs.components.reusable

// One settings row: the SchemaField, with a dot while it has an unsaved
// edit (clicking it discards just that edit) and a button that puts it
// back to the schema default, and under a field with `x-hookup` (theme
// integrations) the IntegrationHookup panel, drawn as a FormRow (the
// divider above it, the rail, the fold as its `x-showIf` flips). A field
// with `x-row` is drawn by settings/<Name>.qml instead (given `row` and
// `form`), and the rows its `x-rowDraws` names hide (an object with
// `x-row`: every row under it); an object with `x-fold` is a fold header,
// its rows shown only while it's open (SettingsManager.isFoldOpen), and
// always in a search. A card with an `x-intro` `setup` has one too, a
// `Settings` row (`foldRows`: the rows behind it) hidden while none of them
// shows, its rows `foldedBy` it (`foldedIn` when also inside an `x-fold`)
FormRow {
  id: root

  required property var row
  required property var form

  readonly property bool isValue: row.kind !== "group"
  readonly property bool changed: isValue && SettingsManager.isChanged(row.path)
  // `x-row`: the hand-built piece drawing this field
  readonly property string custom: root.isValue ? (root.row.schema?.["x-row"] ?? "") : ""
  // `x-fold`: this row is the header of its object's fold
  readonly property bool foldHeader: !root.isValue && root.row.fold === true
  // Search results and the changed list show every row they match
  readonly property bool listing: root.form?.listing === true
  readonly property bool foldOpen: root.listing || SettingsManager.isFoldOpen(root.foldHeader ? root.row.path.join(".") : (root.row.foldedBy ?? ""))

  // A row another field's `x-row` draws (`drawnBy`) is drawn there
  readonly property bool foldedInOpen: root.listing || !root.row.foldedIn || SettingsManager.isFoldOpen(root.row.foldedIn)
  // A card's settings fold with nothing shown behind it isn't drawn
  readonly property bool foldHasRows: !root.row.foldRows || root.row.foldRows.some(inner => inner.kind !== "group" && root.form.rowShown(inner))

  shown: field.shown && (!root.row.foldedBy || root.foldOpen) && root.foldedInOpen && root.foldHasRows && !root.row.drawnBy
  // A row shown by a sibling's value (Night light's times, under "On a
  // schedule")
  indented: root.isValue && field.followsSibling
  bodyHeight: (root.custom !== "" ? customRow.implicitHeight : root.foldHeader ? foldTitle.implicitHeight : field.implicitHeight) + hookup.shownHeight + (links.shows ? links.implicitHeight + Widget.spacing : 0)
  railHeight: root.custom !== "" ? 0 : field.implicitHeight

  // Outlines the row for a moment (a link to this setting)
  function flash() {
    outline.flash();
  }

  FlashOutline {
    id: outline
    anchors.fill: parent
    anchors.margins: -Widget.spacing / 2
  }

  SchemaField {
    id: field
    width: parent.width
    row: root.row
    form: root.form
    headerExtra: root.isValue ? changeMarks : null
    // Kept drawn while the row folds shut (the row hides once it has);
    // not built for a row drawn otherwise (its `shown` still holds)
    active: root.custom === "" && !root.foldHeader && !root.row.drawnBy
    visible: true
  }

  Loader {
    id: customRow
    width: parent.width
    active: root.custom !== ""
    Component.onCompleted: {
      if (root.custom !== "")
        customRow.setSource(Qt.resolvedUrl(root.custom + ".qml"), {
          "row": root.row,
          "form": root.form
        });
    }
  }

  FoldHeader {
    id: foldTitle
    visible: root.foldHeader
    width: parent.width
    // I18n.tr("Settings") (a card's fold behind its `x-intro`)
    title: I18n.tr(root.row.title)
    collapsed: !root.foldOpen
    foldable: !root.listing
    marked: root.foldHeader && (root.row.foldRows ? root.row.foldRows.some(inner => SettingsManager.hasChangesUnder(inner.path.join("."))) : SettingsManager.hasChangesUnder(root.row.path.join(".")))
    onToggled: SettingsManager.setFoldOpen(root.row.path.join("."), !root.foldOpen)
  }

  Loader {
    id: hookup
    // Its height and the gap above it, while it shows
    readonly property real shownHeight: {
      const panel = hookup.item as Item;
      return panel && panel.visible ? panel.implicitHeight + Widget.spacing : 0;
    }
    y: field.implicitHeight + Widget.spacing
    width: parent.width
    active: root.isValue && !!root.row.schema?.["x-hookup"]
    sourceComponent: IntegrationHookup {
      integration: root.row.path[root.row.path.length - 1]
      active: field.current === true
    }
  }

  // `x-link`: where something it follows or names is set
  FieldLinks {
    id: links
    y: field.implicitHeight + hookup.shownHeight + Widget.spacing
    width: parent.width
    links: root.isValue ? root.row.schema?.["x-link"] : undefined
  }

  // After the label, on its line
  Component {
    id: changeMarks
    FieldChangeMarks {
      schema: root.row.schema
      current: field.current
      optionLabels: field.optionLabels
      changed: root.changed
      onReset: value => root.form.edited(root.row.path, value)
      onDiscard: {
        EditsManager.discardTypingIn(root);
        SettingsManager.discard([root.row.path]);
      }
    }
  }
}
