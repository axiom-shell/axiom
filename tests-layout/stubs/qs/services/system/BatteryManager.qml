pragma Singleton
import QtQuick

// Stand-in for the shell's BatteryManager in the layout harness (the Battery
// card): a laptop battery at half charge with power profiles, no peripherals.
QtObject {
  property bool isAvailable: true
  property bool hasPowerProfiles: true
  property bool hasPerformance: true
  property string profile: "balanced"
  property real percentage: 50
  property bool isCharging: false
  property bool isFull: false
  property bool isLow: false
  property bool isCritical: false
  property string timeRemaining: "3h"
  property string timeToFull: "1h"
  property var peripherals: []
  property var lowestPeripheral: ({})

  function getBatteryIcon() {
    return "battery_horiz_050";
  }

  function setProfile(name) {
  }
}
