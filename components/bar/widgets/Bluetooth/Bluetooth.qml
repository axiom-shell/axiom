pragma ComponentBehavior: Bound
import QtQuick

import qs.services.core
import qs.services.system
import qs.config
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// Bluetooth status: off / on / connected, optionally with the connected
// device's name and battery. Click toggles power, middle click runs a
// command; hovering opens the Bluetooth menu. (Reads BluetoothManager
// only: inside this file `Bluetooth` would mean this component.) Its
// display style draws a lone device's battery.
ValueStyleWidget {
  id: root

  readonly property var connected: BluetoothManager.connectedDevices
  readonly property var firstDevice: connected[0] ?? null

  hidden: properties.hideWhenOff && !BluetoothManager.enabled

  icon: !BluetoothManager.enabled ? "bluetooth_disabled" : connected.length > 0 ? "bluetooth_connected" : "bluetooth"
  text: {
    if (connected.length > 1)
      return I18n.tr("{0} devices", connected.length);
    if (!firstDevice)
      return "";
    const battery = properties.showBattery && firstDevice.batteryAvailable ? ` ${Math.round(firstDevice.battery * 100)}%` : "";
    return BluetoothManager.deviceLabel(firstDevice) + battery;
  }
  labelShown: properties.showDevice && text !== ""
  // One device reporting its battery
  readonly property bool hasBattery: connected.length === 1 && firstDevice.batteryAvailable
  ratio: hasBattery ? firstDevice.battery : -1
  styleText: connected.length > 1 ? text : firstDevice ? BluetoothManager.deviceLabel(firstDevice) : ""
  subtext: hasBattery ? `${Math.round(firstDevice.battery * 100)}%` : ""

  accentColor: Theme.resolveColor(!BluetoothManager.enabled ? properties.disabledColor : connected.length > 0 ? properties.connectedColor : properties.backgroundColor)
  clickable: true
  acceptedButtons: Qt.LeftButton | Qt.MiddleButton
  onClicked: button => {
    if (button === Qt.MiddleButton)
      CommandManager.runDetached(root.properties.middleCommand);
    else
      BluetoothManager.toggleEnabled();
  }

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "BluetoothDevices"
    active: EdgeMenusConfig.opensOwnPopout(root.properties) && !root.hidden && BluetoothManager.available
  }
}
