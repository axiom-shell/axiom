pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.reusable

// The top of a placed-anywhere surface's card (its section's `x-intro`:
// LauncherPlace, WindowSwitcherPlace): where it opens, on a screen picker
// with presets and a drag, as a dock's or OSD's (EntryListCard), above the
// place fields it sets (`edge`, `position`, `detached`, `distance`). Edits
// go through the settings draft like the fields below.
RowLayout {
  id: root

  // The config section it places
  required property string sectionKey
  // The section as edited
  readonly property var section: SettingsManager.localConfig?.[root.sectionKey] ?? null

  visible: root.section !== null
  spacing: Widget.spacing * 2

  // I18n.tr("Top") I18n.tr("Upper") I18n.tr("Center") I18n.tr("Bottom")
  // I18n.tr("Left") I18n.tr("Right")
  readonly property var presets: [
    {
      "label": "Top",
      "values": {
        "edge": "top",
        "position": 50,
        "detached": false
      },
      "x": 0.5,
      "y": 0
    },
    {
      "label": "Upper",
      "values": {
        "edge": "top",
        "position": 50,
        "detached": true,
        "distance": 30
      },
      "x": 0.5,
      "y": 0.3
    },
    {
      "label": "Center",
      "values": {
        "edge": "top",
        "position": 50,
        "detached": true,
        "distance": 50
      },
      "x": 0.5,
      "y": 0.5
    },
    {
      "label": "Bottom",
      "values": {
        "edge": "bottom",
        "position": 50,
        "detached": false
      },
      "x": 0.5,
      "y": 1
    },
    {
      "label": "Left",
      "values": {
        "edge": "left",
        "position": 50,
        "detached": false
      },
      "x": 0,
      "y": 0.5
    },
    {
      "label": "Right",
      "values": {
        "edge": "right",
        "position": 50,
        "detached": false
      },
      "x": 1,
      "y": 0.5
    }
  ]

  ScreenSpotPicker {
    Layout.alignment: Qt.AlignTop
    presets: root.presets
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
