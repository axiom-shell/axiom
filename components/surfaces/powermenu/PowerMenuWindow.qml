pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.components.reusable
import qs.config
import qs.services.core
import qs.services.compositor
import qs.services.session
import qs.services.ui

// The power menu on one screen: a card with a greeting and the uptime, a
// row of session actions and a controls hint, over the dim backdrop.
// Destructive actions ask for a second press (PowerMenu.confirm).
PanelWindow {
  id: root

  property bool shown: false
  // Session actions shown, in order
  readonly property var actions: PowerMenuConfig.actions.filter(a => SessionManager.sessionActionInfo(a) !== null)
  // The tile the keys act on (hover moves it too)
  property int selected: 0
  // A destructive action waiting for its confirming press
  property string armed: ""
  // "3h 12m", read from /proc/uptime when it opens
  property string uptime: ""

  readonly property int pad: 18

  function toggle() {
    shown = !shown;
  }

  function run(action) {
    if (PowerMenuConfig.confirm && SessionManager.destructiveActions.includes(action) && armed !== action) {
      armed = action;
      disarm.restart();
      return;
    }
    armed = "";
    shown = false;
    SessionManager.sessionAction(action);
  }

  function select(index) {
    const count = root.actions.length;
    if (count === 0)
      return;
    const next = ((index % count) + count) % count;
    if (next !== root.selected)
      root.armed = "";
    root.selected = next;
  }

  function readUptime() {
    const text = FileManager.read("/proc/uptime");
    const seconds = text ? parseFloat(text.split(" ")[0]) : NaN;
    if (isNaN(seconds)) {
      root.uptime = "";
      return;
    }
    const minutes = Math.floor(seconds / 60) % 60;
    const hours = Math.floor(seconds / 3600) % 24;
    const days = Math.floor(seconds / 86400);
    if (days > 0)
      root.uptime = I18n.tr("{0}d {1}h", days, hours);
    else if (hours > 0)
      root.uptime = I18n.tr("{0}h {1}m", hours, minutes);
    else
      root.uptime = I18n.tr("{0}m", minutes);
  }

  onShownChanged: {
    armed = "";
    if (shown) {
      selected = 0;
      readUptime();
    }
  }

  Timer {
    id: disarm
    interval: 3000
    onTriggered: root.armed = ""
  }

  Connections {
    target: ShellManager
    function onOpenPowerMenu() {
      if (ShellManager.isTarget(root.screen, PowerMenuConfig.screen))
        root.toggle();
    }
  }

  // Locking from anywhere closes the menu, so it isn't still up on unlock
  Connections {
    target: LockManager
    function onLockStarted() {
      root.shown = false;
    }
  }

  IpcTarget {
    target: "powermenu"
    enabled: ShellManager.isTarget(root.screen, PowerMenuConfig.screen)
    function toggle() {
      root.toggle();
    }
    function open() {
      root.shown = true;
    }
    function close() {
      root.shown = false;
    }
  }

  // On every monitor, the instances open and close together
  SurfaceGroup {
    id: group
    kind: "powermenu"
    target: PowerMenuConfig.screen
    screen: root.screen
    window: root
    shown: root.shown
    onSyncRequested: shown => root.shown = shown
  }

  FocusGrab {
    id: grab
    active: root.shown && group.ownsGrab
    windows: group.windows.concat(SurfaceManager.modalWindows)
    onCleared: root.shown = false
  }

  // The dim background, under the bars and border
  BackdropRequest {
    screen: root.screen
    shown: root.shown && PowerMenuConfig.showBackdrop
    fillColor: Theme.background
    fillOpacity: PowerMenuConfig.backdrop
  }

  anchors {
    left: true
    right: true
    top: true
    bottom: true
  }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  focusable: true
  // Stays mapped while the card fades out
  visible: shown || card.opacity > 0

  WlrLayershell.keyboardFocus: grab.exclusive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "axiom-powermenu"

  // Where the compositor blurs only what a window asks: the card, as it
  // fades and scales in
  // (attached only there: attached at all, it claims the window's blur, and
  // Hyprland's layer rules no longer blur it)
  Component.onCompleted: if (CompositorManager.supports.blurRegion === true)
    BackgroundEffect.blurRegion = Qt.binding(() => BlurManager.regions ? cardBlur : null)
  BoxBlurRegion {
    id: cardBlur
    target: card
    opacity: card.opacity
  }

  Item {
    anchors.fill: parent
    // Keys can't attach to the window itself
    focus: true

    Keys.onPressed: event => {
      const digit = event.key - Qt.Key_1;
      if (event.key === Qt.Key_Escape) {
        root.shown = false;
      } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab || event.key === Qt.Key_H) {
        root.select(root.selected - 1);
      } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab || event.key === Qt.Key_L) {
        root.select(root.selected + 1);
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
        if (root.actions.length > 0)
          root.run(root.actions[root.selected]);
      } else if (digit >= 0 && digit < Math.min(9, root.actions.length)) {
        root.select(digit);
        root.run(root.actions[digit]);
      } else {
        return;
      }
      event.accepted = true;
    }

    // The empty background (the backdrop shows through it): a click on
    // it closes
    MouseArea {
      anchors.fill: parent
      onClicked: root.shown = false
    }

    Rectangle {
      id: card

      anchors.centerIn: parent
      width: Math.min(tiles.implicitWidth + root.pad * 2, root.width - Widget.px(32))
      height: content.implicitHeight + root.pad * 2
      color: Appearance.fill(Theme.background)
      border.color: Theme.border
      border.width: Appearance.borderWidth
      radius: Appearance.borderRadius
      clip: true

      opacity: root.shown ? 1 : 0
      scale: root.shown ? 1 : 0.97
      Glide on opacity {
        duration: Appearance.animNormal
      }
      Glide on scale {
        duration: Appearance.animNormal
      }

      // Swallow clicks so they don't reach the background
      MouseArea {
        anchors.fill: parent
      }

      Column {
        id: content
        x: root.pad
        y: root.pad
        width: card.width - root.pad * 2
        spacing: root.pad

        Item {
          id: header
          visible: PowerMenuConfig.showHeader
          width: parent.width
          height: Math.max(greeting.implicitHeight, uptimeRow.implicitHeight)

          StyledText {
            id: greeting
            anchors.left: parent.left
            anchors.right: uptimeRow.left
            anchors.rightMargin: root.pad
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: I18n.tr("Goodbye, {0}", General.displayName)
            textSize: Appearance.fontSizeLarge
            font.weight: Font.DemiBold
          }

          Row {
            id: uptimeRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.uptime !== ""
            spacing: Widget.spacing / 2

            StyledIcon {
              anchors.verticalCenter: parent.verticalCenter
              text: "schedule"
              textColor: Theme.foregroundInactive
              textSize: Appearance.fontSize
            }
            StyledText {
              anchors.verticalCenter: parent.verticalCenter
              text: I18n.tr("up {0}", root.uptime)
              textColor: Theme.foregroundInactive
              textSize: Appearance.fontSizeBy(-1)
            }
          }
        }

        Row {
          id: tiles
          spacing: Widget.spacing * 1.5

          Repeater {
            model: root.actions

            PowerMenuTile {
              required property string modelData
              action: modelData
              selected: root.selected === index
              armed: root.armed === modelData
              armedTimeout: disarm.interval
              revealed: root.shown
              onHovered: root.select(index)
              onClicked: {
                root.select(index);
                root.run(modelData);
              }
            }
          }
        }

        Rectangle {
          visible: PowerMenuConfig.showHint
          width: parent.width
          height: Appearance.borderWidth
          color: Theme.border
        }

        Flow {
          visible: PowerMenuConfig.showHint
          width: parent.width
          spacing: Widget.padding

          // I18n.tr("select") I18n.tr("run") I18n.tr("pick") I18n.tr("close")
          Repeater {
            model: [["← →", "select"], ["↵", "run"], ["1–" + Math.min(9, root.actions.length), "pick"], ["Esc", "close"]]

            KeyHint {
              required property var modelData
              key: modelData[0]
              label: I18n.tr(modelData[1])
            }
          }
        }
      }
    }
  }
}
