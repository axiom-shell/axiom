pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A radio menu's title row (Wi-Fi, Bluetooth), a ModuleHeader: the title, a
// refresh icon spinning while it scans, any `extras` (Wi-Fi's airplane
// mode), and the power switch (none without `switchShown`). Everything is
// always laid out, so the row never shifts.
ModuleHeader {
  id: root

  property bool scanning: false
  property bool checked: false
  property bool switchEnabled: true
  property bool switchShown: true
  default property alias extras: extrasRow.data

  signal toggled(bool checked)

  Layout.fillHeight: false
  trailSpacing: Widget.spacing

  SpinningIcon {
    text: "refresh"
    tone: "muted"
    opacity: root.scanning ? 1 : 0
    spinning: root.scanning

    Glide on opacity {}
  }

  RowLayout {
    id: extrasRow
    spacing: Widget.spacing / 2
  }

  StyledSwitch {
    visible: root.switchShown
    enabled: root.switchEnabled
    checked: root.checked
    onToggled: root.toggled(checked)
  }
}
