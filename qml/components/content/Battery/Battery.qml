pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.system
import qs.components.reusable
import qs.components.content.parts
import qs.components.content.base

// Battery charge, state and time left; "On AC power" on machines without
// a battery. The charge circle over the figures, beside them when wide;
// compact, the figure only.
Card {
  id: root

  readonly property string stateText: BatteryManager.isCharging ? I18n.tr("Charging · {0} to full", BatteryManager.timeToFull) : BatteryManager.isFull ? I18n.tr("Fully charged") : I18n.tr("{0} left", BatteryManager.timeRemaining)
  readonly property color levelColor: BatteryManager.isCritical ? Theme.error : BatteryManager.isLow ? Theme.warning : Theme.success
  readonly property bool sideBySide: root.shape === "horizontal"

  fullMinWidth: Appearance.fontSize * 6
  fullMinHeight: Appearance.fontSize * 6

  compactContent: CompactFigure {
    icon: BatteryManager.isAvailable ? BatteryManager.getBatteryIcon() : "power"
    iconColor: BatteryManager.isAvailable ? root.levelColor : Theme.foregroundAlt
    value: BatteryManager.isAvailable ? String(Math.round(BatteryManager.percentage)) : ""
    unit: BatteryManager.isAvailable ? "%" : ""
    label: BatteryManager.isAvailable ? root.stateText : I18n.tr("On AC power")
  }

  EmptyState {
    visible: !BatteryManager.isAvailable
    anchors.centerIn: parent
    maxWidth: root.innerWidth
    availableHeight: root.innerHeight
    icon: "power"
    text: I18n.tr("On AC power")
  }

  GridLayout {
    visible: BatteryManager.isAvailable
    anchors.fill: parent
    anchors.margins: root.pad
    columns: root.sideBySide ? 2 : 1
    columnSpacing: root.pad
    rowSpacing: Widget.spacing

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true
      PercentageCircle {
        anchors.fill: parent
        percentage: Math.round(BatteryManager.percentage)
        iconText: BatteryManager.getBatteryIcon()
        iconColor: Theme.foreground
        fillColor: root.levelColor
      }
    }

    ColumnLayout {
      Layout.fillWidth: root.sideBySide
      Layout.preferredWidth: root.sideBySide ? (root.width - root.pad * 3) / 2 : -1
      Layout.alignment: Qt.AlignCenter
      spacing: Widget.spacing / 2

      StyledText {
        Layout.alignment: root.sideBySide ? Qt.AlignLeft : Qt.AlignHCenter
        text: `${Math.round(BatteryManager.percentage)}%`
        textSize: root.sideBySide ? Appearance.fontSize * 1.6 : Appearance.fontSize
        font.bold: true
      }
      StyledText {
        Layout.fillWidth: true
        Layout.maximumWidth: root.innerWidth
        horizontalAlignment: root.sideBySide ? Text.AlignLeft : Text.AlignHCenter
        elide: Text.ElideRight
        text: root.stateText
        textSize: Appearance.fontSizeBy(-2)
        opacity: 0.7
      }
    }
  }
}
