pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.reusable

// The top of a placed-anywhere surface's card (its section's `x-intro`:
// LauncherPlace, WindowSwitcherPlace): where it opens, on the screen
// picker every placed surface has (ScreenSpotPicker, its nine spots and a
// drag; a dock's or OSD's in EntryListCard), above the place fields it
// sets (`edge`, `position`, `detached`, `distance`). Edits go through the
// settings draft like the fields below. NotificationsPreview is one with its
// own dots (`presets`, `floats` off), its own text and a `trailing` button.
RowLayout {
  id: root

  // The config section it places
  required property string sectionKey
  // The section as edited
  readonly property var section: SettingsManager.localConfig?.[root.sectionKey] ?? null
  // The picker's dots, and whether a drag also detaches (the picker's own)
  property var presets: root.floats ? picker.placeSpots : []
  property bool floats: true
  property string text: I18n.tr("Click a spot or drag to place it, to an edge to attach it; fine-tune below. Detached, it floats a distance across the free screen; attached, it grows out of the edge.")
  property string textTone: ""
  // What follows the text (a button)
  default property alias trailing: trailingSlot.data

  visible: root.section !== null
  spacing: Widget.spacing * 2

  ScreenSpotPicker {
    id: picker
    Layout.alignment: Qt.AlignTop
    edge: root.section?.edge ?? "top"
    floats: root.floats
    presets: root.presets
    spot: root.section ? ScreenEdge.edgeSpot(root.section.edge, root.section.position / 100, root.section.detached ? root.section.distance / 100 : 0) : Qt.point(0.5, 0.5)
    onPicked: values => SettingsManager.setValues(Object.keys(values).map(key => ({
            "path": [root.sectionKey, key],
            "value": values[key]
          })))
  }

  StyledText {
    text: root.text
    tone: root.textTone
    role: "caption"
    overflow: "wrap"
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop
  }

  RowLayout {
    id: trailingSlot
    visible: children.length > 0
    Layout.alignment: Qt.AlignTop
    spacing: Widget.spacing
  }
}
