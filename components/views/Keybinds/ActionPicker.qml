pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.components.reusable

// A bind's action: a button showing it, opening a popup with a search and
// one scrolling list of actions under collapsible category headers
// (KeybindManager.actionInfo). Only the current action's category starts
// open; a search opens every category and lists just the matches. Up/Down
// move through the rows, Enter picks an action or folds a category,
// Escape closes.
Item {
  id: root

  required property string currentValue
  signal picked(string action)

  property string query: ""
  // Section -> true when open
  property var expanded: ({})
  property int highlighted: 0

  readonly property bool searching: root.query.trim() !== ""

  // [{ header: true, section, count, open } | { header: false, info }]
  readonly property var rows: {
    const query = root.query.trim().toLowerCase();
    const result = [];
    for (const section of KeybindManager.actionSections) {
      const infos = KeybindManager.actionInfo.filter(info => info.section === section && (query === "" || info.label.toLowerCase().includes(query) || info.action.toLowerCase().includes(query) || I18n.tr(section).toLowerCase().includes(query)));
      if (infos.length === 0)
        continue;
      const open = query !== "" || root.expanded[section] === true;
      result.push({
        "header": true,
        "section": section,
        "count": infos.length,
        "open": open
      });
      if (open)
        for (const info of infos)
          result.push({
            "header": false,
            "info": info
          });
    }
    return result;
  }

  function toggle(section) {
    const next = Object.assign({}, root.expanded);
    next[section] = !next[section];
    root.expanded = next;
  }

  function open() {
    const current = KeybindManager.actionInfo.find(info => info.action === root.currentValue);
    const expanded = {};
    if (current)
      expanded[current.section] = true;
    root.expanded = expanded;
    search.input.text = "";
    root.query = "";
    popup.open();
    root.highlighted = Math.max(0, root.rows.findIndex(row => !row.header && row.info.action === root.currentValue));
    list.positionViewAtIndex(root.highlighted, ListView.Center);
    search.input.forceActiveFocus();
  }

  function activate(index) {
    const row = root.rows[index];
    if (!row)
      return;
    if (row.header) {
      if (!root.searching)
        root.toggle(row.section);
      return;
    }
    popup.close();
    if (row.info.action !== root.currentValue)
      root.picked(row.info.action);
  }

  function move(step) {
    if (root.rows.length === 0)
      return;
    root.highlighted = Math.max(0, Math.min(root.rows.length - 1, root.highlighted + step));
    list.positionViewAtIndex(root.highlighted, ListView.Contain);
  }

  // The first action row, so Enter after typing picks the best match
  function firstAction() {
    return Math.max(0, root.rows.findIndex(row => !row.header));
  }

  implicitHeight: Widget.height

  StyledContainer {
    id: button
    anchors.fill: parent
    backgroundColor: buttonArea.containsMouse ? Theme.backgroundHighlight : Theme.backgroundAlt
    borderColor: popup.visible ? Theme.accent : Theme.border

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Widget.padding
      anchors.rightMargin: Widget.padding
      spacing: Widget.spacing

      StyledIcon {
        text: KeybindManager.actionIcon(root.currentValue)
        textColor: Theme.accent
      }

      StyledText {
        text: KeybindManager.actionLabels[root.currentValue] ?? root.currentValue
        elide: Text.ElideRight
        Layout.fillWidth: true
      }

      StyledIcon {
        text: "arrow_drop_down"
        textColor: Theme.accent
        textSize: Appearance.fontSizeBy(2)
      }
    }

    MouseArea {
      id: buttonArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.open()
    }
  }

  Popup {
    id: popup
    y: button.height + Widget.spacing
    width: Math.max(root.width, Widget.px(320))
    // Kept inside the window
    margins: Widget.spacing
    padding: Widget.spacing
    focus: true

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
        placeholderText: I18n.tr("Search actions")
        onTextChanged: {
          root.query = text;
          root.highlighted = root.searching ? root.firstAction() : 0;
          list.positionViewAtBeginning();
        }
        onAccepted: root.activate(root.highlighted)
        Keys.onUpPressed: root.move(-1)
        Keys.onDownPressed: root.move(1)
      }

      ListView {
        id: list
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, Widget.height * 12)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: popup.visible ? root.rows.length : 0

        ScrollIndicator.vertical: ScrollIndicator {}

        delegate: Rectangle {
          id: row
          required property int index
          readonly property var entry: root.rows[index] ?? ({})
          readonly property bool header: entry.header === true
          readonly property bool current: !header && entry.info?.action === root.currentValue

          width: ListView.view.width
          height: Widget.height
          radius: Widget.radius
          color: index === root.highlighted ? Theme.backgroundHighlight : "transparent"

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: row.header ? Widget.spacing : Widget.padding * 2
            anchors.rightMargin: Widget.padding
            spacing: Widget.spacing

            StyledIcon {
              text: row.header ? (row.entry.open ? "expand_more" : "chevron_right") : KeybindManager.actionIcon(row.entry.info?.action)
              textColor: row.header || row.current ? Theme.accent : Theme.foreground
              opacity: row.header && root.searching ? 0.4 : 1
            }

            StyledText {
              text: row.header ? I18n.tr(row.entry.section ?? "") : (row.entry.info?.label ?? "")
              textColor: row.header || row.current ? Theme.accent : Theme.foreground
              font.bold: row.header || row.current
              elide: Text.ElideRight
              Layout.fillWidth: true
            }

            StyledText {
              visible: row.header
              text: String(row.entry.count ?? "")
              opacity: 0.5
              textSize: Appearance.fontSizeBy(-2)
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.highlighted = row.index
            onClicked: root.activate(row.index)
          }
        }
      }

      StyledText {
        visible: root.rows.length === 0
        text: I18n.tr("No actions match \"{0}\"", root.query.trim())
        opacity: 0.6
        Layout.fillWidth: true
      }
    }
  }
}
