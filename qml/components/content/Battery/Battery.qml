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
// compact, the figure only. Under them the peripherals' batteries
// (connected Bluetooth devices, with showPeripherals): icon, name, a
// meter and the percent; with no laptop battery only them (compact, the
// lowest one's figure).
Card {
  id: root

  readonly property bool peripheralsShown: root.properties.showPeripherals && BatteryManager.peripherals.length > 0
  // No laptop battery: the peripherals take the whole card
  readonly property bool onlyPeripherals: !BatteryManager.isAvailable && root.peripheralsShown
  readonly property var lowest: BatteryManager.lowestPeripheral

  function peripheralColor(level) {
    return level === "critical" ? Theme.error : level === "low" ? Theme.warning : Theme.success;
  }

  readonly property string stateText: BatteryManager.isCharging ? I18n.tr("Charging · {0} to full", BatteryManager.timeToFull) : BatteryManager.isFull ? I18n.tr("Fully charged") : I18n.tr("{0} left", BatteryManager.timeRemaining)
  readonly property color levelColor: BatteryManager.isCritical ? Theme.error : BatteryManager.isLow ? Theme.warning : Theme.success
  readonly property bool sideBySide: root.shape === "horizontal"

  fullMinWidth: Appearance.fontSize * 6
  fullMinHeight: Appearance.fontSize * 6

  compactContent: CompactFigure {
    icon: BatteryManager.isAvailable ? BatteryManager.getBatteryIcon() : root.onlyPeripherals ? root.lowest.glyph : "power"
    iconColor: BatteryManager.isAvailable ? root.levelColor : root.onlyPeripherals ? root.peripheralColor(root.lowest.level) : Theme.foregroundAlt
    value: BatteryManager.isAvailable ? String(Math.round(BatteryManager.percentage)) : root.onlyPeripherals ? String(root.lowest.percentage) : ""
    unit: BatteryManager.isAvailable || root.onlyPeripherals ? "%" : ""
    label: BatteryManager.isAvailable ? root.stateText : root.onlyPeripherals ? root.lowest.name : I18n.tr("On AC power")
  }

  EmptyState {
    visible: !BatteryManager.isAvailable && !root.onlyPeripherals
    anchors.centerIn: parent
    maxWidth: root.innerWidth
    availableHeight: root.innerHeight
    icon: "power"
    text: I18n.tr("On AC power")
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: root.pad
    spacing: Widget.spacing

    GridLayout {
      // Hidden by size, not `visible`: a Layout misses a child shown while
      // it's hidden (qml-pitfalls)
      enabled: BatteryManager.isAvailable
      opacity: enabled ? 1 : 0
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.maximumHeight: enabled ? Infinity : 0
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

    // The peripherals, one line each, by name
    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: root.onlyPeripherals
      Layout.alignment: Qt.AlignTop
      Layout.maximumHeight: root.peripheralsShown ? Infinity : 0
      spacing: Widget.spacing / 2
      clip: true

      Repeater {
        // A count, so the rows outlive each state
        model: root.properties.showPeripherals ? BatteryManager.peripherals.length : 0

        RowLayout {
          id: line
          required property int index
          readonly property var peripheral: BatteryManager.peripherals[line.index] ?? null
          Layout.fillWidth: true
          spacing: Widget.spacing

          StyledIcon {
            text: line.peripheral?.glyph ?? ""
            textSize: Appearance.fontSize
            textColor: root.peripheralColor(line.peripheral?.level ?? "none")
          }
          StyledText {
            Layout.fillWidth: true
            text: line.peripheral?.name ?? ""
            elide: Text.ElideRight
            textSize: Appearance.fontSizeBy(-2)
          }
          LevelMeter {
            Layout.preferredWidth: Widget.px(40)
            Layout.fillHeight: true
            thickness: Widget.px(4)
            share: (line.peripheral?.percentage ?? 0) / 100
            fillColor: root.peripheralColor(line.peripheral?.level ?? "none")
          }
          StyledText {
            Layout.preferredWidth: percentMetrics.advanceWidth("100%") // fixed px: a measuring string, the widest percent
            horizontalAlignment: Text.AlignRight
            text: (line.peripheral?.percentage ?? 0) + "%"
            textSize: Appearance.fontSizeBy(-2)
            opacity: 0.7
          }
        }
      }

      Item {
        Layout.fillHeight: true
      }
    }

    FontMetrics {
      id: percentMetrics
      font.family: Appearance.fontFamily
      font.pixelSize: Appearance.fontSizeBy(-2)
    }
  }
}
