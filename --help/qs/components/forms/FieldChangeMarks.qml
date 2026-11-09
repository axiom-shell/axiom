pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.config
import qs.components.methods
import qs.components.reusable

// A form field's change marks, after its label (a SchemaField's
// `headerExtra`): a button putting it back to its schema default while it
// differs, and a dot while it has an unsaved edit (clicking it discards
// just that edit). The host says what changed and acts on the signals:
// the settings page's rows, and any form given `changedAt`
// (SchemaPropertiesForm, OptionsGroup).
Item {
  id: root

  // The field's schema, its value as shown and its options' labels (a
  // SchemaField's `optionLabels`), for the default's text
  property var schema: null
  property var current: undefined
  property var optionLabels: ({})
  // An unsaved edit: shows the dot
  property bool changed: false

  readonly property var defaultValue: root.schema?.default
  readonly property bool atDefault: root.defaultValue === undefined || JSON.stringify(root.current) === JSON.stringify(root.defaultValue)
  // The default as the field shows it, for the reset button's tooltip
  // ("" for one with no short form, an object)
  readonly property string defaultText: {
    const value = root.defaultValue;
    if (typeof value === "boolean")
      return value ? I18n.tr("On") : I18n.tr("Off");
    if (typeof value === "number") {
      const unit = root.schema?.["x-unit"] ?? "";
      const shown = Math.round(value / SchemaLayout.unitScale(unit));
      return unit === "" ? String(shown) : I18n.tr("{0} {1}", shown, I18n.tr(unit));
    }
    if (typeof value === "string")
      return root.optionLabels?.[value] ?? (value === "" ? I18n.tr("Empty") : root.schema?.enum ? I18n.tr(value) : value);
    if (Array.isArray(value) && value.every(v => typeof v === "string"))
      return value.length === 0 ? I18n.tr("None") : value.map(v => root.optionLabels?.[v] ?? v).join(", ");
    return "";
  }

  // The reset button: with a copy of the default to write
  signal reset(var value)
  // The dot: drop this field's unsaved edit
  signal discard

  implicitWidth: marks.implicitWidth

  // Centred on the label's line, whatever their height
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
      onClicked: root.reset(Utils.clone(root.defaultValue))
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
        onClicked: root.discard()
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
