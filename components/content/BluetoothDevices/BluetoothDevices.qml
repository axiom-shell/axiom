pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth

import qs.services.system
import qs.config
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// Bluetooth menu for the Bluetooth widget: power switch, a Devices tab for
// paired devices (click to connect / disconnect, forget on hover) and a
// Discover tab that scans while it's open and pairs + connects on click.
// The popout keeps one size whatever the tab, the device count or the
// adapter state, and rows keep their order, so nothing moves under the
// pointer.
Panel {
  id: root

  property int currentTab: 0
  // Only stop a scan this popout started
  property bool _startedScan: false

  readonly property var shownDevices: currentTab === 0 ? BluetoothManager.pairedDevices : BluetoothManager.discoveredDevices
  readonly property string offMessage: I18n.tr(!BluetoothManager.available ? "No Bluetooth adapter found" : BluetoothManager.blocked ? "Bluetooth is blocked (rfkill)" : "Bluetooth is off")

  compactContent: CompactFigure {
    icon: BluetoothManager.enabled ? "bluetooth" : "bluetooth_disabled"
    iconColor: BluetoothManager.connectedDevices.length > 0 ? Theme.accent : Theme.foregroundAlt
    value: BluetoothManager.enabled ? String(BluetoothManager.connectedDevices.length) : ""
    label: BluetoothManager.enabled ? I18n.tr("connected") : I18n.tr("off")
  }

  implicitWidth: Widget.px(380)
  // The switch, the tabs and a row or two, else the figure
  fullMinWidth: Appearance.fontSize * 15
  fullMinHeight: Appearance.fontSize * 12

  function updateScan() {
    const want = currentTab === 1 && BluetoothManager.enabled;
    if (want && !BluetoothManager.discovering) {
      BluetoothManager.setDiscovering(true);
      _startedScan = true;
    } else if (!want && _startedScan) {
      BluetoothManager.setDiscovering(false);
      _startedScan = false;
    }
  }

  onCurrentTabChanged: {
    updateScan();
    list.fadeIn();
  }
  Connections {
    target: BluetoothManager
    function onEnabledChanged() {
      root.updateScan();
    }
  }
  Component.onDestruction: {
    if (_startedScan)
      BluetoothManager.setDiscovering(false);
  }

  component BluetoothRow: DeviceRow {
    id: row
    required property int index
    readonly property var device: root.shownDevices[index] ?? null

    rowHeight: list.rowHeight
    icon: BluetoothManager.deviceIcon(row.device)
    title: BluetoothManager.deviceLabel(row.device)
    status: BluetoothManager.deviceStatus(row.device)
    connected: row.device?.connected ?? false
    known: (row.device?.paired || row.device?.bonded) ?? false
    busy: row.device !== null && (row.device.pairing || row.device.state === BluetoothDeviceState.Connecting || row.device.state === BluetoothDeviceState.Disconnecting)
    connectTip: I18n.tr(row.known ? "Connect" : "Pair and connect")
    onDeviceChanged: row.reset()
    onActivated: BluetoothManager.toggleDevice(row.device)
    onConnectClicked: BluetoothManager.toggleDevice(row.device)
    onForgetConfirmed: BluetoothManager.forget(row.device)
  }

  RadioHeader {
    title: I18n.tr("Bluetooth")
    scanning: BluetoothManager.discovering
    checked: BluetoothManager.enabled
    switchEnabled: BluetoothManager.available && !BluetoothManager.blocked
    onToggled: checked => BluetoothManager.setEnabled(checked)
  }

  StyledSeparator {
    Layout.fillWidth: true
    separatorColor: Theme.backgroundHighlight
  }

  StyledTabBar {
    enabled: BluetoothManager.enabled
    opacity: enabled ? 1 : 0.5
    tabs: [I18n.tr("Devices ({0})", BluetoothManager.pairedDevices.length), I18n.tr("Discover")]
    currentIndex: root.currentTab
    onTabClicked: index => root.currentTab = index
  }

  // Grows to list every row (from compact, to the full layout); off, back
  // to its place
  wantedHeight: !BluetoothManager.enabled ? 0 : root.compact ? 1 : root.height > 0 ? root.height + list.overflow : 0

  DeviceList {
    id: list
    embedded: root.embedded
    on: BluetoothManager.enabled
    offIcon: "bluetooth_disabled"
    offMessage: root.offMessage
    count: root.shownDevices.length
    emptyText: I18n.tr(root.currentTab === 0 ? "No paired devices" : "Looking for devices…")
    delegate: BluetoothRow {}
  }
}
