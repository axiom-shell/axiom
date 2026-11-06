pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.reusable
import qs.components.methods

// A dock app's menu, opening towards the screen from its icon: its name and
// windows (click one to focus it), and, opened by a right click (`full`),
// Keep in dock / Remove from dock, New window and Close: MenuList's rows
// and keys. The small one
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
  readonly property int _towards: _edge === ScreenEdge.Bottom ? Edges.Top : _edge === ScreenEdge.Top ? Edges.Bottom : _edge === ScreenEdge.Left ? Edges.Right : Edges.Left

  visible: root.active && !!root.anchorItem?.QsWindow.window && !SurfaceManager.captureFrozen
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

  // Its windows (up to 10), then, full, what it can do
  readonly property var menuItems: {
    const items = root.windows.slice(0, 10).map((win, i) => ({
          "id": "window:" + i,
          "text": win?.title || win?.appId || "",
          "icon": win?.id === DockManager.focusedId ? "radio_button_checked" : "select_window"
        }));
    if (!root.full)
      return items;
    items.push({
      "separator": true
    }, {
      "id": "pin",
      "text": root.item?.pinned ? I18n.tr("Remove from dock") : I18n.tr("Keep in dock"),
      "icon": root.item?.pinned ? "keep_off" : "keep"
    });
    if (DockManager.entryFor(root.key) !== null)
      items.push({
        "id": "launch",
        "text": I18n.tr("New window"),
        "icon": "add"
      });
    if (root.windows.length > 0)
      items.push({
        "id": "close",
        "text": root.windows.length > 1 ? I18n.tr("Close {0} windows", root.windows.length) : I18n.tr("Close window"),
        "icon": "close"
      });
    return items;
  }
  // The dock's window takes the keyboard for the full menu (as a grabbed
  // popout's does)
  readonly property bool wantsKeyboard: root.visible && root.full
  readonly property bool exclusiveKeyboard: grab.exclusive
  readonly property Item menuList: list

  function close() {
    root.dockWindow.closeMenu();
  }

  function _pick(id) {
    const win = id.startsWith("window:") ? root.windows[Number(id.slice(7))] : null;
    if (win)
      CompositorManager.focusWindow(win.id);
    else if (id === "pin" && root.item.pinned)
      DockManager.unpin(root.dockWindow.dock.id, root.key);
    else if (id === "pin")
      DockManager.pin(root.dockWindow.dock.id, root.key, -1);
    else if (id === "launch")
      DockManager.launch(root.key);
    else if (id === "close")
      DockManager.closeWindows(root.item);
    root.close();
  }

  // Each opening starts at the top, the full one with the keyboard
  onKeyChanged: list.reset()
  onFullChanged: {
    list.reset();
    if (root.full)
      list.forceActiveFocus();
  }

  // The small menu closes a moment after the pointer leaves the icon and it
  Timer {
    interval: 250
    running: root.active && !root.full && !root.hovered && !(root.anchorItem?.hovered ?? false)
    onTriggered: root.close()
  }

  FocusGrab {
    id: grab
    windows: [root, root.grabWindow].concat(SurfaceManager.modalWindows)
    active: root.visible && root.full
    onCleared: root.close()
  }

  // Where the compositor blurs only what a window asks: the box, as
  // Hyprland blurs layers' popups
  // (attached only there: attached at all, it claims the window's blur, and
  // Hyprland's layer rules no longer blur it)
  Component.onCompleted: if (CompositorManager.supports.blurRegion === true)
    BackgroundEffect.blurRegion = Qt.binding(() => BlurManager.regionsOn(root.screen) ? boxBlur : null)
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

      MenuList {
        id: list
        visible: root.menuItems.length > 0
        Layout.fillWidth: true
        items: root.menuItems
        onTriggered: id => root._pick(id)
        onDismissed: root.close()
      }
    }
  }
}
