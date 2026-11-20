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
// lowest one's figure). showPowerProfile adds a row to pick the power
// profile (not on the lock screen or the login screen).
Card {
  id: root

  readonly property bool peripheralsShown: root.properties.showPeripherals && BatteryManager.peripherals.length > 0
  // No laptop battery: the peripherals take the whole card
  readonly property bool onlyPeripherals: !BatteryManager.isAvailable && root.peripheralsShown
  readonly property var lowest: BatteryManager.lowestPeripheral

  function peripheralColor(level) {
    return level === "critical" ? Style.error : level === "low" ? Style.warning : Style.success;
  }
  function peripheralTone(level) {
    return level === "critical" ? "error" : level === "low" ? "warning" : "success";
  }

  // showTime off: the state alone, no estimate
  readonly property string stateText: BatteryManager.isCharging ? (root.properties.showTime ? I18n.tr("Charging · {0} to full", BatteryManager.timeToFull) : I18n.tr("Charging")) : BatteryManager.isFull ? I18n.tr("Fully charged") : root.properties.showTime ? I18n.tr("{0} left", BatteryManager.timeRemaining) : ""
  // The profile row: not on the lock screen or the login screen, which don't change the system
  readonly property bool showsProfile: root.properties.showPowerProfile && BatteryManager.hasPowerProfiles && root.host.kind !== "lockscreen" && root.host.kind !== "greeter"
  readonly property color levelColor: BatteryManager.isCritical ? Style.error : BatteryManager.isLow ? Style.warning : Style.success
  readonly property string levelTone: BatteryManager.isCritical ? "error" : BatteryManager.isLow ? "warning" : "success"
  readonly property bool sideBySide: root.shape === "horizontal"

  fullMinWidth: Appearance.fontSize * 6
  fullMinHeight: Appearance.fontSize * 6

  compactContent: CompactFigure {
    icon: BatteryManager.isAvailable ? BatteryManager.getBatteryIcon() : root.onlyPeripherals ? root.lowest.glyph : "power"
    iconColor: BatteryManager.isAvailable ? root.levelColor : root.onlyPeripherals ? root.peripheralColor(root.lowest.level) : Style.textMuted
    value: BatteryManager.isAvailable ? String(Math.round(BatteryManager.percentage)) : root.onlyPeripherals ? String(root.lowest.percentage) : ""
    unit: BatteryManager.isAvailable || root.onlyPeripherals ? "%" : ""
    label: BatteryManager.isAvailable ? root.stateText : root.onlyPeripherals ? root.lowest.name : I18n.tr("On AC power")
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: root.pad
    // The gap is the peripherals' own, only with both parts shown
    spacing: 0

    // "On AC power", over the profile row when it shows
    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.maximumHeight: !BatteryManager.isAvailable && !root.onlyPeripherals ? Infinity : 0
      EmptyState {
        visible: !BatteryManager.isAvailable && !root.onlyPeripherals
        anchors.centerIn: parent
        maxWidth: root.innerWidth
        availableHeight: parent.height
        icon: "power"
        text: I18n.tr("On AC power")
      }
    }

    GridLayout {
      // Hidden by size, not `visible`: a Layout misses a child shown while
      // it's hidden (qml-pitfalls)
      enabled: BatteryManager.isAvailable
      opacity: enabled ? 1 : 0
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 0
      Layout.maximumHeight: enabled ? Infinity : 0
      clip: true
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
          iconColor: Style.text
          fillTone: root.levelTone
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
          role: "label"
          textSize: root.sideBySide ? Math.round(Style.typeBody * 1.6) : Style.typeBody // fitted: the figure beside the ring
        }
        StyledText {
          Layout.fillWidth: true
          Layout.maximumWidth: root.innerWidth
          horizontalAlignment: root.sideBySide ? Text.AlignLeft : Text.AlignHCenter
          role: "caption"
          overflow: "line"
          text: root.stateText
        }
      }
    }

    SegmentRow {
      enabled: root.showsProfile
      opacity: enabled ? 1 : 0
      Layout.maximumHeight: enabled ? Infinity : 0
      clip: true
      Layout.fillWidth: true
      Layout.topMargin: root.showsProfile && BatteryManager.isAvailable ? Widget.spacing : 0

      SegmentButton {
        text: I18n.tr("Power saver")
        active: BatteryManager.profile === "powerSaver"
        onClicked: BatteryManager.setProfile("powerSaver") // lock-inert: hidden on the lock screen and greeter
      }
      SegmentButton {
        text: I18n.tr("Balanced")
        active: BatteryManager.profile === "balanced"
        onClicked: BatteryManager.setProfile("balanced") // lock-inert: hidden on the lock screen and greeter
      }
      SegmentButton {
        visible: BatteryManager.hasPerformance
        text: I18n.tr("Performance")
        active: BatteryManager.profile === "performance"
        onClicked: BatteryManager.setProfile("performance") // lock-inert: hidden on the lock screen and greeter
      }
    }

    // The peripherals, one line each, by name
    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: root.onlyPeripherals
      Layout.alignment: Qt.AlignTop
      Layout.maximumHeight: root.peripheralsShown ? Infinity : 0
      Layout.topMargin: BatteryManager.isAvailable && root.peripheralsShown ? Widget.spacing : 0
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
          // A child layout fills by default: the lines keep to the top
          Layout.fillHeight: false
          spacing: Widget.spacing

          StyledIcon {
            text: line.peripheral?.glyph ?? ""
            size: "sm"
            tone: root.peripheralTone(line.peripheral?.level ?? "none")
          }
          StyledLabel {
            Layout.fillWidth: true
            text: line.peripheral?.name ?? ""
            role: "caption"
            overflow: "line"
          }
          LevelMeter {
            Layout.preferredWidth: Widget.px(40)
            Layout.fillHeight: true
            thickness: Widget.px(4)
            share: (line.peripheral?.percentage ?? 0) / 100
            fillTone: root.peripheralTone(line.peripheral?.level ?? "none")
          }
          StyledLabel {
            Layout.preferredWidth: percentMetrics.advanceWidth("100%") // a measuring string, the widest percent
            horizontalAlignment: Text.AlignRight
            text: (line.peripheral?.percentage ?? 0) + "%"
            role: "caption"
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
      font.pixelSize: Style.typeCaption
    }
  }
}
