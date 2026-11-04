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
// divider above it, the rail, the fold as its `x-showIf` flips)
FormRow {
  id: root

  required property var row
  required property var form

  readonly property bool isValue: row.kind !== "group"
  readonly property bool changed: isValue && SettingsManager.isChanged(row.path)

  shown: field.shown
  // A row shown by a sibling's value (Night light's times, under "On a
  // schedule")
  indented: root.isValue && field.followsSibling
  bodyHeight: field.implicitHeight + hookup.shownHeight + (links.shows ? links.implicitHeight + Widget.spacing : 0)
  railHeight: field.implicitHeight

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
    // Kept drawn while the row folds shut (the row hides once it has)
    visible: true
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
