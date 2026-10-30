pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A radio menu's title row (Wi-Fi, Bluetooth): the title, a refresh icon
// spinning while it scans, any `extras` (Wi-Fi's airplane mode), and the
// power switch (none without `switchShown`). Everything is always laid
// out, so the row never shifts.
RowLayout {
  id: root

  property string title: ""
  property bool scanning: false
  property bool checked: false
  property bool switchEnabled: true
  property bool switchShown: true
  default property alias extras: extrasRow.data

  signal toggled(bool checked)

  Layout.fillWidth: true
  Layout.fillHeight: false
  spacing: Widget.spacing

  StyledText {
    Layout.fillWidth: true
    text: root.title
    elide: Text.ElideRight
    font.bold: true
    textColor: Theme.accent
  }

  StyledIcon {
    text: "refresh"
    textColor: Theme.foregroundAlt
    opacity: root.scanning ? 1 : 0

    RotationAnimation on rotation {
      running: root.scanning && Appearance.animations
      loops: Animation.Infinite
      from: 0
      to: 360
      duration: Appearance.animSlow * 4
    }

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
