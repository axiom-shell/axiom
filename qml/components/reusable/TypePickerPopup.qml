pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.components.methods

// i18n: keys from callers and the schema (titles, descriptions, type labels)
// Shared "pick a type to add" popup (bar widgets, an OSD's systems, ...),
// with a search field: typing filters the types as the editors' libraries
// do (LibraryOrder.filtered: by label, type, group heading or keyword),
// Up/Down move, Enter picks, Escape closes. `types` is a list of
// { type, label, icon?, group?, keywords? }, shown in the order given, or
// with `groups` (the schema's `x-libraryGroups`) under a heading per
// group (LibraryOrder.grouped). The caller tracks what it opened this
// for. `openAt(item)` opens it under `item` (or above it when there's no
// room below), else set x/y and call open().
Popup {
  id: root

  required property var types
  property string placeholderText: I18n.tr("Search")

  // Group names in order; empty: one list, as given
  property var groups: []
  // A type's label and a group's heading as shown (the caller's schema
  // keys are translated here by default)
  property var labelOf: type => I18n.tr(type.label)
  property var headingOf: name => name ? I18n.tr(name) : I18n.tr("Other")

  property string query: ""
  property int highlighted: 0

  // The types the search finds, in the order shown
  readonly property var matches: root.groups.length > 0 ? [].concat(...root._sections.map(section => section.types)) : root._found
  readonly property var _found: LibraryOrder.filtered(root.types, root.query, root.labelOf, root.headingOf)
  readonly property var _sections: root.groups.length > 0 ? LibraryOrder.grouped(root._found, root.groups, root.labelOf) : []
  // The list's rows: { heading } over each group, then { at } (an index
  // into `matches`) per type
  readonly property var rows: {
    if (root.groups.length === 0)
      return root.matches.map((type, at) => ({
            "at": at
          }));
    const out = [];
    let at = 0;
    for (const section of root._sections) {
      out.push({
        "heading": root.headingOf(section.name)
      });
      for (const type of section.types)
        out.push({
          "at": at++
        });
    }
    return out;
  }

  function _rowOf(at) {
    return root.rows.findIndex(row => row.at === at);
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
    list.positionViewAtIndex(root._rowOf(root.highlighted), ListView.Contain);
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

  // Solid, as every dropdown's list: nothing blurs behind a Popup
  background: DropdownSurface {
    color: Theme.backgroundAlt
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
      model: root.rows

      ScrollIndicator.vertical: ScrollIndicator {}

      // A group's heading, or a type to pick
      delegate: Item {
        id: rowDelegate
        required property var modelData
        readonly property bool heading: rowDelegate.modelData.heading !== undefined
        readonly property int at: rowDelegate.modelData.at ?? -1
        readonly property var entry: root.matches[rowDelegate.at] ?? null
        readonly property string icon: root.iconOf(rowDelegate.entry)

        width: ListView.view.width
        height: rowDelegate.heading ? Widget.smallHeight + Widget.spacing : Widget.height

        StyledText {
          visible: rowDelegate.heading
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.leftMargin: Widget.smallPadding
          text: rowDelegate.modelData.heading ?? ""
          textColor: Theme.foregroundAlt
          textSize: Appearance.fontSizeBy(-1)
          font.weight: Font.Medium
        }

        Rectangle {
          visible: !rowDelegate.heading
          anchors.fill: parent
          radius: Widget.radius
          color: rowDelegate.at === root.highlighted ? Theme.backgroundHighlight : "transparent"

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
              text: rowDelegate.entry ? root.labelOf(rowDelegate.entry) : ""
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.highlighted = rowDelegate.at
            onClicked: root.activate(rowDelegate.at)
          }
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
