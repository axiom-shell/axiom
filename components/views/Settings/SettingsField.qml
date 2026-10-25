pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services.ui
import qs.components.forms
import qs.components.methods
import qs.components.reusable

// One settings row: the SchemaField, with a dot while it has an unsaved
// edit (clicking it discards just that edit) and a button that puts it
// back to the schema default, and under a field with `x-hookup` (theme
// integrations) the IntegrationHookup panel
Item {
  id: root

  required property var row
  required property var form

  readonly property bool isValue: row.kind !== "group"
  readonly property var defaultValue: row.schema?.default
  readonly property bool changed: isValue && SettingsManager.isChanged(row.path)
  readonly property bool atDefault: defaultValue === undefined || JSON.stringify(field.current) === JSON.stringify(defaultValue)

  Layout.fillWidth: true
  implicitHeight: field.implicitHeight + hookup.shownHeight + (links.shows ? links.implicitHeight + Widget.spacing : 0)
  visible: field.shown

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
    width: root.width
    row: root.row
    form: root.form
    // The dot and reset button's full width, kept even while they're
    // hidden, so their appearing doesn't shift a stepper under the cursor
    headerInset: 8 + Widget.spacing / 2 + Appearance.fontSizeBy(8) + Widget.spacing
  }

  Loader {
    id: hookup
    // Its height and the gap above it, while it shows
    readonly property real shownHeight: {
      const panel = hookup.item as Item;
      return panel && panel.visible ? panel.implicitHeight + Widget.spacing : 0;
    }
    y: field.implicitHeight + Widget.spacing
    width: root.width
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
    width: root.width
    links: root.isValue ? root.row.schema?.["x-link"] : undefined
  }

  Row {
    anchors.top: parent.top
    anchors.right: parent.right
    spacing: Widget.spacing / 2
    visible: root.isValue

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

    SquareIconButton {
      visible: !root.atDefault
      size: Appearance.fontSizeBy(8)
      iconText: "settings_backup_restore"
      iconSize: Appearance.fontSizeBy(-1)
      backgroundColor: Theme.backgroundHighlight
      tooltipText: I18n.tr("Reset to default")
      onClicked: root.form.edited(root.row.path, Utils.clone(root.defaultValue))
    }
  }
}
