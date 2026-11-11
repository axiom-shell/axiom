pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.components.forms
import qs.components.reusable

// The ScreenSharing section's first card (its `x-card`): ScreenSharingSetup
// under a header chip of its status
FieldGroup {
  id: root

  headerExtras: [
    StatusChip {
      text: setup.statusLabel
      color: setup.statusColor
    }
  ]

  ScreenSharingSetup {
    id: setup
    Layout.fillWidth: true
  }
}
