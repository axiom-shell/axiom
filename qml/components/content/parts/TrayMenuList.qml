pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components.reusable

// A tray menu's entries, shared by the tray popout and its submenus. Sized
// to its widest entry, between `minWidth` and `maxWidth` (longer labels
// elide); the host surface pads it.
Item {
  id: root

  // The QsMenuHandle (or menu entry with children) to list
  required property var menu
  property bool openToLeft: false
  property string emptyText: I18n.tr("No menu items")

  readonly property int itemHeight: Widget.height
  readonly property int itemPadding: Widget.padding
  property real minWidth: Widget.height * 4
  property real maxWidth: Widget.px(600)

  signal itemClicked
  signal submenuRequested(Item itemDelegate)
  signal plainItemHovered

  implicitWidth: Math.round(Math.max(minWidth, Math.min(maxWidth, menuLayout.implicitWidth)))
  implicitHeight: menuLayout.implicitHeight

  // Entries arrive over DBus after the opener is created. Hosts keep the
  // popout hidden until they have (or the wait runs out), so it maps at its
  // final size instead of showing the empty state first.
  property bool _waitedForMenu: false
  readonly property bool contentReady: menuRepeater.count > 0 || _waitedForMenu

  Timer {
    interval: 300
    running: true
    onTriggered: root._waitedForMenu = true
  }

  QsMenuOpener {
    id: menuOpener
    menu: root.menu
  }

  ColumnLayout {
    id: menuLayout
    width: parent.width
    spacing: Widget.spacing

    Repeater {
      id: menuRepeater
      model: menuOpener.children

      delegate: TrayMenuItem {
        required property var modelData
        menuItem: modelData
        openToLeft: root.openToLeft
        itemHeight: root.itemHeight
        itemPadding: root.itemPadding

        onItemClicked: root.itemClicked()
        onSubmenuRequested: itemDelegate => root.submenuRequested(itemDelegate)
        onPlainItemHovered: root.plainItemHovered()
      }
    }

    // Empty state
    StyledText {
      wrapMode: Text.WordWrap
      visible: root.contentReady && menuRepeater.count === 0
      text: root.emptyText
      textColor: Theme.accent
      opacity: 0.5
      Layout.fillWidth: true
      Layout.preferredHeight: root.itemHeight
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }
  }
}
