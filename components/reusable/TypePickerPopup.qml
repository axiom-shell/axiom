pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config

// i18n: keys from callers and the schema (titles, descriptions, type labels)
// Shared "pick a type to add" popup (bar widgets, overlay views, ...), with a
// search field: typing filters by label or type, Up/Down move, Enter picks,
// Escape closes. `types` is a list of { type, label, icon? }; the caller
// tracks what it opened this for. `openAt(item)` opens it under `item` (or
// above it when there's no room below), else set x/y and call open().
Popup {
  id: root

  required property var types
  property string placeholderText: I18n.tr("Search")

  property string query: ""
  property int highlighted: 0

  readonly property var matches: {
    const query = root.query.trim().toLowerCase();
    if (query === "")
      return root.types;
    return root.types.filter(t => I18n.tr(t.label).toLowerCase().includes(query) || String(t.type).toLowerCase().includes(query));
  }

  signal typeSelected(string type)

  function iconOf(entry) {
    return entry?.icon ?? "";
  }

  function openAt(item) {
    const p = parent;
    const below = item.mapToItem(p, 0, item.height + Widget.spacing / 2);
    const above = item.mapToItem(p, 0, -Widget.spacing / 2);
    const win = item.Window.window;
    const winBelow = item.mapToItem(null, 0, item.height).y;
    // Flip above when the list wouldn't fit under the item
    const flip = win && winBelow + root.implicitHeight > win.height && item.mapToItem(null, 0, 0).y > root.implicitHeight;
    // Right-aligned with the item when it would run off the right side
    const right = item.mapToItem(p, item.width, 0).x;
    root.x = below.x + root.width > p.width ? right - root.width : below.x;
    root.y = flip ? above.y - root.implicitHeight : below.y;
    root.open();
  }

  function activate(index) {
    const entry = root.matches[index];
    if (!entry)
      return;
    root.close();
    root.typeSelected(entry.type);
  }

  function move(step) {
    if (root.matches.length === 0)
      return;
    root.highlighted = Math.max(0, Math.min(root.matches.length - 1, root.highlighted + step));
    list.positionViewAtIndex(root.highlighted, ListView.Contain);
  }

  width: Widget.px(260)
  // Kept inside the window
  margins: Widget.spacing
  padding: Widget.spacing
  focus: true

  onAboutToShow: {
    search.input.text = "";
    root.query = "";
    root.highlighted = 0;
    list.positionViewAtBeginning();
  }
  onOpened: search.input.forceActiveFocus()

  background: DropdownSurface {
    color: Appearance.fill(Theme.backgroundAlt)
    border.width: Appearance.borderWidth
  }

  contentItem: ColumnLayout {
    spacing: Widget.spacing

    StyledTextEntry {
      id: search
      Layout.fillWidth: true
      Layout.preferredHeight: Widget.height
      placeholderText: root.placeholderText
      clearable: true
      onTextChanged: {
        root.query = text;
        root.highlighted = 0;
        list.positionViewAtBeginning();
      }
      onAccepted: root.activate(root.highlighted)
      Keys.onUpPressed: root.move(-1)
      Keys.onDownPressed: root.move(1)
    }

    ListView {
      id: list
      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(contentHeight, Widget.height * 9)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: root.matches

      ScrollIndicator.vertical: ScrollIndicator {}

      delegate: Rectangle {
        id: rowDelegate
        required property var modelData
        required property int index
        readonly property string icon: root.iconOf(modelData)

        width: ListView.view.width
        height: Widget.height
        radius: Widget.radius
        color: index === root.highlighted ? Theme.backgroundHighlight : "transparent"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Widget.padding
          anchors.rightMargin: Widget.padding
          spacing: Widget.spacing

          StyledIcon {
            visible: rowDelegate.icon !== ""
            text: rowDelegate.icon
            textColor: Theme.accent
          }

          StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: I18n.tr(rowDelegate.modelData.label)
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.highlighted = rowDelegate.index
          onClicked: root.activate(rowDelegate.index)
        }
      }
    }

    StyledText {
      visible: root.matches.length === 0
      text: I18n.tr("Nothing matches \"{0}\"", root.query.trim())
      opacity: 0.6
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }
  }
}
