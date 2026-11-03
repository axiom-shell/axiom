pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.components.reusable
import qs.config

// Title row of a TitledCard, with Save and Discard (shown while `dirty`)
// buttons for whichever service owns the panel's pending edits. Items
// placed inside sit just after the title. The title elides and the buttons
// drop to icons when the row is too narrow.
Rectangle {
  id: root
  property string title
  property bool dirty: false
  // Hide both buttons for panels with nothing to save
  property bool showActions: true
  // Save stays visible while dirty but is disabled when false
  property bool canSave: true
  property string saveLabel: I18n.tr("Save")
  // Controls beside the title
  default property alias extras: extrasRow.data

  signal save
  signal reset

  Layout.fillWidth: true
  Layout.preferredHeight: Math.max(Widget.height + Widget.padding, headerRow.implicitHeight)
  color: "transparent"

  RowLayout {
    id: headerRow
    anchors.fill: parent
    spacing: Widget.spacing

    StyledText {
      id: titleText
      Layout.fillWidth: true
      // Shrinks to elide, but doesn't push the extras away from it. In
      // whole pixels: the layout rounds a width it grows down, and a title
      // a fraction short elides its last letters
      Layout.preferredWidth: Math.ceil(implicitWidth)
      Layout.maximumWidth: Math.ceil(implicitWidth)
      text: root.title
      textSize: Appearance.fontSizeBy(4)
      font.bold: true
      elide: Text.ElideRight
    }

    RowLayout {
      id: extrasRow
      visible: children.length > 0
      spacing: Widget.spacing / 2
    }

    Item {
      Layout.fillWidth: true
    }

    SaveResetActions {
      visible: root.showActions
      dirty: root.dirty
      canSave: root.canSave
      saveLabel: root.saveLabel
      compact: root.width < titleText.implicitWidth + (extrasRow.visible ? extrasRow.implicitWidth + headerRow.spacing : 0) + headerRow.spacing + fullWidth
      onSave: root.save()
      onReset: root.reset()
    }
  }
}
