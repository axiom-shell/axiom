pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.system
import qs.components.reusable

// The top of the Notifications card (the section's `x-intro`): where the
// toasts sit, on PlaceIntro's screen picker with its own eight dots, and a
// Show button (its `trailing`) sending a test notification, toasted with the
// settings as edited, as the OSD and dock cards' Show
PlaceIntro {
  id: root

  sectionKey: "Notifications"
  floats: false
  text: NotificationManager.dnd ? I18n.tr("Do not disturb is on: a test notification goes only to the history.") : I18n.tr("Click a spot or drag to place the toasts; fine-tune below. Show sends a test notification, toasted with the settings below as edited.")
  textTone: NotificationManager.dnd ? "warning" : "muted"

  // I18n.tr("Top left") I18n.tr("Top") I18n.tr("Top right") I18n.tr("Right")
  // I18n.tr("Bottom right") I18n.tr("Bottom") I18n.tr("Bottom left")
  // I18n.tr("Left")
  presets: [["Top left", "top", 0, 0, 0], ["Top", "top", 50, 0.5, 0], ["Top right", "top", 100, 1, 0], ["Right", "right", 50, 1, 0.5], ["Bottom right", "bottom", 100, 1, 1], ["Bottom", "bottom", 50, 0.5, 1], ["Bottom left", "bottom", 0, 0, 1], ["Left", "left", 50, 0, 0.5]].map(p => ({
        "label": p[0],
        "values": {
          "edge": p[1],
          "position": p[2]
        },
        "x": p[3],
        "y": p[4]
      }))

  StyledTextButton {
    iconText: "visibility"
    text: I18n.tr("Show")
    onClicked: NotificationManager.sendNotification("axiom", I18n.tr("A test notification"), I18n.tr("Change the settings below and show another to see them."))
  }
}
