pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.components.forms

// The top of the Screen sharing card (the section's `x-intro`):
// ScreenSharingSetup. `status` and `statusColor` are the card's header chip
ColumnLayout {
  id: root

  readonly property string status: setup.statusLabel
  readonly property color statusColor: setup.statusColor

  ScreenSharingSetup {
    id: setup
    Layout.fillWidth: true
  }
}
