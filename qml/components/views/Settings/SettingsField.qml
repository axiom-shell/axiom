pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.config
import qs.services.ui
import qs.components.forms
import qs.components.methods
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
  readonly property var defaultValue: row.schema?.default
  readonly property bool changed: isValue && SettingsManager.isChanged(row.path)
  // The default as the field shows it, for the reset button's tooltip
  // ("" for one with no short form, an object)
  readonly property string defaultText: {
    const value = root.defaultValue;
    if (typeof value === "boolean")
      return value ? I18n.tr("On") : I18n.tr("Off");
    if (typeof value === "number") {
      const unit = root.row.schema?.["x-unit"] ?? "";
      const shown = Math.round(value / SchemaLayout.unitScale(unit));
      return unit === "" ? String(shown) : I18n.tr("{0} {1}", shown, I18n.tr(unit));
    }
    if (typeof value === "string")
      return field.optionLabels?.[value] ?? (value === "" ? I18n.tr("Empty") : root.row.schema?.enum ? I18n.tr(value) : value);
    if (Array.isArray(value) && value.every(v => typeof v === "string"))
      return value.length === 0 ? I18n.tr("None") : value.map(v => field.optionLabels?.[v] ?? v).join(", ");
    return "";
  }
  readonly property bool atDefault: defaultValue === undefined || JSON.stringify(field.current) === JSON.stringify(defaultValue)

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

  // After the label, on its line (centred on it, whatever their height)
  Component {
    id: changeMarks
    Item {
      implicitWidth: marks.implicitWidth
      Row {
        id: marks
        anchors.verticalCenter: parent.verticalCenter
        spacing: Widget.spacing / 2

        SquareIconButton {
          visible: !root.atDefault
          size: Appearance.fontSizeBy(8)
          iconText: "settings_backup_restore"
          iconSize: Appearance.fontSizeBy(-1)
          backgroundColor: Theme.backgroundHighlight
          tooltipText: root.defaultText === "" ? I18n.tr("Reset to default") : I18n.tr("Reset to default: {0}", root.defaultText)
          onClicked: root.form.edited(root.row.path, Utils.clone(root.defaultValue))
        }

        UnsavedDot {
          id: dot
          anchors.verticalCenter: parent.verticalCenter
          shown: root.changed

          // Larger than the dot, which is hard to hit
          MouseArea {
            id: dotArea
            anchors.fill: parent
            anchors.margins: -Widget.px(4)
            enabled: root.changed
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              EditsManager.discardTypingIn(root);
              SettingsManager.discard([root.row.path]);
            }
          }

          LazyLoader {
            active: dotArea.containsMouse
            StyledToolTip {
              target: dot
              text: I18n.tr("Discard this change")
            }
          }
        }
      }
    }
  }
}
