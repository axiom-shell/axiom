pragma Singleton
import QtQuick
import Quickshell.Services.UPower

import qs.config
import qs.services.core

// The laptop battery (UPower's display device, when it is one) and the
// power-saver profile, for the Battery widget and module, and the low
// battery's notification or OSD card (at BatteryConfig's levels).
QtObject {
  id: root

  // The display device exists before UPower has been queried for it (0%,
  // unknown state): until it is ready it would read as a critical battery
  readonly property UPowerDevice battery: UPower.displayDevice?.ready && UPower.displayDevice.isLaptopBattery ? UPower.displayDevice : null
  readonly property bool isAvailable: battery !== null
  // UPowerDevice.percentage is a 0-1 ratio
  readonly property int percentage: Math.round((battery?.percentage ?? 0) * 100)
  readonly property bool isCharging: battery?.state === UPowerDeviceState.Charging
  readonly property bool isFull: battery?.state === UPowerDeviceState.FullyCharged
  // At or below BatteryConfig's levels, while discharging
  readonly property bool isLow: isAvailable && !isCharging && percentage <= BatteryConfig.lowThreshold
  readonly property bool isCritical: isAvailable && !isCharging && percentage <= BatteryConfig.criticalThreshold
  // "none" | "low" | "critical"
  readonly property string level: isCritical ? "critical" : isLow ? "low" : "none"
  // "2h 5m", "" when unknown
  readonly property string timeRemaining: formatTime(battery?.timeToEmpty ?? 0)
  readonly property string timeToFull: formatTime(battery?.timeToFull ?? 0)

  // power-profiles-daemon, over D-Bus. Quickshell can't tell whether the
  // daemon is there, so its CLI being installed stands in for it
  readonly property bool hasPowerProfiles: DependencyManager.found.powerprofilesctl === true
  readonly property bool powerSaver: hasPowerProfiles && PowerProfiles.profile === PowerProfile.PowerSaver
  // The power profile as a name: "powerSaver" | "balanced" |
  // "performance", "" without power-profiles-daemon
  readonly property string profile: !hasPowerProfiles ? "" : PowerProfiles.profile === PowerProfile.PowerSaver ? "powerSaver" : PowerProfiles.profile === PowerProfile.Performance ? "performance" : "balanced"
  // Running on the battery, not on a charger (UPower's own, so it holds
  // while a full battery stops charging)
  readonly property bool onBattery: UPower.onBattery

  // The last level notified about, so each drop into low and then
  // critical notifies once (charging, or a reload, starts over)
  property string _notifiedLevel: "none"

  // UPower's readings arrive over D-Bus after the device does, not all at
  // once (even once it's `ready` it can read 0% for a moment), so the level
  // is only judged once they've settled: then once as it stands, and on
  // every change after
  property bool _settled: false

  property Timer _settle: Timer {
    interval: 3000
    onTriggered: {
      root._settled = true;
      root._checkLevel();
    }
  }

  onIsAvailableChanged: {
    root._settled = false;
    if (root.isAvailable)
      root._settle.restart();
  }

  onLevelChanged: _checkLevel()

  function _checkLevel() {
    if (!root._settled)
      return;
    const dropped = (level === "critical" && _notifiedLevel !== "critical") || (level === "low" && _notifiedLevel === "none");
    root._notifiedLevel = level;
    if (dropped)
      root._sayLevel(level);
  }

  // The battery dropping to `level`, where the OSD's `battery` status or
  // Battery.notify puts it (NotificationManager.announce): its card
  // (levelEvent), a notification, or nothing; a critical one is urgent and
  // notifies beside its card too
  function _sayLevel(level) {
    const critical = level === "critical";
    const summary = critical ? I18n.tr("Critical Battery") : I18n.tr("Low Battery");
    const body = critical ? I18n.tr("Battery critically low: {0}%", root.percentage) : I18n.tr("Battery low: {0}%", root.percentage);
    // One entry: critical replaces low
    const route = NotificationManager.announce("battery", BatteryConfig.notify, summary, body, {
      "urgency": critical ? "critical" : "normal",
      "key": "battery"
    });
    if (route !== "osd")
      return;
    root._levelSerial += 1;
    root.levelEvent = {
      "level": level,
      "serial": root._levelSerial
    };
  }

  // The last drop to low or critical, for the OSD's `battery` status:
  // { level: "low" | "critical", serial }, else null. Set only when the
  // OSD says it (_sayLevel)
  property var levelEvent: null
  property int _levelSerial: 0

  function setPowerSaver(on) {
    PowerProfiles.profile = on ? PowerProfile.PowerSaver : PowerProfile.Balanced;
  }

  // Keybind action powerSaver: axiom ipc powerSaver toggle|enable|disable
  // (power-profiles-daemon's power saver, else balanced)
  property IpcTarget _powerSaverIpc: IpcTarget {
    target: "powerSaver"
    enabled: root.hasPowerProfiles

    function toggle(): void {
      root.setPowerSaver(!root.powerSaver);
    }

    function enable(): void {
      root.setPowerSaver(true);
    }

    function disable(): void {
      root.setPowerSaver(false);
    }
  }

  Component.onCompleted: {
    DependencyManager.check(["powerprofilesctl"]);
    if (root.isAvailable)
      root._settle.restart();
  }

  function formatTime(seconds) {
    if (seconds <= 0)
      return "";

    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);

    if (hours > 0) {
      return I18n.tr("{0}h {1}m", hours, minutes);
    } else {
      return I18n.tr("{0}m", minutes);
    }
  }

  function getBatteryIcon() {
    if (isCharging) {
      if (percentage >= 90)
        return "battery_charging_full";
      if (percentage >= 80)
        return "battery_charging_90";
      if (percentage >= 60)
        return "battery_charging_80";
      if (percentage >= 40)
        return "battery_charging_60";
      if (percentage >= 20)
        return "battery_charging_50";
      return "battery_charging_20";
    } else {
      if (percentage >= 90)
        return "battery_full";
      if (percentage >= 80)
        return "battery_6_bar";
      if (percentage >= 60)
        return "battery_5_bar";
      if (percentage >= 50)
        return "battery_4_bar";
      if (percentage >= 30)
        return "battery_3_bar";
      if (percentage >= 20)
        return "battery_2_bar";
      return "battery_1_bar";
    }
  }
}
