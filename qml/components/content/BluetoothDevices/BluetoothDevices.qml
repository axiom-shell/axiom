pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.services.system
import qs.services.ui
import qs.config
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// Bluetooth menu for the Bluetooth widget: power switch and Discoverable
// (lit, counting down, while devices can find this computer), a Devices
// tab for paired devices (click to connect / disconnect; on hover rename,
// auto-connect, block and forget, rename opening a field in the row) and
// a Discover tab that scans while it's open and pairs + connects on click.
// A soft rfkill block offers Unblock. The popout keeps one size whatever
// the tab, the device count or the adapter state, and rows keep their
// order, so nothing moves under the pointer.
Panel {
  id: root

  property int currentTab: 0

  readonly property var shownDevices: currentTab === 0 ? BluetoothManager.pairedDevices : BluetoothManager.discoveredDevices
  readonly property string offMessage: I18n.tr(!BluetoothManager.available ? "No Bluetooth adapter found" : BluetoothManager.hardBlocked ? "Bluetooth is blocked by a hardware switch" : BluetoothManager.blocked ? "Bluetooth is blocked (rfkill)" : "Bluetooth is off")
  // The header's icon buttons, as high as its switch (StyledSwitch's)
  readonly property int headerButton: Widget.height - Widget.px(4)

  // The address of the device being renamed, "" none
  property string renaming: ""

  // The field is up: keep the keyboard, and the popout open
  wantsKeyboardFocus: root.renaming !== ""
  hovered: pointerInside || wantsKeyboardFocus
  onFocusLost: root.renaming = ""

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
  // In a popout the list grows away from the controls, which stay by the
  // bar (Panel.growth)
  flips: true
  maxImplicitHeight: root.implicitHeight + list.growRoom

  onCurrentTabChanged: {
    root.renaming = "";
    if (currentTab === 1)
      BluetoothManager.acquireDiscovery(root);
    else
      BluetoothManager.releaseDiscovery(root);
    list.fadeIn();
  }
  Component.onCompleted: BluetoothManager.acquireCountdown(root)
  Component.onDestruction: {
    BluetoothManager.releaseDiscovery(root);
    BluetoothManager.releaseCountdown(root);
  }

  // A device connected, disconnected or paired from here: marked as the
  // pointer's (ShellManager.onScreen), so its OSD card updates an open
  // OSD but opens none
  function _toggle(device) {
    ShellManager.onScreen("bluetooth");
    BluetoothManager.toggleDevice(device);
  }

  // "2:45"
  function _clock(seconds) {
    return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0");
  }

  component BluetoothRow: DeviceRow {
    id: row
    required property int index
    readonly property var device: root.shownDevices[index] ?? null
    // Each state push makes the device anew: the row is another device
    // only when its address changes
    readonly property string address: device?.address ?? ""
    readonly property bool renamingThis: row.address !== "" && root.renaming === row.address

    rowHeight: list.rowHeight
    icon: BluetoothManager.deviceIcon(row.device)
    title: BluetoothManager.deviceLabel(row.device)
    status: BluetoothManager.deviceStatus(row.device)
    connected: row.device?.connected ?? false
    known: (row.device?.paired || row.device?.bonded) ?? false
    busy: BluetoothManager.busy(row.device)
    selected: row.renamingThis
    expanded: row.renamingThis
    connectTip: I18n.tr(row.known ? "Connect" : "Pair and connect")
    onAddressChanged: row.reset()
    onActivated: root._toggle(row.device)
    onConnectClicked: root._toggle(row.device)
    onForgetConfirmed: {
      ShellManager.onScreen("bluetooth");
      BluetoothManager.forget(row.device);
    }

    // Before forget, on a paired device's hover
    hoverActions: [
      StyledRectButton {
        size: Widget.iconButton
        visible: row.known
        enabled: row.hovered && !row.busy
        backgroundColor: "transparent"
        borderHoverColor: Theme.accent
        iconColor: row.renamingThis ? Theme.accent : Theme.foregroundAlt
        iconText: "edit"
        tooltipText: I18n.tr("Rename")
        onClicked: root.renaming = row.renamingThis ? "" : row.address
      },
      StyledRectButton {
        id: trustButton
        readonly property bool trusted: row.device?.trusted ?? false
        size: Widget.iconButton
        visible: row.known
        enabled: row.hovered && !row.busy
        backgroundColor: "transparent"
        borderHoverColor: Theme.accent
        iconColor: trustButton.trusted ? Theme.accent : Theme.foregroundAlt
        iconText: trustButton.trusted ? "sync" : "sync_disabled"
        tooltipText: trustButton.trusted ? I18n.tr("Connects automatically: click to stop") : I18n.tr("Doesn't connect automatically: click to allow")
        onClicked: {
          ShellManager.onScreen("bluetooth");
          BluetoothManager.setTrusted(row.device, !trustButton.trusted);
        }
      },
      StyledRectButton {
        id: blockButton
        readonly property bool blocked: row.device?.blocked ?? false
        size: Widget.iconButton
        visible: row.known
        enabled: row.hovered && !row.busy
        backgroundColor: "transparent"
        borderHoverColor: Theme.error
        iconColor: blockButton.blocked ? Theme.error : Theme.foregroundAlt
        iconText: "block"
        tooltipText: blockButton.blocked ? I18n.tr("Blocked: click to let it connect") : I18n.tr("Block: disconnect it and refuse its connections")
        onClicked: {
          ShellManager.onScreen("bluetooth");
          BluetoothManager.setBlocked(row.device, !blockButton.blocked);
        }
      }
    ]

    // The new name: built only while renaming. Enter saves (empty, its
    // own name again), Escape cancels
    Loader {
      width: parent.width
      active: row.renamingThis

      sourceComponent: StyledTextEntry {
        id: nameField
        height: Widget.height
        placeholderText: row.device?.deviceName ? I18n.tr("Its own name: {0}", row.device.deviceName) : I18n.tr("Its own name")
        input.wrapMode: Text.NoWrap
        // Pushed in once: a state push never overwrites what's typed
        Component.onCompleted: {
          nameField.text = BluetoothManager.deviceLabel(row.device);
          nameField.input.selectAll();
          nameField.input.forceActiveFocus();
        }
        onAccepted: {
          ShellManager.onScreen("bluetooth");
          BluetoothManager.setAlias(row.device, nameField.text);
          root.renaming = "";
        }
        Keys.onEscapePressed: root.renaming = ""
      }
    }
  }

  RadioHeader {
    title: I18n.tr("Bluetooth")
    scanning: BluetoothManager.discovering
    checked: BluetoothManager.enabled
    switchEnabled: BluetoothManager.available && !BluetoothManager.blocked
    onToggled: checked => ActionsManager.run("bluetooth", {
        "call": checked ? "open" : "close",
        "fromScreen": true
      })

    // Time left discoverable, its width kept so nothing shifts
    StyledText {
      Layout.preferredWidth: clockMetrics.advanceWidth("0:00")
      horizontalAlignment: Text.AlignRight
      opacity: BluetoothManager.discoverable && BluetoothManager.discoverableLeft >= 0 ? 1 : 0
      text: root._clock(Math.max(0, BluetoothManager.discoverableLeft))
      textSize: Appearance.fontSizeBy(-2)
      textColor: Theme.accent

      FontMetrics {
        id: clockMetrics
        font.family: Appearance.fontFamily
        font.pixelSize: Appearance.fontSizeBy(-2)
      }
    }
    FlatIconButton {
      size: root.headerButton
      enabled: BluetoothManager.enabled
      opacity: enabled ? 1 : 0.5
      iconText: BluetoothManager.discoverable ? "visibility" : "visibility_off"
      iconColor: BluetoothManager.discoverable ? Theme.accent : Theme.foregroundAlt
      tooltipText: !BluetoothManager.discoverable ? I18n.tr("Not discoverable: click to let devices find this computer") : BluetoothManager.discoverableLeft >= 0 ? I18n.tr("Discoverable for {0}: click to hide", root._clock(BluetoothManager.discoverableLeft)) : I18n.tr("Discoverable: click to hide")
      onClicked: {
        ShellManager.onScreen("bluetooth");
        BluetoothManager.setDiscoverable(!BluetoothManager.discoverable);
      }
    }
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
    offAction: BluetoothManager.available && BluetoothManager.blocked && !BluetoothManager.hardBlocked ? I18n.tr("Unblock") : ""
    onOffActionClicked: {
      ShellManager.onScreen("bluetooth");
      BluetoothManager.unblock();
    }
    count: root.shownDevices.length
    emptyText: I18n.tr(root.currentTab === 0 ? "No paired devices" : "Looking for devices…")
    delegate: BluetoothRow {}
  }
}
