pragma ComponentBehavior: Bound
import QtQuick
import qs.services.system
import qs.components.surfaces.osd.engine

// Bluetooth's state for the OSD: the radio on, the connected devices'
// names and its devices' last event (BluetoothManager.lastEvent, its
// serial the seq). Not available with no adapter
OSDWatch {
  state: ({
      "bluetooth": {
        "available": BluetoothManager.available,
        "value": BluetoothManager.enabled,
        "connected": BluetoothManager.connectedDevices.map(d => BluetoothManager.deviceLabel(d)),
        "event": BluetoothManager.lastEvent,
        "seq": BluetoothManager.lastEvent?.serial ?? 0
      }
    })
}
