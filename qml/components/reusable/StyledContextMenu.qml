pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.config

// A right-click menu, opened at a point (openAt): MenuList's `items`, rows
// and keys; an item picked emits triggered(id) and closes the menu, as
// Escape at the top level does. A press outside closes it (Popup's
// closePolicy, as TypePickerPopup's). The caller translates the texts.
Popup {
  id: root

  property var items: []

  signal triggered(string id)

  // Opens it at (x, y) in `item`'s coordinates (kept inside the window)
  function openAt(item, x, y) {
    const p = item.mapToItem(root.parent, x, y);
    root.x = p.x;
    root.y = p.y;
    root.open();
  }

  margins: Widget.spacing
  padding: Widget.spacing / 2
  focus: true
  closePolicy: Popup.CloseOnPressOutside

  onAboutToShow: list.reset()
  onOpened: list.forceActiveFocus()

  // Solid, as every dropdown's list: nothing blurs behind a Popup
  background: DropdownSurface {
    color: Theme.backgroundAlt
    border.width: Appearance.borderWidth
  }

  contentItem: MenuList {
    id: list
    items: root.items
    minimumWidth: Widget.px(180)
    focus: true
    onTriggered: id => {
      root.close();
      root.triggered(id);
    }
    onDismissed: root.close()
  }
}
