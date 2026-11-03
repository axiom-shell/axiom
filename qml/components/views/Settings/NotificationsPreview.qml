pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.system
import qs.services.ui
import qs.components.methods
import qs.components.reusable

// The top of the Notifications card (the section's `x-intro`): where the
// toasts sit, on a screen picker with presets as the launcher's
// (LauncherPlace), and a Show button sending a test notification, toasted
// with the settings as edited, as the OSD and dock cards' Show
RowLayout {
  id: root

  // The section as edited
  readonly property var section: SettingsManager.localConfig?.Notifications ?? null

  spacing: Widget.spacing * 2

  // I18n.tr("Top left") I18n.tr("Top") I18n.tr("Top right") I18n.tr("Right")
  // I18n.tr("Bottom right") I18n.tr("Bottom") I18n.tr("Bottom left")
  // I18n.tr("Left")
  readonly property var presets: [["Top left", "top", 0, 0, 0], ["Top", "top", 50, 0.5, 0], ["Top right", "top", 100, 1, 0], ["Right", "right", 50, 1, 0.5], ["Bottom right", "bottom", 100, 1, 1], ["Bottom", "bottom", 50, 0.5, 1], ["Bottom left", "bottom", 0, 0, 1], ["Left", "left", 50, 0, 0.5]].map(p => ({
        "label": p[0],
        "values": {
          "edge": p[1],
          "position": p[2]
        },
        "x": p[3],
        "y": p[4]
      }))

  ScreenSpotPicker {
    Layout.alignment: Qt.AlignTop
    visible: root.section !== null
    presets: root.presets
    edge: root.section?.edge ?? "top"
    spot: root.section ? ScreenEdge.edgeSpot(root.section.edge, root.section.position / 100, 0) : Qt.point(0.5, 0.5)
    onPicked: values => SettingsManager.setValues(Object.keys(values).map(key => ({
            "path": ["Notifications", key],
            "value": values[key]
          })))
  }

  StyledText {
    text: NotificationManager.dnd ? I18n.tr("Do not disturb is on: a test notification goes only to the history.") : I18n.tr("Click a spot or drag to place the toasts; fine-tune below. Show sends a test notification, toasted with the settings below as edited.")
    textColor: NotificationManager.dnd ? Theme.warning : Theme.foregroundAlt
    textSize: Appearance.fontSizeBy(-2)
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop
  }

  StyledTextButton {
    Layout.alignment: Qt.AlignTop
    implicitHeight: Widget.height - Widget.px(4)
    iconText: "visibility"
    text: I18n.tr("Show")
    onClicked: NotificationManager.sendNotification("axiom", I18n.tr("A test notification"), I18n.tr("Change the settings below and show another to see them."))
  }
}
