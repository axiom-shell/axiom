pragma ComponentBehavior: Bound
import QtQuick

import qs.services.system
import qs.config
import qs.components.bar.widgets.base

// The Battery bar widget: charge level and icon from BatteryManager,
// colored by charging, low and critical; hidden on machines with no battery.
BarIconWidget {
  id: root

  // From UPower's display device (services/system/BatteryManager.qml)
  readonly property bool isCharging: BatteryManager.isCharging
  readonly property int percentage: BatteryManager.percentage
  readonly property string timeRemaining: isCharging ? BatteryManager.timeToFull : BatteryManager.timeRemaining
  // No laptop battery (a desktop): collapse to nothing, so a default bar
  // can carry the widget on any machine
  hidden: !BatteryManager.isAvailable

  icon: BatteryManager.getBatteryIcon()
  text: `${percentage}%`
  showText: properties.showPercentage

  accentColor: getBatteryColor()

  iconScale: 1.1
  textScale: 0.9

  function getBatteryColor() {
    if (isCharging)
      return Theme.resolveColor(properties.chargingColor);
    if (BatteryManager.level === "critical")
      return Theme.resolveColor(properties.criticalColor);
    if (BatteryManager.level === "low")
      return Theme.resolveColor(properties.lowColor);
    return Theme.resolveColor(properties.backgroundColor);
  }

  function getBatteryStatus() {
    let status = I18n.tr(isCharging ? "Charging" : "Discharging");
    let details = I18n.tr("{0}: {1}%", status, percentage);
    if (timeRemaining) {
      details += " " + (isCharging ? I18n.tr("({0} to full)", timeRemaining) : I18n.tr("({0} remaining)", timeRemaining));
    }
    return details;
  }

  // Charging: a slow pulse, back to full when it stops
  SequentialAnimation {
    running: root.isCharging && !root.hidden && Appearance.animations
    loops: Animation.Infinite
    onRunningChanged: {
      if (!running)
        root.dim = 1;
    }

    PropertyAnimation {
      target: root
      property: "dim"
      from: 1.0
      to: 0.7
      duration: Appearance.animSlow * 5
      easing.type: Easing.InOutQuad
    }

    PropertyAnimation {
      target: root
      property: "dim"
      from: 0.7
      to: 1.0
      duration: Appearance.animSlow * 5
      easing.type: Easing.InOutQuad
    }
  }

  clickable: true
  onClicked: NotificationManager.sendNotification("axiom", I18n.tr("Battery Status"), root.getBatteryStatus())
}
