pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.services.core
import qs.services.compositor
import qs.services.ui
import qs.components.reusable

// A dock app's menu, opening towards the screen from its icon: its name and
// windows (click one to focus it), and, opened by a right click (`full`),
// Keep in dock / Remove from dock, New window and Close. The small one
// (resting on the icon) closes once the pointer leaves both; the full one
// on a click elsewhere.
PopupWindow {
  id: root

  required property var dockWindow
  property DockItem anchorItem: null
  // The dock's window, which clicks may go to without closing a full menu
  property var grabWindow: null

  readonly property bool active: root.anchorItem !== null
  readonly property bool full: root.dockWindow.menuFull
  readonly property var item: root.anchorItem?.item ?? null
  readonly property string key: root.item?.key ?? ""
  readonly property var windows: root.item?.windows ?? []
  readonly property string name: root.key ? DockManager.nameFor(root.key, root.windows[0]) : ""
  readonly property bool hovered: menuHover.hovered

  readonly property int _edge: root.dockWindow.edge
  readonly property int _towards: _edge === Bar.Bottom ? Edges.Top : _edge === Bar.Top ? Edges.Bottom : _edge === Bar.Left ? Edges.Right : Edges.Left

  visible: root.active && !!root.anchorItem?.QsWindow.window && !ShellManager.captureFrozen
  color: "transparent"
  implicitWidth: box.implicitWidth
  implicitHeight: box.implicitHeight

  anchor.item: root.anchorItem
  anchor.edges: root._towards
  anchor.gravity: root._towards
  anchor.margins.top: root._towards === Edges.Bottom ? Widget.spacing : 0
  anchor.margins.bottom: root._towards === Edges.Top ? Widget.spacing : 0
  anchor.margins.left: root._towards === Edges.Right ? Widget.spacing : 0
  anchor.margins.right: root._towards === Edges.Left ? Widget.spacing : 0

  function close() {
    root.dockWindow.closeMenu();
  }

  // The small menu closes a moment after the pointer leaves the icon and it
  Timer {
    interval: 250
    running: root.active && !root.full && !root.hovered && !(root.anchorItem?.hovered ?? false)
    onTriggered: root.close()
  }

  FocusGrab {
    windows: [root, root.grabWindow].concat(ShellManager.modalWindows)
    active: root.visible && root.full
    onCleared: root.close()
  }

  // Where the compositor blurs only what a window asks: the box, as
  // Hyprland blurs layers' popups
  // (attached only there: attached at all, it claims the window's blur, and
  // Hyprland's layer rules no longer blur it)
  Component.onCompleted: if (CompositorManager.supports.blurRegion === true)
    BackgroundEffect.blurRegion = Qt.binding(() => BlurManager.regions ? boxBlur : null)
  BoxBlurRegion {
    id: boxBlur
    target: box
  }

  StyledContainer {
    id: box
    anchors.fill: parent
    implicitWidth: Math.min(Widget.px(360), Math.max(Widget.px(160), column.implicitWidth + Widget.padding * 2))
    implicitHeight: column.implicitHeight + Widget.spacing * 2
    backgroundColor: Theme.background
    borderColor: Theme.border

    HoverHandler {
      id: menuHover
    }

    ColumnLayout {
      id: column
      anchors.fill: parent
      anchors.leftMargin: Widget.padding
      anchors.rightMargin: Widget.padding
      anchors.topMargin: Widget.spacing
      anchors.bottomMargin: Widget.spacing
      spacing: 2

      StyledText {
        visible: root.full || root.dockWindow.dock.showLabels
        Layout.fillWidth: true
        text: root.name
        font.bold: root.windows.length > 0
        elide: Text.ElideRight
      }

      Repeater {
        model: Math.min(root.windows.length, 10)

        delegate: DockMenuRow {
          required property int index
          readonly property var win: root.windows[index]
          Layout.fillWidth: true
          icon: win?.id === DockManager.focusedId ? "radio_button_checked" : "select_window"
          text: win?.title || win?.appId || ""
          onClicked: {
            DockManager.focus(win.id);
            root.close();
          }
        }
      }

      StyledSeparator {
        separatorColor: Theme.accent
        visible: root.full
        Layout.fillWidth: true
      }

      DockMenuRow {
        visible: root.full
        Layout.fillWidth: true
        icon: root.item?.pinned ? "keep_off" : "keep"
        text: root.item?.pinned ? I18n.tr("Remove from dock") : I18n.tr("Keep in dock")
        onClicked: {
          if (root.item.pinned)
            DockManager.unpin(root.dockWindow.dock.id, root.key);
          else
            DockManager.pin(root.dockWindow.dock.id, root.key, -1);
          root.close();
        }
      }

      DockMenuRow {
        visible: root.full && DockManager.entryFor(root.key) !== null
        Layout.fillWidth: true
        icon: "add"
        text: I18n.tr("New window")
        onClicked: {
          DockManager.launch(root.key);
          root.close();
        }
      }

      DockMenuRow {
        visible: root.full && root.windows.length > 0
        Layout.fillWidth: true
        icon: "close"
        text: root.windows.length > 1 ? I18n.tr("Close {0} windows", root.windows.length) : I18n.tr("Close window")
        danger: true
        onClicked: {
          DockManager.closeWindows(root.item);
          root.close();
        }
      }
    }
  }
}
