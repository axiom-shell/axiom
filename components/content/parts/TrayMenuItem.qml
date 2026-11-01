pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components.reusable

// One entry of a tray menu (TrayMenuList): a separator, or a label with its
// check/radio indicator, icon and submenu chevron
Rectangle {
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
  readonly property bool hovered: menuItemArea.containsMouse

  Layout.fillWidth: true
  Layout.preferredWidth: contentRow.implicitWidth + (itemPadding * 2)
  // A label may hold line breaks (DBus labels can): each line past the
  // first adds its height, so a one-line entry keeps `itemHeight`
  Layout.preferredHeight: menuItem.isSeparator ? 1 : Math.round(itemHeight + label.implicitHeight * (1 - 1 / Math.max(1, label.lineCount)))
  color: menuItemArea.containsMouse && menuItem.enabled && !menuItem.isSeparator ? Theme.backgroundHighlight : "transparent"
  radius: Widget.radius
  opacity: menuItem.enabled ? 1.0 : 0.5

  // Main content row
  RowLayout {
    id: contentRow
    anchors.fill: parent
    anchors.leftMargin: root.itemPadding
    anchors.rightMargin: root.itemPadding
    spacing: Widget.spacing * 2
    visible: !root.menuItem.isSeparator
    layoutDirection: root.openToLeft ? Qt.RightToLeft : Qt.LeftToRight

    // Checkbox/Radio indicator
    Rectangle {
      visible: root.menuItem.buttonType !== QsMenuButtonType.None
      Layout.preferredWidth: root.indicatorSize
      Layout.maximumWidth: root.indicatorSize
      Layout.minimumWidth: root.indicatorSize
      Layout.preferredHeight: root.indicatorSize
      color: "transparent"
      border.color: Theme.foreground
      border.width: 1
      radius: root.menuItem.buttonType === QsMenuButtonType.RadioButton ? width / 2 : 2

      Rectangle {
        anchors.centerIn: parent
        width: parent.width - Widget.smallPadding
        height: parent.height - Widget.smallPadding
        radius: root.menuItem.buttonType === QsMenuButtonType.RadioButton ? width / 2 : 1
        color: Theme.accent
        visible: root.menuItem.checkState === Qt.Checked
      }
    }

    // Icon
    Image {
      visible: root.menuItem.icon !== ""
      source: root.menuItem.icon
      sourceSize.width: root.indicatorSize
      sourceSize.height: root.indicatorSize
      Layout.preferredWidth: root.indicatorSize
      Layout.maximumWidth: root.indicatorSize
      Layout.minimumWidth: root.indicatorSize
      Layout.preferredHeight: root.indicatorSize
      fillMode: Image.PreserveAspectFit
      smooth: true
    }

    // Label
    StyledText {
      id: label
      text: root.menuItem.text
      Layout.fillWidth: true
      elide: Text.ElideRight
      wrapMode: Text.NoWrap
      clip: true
      horizontalAlignment: root.openToLeft ? Text.AlignRight : Text.AlignLeft
    }

    // Submenu indicator
    StyledIcon {
      visible: root.menuItem.hasChildren
      text: root.openToLeft ? "chevron_left" : "chevron_right"
      textColor: Theme.accent
      Layout.preferredWidth: implicitWidth
      Layout.maximumWidth: Math.ceil(implicitWidth)
      Layout.minimumWidth: implicitWidth
    }
  }

  // Separator line
  Rectangle {
    anchors.centerIn: parent
    width: parent.width - (root.itemPadding * 2)
    height: 1
    color: Theme.foreground
    opacity: 0.2
    visible: root.menuItem.isSeparator
  }

  // Hover timer for submenu opening
  Timer {
    id: submenuHoverTimer
    interval: 100
    repeat: false
    onTriggered: {
      if (root.menuItem.hasChildren && menuItemArea.containsMouse) {
        root.submenuRequested(root);
      }
    }
  }

  MouseArea {
    id: menuItemArea
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.menuItem.enabled && !root.menuItem.isSeparator

    onEntered: {
      if (root.menuItem.hasChildren) {
        submenuHoverTimer.restart();
      } else {
        root.plainItemHovered();
      }
    }

    onExited: {
      submenuHoverTimer.stop();
    }

    onClicked: {
      if (root.menuItem.hasChildren) {
        root.submenuRequested(root);
      } else {
        root.menuItem.triggered();
        root.itemClicked();
      }
    }
  }
}
