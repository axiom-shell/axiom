pragma ComponentBehavior: Bound
import QtQuick

import qs.services.system
import qs.config
import qs.components.bar.widgets.base

// The Battery bar widget: charge level and icon from BatteryManager,
// colored by charging, low and critical, in its display style (charge as the
// value). The peripherals' batteries (connected Bluetooth devices, with
// showPeripherals) are listed in its tooltip and status; with no laptop
// battery it shows the lowest of them, and with none of those either it
// hides.
BarWidget {
  id: root

  // Peripherals to list (showPeripherals, and some connected)
  readonly property bool peripheralsShown: properties.showPeripherals && BatteryManager.peripherals.length > 0
  // No laptop battery: the lowest peripheral stands in
  readonly property var stand: BatteryManager.isAvailable || !root.peripheralsShown ? null : BatteryManager.lowestPeripheral
  // From UPower's display device (services/system/BatteryManager.qml)
  readonly property bool isCharging: root.stand === null && BatteryManager.isCharging
  readonly property int percentage: root.stand?.percentage ?? BatteryManager.percentage
  readonly property string timeRemaining: root.stand !== null ? "" : isCharging ? BatteryManager.timeToFull : BatteryManager.timeRemaining
  readonly property string level: root.stand?.level ?? BatteryManager.level
  // No battery at all (a desktop with none connected): collapse to
  // nothing, so a default bar can carry the widget on any machine
  hidden: !BatteryManager.isAvailable && root.stand === null

  icon: root.stand?.glyph ?? BatteryManager.getBatteryIcon()
  text: `${percentage}%`
  minimumText: "00%"
  labelShown: properties.showPercentage
  ratio: percentage / 100
  subtext: timeRemaining

  accentField: isCharging ? "chargingColor" : root.level === "critical" ? "criticalColor" : root.level === "low" ? "lowColor" : "backgroundColor"

  iconScale: 1.1
  textScale: 0.9

  function getBatteryStatus() {
    const lines = [];
    if (BatteryManager.isAvailable) {
      let status = I18n.tr(isCharging ? "Charging" : "Discharging");
      let details = I18n.tr("{0}: {1}%", status, percentage);
      if (timeRemaining) {
        details += " " + (isCharging ? I18n.tr("({0} to full)", timeRemaining) : I18n.tr("({0} remaining)", timeRemaining));
      }
      lines.push(details);
    }
    return lines.concat(root.peripheralLines()).join("\n");
  }

  // "Mouse: 80%", one per peripheral listed
  function peripheralLines() {
    return root.peripheralsShown ? BatteryManager.peripherals.map(p => I18n.tr("{0}: {1}%", p.name, p.percentage)) : [];
  }

  // News: it fell below the low threshold (its level, while discharging)
  attentionLevel: root.hidden ? -1 : root.level === "none" ? 0 : 1

  // The peripherals, with the popout off
  BarToolTip {
    widget: root
    shown: root.peripheralsShown && !root.properties.popout.enabled
    text: root.peripheralLines().join("\n")
  }

  // Charging: a slow colour pulse
  pulsing: root.isCharging

  clickable: true
  // An answer: a toast that isn't kept
  onClicked: NotificationManager.sendNotification("axiom", I18n.tr("Battery Status"), root.getBatteryStatus(), {
    "transient": true
  })
}
