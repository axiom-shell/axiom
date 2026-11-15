pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components.reusable

// One entry of a tray menu (TrayMenuList): a separator, or a MenuRow with
// its check/radio indicator, image icon and submenu chevron
Item {
  id: root
  required property var menuItem
  required property int itemHeight
  required property int itemPadding
  signal itemClicked
  signal submenuRequested(Item itemDelegate)
  // Pointer entered an item without a submenu (callers close open submenus)
  signal plainItemHovered
  readonly property int indicatorSize: Math.round(itemHeight * 0.5)
  property bool openToLeft
  // Keeps a submenu opened from this item up while the pointer is on it
  readonly property bool hovered: row.hovered

  Layout.fillWidth: true
  Layout.preferredWidth: row.implicitWidth
  Layout.preferredHeight: menuItem.isSeparator ? 1 : itemHeight

  MenuRow {
    id: row
    anchors.fill: parent
    visible: !root.menuItem.isSeparator
    enabled: root.menuItem.enabled
    // DBus labels may hold line breaks: one line here
    text: (root.menuItem.text ?? "").replace(/\s*\n\s*/g, " ")
    image: root.menuItem.icon
    chevron: root.menuItem.hasChildren && !root.openToLeft

    onActivated: {
      if (root.menuItem.hasChildren) {
        root.submenuRequested(root);
      } else {
        root.menuItem.triggered();
        root.itemClicked();
      }
    }
    onHoveredChanged: {
      if (!row.hovered) {
        submenuHoverTimer.stop();
      } else if (root.menuItem.hasChildren) {
        submenuHoverTimer.restart();
      } else {
        root.plainItemHovered();
      }
    }

    // A submenu that opens to the left shows its chevron first
    StyledIcon {
      visible: root.openToLeft && root.menuItem.hasChildren
      text: "chevron_left"
      tone: "faint"
    }

    // Checkbox/Radio indicator
    Rectangle {
      visible: root.menuItem.buttonType !== QsMenuButtonType.None
      width: root.indicatorSize
      height: root.indicatorSize
      color: "transparent"
      border.color: Style.borderStrong
      border.width: Style.hairline
      radius: root.menuItem.buttonType === QsMenuButtonType.RadioButton ? width / 2 : 2

      Rectangle {
        anchors.centerIn: parent
        width: parent.width - Widget.smallPadding
        height: parent.height - Widget.smallPadding
        radius: root.menuItem.buttonType === QsMenuButtonType.RadioButton ? width / 2 : 1
        color: Style.accent
        visible: root.menuItem.checkState === Qt.Checked
      }
    }
  }

  StyledSeparator {
    anchors.centerIn: parent
    width: parent.width - root.itemPadding * 2
    visible: root.menuItem.isSeparator
  }

  // Hover timer for submenu opening
  Timer {
    id: submenuHoverTimer
    interval: 100
    repeat: false
    onTriggered: {
      if (root.menuItem.hasChildren && row.hovered) {
        root.submenuRequested(root);
      }
    }
  }
}
