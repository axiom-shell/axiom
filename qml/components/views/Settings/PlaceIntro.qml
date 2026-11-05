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
// settings draft like the fields below.
RowLayout {
  id: root

  // The config section it places
  required property string sectionKey
  // The section as edited
  readonly property var section: SettingsManager.localConfig?.[root.sectionKey] ?? null

  visible: root.section !== null
  spacing: Widget.spacing * 2

  ScreenSpotPicker {
    Layout.alignment: Qt.AlignTop
    edge: root.section?.edge ?? "top"
    floats: true
    spot: root.section ? ScreenEdge.edgeSpot(root.section.edge, root.section.position / 100, root.section.detached ? root.section.distance / 100 : 0) : Qt.point(0.5, 0.5)
    onPicked: values => SettingsManager.setValues(Object.keys(values).map(key => ({
            "path": [root.sectionKey, key],
            "value": values[key]
          })))
  }

  StyledText {
    text: I18n.tr("Click a spot or drag to place it, to an edge to attach it; fine-tune below. Detached, it floats a distance across the free screen; attached, it grows out of the edge.")
    textColor: Theme.foregroundAlt
    textSize: Appearance.fontSizeBy(-2)
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop
  }
}
