pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config

// A right-click menu, opened at a point (openAt). `items` is a list of
// { id, text, icon?, shortcut?, enabled?, checked?, submenu? }, or
// { separator: true } for a line between groups. An item with a `submenu`
// (a list of the same) opens it in place, under a row leading back;
// another item emits triggered(id) and closes the menu. Up/Down move,
// Enter or Right picks or opens, Left goes back, Escape goes back or
// closes. A press outside closes it (Popup's closePolicy, as
// TypePickerPopup's). The caller translates the texts.
Popup {
  id: root

  property var items: []

  signal triggered(string id)

  // The submenus opened, outermost first (their items)
  property var _path: []
  readonly property var _parentItem: root._path.length > 0 ? root._path[root._path.length - 1] : null
  readonly property var shownItems: root._parentItem ? (root._parentItem.submenu ?? []) : root.items
  property int highlighted: -1

  // Opens it at (x, y) in `item`'s coordinates (kept inside the window)
  function openAt(item, x, y) {
    const p = item.mapToItem(root.parent, x, y);
    root.x = p.x;
    root.y = p.y;
    root.open();
  }

  function _selectable(entry) {
    return !!entry && entry.separator !== true && entry.enabled !== false;
  }

  function _first() {
    return root.shownItems.findIndex(e => root._selectable(e));
  }

  function _move(step) {
    const list = root.shownItems;
    if (!list.some(e => root._selectable(e)))
      return;
    let i = root.highlighted;
    for (let n = 0; n < list.length; n++) {
      i = (i + step + list.length) % list.length;
      if (root._selectable(list[i])) {
        root.highlighted = i;
        return;
      }
    }
  }

  function activate(index) {
    const entry = root.shownItems[index];
    if (!root._selectable(entry))
      return;
    if (Array.isArray(entry.submenu)) {
      root._path = root._path.concat([entry]);
      root.highlighted = root._first();
      return;
    }
    root.close();
    root.triggered(String(entry.id));
  }

  function back() {
    if (root._path.length === 0) {
      root.close();
      return;
    }
    const left = root._parentItem;
    root._path = root._path.slice(0, -1);
    root.highlighted = root.shownItems.indexOf(left);
  }

  margins: Widget.spacing
  padding: Widget.spacing / 2
  focus: true
  closePolicy: Popup.CloseOnPressOutside

  onAboutToShow: {
    root._path = [];
    root.highlighted = -1;
  }
  onOpened: content.forceActiveFocus()

  // Solid, as every dropdown's list: nothing blurs behind a Popup
  background: DropdownSurface {
    color: Theme.backgroundAlt
    border.width: Appearance.borderWidth
  }

  contentItem: FocusScope {
    id: content
    implicitWidth: Math.max(Widget.px(180), column.implicitWidth)
    implicitHeight: column.implicitHeight
    focus: true

    Keys.onPressed: event => {
      switch (event.key) {
      case Qt.Key_Up:
        root._move(-1);
        break;
      case Qt.Key_Down:
        root._move(1);
        break;
      case Qt.Key_Return:
      case Qt.Key_Enter:
      case Qt.Key_Space:
        root.activate(root.highlighted);
        break;
      case Qt.Key_Right:
        if (Array.isArray(root.shownItems[root.highlighted]?.submenu))
          root.activate(root.highlighted);
        break;
      case Qt.Key_Left:
        if (root._path.length > 0)
          root.back();
        break;
      case Qt.Key_Escape:
        root.back();
        break;
      default:
        return;
      }
      event.accepted = true;
    }

    ColumnLayout {
      id: column
      width: parent.width
      spacing: 0

      // Back out of a submenu, named for it
      Rectangle {
        visible: root._parentItem !== null
        Layout.fillWidth: true
        implicitWidth: backRow.implicitWidth + Widget.smallPadding * 2
        implicitHeight: Widget.height
        radius: Widget.radius
        color: backArea.containsMouse ? Theme.backgroundHighlight : "transparent"

        RowLayout {
          id: backRow
          anchors.fill: parent
          anchors.leftMargin: Widget.smallPadding
          anchors.rightMargin: Widget.smallPadding
          spacing: Widget.spacing

          StyledIcon {
            text: "arrow_back"
            textColor: Theme.accent
          }
          StyledText {
            Layout.fillWidth: true
            text: root._parentItem?.text ?? ""
            font.weight: Font.Medium
            elide: Text.ElideRight
          }
        }

        MouseArea {
          id: backArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.back()
        }
      }

      Repeater {
        model: root.shownItems

        delegate: Item {
          id: row
          required property var modelData
          required property int index
          readonly property bool separator: modelData?.separator === true
          readonly property bool usable: root._selectable(modelData)
          readonly property bool hasSubmenu: Array.isArray(modelData?.submenu)

          Layout.fillWidth: true
          implicitWidth: separator ? 0 : rowContent.implicitWidth + Widget.smallPadding * 2
          implicitHeight: separator ? Widget.spacing + 1 : Widget.height

          StyledSeparator {
            visible: row.separator
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
          }

          Rectangle {
            visible: !row.separator
            anchors.fill: parent
            radius: Widget.radius
            color: row.index === root.highlighted && row.usable ? Theme.backgroundHighlight : "transparent"
            opacity: row.usable ? 1 : 0.4

            RowLayout {
              id: rowContent
              anchors.fill: parent
              anchors.leftMargin: Widget.smallPadding
              anchors.rightMargin: Widget.smallPadding
              spacing: Widget.spacing

              StyledIcon {
                // A checked item's mark takes the icon's place
                text: row.modelData?.checked === true ? "check" : (row.modelData?.icon ?? "")
                textColor: Theme.accent
                Layout.preferredWidth: Appearance.fontSizeBy(4)
              }
              StyledText {
                Layout.fillWidth: true
                text: row.modelData?.text ?? ""
                elide: Text.ElideRight
              }
              StyledText {
                visible: text !== ""
                text: row.modelData?.shortcut ?? ""
                textColor: Theme.foregroundInactive
                textSize: Appearance.fontSizeBy(-1)
              }
              StyledIcon {
                visible: row.hasSubmenu
                text: "chevron_right"
                textColor: Theme.foregroundInactive
              }
            }

            MouseArea {
              anchors.fill: parent
              enabled: row.usable
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.highlighted = row.index
              onClicked: root.activate(row.index)
            }
          }
        }
      }
    }
  }
}
