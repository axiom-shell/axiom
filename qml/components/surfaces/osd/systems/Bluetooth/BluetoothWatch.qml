pragma ComponentBehavior: Bound
import QtQuick
import qs.services.system
import qs.components.surfaces.osd.engine

// Bluetooth's state for the OSD: the radio on, the connected devices'
// names and its devices' last event (BluetoothManager.lastEvent, its
// serial the seq). Not available with no adapter. lastEvent comes with
// the daemon's Bluetooth (PR #388): until that's merged it's read only if
// BluetoothManager has it, so no event ever comes
OSDWatch {
  id: root

  // BluetoothManager untyped: its lastEvent may not exist yet
  readonly property var _manager: BluetoothManager
  // { kind, devices, serial } or null
  readonly property var _event: "lastEvent" in root._manager ? root._manager.lastEvent : null

  state: ({
      "bluetooth": {
        "available": BluetoothManager.available,
        "value": BluetoothManager.enabled,
        "connected": BluetoothManager.connectedDevices.map(d => BluetoothManager.deviceLabel(d)),
        "event": root._event ?? null,
        "seq": root._event?.serial ?? 0
      }
    })
}
