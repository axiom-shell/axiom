pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Bluetooth section. Named BluetoothConfig because
// `Bluetooth` is a bar widget type. Bluetooth.pairingAgent has no reader:
// the daemon reads it.
QtObject {
  readonly property var _c: ConfigManager.live.Bluetooth

  // Percentages at or below which a connected device's battery is low /
  // critical (BluetoothManager says each drop once)
  // A device's battery low said as a notification where no OSD says it
  readonly property bool notify: _c.notify
  readonly property int lowBattery: _c.lowBattery
  readonly property int criticalBattery: _c.criticalBattery
}
