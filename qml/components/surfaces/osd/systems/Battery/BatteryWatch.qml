pragma ComponentBehavior: Bound
import QtQuick
import qs.services.system
import qs.components.surfaces.osd.engine

// The battery and charger's state for the OSD: plugged in, the level,
// charging or full and the time to full; the level ("none" | "low" |
// "critical"), the time left and the last drop (BatteryManager.levelEvent,
// set only as the level drops, once settled, where an OSD shows
// `battery`; its serial the seq). Not available with no battery
OSDWatch {
  state: ({
      "charger": {
        "available": BatteryManager.isAvailable,
        "value": !BatteryManager.onBattery,
        "percent": BatteryManager.percentage,
        "charging": BatteryManager.isCharging,
        "full": BatteryManager.isFull,
        "untilFull": BatteryManager.timeToFull
      },
      "battery": {
        "available": BatteryManager.isAvailable,
        "level": BatteryManager.level,
        "percent": BatteryManager.percentage,
        "timeLeft": BatteryManager.timeRemaining,
        "event": BatteryManager.levelEvent,
        "seq": BatteryManager.levelEvent?.serial ?? 0
      }
    })
}
